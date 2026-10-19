import BackgroundTasks
import Foundation
import TimetrackCore
import TimetrackStores
import UIKit
import UserNotifications

/// Wires the pure Focus logic (in `TimetrackStores`) to the stored session, local notifications, the retry queue and the widget snapshot.
///
/// The system runs the filter intent inside the app process (no extension). Everything the pipeline needs is therefore either
/// in the App Group (state, log), in the app container (retry queue) or in the Keychain (session, readable after first unlock);
/// nothing depends on the app UI being alive.
enum FocusEnvironment {
    static let retryTaskIdentifier = "de.linolaske.timetrack.focus.retry"
    /// Posted (in-process) after every delivery so an open Focus page refreshes at once.
    static let changed = Notification.Name("de.linolaske.timetrack.focus.changed")

    /// One queue instance per process (an actor guarding one file).
    static var queue: TimerActionQueue { TimerControlRunner.queue } // LA1: shared with the Live Activity buttons

    /// Client for the stored session WITHOUT a validation round trip (that call is the first to time out on a bad network).
    /// A rejected session surfaces as a 401 on the real call and is handled there.
    static func storedClient() async -> APIClient? {
        await AuthService(secrets: KeychainSecretStore(), transport: URLSessionTransport(timeout: 8)).optimisticClient()
    }

