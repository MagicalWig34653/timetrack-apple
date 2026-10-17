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

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Timer starten"
    static let description = IntentDescription("Startet einen Arbeitszeitabschnitt in Timetrack.")
    static let openAppWhenRun = false

    // L2: optional parameters for the Shortcuts app (empty = work timer without a place, as before).
    @Parameter(title: "Art") var kind: TimerKindOption?
    @Parameter(title: "Ort") var place: PlaceEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = try await IntentSession.client()
        do {
            let zone = await IntentSession.zone(client: client)
            switch try await TimerCommand.start(client: client, kind: kind?.segmentKind ?? .work, placeId: place?.id) {
            case .started(let segment):
                return .result(dialog: "Timer gestartet um \(segment.startedAt.formatted(Date.FormatStyle(timeZone: zone).hour().minute())).")
            case .alreadyRunning(let segment):
                return .result(dialog: "Der Timer läuft bereits seit \(segment.startedAt.formatted(Date.FormatStyle(timeZone: zone).hour().minute())).")
            default:
                return .result(dialog: "Fertig.")
            }
        } catch let error as TimetrackError {
            throw IntentError.failed(error.germanDescription)
        }
    }
}

struct StopTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Timer stoppen"
    static let description = IntentDescription("Beendet den laufenden Zeitabschnitt in Timetrack.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = try await IntentSession.client()
        do {
            switch try await TimerCommand.stop(client: client) {
            case .stopped(let segment):
                let seconds = Int((segment.endedAt ?? .now).timeIntervalSince(segment.startedAt))
                return .result(dialog: "Timer gestoppt. Dauer: \(DurationFormat.hoursMinutes(seconds)).")
            case .notRunning:
                return .result(dialog: "Es läuft kein Timer.")
            default:
                return .result(dialog: "Fertig.")
            }
        } catch let error as TimetrackError {
            throw IntentError.failed(error.germanDescription)
        }
    }
}

struct TimetrackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTimerIntent(), phrases: ["Starte den Timer in \(.applicationName)", "Timer starten in \(.applicationName)"],
                    shortTitle: "Timer starten", systemImageName: "play.fill")
        AppShortcut(intent: StopTimerIntent(), phrases: ["Stoppe den Timer in \(.applicationName)", "Timer stoppen in \(.applicationName)"],
                    shortTitle: "Timer stoppen", systemImageName: "stop.fill")
        // L2: one shortcut per place (Siri/Shortcuts expand the place parameter from `PlaceEntityQuery`).
        AppShortcut(intent: ArriveAtPlaceIntent(), phrases: ["Ankunft in \(\.$place) erfassen mit \(.applicationName)", "Ich bin in \(\.$place) angekommen mit \(.applicationName)"],
                    shortTitle: "Ankunft erfassen", systemImageName: "mappin.and.ellipse")
        AppShortcut(intent: LeaveAtPlaceIntent(), phrases: ["Abfahrt von \(\.$place) erfassen mit \(.applicationName)", "Ich habe \(\.$place) verlassen mit \(.applicationName)"],
                    shortTitle: "Abfahrt erfassen", systemImageName: "figure.walk.departure")
    }
}
