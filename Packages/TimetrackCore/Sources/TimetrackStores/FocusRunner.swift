import Foundation
import TimetrackCore

/// Timer access the Focus filter needs. The app implements it with `TimerCommand` and the stored session; tests use a mock.
public protocol FocusTimerBackend: Sendable {
    func currentTimer() async throws -> Segment?
    func start(kind: SegmentKind, placeId: UUID?, eventId: UUID) async throws -> TimerCommand.Outcome
    func stop(eventId: UUID) async throws -> TimerCommand.Outcome
}

/// Posts the local questions ("Timer starten?"). Returns false when the system does not allow notifications.
public protocol FocusNotifier: Sendable {
    func postStart(_ configuration: FocusConfiguration, eventId: UUID) async -> Bool
    func postStop(_ configuration: FocusConfiguration) async -> Bool
    func postSignIn() async -> Bool
}

public struct FocusRunReport: Sendable, Hashable {
    public var decision: FocusDecision
    public var entry: FocusLogEntry
}

/// Applies Focus callbacks: derives the events, decides, executes and records the result. Everything is bounded by one
/// optional timer lookup and one start/stop call; no store loads.
public struct FocusRunner: Sendable {
    public typealias BackendProvider = @Sendable () async -> (any FocusTimerBackend)?

    private let store: FocusStateStore
    private let log: FocusActionLog
    private let backend: BackendProvider
    private let notifier: any FocusNotifier
    private let sessionAvailable: @Sendable () -> Bool
    private let snapshot: @Sendable () -> WidgetSnapshot?
    private let now: @Sendable () -> Date

    public init(store: FocusStateStore = FocusStateStore(), log: FocusActionLog = FocusActionLog(), backend: @escaping BackendProvider,
                notifier: any FocusNotifier, sessionAvailable: @escaping @Sendable () -> Bool = { true },
                snapshot: @escaping @Sendable () -> WidgetSnapshot? = { WidgetSnapshotStore().read() },
                now: @escaping @Sendable () -> Date = { .now }) {
        self.store = store
        self.log = log
        self.backend = backend
        self.notifier = notifier
        self.sessionAvailable = sessionAvailable
        self.snapshot = snapshot
        self.now = now
    }

    /// Handles one callback of the system filter. `incoming == nil` means the Focus ended (no usable configuration).
    /// `dryRun` only reports what would happen: no state change, no request that changes data, no notification.
    /// `assumingActive` lets a dry run simulate "Focus off" for a configuration that is not really active.
    @discardableResult
    public func handle(incoming: FocusConfiguration?, trigger: FocusTrigger, dryRun: Bool = false, assumingActive: FocusConfiguration? = nil) async -> [FocusRunReport] {
        var state = store.load()
        let previous = assumingActive ?? state.active
        let events = FocusTransition.events(previous: previous, incoming: incoming)

        // Bookkeeping first (cheap), so even a failing network call leaves a correct "Fokus ist an/aus" state.
        if !dryRun {
            if let new = incoming {
                if state.active != new { state.activationId = UUID() }
                if state.active == nil { state.activatedAt = now() }
                state.active = new
            } else {
                state.active = nil
                state.activatedAt = nil
                state.activationId = nil
            }
            store.save(state)
        }

        var reports: [FocusRunReport] = []
        for event in events {
            reports.append(await run(event, state: state, trigger: trigger, dryRun: dryRun, assumeFocusStarted: assumingActive != nil))
        }
        if incoming == nil && !dryRun { store.update { $0.startedTimer = nil } }
        return reports
    }

    /// The user answered a notification with "Start": executes it without asking again (the user decided).
    public func confirmStart(_ configuration: FocusConfiguration, eventId: UUID) async -> FocusRunReport {
        await execute(.start, configuration: configuration, trigger: .notificationAction, dryRun: false, eventId: eventId)
    }

    /// The user answered with "Stopp".
    public func confirmStop(_ configuration: FocusConfiguration) async -> FocusRunReport {
        await execute(.stop, configuration: configuration, trigger: .notificationAction, dryRun: false, eventId: UUID())
    }

    private func run(_ event: FocusEvent, state: FocusState, trigger: FocusTrigger, dryRun: Bool, assumeFocusStarted: Bool) async -> FocusRunReport {
        let configuration: FocusConfiguration
        let activating: Bool
        switch event {
        case .activated(let value): configuration = value; activating = true
        case .deactivated(let value): configuration = value; activating = false
        }
        let eventTrigger: FocusTrigger = trigger == .test ? .test : (activating ? .focusOn : .focusOff)
        // Direct mode acts on the server and so needs a validated session; Ask mode only needs to know that one is stored
        // (a cheap Keychain check), so the callback never waits for the network there.
        let backend = configuration.mode == .direct ? await self.backend() : nil
        let hasSession = configuration.mode == .direct ? backend != nil : (configuration.mode == .suggest && sessionAvailable())
        let timer = await timerState(backend: backend, mode: configuration.mode, state: state, assumeFocusStarted: assumeFocusStarted)
        let decision = FocusDecision.decide(event: event, timer: timer, settings: state.settings, hasSession: hasSession,
                                            automationEnabled: state.automationEnabled ?? true)
        return await execute(decision, configuration: configuration, trigger: eventTrigger, dryRun: dryRun, eventId: state.activationId ?? UUID(), backend: backend)
    }

