import Foundation
import TimetrackCore

/// Timer access the Focus filter needs. The app implements it with `TimerCommand` and the stored session; tests use a mock.
public protocol FocusTimerBackend: Sendable {
    func currentTimer() async throws -> Segment?
    func start(kind: SegmentKind, placeId: UUID?, eventId: UUID) async throws -> TimerCommand.Outcome
    func stop(eventId: UUID) async throws -> TimerCommand.Outcome
}

/// Posts the local questions ("Timer starten?"). Returns false when the system does not allow notifications.
/// `sequence` is the stamp of the transition that asked; the answer carries it back so stale answers can be recognised.
public protocol FocusNotifier: Sendable {
    func postStart(_ configuration: FocusConfiguration, eventId: UUID, sequence: Int64) async -> Bool
    func postStop(_ configuration: FocusConfiguration, eventId: UUID, sequence: Int64) async -> Bool
    func postSignIn() async -> Bool
}

public struct FocusRunReport: Sendable, Hashable {
    public var decision: FocusDecision
    public var entry: FocusLogEntry
}

/// Applies Focus callbacks as an idempotent state machine.
///
/// Order of work for one callback (all inside `FocusGate`, so callbacks, notification answers and retries never interleave):
/// 1. classify (activated / deactivated / hand-over / duplicate / not active) and stamp it with a monotonic sequence;
/// 2. persist the state, the received parameters and a log entry (durable, local, no network);
/// 3. decide and act; network effects have a hard time budget and, when the server cannot be reached, go into the persistent
///    retry queue with the activation's stable `clientEventId` (so a late or repeated delivery never books twice).
public struct FocusRunner: Sendable {
    public typealias BackendProvider = @Sendable () async -> (any FocusTimerBackend)?
    public typealias ClientProvider = @Sendable () async -> APIClient?

    /// Two identical activations closer together than this are one delivery.
    public static let duplicateWindowMilliseconds: Int64 = 5_000

    private let store: FocusStateStore
    private let log: FocusActionLog
    private let backend: BackendProvider
    private let notifier: any FocusNotifier
    private let sessionAvailable: @Sendable () -> Bool
    private let snapshot: @Sendable () -> WidgetSnapshot?
    private let now: @Sendable () -> Date
    private let queue: TimerActionQueue?
    private let clientProvider: ClientProvider
    private let onQueued: @Sendable () -> Void
    private let networkBudget: Double
    private let drainBudget: Double

    public init(store: FocusStateStore = FocusStateStore(), log: FocusActionLog = FocusActionLog(), backend: @escaping BackendProvider,
                notifier: any FocusNotifier, sessionAvailable: @escaping @Sendable () -> Bool = { true },
                snapshot: @escaping @Sendable () -> WidgetSnapshot? = { WidgetSnapshotStore().read() },
                now: @escaping @Sendable () -> Date = { .now },
                queue: TimerActionQueue? = nil, clientProvider: @escaping ClientProvider = { nil },
                onQueued: @escaping @Sendable () -> Void = {}, networkBudget: Double = 10, drainBudget: Double = 20) {
        self.store = store
        self.log = log
        self.backend = backend
        self.notifier = notifier
        self.sessionAvailable = sessionAvailable
        self.snapshot = snapshot
        self.now = now
        self.queue = queue
        self.clientProvider = clientProvider
        self.onQueued = onQueued
        self.networkBudget = networkBudget
        self.drainBudget = drainBudget
    }

    public var pendingCount: Int { get async { await queue?.count ?? 0 } }

    /// Handles one callback of the system filter. `incoming == nil` means the Focus ended (no usable configuration).
    /// `received` is what the system actually delivered (for the diagnostics); defaults to the configuration.
    /// `dryRun` only reports what would happen: no state change, no request that changes data, no notification.
    /// `assumingActive` lets a dry run simulate "Focus off" for a configuration that is not really active.
    @discardableResult
    public func handle(incoming: FocusConfiguration?, trigger: FocusTrigger, dryRun: Bool = false, assumingActive: FocusConfiguration? = nil,
                       received: FocusParameters? = nil) async -> [FocusRunReport] {
        if dryRun { return await apply(incoming: incoming, trigger: trigger, dryRun: true, assumingActive: assumingActive, received: received) }
        return await FocusGate.shared.run { await apply(incoming: incoming, trigger: trigger, dryRun: false, assumingActive: assumingActive, received: received) }
    }

