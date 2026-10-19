import Foundation
import TimetrackCore

/// User-adjustable automation settings (stored on the device only).
public struct AutomationConfig: Codable, Sendable, Hashable {
    /// Master switch: off stops all monitoring and ignores shortcut events.
    public var enabled = true
    /// Presence must last this long after the arrival before anything is booked (pass-by protection), 2 to 15 minutes.
    public var dwellMinutes = 4
    /// After a booked visit ended, a new arrival at the same place within this time is ignored (GPS jitter), 10 to 60 minutes.
    public var cooldownMinutes = 10
    /// L4: after leaving a place, the running timer is only stopped when the device stayed outside this long (GPS jumps, short detours), 1 to 15 minutes.
    public var leaveWaitMinutes = 3
    /// L4: per-place override of "stop when leaving" (key: place id). Without an entry the default applies (on unless the place is off).
    public var stopOnLeaveOverrides: [String: Bool] = [:]

    public static let dwellRange = 2...15
    public static let leaveWaitRange = 1...15
    public static let cooldownRange = 10...60
    /// Above this speed (m/s, about 29 km/h) the device is considered to be driving past.
    public static let maxSpeed = 8.0
    /// A pending arrival that never resolved is dropped after this time.
    public static let pendingExpiry: TimeInterval = 12 * 3600

    public init() {}

    private enum CodingKeys: String, CodingKey { case enabled, dwellMinutes, cooldownMinutes, leaveWaitMinutes, stopOnLeaveOverrides }

    /// Tolerant decoding: stored settings from before L4 have no leave keys and must keep working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        dwellMinutes = try container.decodeIfPresent(Int.self, forKey: .dwellMinutes) ?? 4
        cooldownMinutes = try container.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 10
        leaveWaitMinutes = try container.decodeIfPresent(Int.self, forKey: .leaveWaitMinutes) ?? 3
        stopOnLeaveOverrides = try container.decodeIfPresent([String: Bool].self, forKey: .stopOnLeaveOverrides) ?? [:]
    }

    /// Whether leaving `place` stops (direct) or offers to stop (suggestion) a running timer. Default: on for every active place.
    public func stopsOnLeave(_ place: AutomationPlace) -> Bool {
        guard place.mode != .off else { return false }
        return stopOnLeaveOverrides[place.id.uuidString] ?? true
    }

    public var clamped: AutomationConfig {
        var copy = self
        copy.leaveWaitMinutes = min(max(leaveWaitMinutes, Self.leaveWaitRange.lowerBound), Self.leaveWaitRange.upperBound)
        copy.dwellMinutes = min(max(dwellMinutes, Self.dwellRange.lowerBound), Self.dwellRange.upperBound)
        copy.cooldownMinutes = min(max(cooldownMinutes, Self.cooldownRange.lowerBound), Self.cooldownRange.upperBound)
        return copy
    }
}

public enum ArrivalOrigin: String, Codable, Sendable, Hashable {
    /// Region monitoring of this app.
    case region
    /// A Shortcuts personal automation ("Arrive"/"Leave") calling the app intent.
    case shortcut
}

/// How sure the app is that the user really stayed. Not sent to the server (the contract has no field yet), kept in the log.
public enum PresenceConfidence: String, Codable, Sendable, Hashable {
    /// A location fix after the dwell time was inside the place and slow.
    case verified
    /// No fix possible, but the region stayed inside until the exit event (inside the whole time).
    case regionOnly
    /// The user's own Shortcuts automation triggered and no fix was possible.
    case trigger
}

/// Outcome of one evaluation step; stored in the log and mapped to German texts by the UI.
public enum AutomationDecision: String, Codable, Sendable, Hashable {
    case pendingStarted, alreadyInside, cooldown, modeOff, globalOff, unknownPlace
    case stillWaiting, speedTooHigh, passBy, outsideAtCheck, expired
    case confirmed, confirmedOnExit, departureQueued, noArrival
    case sent, sendFailed, dropped, unauthorized
    /// L4 (stop when leaving): scheduled, back inside, no timer, timer restarted, stopped, queued offline, offered, failed, expired.
    case leaveScheduled, leaveReturned, leaveNoTimer, leaveTimerRestarted, leaveStopped, leaveStopQueued, leaveOffered, leaveHandledByServer, leaveExpired, leaveStayTooShort
}

