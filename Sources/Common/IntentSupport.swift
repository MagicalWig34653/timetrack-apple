import AppIntents
import Foundation
import TimetrackCore
import TimetrackStores

/// Shortcuts/Siri access. The intents run in the app process and use the session stored in the Keychain; they never
/// show UI and never keep credentials of their own.
enum IntentSession {
    static func client() async throws -> APIClient {
        let auth = AuthService(secrets: KeychainSecretStore(), transport: URLSessionTransport())
        switch await auth.restore() {
        case .signedIn(let context):
            guard !context.session.recovery else { throw IntentError.signedOut }
            return context.client
        case .signedOut: throw IntentError.signedOut
        case .offline: throw IntentError.offline
        }
    }

    static func zone(client: APIClient) async -> TimeZone {
        (try? await client.listWorkModels())?.current()?.timeZone ?? TimeZone(identifier: "Europe/Berlin") ?? .current
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut, offline, failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: "Bitte zuerst in der Timetrack-App anmelden."
        case .offline: "Der Server ist nicht erreichbar."
        case .failed(let text): "\(text)"
        }
    }
}


/// H5: "Letzten Timer fortführen" for Shortcuts, Siri and the Action Button (iOS) and Shortcuts/Spotlight (macOS). Reopens the last finished
/// entry of today like the "Fortführen" button; a server that cannot reopen gets a new entry of the same kind from now (gap stays a pause).
/// `startNew` ("Neu starten") skips the reopen. The intent never asks about a long gap itself: the Shortcut author chooses the parameter.
struct ContinueTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Letzten Timer fortführen"
    static let description = IntentDescription("Führt den zuletzt beendeten Zeitabschnitt von heute fort, statt einen neuen zu beginnen. Die Lücke seit dem Ende zählt dann mit.")
    static let openAppWhenRun = false

    @Parameter(title: "Neu starten (Lücke bleibt Pause)", default: false) var startNew: Bool

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = try await IntentSession.client()
        do {
            let zone = await IntentSession.zone(client: client)
            let today = DayCalendar(timeZone: zone).day(for: .now)
            switch try await TimerCommand.continueLast(client: client, today: today, startNew: startNew) {
            case .continued(let segment, let mode):
                #if os(iOS)
                await WidgetPublisher.refresh(client: client, source: "intent")
                #endif
                let at = segment.startedAt.formatted(Date.FormatStyle(timeZone: zone).hour().minute())
                switch mode {
                case .reopened: return .result(dialog: "Eintrag wieder geöffnet, die Lücke zählt mit. Der Timer läuft seit \(at).")
                case .startedNew: return .result(dialog: "Neuer Eintrag ab jetzt, die Lücke bleibt eine Pause. Der Server kann Einträge nicht wieder öffnen.")
                }
            case .alreadyRunning(let segment):
                return .result(dialog: "Der Timer läuft bereits seit \(segment.startedAt.formatted(Date.FormatStyle(timeZone: zone).hour().minute())).")
            case .nothingToContinue:
                return .result(dialog: "Heute gibt es keinen beendeten Eintrag zum Fortführen.")
            default:
                return .result(dialog: "Fertig.")
            }
        } catch let error as TimetrackError {
            throw IntentError.failed(error.germanDescription)
        }
    }
}
