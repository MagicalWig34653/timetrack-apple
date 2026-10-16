#if os(iOS)
import ActivityKit
import Foundation
import TimetrackCore

/// Live Activity for a running timer. The timer ticks through `Text(timerInterval:)`; there are no push updates.
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var kind: SegmentKind
        var startedAt: Date
    }
}

enum TimerLiveActivity {
    /// Starts, keeps or ends the activity so it mirrors `running`. Activities can only be requested while the app can run
    /// (foreground, or a `LiveActivityIntent` executing in the app process); a failed request is not an error for the timer.
    static func sync(running: (startedAt: Date, kind: SegmentKind)?) async {
        let existing = Activity<TimerActivityAttributes>.activities
        guard let running else {
            for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let state = TimerActivityAttributes.ContentState(kind: running.kind, startedAt: running.startedAt)
        if let current = existing.first(where: { $0.content.state == state }) {
            for activity in existing where activity.id != current.id { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(attributes: TimerActivityAttributes(), content: .init(state: state, staleDate: nil), pushType: nil)
    }
}
#endif
