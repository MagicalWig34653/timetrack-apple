import Foundation

/// H3: what the "Jetzt" sheet and the top of "Heute" say about the rest of the day: live worked time, the time until the target,
/// the expected end of the day and the break status. Pure rules; the numbers come from the backend's day evaluation, nothing is booked.
/// Break hints follow the same constants as the overwork notifications (ADR-0004, profile `arbzg-adult-de`) and only use actual times:
/// a break that was not taken is never invented.
public struct DayOutlook: Equatable, Sendable {
    public enum End: Equatable, Sendable {
        /// Nothing known (no target, no plan, timer not running).
        case unknown
        /// Planned end from the plan day (a plan, not a booking).
        case planned(Date)
        /// When the target is reached if the work timer keeps running.
        case estimated(Date)
        case reached
    }

    public enum BreakStatus: Equatable, Sendable {
        /// Nothing to say (little work, no break yet).
        case none
        /// Enough break time for the work so far (seconds of actual breaks).
        case taken(Int)
        /// The next break threshold is `seconds` of work away (needs `required` seconds of break in total).
        case dueIn(seconds: Int, required: Int)
        /// The threshold is passed and the actual breaks do not reach the required total.
        case missing(required: Int, taken: Int)
    }

    /// Work of today including the running work segment up to `now`.
    public let workedSeconds: Int
    public let targetSeconds: Int
    /// Seconds to the target; nil without a target, 0 when reached.
    public let remainingSeconds: Int?
    public let end: End
    public let breakStatus: BreakStatus
    /// Sum of the gaps between today's segments of at least 15 minutes.
    public let takenBreakSeconds: Int

    /// - Parameters:
    ///   - doneAtLoad: evaluated work plus school credit as the server reported it at `loadedAt` (it includes the open segment up to then).
    ///   - plannedEnd: planned end of today from the plan day, if any.
    public init(now: Date, running: Segment?, segments: [Segment], doneAtLoad: Int, loadedAt: Date?, targetSeconds: Int, plannedEnd: Date? = nil) {
        let runsWork = running.map { $0.kind != .travel && $0.kind != .school } ?? false
        var live = max(0, doneAtLoad)
        if runsWork, let running, let loadedAt {
            live += max(0, Int(now.timeIntervalSince(max(loadedAt, running.startedAt))))
        }
        workedSeconds = live
        self.targetSeconds = max(0, targetSeconds)
        let remaining = self.targetSeconds > 0 ? max(0, self.targetSeconds - live) : nil
        remainingSeconds = remaining

        if self.targetSeconds == 0 && plannedEnd == nil {
            end = .unknown
        } else if let remaining, remaining < 60, live > 0 {
            end = .reached
        } else if let plannedEnd, plannedEnd > now {
            end = .planned(plannedEnd)
        } else if runsWork, let remaining, remaining > 0 {
            end = .estimated(now.addingTimeInterval(TimeInterval(remaining)))
        } else {
            end = .unknown
        }

        let taken = Self.takenBreakSeconds(segments: segments)
        takenBreakSeconds = taken
        let rules = OverworkRules.self
        if live >= rules.secondBreakAfterSeconds {
            breakStatus = taken >= rules.secondBreakRequiredSeconds ? .taken(taken) : .missing(required: rules.secondBreakRequiredSeconds, taken: taken)
        } else if live >= rules.firstBreakAfterSeconds {
            breakStatus = taken >= rules.firstBreakRequiredSeconds ? .taken(taken) : .missing(required: rules.firstBreakRequiredSeconds, taken: taken)
        } else if taken >= rules.minimumBreakPartSeconds {
            breakStatus = .taken(taken)
        } else if runsWork, live > 0 {
            breakStatus = .dueIn(seconds: rules.firstBreakAfterSeconds - live, required: rules.firstBreakRequiredSeconds)
        } else {
            breakStatus = .none
        }
    }

    /// Gaps between consecutive segments of at least the minimum break part; before the first and after the last segment there is no break.
    public static func takenBreakSeconds(segments: [Segment]) -> Int {
        let ordered = segments.filter { !$0.voided }.sorted { $0.startedAt < $1.startedAt }
        var total = 0
        var coveredUntil: Date?
        for segment in ordered {
            if let covered = coveredUntil {
                let gap = Int(segment.startedAt.timeIntervalSince(covered))
                if gap >= OverworkRules.minimumBreakPartSeconds { total += gap }
            }
            guard let ended = segment.endedAt else { break }
            coveredUntil = max(coveredUntil ?? ended, ended)
        }
        return total
    }
}

/// H3: the gap since the last stopped entry of today, for "Pause seit 12:10 · Weiter" (a pause is a gap: stop, later start).
public struct PauseGap: Equatable, Sendable {
    public let since: Date
    public let kind: SegmentKind

    /// The last finished, non-voided entry of today when nothing runs; nil otherwise.
    public init?(running: Segment?, segments: [Segment]) {
        guard running == nil, let last = segments.filter({ !$0.voided && $0.endedAt != nil }).max(by: { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }),
              let ended = last.endedAt else { return nil }
        since = ended
        kind = last.kind
    }

    public func seconds(at now: Date) -> Int { max(0, Int(now.timeIntervalSince(since))) }
}