    /// The user answered a notification with "Start": executes it without asking again (the user decided).
    /// Ignored when the same answer was already executed or the Focus changed since the question (`sequence` mismatch).
    public func confirmStart(_ configuration: FocusConfiguration, eventId: UUID, sequence: Int64? = nil) async -> FocusRunReport {
        await FocusGate.shared.run { await answer(.start, configuration: configuration, eventId: eventId, sequence: sequence) }
    }

    /// The user answered with "Stopp" (same protections as `confirmStart`).
    public func confirmStop(_ configuration: FocusConfiguration, eventId: UUID = UUID(), sequence: Int64? = nil) async -> FocusRunReport {
        await FocusGate.shared.run { await answer(.stop, configuration: configuration, eventId: eventId, sequence: sequence) }
    }

    /// Delivers queued actions (app start, foreground, background refresh, "Jetzt senden"). `verbose` also logs "still offline".
    @discardableResult
    public func retryPending(verbose: Bool = false) async -> TimerActionQueue.DrainResult? {
        guard let queue, await queue.count > 0 else { return nil }
        return await FocusGate.shared.run { await drainLocked(verbose: verbose) }
    }

    /// Forgets an active Focus whose end was never delivered (user action on the diagnostics page). Does not touch the timer.
    public func resetState() async {
        await FocusGate.shared.run {
            let sequence = nextSequence(store.load())
            store.update {
                $0.active = nil; $0.activatedAt = nil; $0.activationId = nil; $0.startedTimer = nil
                $0.queuedStartEventId = nil; $0.sequence = sequence
            }
            log.append(FocusLogEntry(date: now(), trigger: .test, mode: .off, kind: .work, summary: "Zustand von Hand zurückgesetzt: kein Fokus aktiv.",
                                     result: .done, sequence: sequence))
        }
    }

    // MARK: - Transitions

    private func nextSequence(_ state: FocusState) -> Int64 {
        max(Int64(now().timeIntervalSince1970 * 1000), (state.sequence ?? 0) + 1)
    }

    private func apply(incoming: FocusConfiguration?, trigger: FocusTrigger, dryRun: Bool, assumingActive: FocusConfiguration?, received: FocusParameters?) async -> [FocusRunReport] {
        var state = store.load()
        let parameters = received ?? FocusParameters(incoming)
        let previous = assumingActive ?? state.active
        let receivedAt = now()
        let nowMs = Int64(receivedAt.timeIntervalSince1970 * 1000)
        let fromSystem = trigger == .focusOn || trigger == .focusOff || trigger == .simulated

        // Duplicate / meaningless deliveries are logged (never silent) but change nothing.
        if !dryRun && fromSystem {
            if let incoming, state.active == incoming, let last = state.sequence, nowMs - last < Self.duplicateWindowMilliseconds {
                return [ignored(.duplicate, mode: incoming.mode, kind: incoming.kind, trigger: trigger, parameters: parameters, classification: .duplicate, state: &state, receivedAt: receivedAt)]
            }
            if incoming == nil, previous == nil {
                return [ignored(.notActive, mode: .off, kind: parameters.kind, trigger: trigger, parameters: parameters, classification: .notActive, state: &state, receivedAt: receivedAt)]
            }
        }

        let classification: FocusClassification
        switch (previous, incoming) {
        case (_, nil): classification = .deactivated
        case (nil, _?): classification = .activated
        case (let old?, let new?): classification = old == new ? .activated : (new.mode == .off ? .deactivated : .handover)
        }
        let events = FocusTransition.events(previous: previous, incoming: incoming)
        let sequence = nextSequence(state)

        // Durable local effects first (cheap), so even a failing network call leaves a correct "Fokus ist an/aus" state.
        if !dryRun {
            if let new = incoming {
                if state.active != new { state.activationId = UUID() }
                if state.active == nil { state.activatedAt = receivedAt }
                state.active = new
            } else {
                state.active = nil
                state.activatedAt = nil
                state.activationId = nil
                state.deactivationId = UUID()
            }
            state.sequence = sequence
            state.lastDelivery = FocusDeliverySummary(receivedAt: receivedAt, sequence: sequence, trigger: trigger, parameters: parameters.summary, classification: classification)
            store.save(state)
        }

        // Earlier actions that never reached the server come first (ordered, same ids), so the decision sees the real timer.
        if !dryRun, let queue, await queue.count > 0 {
            _ = await drainLocked(verbose: false)
            state = store.load()
        }

        var reports: [FocusRunReport] = []
        let context = Context(received: parameters.summary, sequence: dryRun ? nil : sequence)
        for event in events {
            reports.append(await run(event, state: state, trigger: trigger, dryRun: dryRun, assumeFocusStarted: assumingActive != nil, context: context))
        }
        if !dryRun {
            if incoming == nil { store.update { $0.startedTimer = nil; $0.queuedStartEventId = nil } }
            if let last = reports.last {
                let failed = last.entry.isFailure
                store.update { if $0.lastDelivery?.sequence == sequence { $0.lastDelivery?.result = last.entry.summary; $0.lastDelivery?.failed = failed } }
            }
        }
        return reports
    }

