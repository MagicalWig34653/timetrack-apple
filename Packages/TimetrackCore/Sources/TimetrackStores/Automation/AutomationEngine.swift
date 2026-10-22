import Foundation
import TimetrackCore

/// One-shot location lookup supplied by the platform layer (`requestLocation()` with 100 m accuracy). Never a stream.
public protocol LocationFixProviding: Sendable {
    func currentFix() async -> LocationFix?
}

public enum LogTrigger: String, Codable, Sendable, Hashable {
    case regionEnter, regionExit, check, reconcile, shortcutArrive, shortcutLeave, sync
    /// L4: the check after the leave wait ("stop when leaving").
    case leaveCheck
}

public struct AutomationLogEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let date: Date
    public let placeName: String
    public let trigger: LogTrigger
    public let decision: AutomationDecision
    public let confidence: PresenceConfidence?
    /// Server result (`booked`, `suggested`, `recorded`, ...) for `sync` entries, or the error code.
    public let detail: String?
}

/// Everything the background launch needs without a network: settings, cached places, per-place progress, log.
public struct AutomationState: Codable, Sendable, Equatable {
    public var config = AutomationConfig()
    public var places: [AutomationPlace] = []
    public var runtime: [String: PlaceRuntimeState] = [:]
    public var log: [AutomationLogEntry] = []
    /// Last position the app knew (significant change / one-shot fix); only used to choose the nearest regions.
    public var lastKnown: GeoPoint?
    /// L4: leaves waiting for their check ("stop when leaving"), by place id.
    public var pendingLeaves: [String: PendingLeave] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey { case config, places, runtime, log, lastKnown, pendingLeaves }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        config = try container.decodeIfPresent(AutomationConfig.self, forKey: .config) ?? AutomationConfig()
        places = try container.decodeIfPresent([AutomationPlace].self, forKey: .places) ?? []
        runtime = try container.decodeIfPresent([String: PlaceRuntimeState].self, forKey: .runtime) ?? [:]
        log = try container.decodeIfPresent([AutomationLogEntry].self, forKey: .log) ?? []
        lastKnown = try container.decodeIfPresent(GeoPoint.self, forKey: .lastKnown)
        pendingLeaves = try container.decodeIfPresent([String: PendingLeave].self, forKey: .pendingLeaves) ?? [:]
    }

    public static let logLimit = 50

    public func place(_ id: UUID) -> AutomationPlace? { places.first { $0.id == id } }
}

public struct AutomationOutcome: Sendable, Equatable {
    public var decision: AutomationDecision
    public var placeName: String?
    public var mode: AutomationMode?
    public var dwellMinutes: Int?
}

