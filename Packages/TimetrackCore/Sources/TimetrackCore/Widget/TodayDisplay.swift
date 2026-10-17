import Foundation

/// What the compact "Heute" screen (watch) shows, independent of where the numbers came from.
///
/// Three layers, newest wins: live server data, then actions still waiting in the offline queue (optimistic), and before
/// either exists the last cached `WidgetSnapshot`, so the screen has content on the first frame.
public struct TodayDisplay: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// Nothing known yet (first launch, no snapshot).
        case empty
        /// From the cached snapshot; a refresh is on its way.
        case cached
        case live
    }

    public var source: Source
    public var isRunning: Bool
    public var kind: SegmentKind
    public var startedAt: Date?
    /// Finished work of today (evaluated work plus credits), without the running segment.
    public var doneSeconds: Int
    public var targetSeconds: Int
    public var balanceSeconds: Int?
    public var provisional: Bool
    public var segments: [WidgetSegment]
    /// Number of start/stop actions waiting for delivery ("wird gesendet ...").
    public var pendingActions: Int
    public var updatedAt: Date?

    public init(source: Source = .empty, isRunning: Bool = false, kind: SegmentKind = .work, startedAt: Date? = nil, doneSeconds: Int = 0,
                targetSeconds: Int = 0, balanceSeconds: Int? = nil, provisional: Bool = false, segments: [WidgetSegment] = [],
                pendingActions: Int = 0, updatedAt: Date? = nil) {
        self.source = source
        self.isRunning = isRunning
        self.kind = kind
        self.startedAt = startedAt
        self.doneSeconds = doneSeconds
        self.targetSeconds = targetSeconds
        self.balanceSeconds = balanceSeconds
        self.provisional = provisional
        self.segments = segments
        self.pendingActions = pendingActions
        self.updatedAt = updatedAt
    }

    /// Display from a cached snapshot. Totals of an earlier day are dropped (a new day starts at zero); a running timer is kept
    /// because it is still running unless the refresh says otherwise.
    public static func cached(_ snapshot: WidgetSnapshot?, now: Date = .now) -> TodayDisplay {
        guard let snapshot, snapshot.updatedAt != .distantPast else { return TodayDisplay() }
        let sameDay = snapshot.todaySeconds(at: now) != nil
        return TodayDisplay(
            source: .cached, isRunning: snapshot.isRunning, kind: snapshot.kind, startedAt: snapshot.startedAt,
            doneSeconds: sameDay ? snapshot.todaySeconds : 0, targetSeconds: sameDay ? (snapshot.targetSeconds ?? 0) : 0,
            balanceSeconds: snapshot.balanceSeconds, segments: sameDay ? (snapshot.segments ?? []) : [], updatedAt: snapshot.updatedAt
        )
    }

    /// Display from loaded server data.
    public static func live(running: Segment?, day: DayEvaluation?, account: TimeAccount?, segments: [Segment], updatedAt: Date?) -> TodayDisplay {
        TodayDisplay(
            source: .live, isRunning: running != nil, kind: running?.kind ?? .work, startedAt: running?.startedAt,
            doneSeconds: (day?.evaluatedWorkSeconds ?? 0) + (day?.creditSeconds ?? 0), targetSeconds: day?.targetSeconds ?? 0,
            balanceSeconds: account?.balanceSeconds, provisional: day?.provisional == true,
            segments: segments.map { WidgetSegment(kind: $0.kind, startedAt: $0.startedAt, endedAt: $0.endedAt) }, updatedAt: updatedAt
        )
    }

    /// Applies queued actions on top (oldest first), so a start or stop pressed offline is visible at once.
    public func applying(_ pending: [QueuedTimerAction]) -> TodayDisplay {
        guard !pending.isEmpty else { return self }
        var result = self
        result.pendingActions = pending.count
        for action in pending {
            switch action.command {
            case .start(let kind):
                result.isRunning = true
                result.kind = kind
                result.startedAt = action.queuedAt
            case .stop:
                if result.isRunning, let start = result.startedAt {
                    result.doneSeconds += max(0, Int(action.queuedAt.timeIntervalSince(start)))
                }
                result.isRunning = false
                result.startedAt = nil
            }
        }
        return result
    }
}