    private func ignored(_ reason: FocusSkipReason, mode: FocusMode, kind: SegmentKind, trigger: FocusTrigger, parameters: FocusParameters,
                         classification: FocusClassification, state: inout FocusState, receivedAt: Date) -> FocusRunReport {
        let entry = FocusLogEntry(date: receivedAt, trigger: trigger, mode: mode, kind: kind, summary: FocusText.skip(reason, kind: kind), result: .skipped(reason),
                                  received: parameters.summary, sequence: state.sequence)
        log.append(entry)
        state.lastDelivery = FocusDeliverySummary(receivedAt: receivedAt, sequence: state.sequence ?? 0, trigger: trigger, parameters: parameters.summary,
                                                  classification: classification, result: entry.summary)
        store.save(state)
        return FocusRunReport(decision: .noop(reason), entry: entry)
    }

    struct Context: Sendable {
        var received: String?
        var sequence: Int64?
    }

    private func answer(_ decision: FocusDecision, configuration: FocusConfiguration, eventId: UUID, sequence: Int64?) async -> FocusRunReport {
        let context = Context(received: "Antwort auf Mitteilung", sequence: sequence)
        if let sequence {
            var state = store.load()
            let key = "\(decision == .start ? "start" : "stop")-\(sequence)"
            func skip(_ reason: FocusSkipReason) -> FocusRunReport {
                let entry = FocusLogEntry(date: now(), trigger: .notificationAction, mode: configuration.mode, kind: configuration.kind,
                                          summary: FocusText.skip(reason, kind: configuration.kind), result: .skipped(reason), received: context.received, sequence: sequence)
                log.append(entry)
                return FocusRunReport(decision: .noop(reason), entry: entry)
            }
            if state.handledActions?.contains(key) == true { return skip(.duplicate) }
            if state.sequence != sequence { return skip(.stale) }
            state.handledActions = Array(((state.handledActions ?? []) + [key]).suffix(20))
            store.save(state)
        }
        return await execute(decision, configuration: configuration, trigger: .notificationAction, dryRun: false, eventId: eventId, context: context)
    }