/// Orchestrates region/shortcut signals: filter, queue and drain. Both entry points (region monitoring in the app, App Intents from
/// Shortcuts) call this actor, so they share state, dedupe and cooldown. One shared instance per process.
public actor AutomationEngine {
    private let stateStorage: BlobStorage
    private let queue: AutomationEventQueue
    private let location: LocationFixProviding
    private let senderFactory: @Sendable () -> AutomationEventSending?
    private let deviceId: String
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private let leaveStop: LeaveStopActing?
    private var state: AutomationState
    private var changeHandler: (@Sendable () -> Void)?

    public init(storage: BlobStorage, queue: AutomationEventQueue, location: LocationFixProviding, deviceId: String,
                senderFactory: @escaping @Sendable () -> AutomationEventSending?,
                now: @escaping @Sendable () -> Date = { .now }, makeID: @escaping @Sendable () -> UUID = { UUID() },
                leaveStop: LeaveStopActing? = nil) {
        self.leaveStop = leaveStop
        self.stateStorage = storage
        self.queue = queue
        self.location = location
        self.deviceId = deviceId
        self.senderFactory = senderFactory
        self.now = now
        self.makeID = makeID
        state = storage.load().flatMap { try? JSONCoding.makeDecoder().decode(AutomationState.self, from: $0) } ?? AutomationState()
    }

    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) { changeHandler = handler }

    // MARK: - Configuration

    public var snapshot: AutomationState { state }
    public var queuedCount: Int { get async { await queue.count } }

    public func setConfig(_ config: AutomationConfig) {
        state.config = config.clamped
        persist()
    }

    public func setLastKnown(_ point: GeoPoint) {
        state.lastKnown = point
        persist(notify: false)
    }

    /// Replaces the cached places (after loading or editing them). Progress of places that no longer exist is dropped.
    public func setPlaces(_ places: [Place]) {
        let cached = places.compactMap(AutomationPlace.init)
        state.places = cached
        let ids = Set(cached.map { $0.id.uuidString })
        state.runtime = state.runtime.filter { ids.contains($0.key) }
        state.pendingLeaves = state.pendingLeaves.filter { ids.contains($0.key) }
        persist()
    }

    public func clearAll() async {
        state = AutomationState(config: state.config)
        await queue.removeAll()
        persist()
    }

    // MARK: - Signals

    @discardableResult
    public func regionEntered(_ placeId: UUID, at date: Date? = nil) async -> AutomationOutcome {
        let time = date ?? now()
        let outcome = enter(placeId, at: time, origin: .region, trigger: .regionEnter)
        if outcome.decision == .pendingStarted { _ = await evaluate() } // may already be due (late delivery); fast pass-by stays pending
        return outcome
    }

    @discardableResult
    public func regionExited(_ placeId: UUID, at date: Date? = nil) async -> AutomationOutcome {
        let outcome = await leave(placeId, at: date ?? now(), trigger: .regionExit)
        return outcome
    }

    /// Shortcuts "Arrive" automation. Same pipeline as the region signal.
    @discardableResult
    public func shortcutArrived(_ placeId: UUID) async -> AutomationOutcome {
        let outcome = enter(placeId, at: now(), origin: .shortcut, trigger: .shortcutArrive)
        await flush()
        return outcome
    }

    @discardableResult
    public func shortcutLeft(_ placeId: UUID) async -> AutomationOutcome {
        let outcome = await leave(placeId, at: now(), trigger: .shortcutLeave, explicit: true)
        // The user's own automation is the evidence of leaving: no wait and no location check, the timer is handled right away
        // (stopped in "Direkt", asked in "Vorschlag"). Without a running timer this is a harmless no-op. If the timer state
        // cannot be read (offline, nothing cached), the leave stays pending and the next wake-up finishes it.
        guard leaveStop != nil, let pending = state.pendingLeaves[placeId.uuidString] else { return outcome }
        if let handled = await checkLeave(pending, fix: nil, immediate: true) { return handled }
        return AutomationOutcome(decision: .leaveScheduled, placeName: outcome.placeName, mode: outcome.mode, dwellMinutes: nil)
    }

    /// Called when the system reports which regions currently contain the device (launch, after restart). A visit that
    /// the app believes is running but whose place does not contain the device any more ended while no exit event arrived.
    public func reconcile(insidePlaceIds: Set<UUID>) async {
        for place in state.places where runtimePhase(place.id) != .outside && !insidePlaceIds.contains(place.id) {
            _ = await leave(place.id, at: now(), trigger: .reconcile)
        }
    }

    /// Checks every due pending arrival with at most one location fix. Call on any wake-up (region callback, significant change,
    /// visit, background refresh, app start/foreground). Then sends what is queued.
    @discardableResult
    public func evaluate() async -> [AutomationOutcome] {
        var outcomes: [AutomationOutcome] = []
        let current = now()
        let due = state.places.filter { place in
            guard let runtime = state.runtime[place.id.uuidString], runtime.phase == .pending, let dueAt = runtime.dueAt else { return false }
            return current >= dueAt || current.timeIntervalSince(runtime.arrivedAt ?? current) > AutomationConfig.pendingExpiry
        }
        let dueLeaves = leaveStop == nil ? [] : state.pendingLeaves.values.filter { current >= $0.dueAt }.sorted { $0.dueAt < $1.dueAt }
        if !due.isEmpty || !dueLeaves.isEmpty {
            let fix = await location.currentFix()
            if let fix { state.lastKnown = GeoPoint(latitude: fix.latitude, longitude: fix.longitude) }
            let filter = ArrivalFilter(config: state.config, makeID: makeID)
            for place in due {
                var runtime = state.runtime[place.id.uuidString] ?? PlaceRuntimeState()
                let result = filter.check(&runtime, place: place, now: now(), verification: .from(fix: fix, place: place))
                state.runtime[place.id.uuidString] = runtime
                await apply(result, place: place, trigger: .check)
                outcomes.append(AutomationOutcome(decision: result.decision, placeName: place.name, mode: place.mode, dwellMinutes: nil))
            }
            if !dueLeaves.isEmpty { await flush() } // departure events first, so the server ends what it created before the app checks the timer
            for leave in dueLeaves { if let outcome = await checkLeave(leave, fix: fix) { outcomes.append(outcome) } }
        }
        await flush()
        return outcomes
    }

    /// Logs the answer to a "Timer stoppen?" question (the notification action runs outside the evaluation).
    public func recordLeaveAnswer(placeName: String, decision: AutomationDecision, detail: String?) {
        appendLog(placeName: placeName, trigger: .leaveCheck, decision: decision, confidence: nil, detail: detail)
        persist()
    }

    /// Earliest time a pending arrival becomes checkable (the platform schedules a background refresh for it).
    public func nextDueDate() -> Date? {
        (state.runtime.values.filter { $0.phase == .pending }.compactMap(\.dueAt) + state.pendingLeaves.values.map(\.dueAt)).min()
    }

    public func flush() async {
        guard await queue.count > 0 else { return }
        guard let sender = senderFactory() else { return } // no device token yet: events wait in the queue
        let summary = await queue.drain(using: sender)
        for report in summary.reports {
            let detail: String
            let decision: AutomationDecision
            switch report.outcome {
            case .sent(let kind): detail = kind.rawValue; decision = .sent
            case .dropped(let code): detail = code; decision = .dropped
            }
            appendLog(placeName: report.queued.placeName, trigger: .sync, decision: decision, confidence: nil, detail: "\(report.queued.event.type.rawValue): \(detail)")
        }
        switch summary.stop {
        case .unauthorized: appendLog(placeName: "", trigger: .sync, decision: .unauthorized, confidence: nil, detail: nil)
        case .retryLater: if await queue.count > 0 { appendLog(placeName: "", trigger: .sync, decision: .sendFailed, confidence: nil, detail: nil, coalesce: true) }
        case .finished: break
        }
        persist()
    }

    // MARK: - Internals

    private func runtimePhase(_ id: UUID) -> PlaceRuntimeState.Phase { state.runtime[id.uuidString]?.phase ?? .outside }

    private func enter(_ placeId: UUID, at time: Date, origin: ArrivalOrigin, trigger: LogTrigger) -> AutomationOutcome {
        guard let place = state.place(placeId) else { return AutomationOutcome(decision: .unknownPlace) }
        var runtime = state.runtime[placeId.uuidString] ?? PlaceRuntimeState()
        let filter = ArrivalFilter(config: state.config, makeID: makeID)
        let result = filter.enter(&runtime, place: place, at: time, origin: origin)
        state.runtime[placeId.uuidString] = runtime
        appendLog(placeName: place.name, trigger: trigger, decision: result.decision, confidence: nil, detail: nil)
        if state.pendingLeaves.removeValue(forKey: placeId.uuidString) != nil {
            // Back at the place before the wait ended: the user did not leave for good, the timer keeps running.
            appendLog(placeName: place.name, trigger: trigger, decision: .leaveReturned, confidence: nil, detail: "Wieder am Ort, Timer läuft weiter")
        }
        persist()
        return AutomationOutcome(decision: result.decision, placeName: place.name, mode: place.mode, dwellMinutes: Int((filter.dwell(for: place) / 60).rounded(.up)))
    }

    private func leave(_ placeId: UUID, at time: Date, trigger: LogTrigger, explicit: Bool = false) async -> AutomationOutcome {
        guard let place = state.place(placeId) else { return AutomationOutcome(decision: .unknownPlace) }
        var runtime = state.runtime[placeId.uuidString] ?? PlaceRuntimeState()
        let result = ArrivalFilter(config: state.config, makeID: makeID).exit(&runtime, place: place, at: time)
        state.runtime[placeId.uuidString] = runtime
        await apply(result, place: place, trigger: trigger)
        if leaveStop != nil {
            let planned = LeaveStopFilter(config: state.config).schedule(place: place, leftAt: time, exit: result, eventId: makeID(), explicit: explicit)
            if let leave = planned.leave { state.pendingLeaves[placeId.uuidString] = leave }
            if let decision = planned.decision {
                appendLog(placeName: place.name, trigger: trigger, decision: decision, confidence: nil,
                          detail: decision == .leaveScheduled ? "Timer wird nach \(state.config.leaveWaitMinutes) min außerhalb geprüft" : nil)
            }
            persist()
        }
        await flush()
        // A zero-length wait could be due right away; normally the next wake-up finds it.
        return AutomationOutcome(decision: result.decision, placeName: place.name, mode: place.mode, dwellMinutes: nil)
    }

    /// Final check of one leave: back inside, timer idle or restarted -> nothing; otherwise stop (direct) or ask (suggestion).
    /// The leave is taken out of the state while the platform acts, so a second `evaluate()` cannot handle it twice.
    private func checkLeave(_ leave: PendingLeave, fix: LocationFix?, immediate: Bool = false) async -> AutomationOutcome? {
        guard let leaveStop, state.pendingLeaves[leave.placeId.uuidString] == leave else { return nil }
        guard let place = state.place(leave.placeId) else {
            state.pendingLeaves.removeValue(forKey: leave.placeId.uuidString)
            persist()
            return nil
        }
        state.pendingLeaves.removeValue(forKey: leave.placeId.uuidString)
        let filter = LeaveStopFilter(config: state.config)
        // `immediate` (Shortcuts departure): treated as due, presence is not re-checked.
        let verification = immediate ? PresenceVerification.unavailable : PresenceVerification.from(fix: fix, place: place)
        let timer = (verification == .outside || verification == .unavailable) ? await leaveStop.observeTimer() : TimerObservation.unknown
        var check = filter.check(leave, place: place, now: immediate ? max(now(), leave.dueAt) : now(), verification: verification, timer: timer)
        var detail: String?
        let clock = LeaveStopFilter.clockText(leave.leftAt)
        switch check.action {
        case .stop:
            switch await leaveStop.stopTimer(eventId: leave.eventId, at: leave.leftAt) {
            case .stopped: detail = "Timer gestoppt um \(clock)"
            case .queued: check.decision = .leaveStopQueued; detail = "Stopp um \(clock) wartet auf Verbindung"
            case .alreadyGone: check.decision = .leaveNoTimer
            case .failed: check.keepWaiting = true
            }
        case .offer:
            detail = await leaveStop.offerStop(placeName: place.name, leftAt: leave.leftAt, eventId: leave.eventId)
                ? "Nachfrage gesendet: Stopp um \(clock)?" : "Mitteilungen nicht erlaubt, keine Nachfrage möglich"
        case .none:
            switch check.decision {
            case .leaveReturned: detail = "Wieder am Ort, Timer läuft weiter"
            case .leaveNoTimer: detail = "Kein Timer läuft"
            case .leaveTimerRestarted: detail = "Timer wurde nach dem Verlassen neu gestartet"
            case .leaveHandledByServer: detail = "Das Ende schlägt der Server vor"
            default: break
            }
        }
        if check.keepWaiting {
            state.pendingLeaves[leave.placeId.uuidString] = leave
            persist(notify: false)
            return nil
        }
        appendLog(placeName: place.name, trigger: .leaveCheck, decision: check.decision, confidence: nil, detail: detail)
        persist()
        return AutomationOutcome(decision: check.decision, placeName: place.name, mode: place.mode, dwellMinutes: nil)
    }

    private func apply(_ result: FilterResult, place: AutomationPlace, trigger: LogTrigger) async {
        for planned in result.events {
            await queue.enqueue(AutomationEventPayload(eventId: planned.eventId, deviceId: deviceId, placeId: place.id, type: planned.type, occurredAt: planned.occurredAt), placeName: place.name)
        }
        // Waiting is the normal case of a periodic check and would flood the log.
        if result.decision != .stillWaiting { appendLog(placeName: place.name, trigger: trigger, decision: result.decision, confidence: result.confidence, detail: nil) }
        persist()
    }

    private func appendLog(placeName: String, trigger: LogTrigger, decision: AutomationDecision, confidence: PresenceConfidence?, detail: String?, coalesce: Bool = false) {
        if coalesce, let last = state.log.last, last.decision == decision, last.trigger == trigger, now().timeIntervalSince(last.date) < 600 { return }
        state.log.append(AutomationLogEntry(id: makeID(), date: now(), placeName: placeName, trigger: trigger, decision: decision, confidence: confidence, detail: detail))
        if state.log.count > AutomationState.logLimit { state.log.removeFirst(state.log.count - AutomationState.logLimit) }
    }

    private func persist(notify: Bool = true) {
        if let data = try? JSONCoding.makeEncoder().encode(state) { stateStorage.save(data) }
        if notify { changeHandler?() }
    }
}

extension AutomationState {
    init(config: AutomationConfig) {
        self.init()
        self.config = config
    }
}
