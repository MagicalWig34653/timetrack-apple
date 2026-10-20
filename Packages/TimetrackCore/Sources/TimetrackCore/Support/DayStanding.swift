import Foundation

// UX3: pure rules for what the "Heute" card and day rows say about the target. The numbers come from the backend; this only
// decides which of them are shown, so a morning without an entry or a future day never reads like a deficit.

/// How far today is from its target, in the words the card uses ("noch 0:26 bis Soll", "0:12 über Soll").
public struct DayStanding: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// No target today (weekend, holiday, absence): no ring, no remaining time.
        case noTarget
        /// A target exists but nothing was recorded yet: say nothing about a difference.
        case notStarted
        /// Seconds still missing to the target.
        case remaining(Int)
        case reached
        /// Seconds beyond the target.
        case over(Int)
    }

    public let doneSeconds: Int
    public let targetSeconds: Int
    public let status: Status

    /// `hasStarted`: a segment runs or exists today (also a zero-length one).
    public init(doneSeconds: Int, targetSeconds: Int, hasStarted: Bool) {
        self.doneSeconds = max(0, doneSeconds)
        self.targetSeconds = max(0, targetSeconds)
        if self.targetSeconds == 0 {
            status = .noTarget
        } else if !hasStarted && self.doneSeconds == 0 {
            status = .notStarted
        } else {
            // Within a minute of the target counts as reached (durations are shown in whole minutes).
            let missing = self.targetSeconds - self.doneSeconds
            if abs(missing) < 60 { status = .reached } else if missing > 0 { status = .remaining(missing) } else { status = .over(-missing) }
        }
    }

    /// The ring only exists for days with a target.
    public var showsRing: Bool { targetSeconds > 0 }

    /// 0...1 for the ring.
    public var progress: Double { targetSeconds > 0 ? min(1, Double(doneSeconds) / Double(targetSeconds)) : 0 }
}

/// Difference line of a day in lists (Zeit tab, calendar): never a warning for the future or for a day that has barely begun.
public enum DayDeltaPolicy {
    public enum Presentation: Equatable, Sendable {
        /// Nothing to show (future, no target, nothing recorded yet, exactly on target).
        case hidden
        /// Neutral information, e.g. "noch 1:30 offen" on the current day.
        case open(Int)
        /// Past day with less than the target: the only case that earns the warning colour.
        case deficit(Int)
        /// Beyond the target (past or current day), positive.
        case surplus(Int)
    }

    /// `delta` = done - target in seconds (the backend's day delta). Past days (`day < today`) show the final difference,
    /// the current day shows what is still open without alarm, future days show nothing.
    public static func presentation(day: LocalDay, today: LocalDay, doneSeconds: Int, targetSeconds: Int, hasStarted: Bool) -> Presentation {
        guard targetSeconds > 0 || doneSeconds > 0, day <= today else { return .hidden }
        let delta = doneSeconds - targetSeconds
        let minutes = abs(delta) / 60
        if day == today {
            guard hasStarted || doneSeconds > 0 else { return .hidden }
            if minutes == 0 { return .hidden }
            return delta < 0 ? .open(-delta) : .surplus(delta)
        }
        if minutes == 0 { return .hidden }
        return delta < 0 ? .deficit(-delta) : .surplus(delta)
    }
}

/// What the small status line under the title says about delivery of timer actions.
public enum SyncStatus: Equatable, Sendable {
    case ok
    /// Actions wait for delivery and the server answers (or has not been asked yet).
    case sending(Int)
    /// The server cannot be reached; `pending` actions are kept on the device.
    case offline(pending: Int)

    public init(pending: Int, networkError: Bool) {
        if networkError { self = .offline(pending: pending) }
        else if pending > 0 { self = .sending(pending) }
        else { self = .ok }
    }
}
