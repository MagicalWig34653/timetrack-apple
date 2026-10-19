#if os(iOS)
import ActivityKit
import Foundation
import TimetrackCore

/// Live Activity for a running or paused timer. Time and progress tick through `Text(timerInterval:)` / `ProgressView(timerInterval:)`;
/// there are no push updates. The content state is the pure `LiveActivityTarget` (LA1).
struct TimerActivityAttributes: ActivityAttributes {
    typealias ContentState = LiveActivityTarget
}

enum TimerLiveActivity {
    private static let gate = SerialGate()
    private static let outcomes = LiveActivityOutcomeStore()

    /// Makes the activities mirror `running` (see `LiveActivityReconciler`). Ending and updating work in any process state;
    /// `Activity.request` only works while the app is in the foreground. A start that iOS refuses (typical for a Focus callback,
    /// a background refresh or a background launch) is recorded as `startDeferred` and repeated by the next reconcile when the app
    /// becomes active (`reconcileFromSnapshot`). The result is kept for the Focus page.
    @discardableResult
    static func sync(target desired: LiveActivityTarget?, source: String) async -> LiveActivityOutcome {
        let outcome = await gate.run { await apply(desired: desired, source: source) }
        outcomes.write(outcome)
        // OT1: every timer change passes here with the snapshot already written (app, intents, Live Activity buttons, Focus filter, sign-out).
        await OverworkScheduler.sync(snapshot: WidgetSnapshotStore().read())
        return outcome
    }

    /// Reconciles from the shared widget snapshot (no network). Called when the app becomes active, so an activity that could not
    /// be requested in the background appears as soon as the app is in front.
    @discardableResult
    static func reconcileFromSnapshot(source: String = "foreground") async -> LiveActivityOutcome {
        await sync(target: .desired(snapshot: WidgetSnapshotStore().read(), pause: PauseMarkerStore().read()), source: source)
    }

    private static func apply(desired: LiveActivityTarget?, source: String) async -> LiveActivityOutcome {
        let alive = Activity<TimerActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        let existing = alive.map { LiveActivityExisting(id: $0.id, target: $0.content.state) }
        let plan = LiveActivityReconciler.plan(desired: desired, existing: existing)

        for id in plan.end { await alive.first { $0.id == id }?.end(nil, dismissalPolicy: .immediate) }
        if let update = plan.update, let id = plan.keep, let activity = alive.first(where: { $0.id == id }) {
            await activity.update(.init(state: update, staleDate: nil))
            return LiveActivityOutcome(result: .updated, source: source)
        }
        if let start = plan.start {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                return LiveActivityOutcome(result: .disabled, source: source, detail: "Live Activities sind für Timetrack ausgeschaltet.")
            }
            do {
                _ = try Activity.request(attributes: TimerActivityAttributes(), content: .init(state: start, staleDate: nil), pushType: nil)
                return LiveActivityOutcome(result: .started, source: source)
            } catch {
                // Typical when not in the foreground (ActivityAuthorizationError.visibility); retried when the app becomes active.
                return LiveActivityOutcome(result: source == "foreground" ? .startFailed : .startDeferred, source: source, detail: "\(error)")
            }
        }
        if desired == nil { return LiveActivityOutcome(result: plan.end.isEmpty ? .none : .ended, source: source) }
        return LiveActivityOutcome(result: .kept, source: source)
    }
}
#endif
