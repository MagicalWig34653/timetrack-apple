import Foundation
import TimetrackCore

/// One-shot location lookup supplied by the platform layer (`requestLocation()` with 100 m accuracy). Never a stream.
public protocol LocationFixProviding: Sendable {
    func currentFix() async -> LocationFix?
}

public enum LogTrigger: String, Codable, Sendable, Hashable {
    case regionEnter, regionExit, check, reconcile, shortcutArrive, shortcutLeave, sync
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

    public init() {}

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
    private var state: AutomationState
    private var changeHandler: (@Sendable () -> Void)?

    public init(storage: BlobStorage, queue: AutomationEventQueue, location: LocationFixProviding, deviceId: String,
                senderFactory: @escaping @Sendable () -> AutomationEventSending?,
                now: @escaping @Sendable () -> Date = { .now }, makeID: @escaping @Sendable () -> UUID = { UUID() }) {
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
        await leave(placeId, at: now(), trigger: .shortcutLeave)
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
        if !due.isEmpty {
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
        }
        await flush()
        return outcomes
    }

    /// Earliest time a pending arrival becomes checkable (the platform schedules a background refresh for it).
    public func nextDueDate() -> Date? { state.runtime.values.filter { $0.phase == .pending }.compactMap(\.dueAt).min() }

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
        persist()
        return AutomationOutcome(decision: result.decision, placeName: place.name, mode: place.mode, dwellMinutes: Int((filter.dwell(for: place) / 60).rounded(.up)))
    }

    private func leave(_ placeId: UUID, at time: Date, trigger: LogTrigger) async -> AutomationOutcome {
        guard let place = state.place(placeId) else { return AutomationOutcome(decision: .unknownPlace) }
        var runtime = state.runtime[placeId.uuidString] ?? PlaceRuntimeState()
        let result = ArrivalFilter(config: state.config, makeID: makeID).exit(&runtime, place: place, at: time)
        state.runtime[placeId.uuidString] = runtime
        await apply(result, place: place, trigger: trigger)
        await flush()
        return AutomationOutcome(decision: result.decision, placeName: place.name, mode: place.mode, dwellMinutes: nil)
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