    private func run(_ event: FocusEvent, state: FocusState, trigger: FocusTrigger, dryRun: Bool, assumeFocusStarted: Bool, context: Context) async -> FocusRunReport {
        let configuration: FocusConfiguration
        let activating: Bool
        switch event {
        case .activated(let value): configuration = value; activating = true
        case .deactivated(let value): configuration = value; activating = false
        }
        let eventTrigger: FocusTrigger = trigger == .test ? .test : (trigger == .simulated ? .simulated : (activating ? .focusOn : .focusOff))
        // Direct mode acts on the server and needs a stored session (no validation round trip: that is the first thing to
        // time out on a bad network); Ask mode only needs to know that one is stored, so the callback never waits for the network there.
        let backend = configuration.mode == .direct ? await self.backend() : nil
        let hasSession = configuration.mode == .direct ? backend != nil : (configuration.mode == .suggest && sessionAvailable())
        let timer = await timerState(backend: backend, mode: configuration.mode, state: state, assumeFocusStarted: assumeFocusStarted)
        let decision = FocusDecision.decide(event: event, timer: timer, settings: state.settings, hasSession: hasSession,
                                            automationEnabled: state.automationEnabled ?? true)
        return await execute(decision, configuration: configuration, trigger: eventTrigger, dryRun: dryRun,
                             eventId: (activating ? state.activationId : state.deactivationId) ?? UUID(), backend: backend, context: context)
    }

    /// Direct mode asks the server (one GET, bounded) because it acts on the answer; Ask/Off use the cached snapshot only.
    /// An unreachable server falls back to the queued actions, then to the snapshot.
    private func timerState(backend: (any FocusTimerBackend)?, mode: FocusMode, state: FocusState, assumeFocusStarted: Bool) async -> FocusTimerState {
        if mode == .direct, let backend {
            if let answer = await liveTimer(backend, budget: networkBudget / 2) {
                guard let live = answer.segment else { return .idle }
                let mine = assumeFocusStarted || state.startedTimer?.segmentId == live.id || state.queuedStartEventId != nil
                return FocusTimerState(running: true, kind: live.kind, startedByFocus: mine)
            }
            if let pending = await queue?.pending.last {
                switch pending.command {
                case .start(let kind): return FocusTimerState(running: true, kind: kind, startedByFocus: state.queuedStartEventId == pending.id)
                case .resume(let target): return FocusTimerState(running: true, kind: target.kind, startedByFocus: false)
                case .stop: return .idle
                }
            }
        }
        guard let cached = snapshot(), cached.isRunning, let startedAt = cached.startedAt else { return .idle }
        let mine = assumeFocusStarted || state.queuedStartEventId != nil || (state.startedTimer.map { abs($0.startedAt.timeIntervalSince(startedAt)) < 2 } ?? false)
        return FocusTimerState(running: true, kind: cached.kind, startedByFocus: mine)
    }

    // MARK: - Execution