public struct PlannedEvent: Sendable, Hashable {
    public let eventId: UUID
    public let type: AutomationEventType
    public let occurredAt: Date
}

public struct FilterResult: Sendable, Hashable {
    public var decision: AutomationDecision
    public var events: [PlannedEvent] = []
    public var confidence: PresenceConfidence?
    /// How long the device was inside the place before this exit (nil: unknown, e.g. the app never saw the entry).
    public var stay: TimeInterval?
}

/// Where the device is relative to a place at check time.
public enum PresenceVerification: Sendable, Hashable {
    case inside(speed: Double?)
    case outside
    case unavailable

    /// Fixes are noisy: inside means within the radius plus the accuracy (capped); outside only when clearly beyond it.
    public static func from(fix: LocationFix?, place: AutomationPlace) -> PresenceVerification {
        guard let fix, fix.horizontalAccuracy >= 0, let center = place.center else { return .unavailable }
        let distance = GeoPoint(latitude: fix.latitude, longitude: fix.longitude).distance(to: center)
        let radius = Double(place.monitoringRadius)
        if distance <= radius + min(fix.horizontalAccuracy, 100) { return .inside(speed: fix.speed) }
        if distance > radius + 100 + min(fix.horizontalAccuracy, 200) { return .outside }
        return .unavailable
    }
}

/// One-shot location result (never a stream).
public struct LocationFix: Sendable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double
    /// m/s; nil or negative when unknown.
    public var speed: Double?
    public var timestamp: Date

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, speed: Double? = nil, timestamp: Date = .now) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed.flatMap { $0 >= 0 ? $0 : nil }
        self.timestamp = timestamp
    }
}

/// Per-place progress of the current visit.
public struct PlaceRuntimeState: Codable, Sendable, Hashable {
    public enum Phase: String, Codable, Sendable, Hashable { case outside, pending, confirmed }

    public var phase: Phase = .outside
    public var origin: ArrivalOrigin = .region
    public var arrivedAt: Date?
    public var dueAt: Date?
    public var arrivalEventId: UUID?
    /// End of the last confirmed visit; starts the cooldown.
    public var lastDepartureAt: Date?
    /// L4: first time the device was seen inside the place for the current stay, whether or not the arrival filter accepted it
    /// (cooldown, mode off). Used to tell a pass-by from a real stay when leaving.
    public var enteredAt: Date?

    public init() {}

    private enum CodingKeys: String, CodingKey { case phase, origin, arrivedAt, dueAt, arrivalEventId, lastDepartureAt, enteredAt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decodeIfPresent(Phase.self, forKey: .phase) ?? .outside
        origin = try container.decodeIfPresent(ArrivalOrigin.self, forKey: .origin) ?? .region
        arrivedAt = try container.decodeIfPresent(Date.self, forKey: .arrivedAt)
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        arrivalEventId = try container.decodeIfPresent(UUID.self, forKey: .arrivalEventId)
        lastDepartureAt = try container.decodeIfPresent(Date.self, forKey: .lastDepartureAt)
        enteredAt = try container.decodeIfPresent(Date.self, forKey: .enteredAt)
    }
}

/// Pure decision logic. A location signal is never booked directly: an arrival becomes "pending", and only presence that lasted
/// the dwell time (verified by a fix, or inferred from an exit after the dwell time) emits the events the backend turns into
/// a segment or suggestion. Driving past (exit before the dwell time, a fast or distant fix) emits nothing.
public struct ArrivalFilter: Sendable {
    public var config: AutomationConfig
    private let makeID: @Sendable () -> UUID

    public init(config: AutomationConfig, makeID: @escaping @Sendable () -> UUID = { UUID() }) {
        self.config = config.clamped
        self.makeID = makeID
    }

    /// Effective dwell: the user's setting, but never shorter than the place's server-side confirmation time (else the backend ignores it).
    public func dwell(for place: AutomationPlace) -> TimeInterval {
        max(TimeInterval(config.dwellMinutes) * 60, TimeInterval(place.confirmAfterSeconds))
    }

