import Foundation
import TimetrackCore

// L4: stop (or offer to stop) a running timer when the user leaves a place.
//
// The backend cannot do this for a manually started timer: its `departure` event only ends segments created by the automation
// (or confirmed suggestions) and answers `needs_review` / `ignored` without a preceding `arrival` (see docs/handoffs/L4.md).
// So the app decides locally, after a wait and one location check, and then uses the normal stop path
// (`POST /time/timer/stop`, idempotent over a stable `clientEventId`, via the persistent `TimerActionQueue`, which corrects the
// end back to the time of leaving when the delivery is late).

/// What the app knows about the timer at check time.
public enum TimerObservation: Sendable, Equatable {
    case running(startedAt: Date, source: SegmentSource)
    case idle
    /// Neither the server nor a local snapshot could tell (offline, nothing cached): check again later.
    case unknown
}

public enum LeaveStopResult: Sendable, Equatable {
    /// The server stopped the timer (end corrected to the leave time).
    case stopped
    /// Offline: the stop waits in the retry queue with its stable event id.
    case queued
    /// The timer was already gone when the stop was sent.
    case alreadyGone
    case failed
}

/// Platform side of "stop when leaving": observing the timer, stopping it, asking the user. Implemented in the iOS app.
public protocol LeaveStopActing: Sendable {
    func observeTimer() async -> TimerObservation
    /// Stops the running timer, ended at `at` (the time of leaving). `eventId` is the idempotency key.
    func stopTimer(eventId: UUID, at: Date) async -> LeaveStopResult
    /// Posts "Du hast {Ort} verlassen – Timer stoppen?" with a Stop action. Returns false when notifications are not allowed.
    func offerStop(placeName: String, leftAt: Date, eventId: UUID) async -> Bool
}

/// A leave that waits for its check. One per place; persisted so that a relaunch finishes it.
public struct PendingLeave: Codable, Sendable, Hashable {
    public var placeId: UUID
    public var leftAt: Date
    public var dueAt: Date
    /// Stable id of the eventual stop (`clientEventId`), so retries and repeated answers never stop twice.
    public var eventId: UUID
    /// The `departure` event of a confirmed visit was queued for the server, which handles segments it created itself.
    public var visitReported: Bool
}

public enum LeaveAction: Sendable, Equatable {
    case none, stop, offer
}

public struct LeaveCheck: Sendable, Equatable {
    public var decision: AutomationDecision
    public var action: LeaveAction = .none
    /// Not final: check again at the next wake-up.
    public var keepWaiting = false
}

/// Pure decision logic of "stop when leaving".
public struct LeaveStopFilter: Sendable {
    public var config: AutomationConfig

    public init(config: AutomationConfig) { self.config = config.clamped }

    public func wait(for place: AutomationPlace) -> TimeInterval { TimeInterval(config.leaveWaitMinutes) * 60 }

    /// Called after the arrival filter handled an exit. Returns the leave to wait for, or the reason there is none (nil: silent).
    public func schedule(place: AutomationPlace, leftAt: Date, exit: FilterResult, eventId: UUID) -> (leave: PendingLeave?, decision: AutomationDecision?) {
        guard config.enabled, config.stopsOnLeave(place) else { return (nil, nil) }
        switch exit.decision {
        case .noArrival, .departureQueued, .confirmedOnExit: break
        default: return (nil, nil) // pass-by or anything else: no stay, nothing to stop
        }
        // A stay shorter than the dwell time is a pass-by even if the arrival was never booked (cooldown, entry missed).
        let dwell = max(TimeInterval(config.dwellMinutes) * 60, TimeInterval(place.confirmAfterSeconds))
        if let stay = exit.stay, stay < dwell { return (nil, .leaveStayTooShort) }
        let leave = PendingLeave(placeId: place.id, leftAt: leftAt, dueAt: leftAt.addingTimeInterval(wait(for: place)), eventId: eventId,
                                 visitReported: exit.decision != .noArrival)
        return (leave, .leaveScheduled)
    }

    /// Whether a running timer may be stopped for a leave at `leftAt`: it must have started before leaving.
    public static func timerDecision(_ timer: TimerObservation, leftAt: Date) -> AutomationDecision? {
        switch timer {
        case .unknown: nil
        case .idle: .leaveNoTimer
        case .running(let startedAt, _): startedAt > leftAt ? .leaveTimerRestarted : nil
        }
    }

    public func check(_ leave: PendingLeave, place: AutomationPlace, now: Date, verification: PresenceVerification, timer: TimerObservation) -> LeaveCheck {
        guard now >= leave.dueAt else { return LeaveCheck(decision: .stillWaiting, keepWaiting: true) }
        guard config.enabled, config.stopsOnLeave(place) else { return LeaveCheck(decision: .modeOff) }
        if now.timeIntervalSince(leave.leftAt) > AutomationConfig.pendingExpiry { return LeaveCheck(decision: .leaveExpired) }
        // Back at the place (or the fix is within it): a detour or a jumping signal, not a leave.
        if case .inside = verification { return LeaveCheck(decision: .leaveReturned) }
        if timer == .unknown { return LeaveCheck(decision: .stillWaiting, keepWaiting: true) }
        if let blocked = Self.timerDecision(timer, leftAt: leave.leftAt) { return LeaveCheck(decision: blocked) }
        guard case .running(_, let source) = timer else { return LeaveCheck(decision: .leaveNoTimer) }
        switch place.mode {
        case .direct:
            return LeaveCheck(decision: .leaveStopped, action: .stop)
        case .suggest:
            // The server already proposes the end of a segment it created itself (`departure` of a confirmed visit).
            if leave.visitReported, source == .automation || source == .suggestion { return LeaveCheck(decision: .leaveHandledByServer) }
            return LeaveCheck(decision: .leaveOffered, action: .offer)
        case .off:
            return LeaveCheck(decision: .modeOff)
        }
    }

    /// "17:02" in the device's time zone (log text).
    public static func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