    /// Direct mode asks the server (one GET) because it acts on the answer; Ask/Off use the cached snapshot only.
    /// An unreachable server falls back to the snapshot.
    private func timerState(backend: (any FocusTimerBackend)?, mode: FocusMode, state: FocusState, assumeFocusStarted: Bool) async -> FocusTimerState {
        if mode == .direct, let backend {
            do {
                guard let live = try await backend.currentTimer() else { return .idle }
                return FocusTimerState(running: true, kind: live.kind, startedByFocus: assumeFocusStarted || state.startedTimer?.segmentId == live.id)
            } catch {}
        }
        guard let cached = snapshot(), cached.isRunning, let startedAt = cached.startedAt else { return .idle }
        let mine = assumeFocusStarted || (state.startedTimer.map { abs($0.startedAt.timeIntervalSince(startedAt)) < 2 } ?? false)
        return FocusTimerState(running: true, kind: cached.kind, startedByFocus: mine)
    }

    private func execute(_ decision: FocusDecision, configuration: FocusConfiguration, trigger: FocusTrigger, dryRun: Bool, eventId: UUID,
                         backend provided: (any FocusTimerBackend)? = nil) async -> FocusRunReport {
        func finish(_ summary: String, _ result: FocusLogResult) -> FocusRunReport {
            let entry = FocusLogEntry(date: now(), trigger: trigger, mode: configuration.mode, kind: configuration.kind, summary: summary, result: result)
            if !dryRun { log.append(entry) }
            return FocusRunReport(decision: decision, entry: entry)
        }
        let kindName = FocusText.kindName(configuration.kind)
        switch decision {
        case .noop(let reason):
            return finish(FocusText.skip(reason, kind: configuration.kind), .skipped(reason))
        case .askSignIn:
            if dryRun { return finish("Würde zur Anmeldung auffordern.", .wouldDo) }
            _ = await notifier.postSignIn()
            return finish("Nicht angemeldet: Hinweis zur Anmeldung gesendet.", .askedSignIn)
        case .notifyStart:
            if dryRun { return finish("Würde fragen: Timer (\(kindName)) starten?", .wouldDo) }
            let posted = await notifier.postStart(configuration, eventId: eventId)
            return posted ? finish("Gefragt: Timer (\(kindName)) starten?", .notified) : finish("Mitteilungen sind nicht erlaubt; keine Frage gestellt.", .notificationsDenied)
        case .notifyStop:
            if dryRun { return finish("Würde fragen: Timer (\(kindName)) stoppen?", .wouldDo) }
            let posted = await notifier.postStop(configuration)
            return posted ? finish("Gefragt: Timer (\(kindName)) stoppen?", .notified) : finish("Mitteilungen sind nicht erlaubt; keine Frage gestellt.", .notificationsDenied)
        case .start:
            if dryRun { return finish("Würde den Timer (\(kindName)) starten.", .wouldDo) }
            guard let backend = await resolved(provided) else { return finish("Nicht angemeldet.", .failed("Nicht angemeldet")) }
            do {
                switch try await backend.start(kind: configuration.kind, placeId: configuration.placeId, eventId: eventId) {
                case .started(let segment):
                    store.update { $0.startedTimer = FocusStartedTimer(segmentId: segment.id, startedAt: segment.startedAt) }
                    return finish("Timer (\(kindName)) gestartet.", .done)
                case .alreadyRunning:
                    return finish(FocusText.skip(.alreadyRunning, kind: configuration.kind), .skipped(.alreadyRunning))
                default: return finish("Fertig.", .done)
                }
            } catch { return finish("Start fehlgeschlagen.", .failed(Self.message(error))) }
        case .stop:
            if dryRun { return finish("Würde den Timer (\(kindName)) stoppen.", .wouldDo) }
            guard let backend = await resolved(provided) else { return finish("Nicht angemeldet.", .failed("Nicht angemeldet")) }
            do {
                switch try await backend.stop(eventId: eventId) {
                case .stopped:
                    store.update { $0.startedTimer = nil }
                    return finish("Timer (\(kindName)) gestoppt.", .done)
                case .notRunning: return finish(FocusText.skip(.notRunning, kind: configuration.kind), .skipped(.notRunning))
                default: return finish("Fertig.", .done)
                }
            } catch { return finish("Stopp fehlgeschlagen.", .failed(Self.message(error))) }
        }
    }

    private func resolved(_ provided: (any FocusTimerBackend)?) async -> (any FocusTimerBackend)? {
        if let provided { return provided }
        return await backend()
    }

    private static func message(_ error: Error) -> String {
        (error as? TimetrackError)?.germanDescription ?? "Der Server ist nicht erreichbar."
    }
}

/// The production backend: one `APIClient` driven through `TimerCommand` (idempotent start/stop).
public struct ClientFocusBackend: FocusTimerBackend {
    private let client: APIClient
    public init(client: APIClient) { self.client = client }
    public func currentTimer() async throws -> Segment? { try await client.currentTimer() }
    public func start(kind: SegmentKind, placeId: UUID?, eventId: UUID) async throws -> TimerCommand.Outcome {
        try await TimerCommand.start(client: client, kind: kind, placeId: placeId, eventId: eventId)
    }
    public func stop(eventId: UUID) async throws -> TimerCommand.Outcome { try await TimerCommand.stop(client: client, eventId: eventId) }
}