    private func execute(_ decision: FocusDecision, configuration: FocusConfiguration, trigger: FocusTrigger, dryRun: Bool, eventId: UUID,
                         backend provided: (any FocusTimerBackend)? = nil, context: Context = Context()) async -> FocusRunReport {
        func finish(_ summary: String, _ result: FocusLogResult, _ detail: String? = nil) -> FocusRunReport {
            let entry = FocusLogEntry(date: now(), trigger: trigger, mode: configuration.mode, kind: configuration.kind, summary: summary, result: result,
                                      received: context.received, detail: detail, sequence: context.sequence)
            if !dryRun { log.append(entry) }
            return FocusRunReport(decision: decision, entry: entry)
        }
        let kindName = FocusText.kindName(configuration.kind)
        switch decision {
        case .noop(let reason):
            return finish(FocusText.skip(reason, kind: configuration.kind), .skipped(reason))
        case .askSignIn:
            if dryRun { return finish("Würde zur Anmeldung auffordern.", .wouldDo) }
            _ = await bounded { await notifier.postSignIn() }
            return finish("Nicht angemeldet: Hinweis zur Anmeldung gesendet.", .askedSignIn)
        case .notifyStart:
            if dryRun { return finish("Würde fragen: Timer (\(kindName)) starten?", .wouldDo) }
            let sequence = context.sequence ?? 0
            guard let posted = await bounded({ await notifier.postStart(configuration, eventId: eventId, sequence: sequence) }) else {
                return finish("Das Mitteilungssystem hat nicht geantwortet; keine Frage gestellt.", .failed("Mitteilung: Zeitüberschreitung"))
            }
            return posted ? finish("Gefragt: Timer (\(kindName)) starten?", .notified) : finish("Mitteilungen sind nicht erlaubt; keine Frage gestellt.", .notificationsDenied)
        case .notifyStop:
            if dryRun { return finish("Würde fragen: Timer (\(kindName)) stoppen?", .wouldDo) }
            let sequence = context.sequence ?? 0
            guard let posted = await bounded({ await notifier.postStop(configuration, eventId: eventId, sequence: sequence) }) else {
                return finish("Das Mitteilungssystem hat nicht geantwortet; keine Frage gestellt.", .failed("Mitteilung: Zeitüberschreitung"))
            }
            return posted ? finish("Gefragt: Timer (\(kindName)) stoppen?", .notified) : finish("Mitteilungen sind nicht erlaubt; keine Frage gestellt.", .notificationsDenied)
        case .start:
            if dryRun { return finish("Würde den Timer (\(kindName)) starten.", .wouldDo) }
            guard let backend = await resolved(provided) else { return finish("Nicht angemeldet.", .failed("Nicht angemeldet")) }
            do {
                let outcome = try await withFocusDeadline(networkBudget) { try await backend.start(kind: configuration.kind, placeId: configuration.placeId, eventId: eventId) }
                switch outcome {
                case .started(let segment):
                    store.update { $0.startedTimer = FocusStartedTimer(segmentId: segment.id, startedAt: segment.startedAt); $0.queuedStartEventId = nil }
                    return finish("Timer (\(kindName)) gestartet.", .done)
                case .alreadyRunning:
                    return finish(FocusText.skip(.alreadyRunning, kind: configuration.kind), .skipped(.alreadyRunning))
                default: return finish("Fertig.", .done)
                }
            } catch {
                return await failure(error, command: .start(configuration.kind), placeId: configuration.placeId, eventId: eventId, what: "Start", finish: finish)
            }
        case .stop:
            if dryRun { return finish("Würde den Timer (\(kindName)) stoppen.", .wouldDo) }
            guard let backend = await resolved(provided) else { return finish("Nicht angemeldet.", .failed("Nicht angemeldet")) }
            do {
                let outcome = try await withFocusDeadline(networkBudget) { try await backend.stop(eventId: eventId) }
                switch outcome {
                case .stopped:
                    store.update { $0.startedTimer = nil; $0.queuedStartEventId = nil }
                    return finish("Timer (\(kindName)) gestoppt.", .done)
                case .notRunning: return finish(FocusText.skip(.notRunning, kind: configuration.kind), .skipped(.notRunning))
                default: return finish("Fertig.", .done)
                }
            } catch {
                return await failure(error, command: .stop, placeId: nil, eventId: eventId, what: "Stopp", finish: finish)
            }
        }
    }

    /// Network trouble is not a failure of the Focus: the action is kept (persistent queue, same event id) and retried.
    /// Only a rejected session or a definite server refusal is reported as failed.
    private func failure(_ error: Error, command: QueuedTimerAction.Command, placeId: UUID?, eventId: UUID, what: String,
                         finish: (String, FocusLogResult, String?) -> FocusRunReport) async -> FocusRunReport {
        let detail = Self.technical(error)
        if let api = error as? TimetrackError, api.isUnauthorized {
            _ = await bounded { await notifier.postSignIn() }
            return finish("\(what) nicht möglich: Sitzung abgelaufen, Hinweis zur Anmeldung gesendet.", .failed("Sitzung abgelaufen"), detail)
        }
        if let queue, Self.isRetryable(error) {
            _ = await queue.enqueue(QueuedTimerAction(id: eventId, command: command, queuedAt: now(), placeId: placeId))
            if case .start = command { store.update { $0.queuedStartEventId = eventId } } else { store.update { $0.startedTimer = nil } }
            onQueued()
            return finish("Server nicht erreichbar: \(what) wartet und wird erneut versucht.", .queued, detail)
        }
        return finish("\(what) fehlgeschlagen.", .failed(Self.message(error)), detail)
    }