    static func makeRunner() -> FocusRunner {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TT_DEV_FOCUS_FAKE"] == "1" {
            return FocusRunner(backend: { DebugFocusBackend.shared }, notifier: LocalFocusNotifier(), sessionAvailable: { true },
                               snapshot: { DebugFocusBackend.shared.snapshot() },
                               queue: queue, clientProvider: { DebugFocusBackend.shared.client() }, onQueued: { scheduleRetry() })
        }
        #endif
        return FocusRunner(
            backend: { await storedClient().map { ClientFocusBackend(client: $0) } },
            notifier: LocalFocusNotifier(),
            sessionAvailable: { hasStoredSession },
            queue: queue, clientProvider: { await storedClient() }, onQueued: { scheduleRetry() })
    }

    /// Cheap check (two Keychain reads): is there a server and a session cookie? Validity is checked when the timer is touched.
    static var hasStoredSession: Bool {
        let secrets = KeychainSecretStore()
        return secrets.read(SecretKey.serverURL) != nil && secrets.read(SecretKey.sessionCookie) != nil
    }

    /// The single entry for everything that behaves like a system callback (the intent, the debug hook, the page's real test).
    @discardableResult
    static func deliver(_ parameters: FocusParameters, trigger: FocusTrigger) async -> [FocusRunReport] {
        await withBackgroundTime("focus.deliver") {
            let reports = await makeRunner().handle(incoming: parameters.configuration, trigger: trigger, received: parameters)
            await publishIfChanged(reports)
            NotificationCenter.default.post(name: changed, object: nil)
            return reports
        }
    }

    /// Delivers queued actions; used at launch, on foreground, by the background task and by "Jetzt senden".
    @discardableResult
    static func retryPending(verbose: Bool = false) async -> TimerActionQueue.DrainResult? {
        let result = await withBackgroundTime("focus.retry") { () -> TimerActionQueue.DrainResult? in
            let result = await makeRunner().retryPending(verbose: verbose)
            // A queued start/stop that arrived changes the timer: update or end the Live Activity (a start is completed on foreground).
            if let result, result.delivered > 0, let client = await storedClient() {
                _ = try? await withFocusDeadline(4) { await WidgetPublisher.refresh(client: client, source: "focus.retry") }
            }
            return result
        }
        NotificationCenter.default.post(name: changed, object: nil)
        return result
    }

    /// After a real start/stop: refresh the widgets and Live Activity (best effort, bounded; the action is already logged).
    static func publishIfChanged(_ reports: [FocusRunReport]) async {
        guard reports.contains(where: { $0.entry.result == .done }), let client = await storedClient() else { return }
        _ = try? await withFocusDeadline(4) { await WidgetPublisher.refresh(client: client, source: "focus") }
    }

    /// Sign-out: waiting actions belong to the old account and must never be sent with another one.
    static func signedOut() async {
        await queue.clear()
        FocusStateStore().update { $0.queuedStartEventId = nil }
    }

    // MARK: Time budget and retries

    /// Keeps the process alive for the short time after the app moved to the background (or was launched for the callback).
    static func withBackgroundTime<T: Sendable>(_ name: String, _ body: @Sendable () async -> T) async -> T {
        let box = BackgroundTaskBox()
        await MainActor.run {
            box.id = UIApplication.shared.beginBackgroundTask(withName: name) { box.end() }
        }
        let value = await body()
        box.end()
        return value
    }

    /// Must run before the app finishes launching (called from `App.init`).
    static func registerBackgroundRetry() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: retryTaskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            nonisolated(unsafe) let task = refresh // BGTask is documented as callable from any queue
            let work = Task {
                let result = await retryPending()
                task.setTaskCompleted(success: (result?.remaining ?? 0) == 0)
            }
            task.expirationHandler = { work.cancel(); scheduleRetry() }
        }
    }

    /// Asks the system for another attempt soon; iOS decides the real time (the date is only a lower bound).
    static func scheduleRetry() {
        let request = BGAppRefreshTaskRequest(identifier: retryTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

private final class BackgroundTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var identifier = UIBackgroundTaskIdentifier.invalid
    var id: UIBackgroundTaskIdentifier {
        get { lock.withLock { identifier } }
        set { lock.withLock { identifier = newValue } }
    }

    func end() {
        let current = lock.withLock { () -> UIBackgroundTaskIdentifier in
            let value = identifier
            identifier = .invalid
            return value
        }
        guard current != .invalid else { return }
        Task { @MainActor in UIApplication.shared.endBackgroundTask(current) }
    }
}

#if DEBUG
/// In-memory timer for simulator/UI tests (`TT_DEV_FOCUS_FAKE=1`): lets the page, the notifications and the retry queue be
/// exercised without a server. `offline` makes every call fail like a missing network (also for the queue's client).
final class DebugFocusBackend: FocusTimerBackend, @unchecked Sendable {
    static let shared = DebugFocusBackend()
    private let lock = NSLock()
    private var running: Segment?
    private var offlineFlag = false

    var offline: Bool {
        get { lock.withLock { offlineFlag } }
        set { lock.withLock { offlineFlag = newValue } }
    }

    func snapshot() -> WidgetSnapshot? {
        guard let running = lock.withLock({ running }) else { return nil }
        return WidgetSnapshot(isRunning: true, kind: running.kind, startedAt: running.startedAt, todaySeconds: 0, day: "", timeZone: "Europe/Berlin", updatedAt: .now)
    }
    func currentTimer() async throws -> Segment? {
        if offline { throw TimetrackError.network(.notConnectedToInternet) }
        return lock.withLock { running }
    }
    func start(kind: SegmentKind, placeId: UUID?, eventId: UUID) async throws -> TimerCommand.Outcome {
        if offline { throw TimetrackError.network(.notConnectedToInternet) }
        return lock.withLock {
            if let running { return .alreadyRunning(running) }
            let segment = Segment(id: eventId, kind: kind, placeId: placeId, startedAt: .now)
            running = segment
            return .started(segment)
        }
    }
    func stop(eventId: UUID) async throws -> TimerCommand.Outcome {
        if offline { throw TimetrackError.network(.notConnectedToInternet) }
        return lock.withLock {
            guard let current = running else { return .notRunning }
            running = nil
            return .stopped(current)
        }
    }

    /// A client whose transport applies queued starts/stops to this fake (or fails like a missing network while `offline`).
    func client() -> APIClient {
        APIClient(baseURL: URL(string: "http://localhost:1")!, transport: FakeTransport(backend: self))
    }

    private struct FakeTransport: HTTPTransport {
        let backend: DebugFocusBackend
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            if backend.offline { throw URLError(.notConnectedToInternet) }
            let path = request.url?.path ?? ""
            let id = ((try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any])?["clientEventId"] as? String
            let eventId = id.flatMap(UUID.init(uuidString:)) ?? UUID()
            let outcome: TimerCommand.Outcome
            if path.hasSuffix("/start") {
                outcome = (try? await backend.start(kind: .work, placeId: nil, eventId: eventId)) ?? .notRunning
            } else {
                outcome = (try? await backend.stop(eventId: eventId)) ?? .notRunning
            }
            var segment: Segment?
            switch outcome {
            case .started(let value), .alreadyRunning(let value), .stopped(let value): segment = value
            case .notRunning: segment = nil
            }
            guard let segment else { return (Data(#"{"error":{"code":"no_running_timer","message":"x"}}"#.utf8), response(request, 409)) }
            return (try JSONCoding.makeEncoder().encode(segment), response(request, 200))
        }
        private func response(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        }
    }
}

/// Simulator/UI-test hook: `TT_DEV_FOCUS_SIMULATE` is a comma-separated script run through the REAL delivery pipeline
/// (same path as the system callback), e.g. `on:direct:work:Arbeit,wait:1,off,off`. Steps: `on:<off|suggest|direct>[:<work|travel|school>[:<name>]]`,
/// `off` (an empty delivery, like iOS sends when a Focus ends), `wait:<seconds>`, `offline`/`online` (fake backend).
enum FocusSimulation {
    static func runFromEnvironment() {
        let environment = ProcessInfo.processInfo.environment
        // `TT_DEV_FOCUS_RESET=1` starts from a clean state (the simulator keeps the App Group between UI-test launches).
        let reset = environment["TT_DEV_FOCUS_RESET"] == "1"
        if reset {
            FocusStateStore().save(FocusState())
            FocusActionLog().clear()
        }
        guard reset || environment["TT_DEV_FOCUS_SIMULATE"] != nil else { return }
        Task {
            if reset { await FocusEnvironment.queue.clear() }
            if let script = environment["TT_DEV_FOCUS_SIMULATE"] { await run(script) }
            NotificationCenter.default.post(name: FocusEnvironment.changed, object: nil)
        }
    }

    static func run(_ script: String) async {
        for step in script.split(separator: ",").map({ $0.split(separator: ":", omittingEmptySubsequences: false).map(String.init) }) {
            switch step.first {
            case "on":
                let mode = FocusMode(rawValue: step.count > 1 ? step[1] : "suggest") ?? .suggest
                let kind = SegmentKind(rawValue: step.count > 2 ? step[2] : "work") ?? .work
                let name = step.count > 3 ? step[3] : nil
                await FocusEnvironment.deliver(FocusParameters(mode: mode, kind: kind, focusName: name), trigger: .simulated)
            case "off":
                await FocusEnvironment.deliver(FocusParameters(mode: nil), trigger: .simulated)
            case "wait":
                try? await Task.sleep(for: .seconds(Double(step.count > 1 ? step[1] : "1") ?? 1))
            case "offline": DebugFocusBackend.shared.offline = true
            case "online": DebugFocusBackend.shared.offline = false
            default: break
            }
        }
    }
}
#endif
