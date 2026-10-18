#if os(iOS)
import AppIntents
import Foundation
import TimetrackCore
import TimetrackStores
import WidgetKit

/// Session for intents started from a widget, control or Live Activity. The cookie stays in the Keychain; the app, the intents and the
/// widget extension share it through a keychain access group (see docs/handoffs/A7.md). Nothing is copied into the App Group.
enum WidgetSession {
    static func client() async throws -> APIClient {
        let auth = AuthService(secrets: KeychainSecretStore(), transport: URLSessionTransport())
        switch await auth.restore() {
        case .signedIn(let context):
            guard !context.session.recovery else { throw WidgetIntentError.signedOut }
            return context.client
        case .signedOut: throw WidgetIntentError.signedOut
        case .offline: throw WidgetIntentError.offline
        }
    }
}

enum WidgetIntentError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut, offline, failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: LocalizedStringResource("w.error.signed_out", table: "Widget")
        case .offline: LocalizedStringResource("w.error.offline", table: "Widget")
        case .failed(let text): "\(text)"
        }
    }
}

enum WidgetTimerAction {
    case start, stop

    /// Runs the command against the API, then refreshes the snapshot, widgets and Live Activity.
    static func perform(_ action: WidgetTimerAction) async throws {
        let client = try await WidgetSession.client()
        do {
            switch action {
            case .start: _ = try await TimerCommand.start(client: client)
            case .stop: _ = try await TimerCommand.stop(client: client)
            }
        } catch let error as TimetrackError {
            throw WidgetIntentError.failed(error.germanDescription)
        }
        await WidgetPublisher.refresh(client: client, source: "intent")
    }
}

/// Run by widget buttons and Live Activity buttons. `LiveActivityIntent` makes the system execute it in the app's process,
/// where Live Activities can be started; if it runs in the extension instead, the shared keychain group provides the session.
struct WidgetStartTimerIntent: LiveActivityIntent {
    static let title = LocalizedStringResource("w.intent.start", table: "Widget")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        try await WidgetTimerAction.perform(.start)
        return .result()
    }
}

struct WidgetStopTimerIntent: LiveActivityIntent {
    static let title = LocalizedStringResource("w.intent.stop", table: "Widget")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        try await WidgetTimerAction.perform(.stop)
        return .result()
    }
}

/// Bound to the Control Center toggle; `value` is the requested running state.
struct ToggleTimerControlIntent: SetValueIntent, LiveActivityIntent {
    static let title = LocalizedStringResource("w.intent.toggle", table: "Widget")
    static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("w.intent.toggle.value", table: "Widget"))
    var value: Bool

    func perform() async throws -> some IntentResult {
        try await WidgetTimerAction.perform(value ? .start : .stop)
        return .result()
    }
}
#endif