    static func isRetryable(_ error: Error) -> Bool {
        if error is FocusDeadlineExceeded || error is CancellationError { return true }
        guard let api = error as? TimetrackError else { return false }
        if api.isNetworkError || api == .cancelled { return true }
        return (api.status ?? 0) >= 500 || api.status == 429
    }

    private static func technical(_ error: Error) -> String {
        if error is FocusDeadlineExceeded { return "Zeitbudget überschritten" }
        if let api = error as? TimetrackError { return "\(api)" }
        return "\(error)"
    }

    // MARK: - Queue

    private func drainLocked(verbose: Bool) async -> TimerActionQueue.DrainResult? {
        guard let queue, await queue.count > 0 else { return nil }
        let state = store.load()
        func record(_ summary: String, _ result: FocusLogResult) {
            log.append(FocusLogEntry(date: now(), trigger: .retry, mode: state.active?.mode ?? .off, kind: state.active?.kind ?? .work, summary: summary, result: result, sequence: state.sequence))
        }
        guard let client = await clientProvider() else {
            if verbose { record("Nicht angemeldet: wartende Aktionen können nicht gesendet werden.", .failed("Nicht angemeldet")) }
            return nil
        }
        let result: TimerActionQueue.DrainResult
        do { result = try await withFocusDeadline(drainBudget) { await queue.drain(client: client) } } catch {
            if verbose { record("Zeitbudget überschritten; wartende Aktionen werden später gesendet.", .queued) }
            onQueued()
            return nil
        }
        if result.unauthorized {
            _ = await bounded { await notifier.postSignIn() }
            record("Sitzung abgelaufen: \(result.remaining) wartende Aktion(en) nicht gesendet.", .failed("Sitzung abgelaufen"))
        } else if result.delivered + result.dropped > 0 {
            record("Wartende Aktionen zugestellt: \(result.delivered)\(result.remaining > 0 ? ", \(result.remaining) warten noch" : "").", .done)
        } else if verbose {
            record("Server weiter nicht erreichbar: \(result.remaining) Aktion(en) warten.", .queued)
        }
        if result.remaining == 0, result.delivered > 0 {
            store.update {
                if $0.lastDelivery?.result?.contains("wartet") == true { $0.lastDelivery?.result = "Nachträglich zugestellt (zuvor: Server nicht erreichbar)."; $0.lastDelivery?.failed = false }
            }
        }
        if result.remaining > 0, !result.unauthorized { onQueued() }
        if result.remaining == 0, store.load().queuedStartEventId != nil, let backend = await backend() {
            // The queued start arrived: remember the timer it created so a later Focus end may stop it.
            if let answer = await liveTimer(backend, budget: networkBudget) {
                let live = answer.segment
                store.update {
                    $0.startedTimer = live.map { FocusStartedTimer(segmentId: $0.id, startedAt: $0.startedAt) }
                    $0.queuedStartEventId = nil
                }
            }
        }
        return result
    }

    /// A notification call must never hold the whole pipeline (and its gate) hostage; nil = no answer within the budget.
    private func bounded<T: Sendable>(_ operation: @escaping @Sendable () async -> T) async -> T? {
        try? await withFocusDeadline(5, operation)
    }

    /// nil = the server could not be asked (error or time budget); otherwise the answer, whose `segment` may be nil (idle).
    private func liveTimer(_ backend: any FocusTimerBackend, budget: Double) async -> (segment: Segment?, Void)? {
        do { return (try await withFocusDeadline(budget) { try await backend.currentTimer() }, ()) } catch { return nil }
    }

    private func resolved(_ provided: (any FocusTimerBackend)?) async -> (any FocusTimerBackend)? {
        if let provided { return provided }
        return await backend()
    }

    private static func message(_ error: Error) -> String {
        (error as? TimetrackError)?.germanDescription ?? "Der Server ist nicht erreichbar."
    }
}

extension FocusLogEntry {
    public var isFailure: Bool {
        if case .failed = result { return true }
        return false
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
