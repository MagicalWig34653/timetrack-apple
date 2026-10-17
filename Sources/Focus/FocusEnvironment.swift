import Foundation
import TimetrackCore
import TimetrackStores
import UserNotifications

/// Wires the pure Focus logic (in `TimetrackStores`) to the stored session, local notifications and the widget snapshot.
enum FocusEnvironment {
    static func makeRunner() -> FocusRunner {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TT_DEV_FOCUS_FAKE"] == "1" { return FocusRunner(backend: { DebugFocusBackend.shared }, notifier: LocalFocusNotifier(), sessionAvailable: { true }, snapshot: { DebugFocusBackend.shared.snapshot() }) }
        #endif
        return FocusRunner(
            backend: { (try? await IntentSession.client()).map { ClientFocusBackend(client: $0) } },
            notifier: LocalFocusNotifier(),
            sessionAvailable: { hasStoredSession })
    }

    /// Cheap check (two Keychain reads): is there a server and a session cookie? Validity is checked when the timer is touched.
    static var hasStoredSession: Bool {
        let secrets = KeychainSecretStore()
        return secrets.read(SecretKey.serverURL) != nil && secrets.read(SecretKey.sessionCookie) != nil
    }

    /// After a real start/stop: refresh the widgets and Live Activity (best effort; the action is already logged).
    static func publishIfChanged(_ reports: [FocusRunReport]) async {
        guard reports.contains(where: { $0.entry.result == .done }), let client = try? await IntentSession.client() else { return }
        await WidgetPublisher.refresh(client: client)
    }
}

#if DEBUG
/// In-memory timer for simulator/UI tests (`TT_DEV_FOCUS_FAKE=1`): lets the page and the notifications be exercised without a server.
final class DebugFocusBackend: FocusTimerBackend, @unchecked Sendable {
    static let shared = DebugFocusBackend()
    private let lock = NSLock()
    private var running: Segment?

    func snapshot() -> WidgetSnapshot? {
        guard let running = lock.withLock({ running }) else { return nil }
        return WidgetSnapshot(isRunning: true, kind: running.kind, startedAt: running.startedAt, todaySeconds: 0, day: "", timeZone: "Europe/Berlin", updatedAt: .now)
    }
    func currentTimer() async throws -> Segment? { lock.withLock { running } }
    func start(kind: SegmentKind, placeId: UUID?, eventId: UUID) async throws -> TimerCommand.Outcome {
        lock.withLock {
            if let running { return .alreadyRunning(running) }
            let segment = Segment(id: eventId, kind: kind, placeId: placeId, startedAt: .now)
            running = segment
            return .started(segment)
        }
    }
    func stop(eventId: UUID) async throws -> TimerCommand.Outcome {
        lock.withLock {
            guard let current = running else { return .notRunning }
            running = nil
            return .stopped(current)
        }
    }
}
#endif