    public func enter(_ state: inout PlaceRuntimeState, place: AutomationPlace, at: Date, origin: ArrivalOrigin) -> FilterResult {
        if state.enteredAt == nil { state.enteredAt = at }
        guard config.enabled else { return FilterResult(decision: .globalOff) }
        guard place.mode != .off else { return FilterResult(decision: .modeOff) }
        guard state.phase == .outside else { return FilterResult(decision: .alreadyInside) }
        if let last = state.lastDepartureAt, at.timeIntervalSince(last) < TimeInterval(config.cooldownMinutes) * 60 {
            return FilterResult(decision: .cooldown)
        }
        state.phase = .pending
        state.origin = origin
        state.arrivedAt = at
        state.dueAt = at.addingTimeInterval(dwell(for: place))
        state.arrivalEventId = makeID()
        return FilterResult(decision: .pendingStarted)
    }

    /// Re-evaluates a pending arrival. `now` before the due time changes nothing.
    public func check(_ state: inout PlaceRuntimeState, place: AutomationPlace, now: Date, verification: PresenceVerification) -> FilterResult {
        guard state.phase == .pending, let arrivedAt = state.arrivedAt, let dueAt = state.dueAt else { return FilterResult(decision: .stillWaiting) }
        guard config.enabled else {
            reset(&state)
            return FilterResult(decision: .globalOff)
        }
        if now.timeIntervalSince(arrivedAt) > AutomationConfig.pendingExpiry {
            reset(&state)
            return FilterResult(decision: .expired)
        }
        guard now >= dueAt else { return FilterResult(decision: .stillWaiting) }
        switch verification {
        case .outside:
            reset(&state)
            return FilterResult(decision: .outsideAtCheck)
        case .inside(let speed):
            if let speed, speed > AutomationConfig.maxSpeed { return FilterResult(decision: .speedTooHigh) }
            return confirm(&state, place: place, arrivedAt: arrivedAt, presenceAt: now, confidence: .verified)
        case .unavailable:
            // A shortcut trigger is the user's own evidence; our own region needs the exit event or a later fix.
            guard state.origin == .shortcut else { return FilterResult(decision: .stillWaiting) }
            return confirm(&state, place: place, arrivedAt: arrivedAt, presenceAt: now, confidence: .trigger)
        }
    }

    public func exit(_ state: inout PlaceRuntimeState, place: AutomationPlace, at: Date) -> FilterResult {
        let stay = state.enteredAt.map { at.timeIntervalSince($0) }
        state.enteredAt = nil
        var result = exitVisit(&state, place: place, at: at)
        result.stay = stay
        return result
    }

    private func exitVisit(_ state: inout PlaceRuntimeState, place: AutomationPlace, at: Date) -> FilterResult {
        switch state.phase {
        case .outside:
            return FilterResult(decision: .noArrival)
        case .pending:
            guard let arrivedAt = state.arrivedAt, let dueAt = state.dueAt, at >= dueAt, config.enabled else {
                reset(&state)
                return FilterResult(decision: .passBy)
            }
            // The device was inside from the arrival until now (a region reports an exit only when it left), so the visit is real.
            var result = confirm(&state, place: place, arrivedAt: arrivedAt, presenceAt: dueAt, confidence: state.origin == .shortcut ? .trigger : .regionOnly)
            result.events.append(PlannedEvent(eventId: makeID(), type: .departure, occurredAt: at))
            result.decision = .confirmedOnExit
            end(&state, at: at)
            return result
        case .confirmed:
            end(&state, at: at)
            return FilterResult(decision: .departureQueued, events: [PlannedEvent(eventId: makeID(), type: .departure, occurredAt: at)])
        }
    }

    private func confirm(_ state: inout PlaceRuntimeState, place: AutomationPlace, arrivedAt: Date, presenceAt: Date, confidence: PresenceConfidence) -> FilterResult {
        let arrivalId = state.arrivalEventId ?? makeID()
        let earliest = arrivedAt.addingTimeInterval(TimeInterval(place.confirmAfterSeconds))
        state.phase = .confirmed
        let events = [
            PlannedEvent(eventId: arrivalId, type: .arrival, occurredAt: arrivedAt),
            PlannedEvent(eventId: makeID(), type: .presenceConfirmed, occurredAt: max(presenceAt, earliest)),
        ]
        return FilterResult(decision: .confirmed, events: events, confidence: confidence)
    }

    private func reset(_ state: inout PlaceRuntimeState) {
        state.phase = .outside
        state.arrivedAt = nil
        state.dueAt = nil
        state.arrivalEventId = nil
    }

    private func end(_ state: inout PlaceRuntimeState, at: Date) {
        reset(&state)
        state.lastDepartureAt = at
    }
}
