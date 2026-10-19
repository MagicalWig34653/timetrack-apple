import Foundation
import Testing
@testable import TimetrackCore

@Suite("Live Activity state, progress, planned end and controls (LA1)")
struct LiveActivityPauseTests {
    let zone = TimeZone(identifier: "Europe/Berlin")!
    /// 2026-10-19 10:00 Berlin (Monday).
    var now: Date { DayCalendar(timeZone: zone).instant(day: "2026-10-19", hour: 10, minute: 0)! }

    func snapshot(running: Bool, startedMinutesAgo: Int = 30, worked: Int = 7_200, target: Int? = 28_800, kind: SegmentKind = .work,
                  plannedEnd: Date? = nil, plannedSeconds: Int? = nil, accent: String? = nil) -> WidgetSnapshot {
        WidgetSnapshot(isRunning: running, kind: kind, startedAt: running ? now.addingTimeInterval(-Double(startedMinutesAgo) * 60) : nil,
                       todaySeconds: worked, day: "2026-10-19", timeZone: zone.identifier, updatedAt: now, targetSeconds: target,
                       accentHex: accent, plannedEnd: plannedEnd, plannedSeconds: plannedSeconds)
    }

    // MARK: Desired state

    @Test func runningSnapshotGivesRunningTargetWithPlanAndAccent() throws {
        let end = now.addingTimeInterval(7 * 3600)
        let target = try #require(LiveActivityTarget.desired(snapshot: snapshot(running: true, plannedEnd: end, plannedSeconds: 27_000, accent: "#0A84FF"), pause: nil, now: now))
        #expect(!target.isPaused && target.kind == .work)
        #expect(target.workedSeconds == 7_200 && target.plannedSeconds == 27_000 && target.plannedEnd == end && target.accentHex == "#0A84FF")
    }

    @Test func plannedLengthFallsBackToTheWorkModelTarget() throws {
        let target = try #require(LiveActivityTarget.desired(snapshot: snapshot(running: true, target: 28_800), pause: nil, now: now))
        #expect(target.plannedSeconds == 28_800)
        let none = try #require(LiveActivityTarget.desired(snapshot: snapshot(running: true, target: 0), pause: nil, now: now))
        #expect(none.plannedSeconds == nil)
    }

    @Test func pausedMarkerWithoutRunningTimerGivesPausedTarget() throws {
        let pausedAt = now.addingTimeInterval(-300)
        let target = try #require(LiveActivityTarget.desired(snapshot: snapshot(running: false), pause: PauseMarker(kind: .travel, pausedAt: pausedAt), now: now))
        #expect(target.isPaused && target.pausedAt == pausedAt && target.startedAt == pausedAt && target.kind == .travel)
        #expect(target.workedSeconds == 7_200)
    }

    @Test func noTimerAndNoMarkerMeansNoActivity() {
        #expect(LiveActivityTarget.desired(snapshot: snapshot(running: false), pause: nil, now: now) == nil)
        #expect(LiveActivityTarget.desired(snapshot: nil, pause: nil, now: now) == nil)
    }

    @Test func runningTimerWinsOverAStaleMarker() throws {
        let marker = PauseMarker(kind: .work, pausedAt: now.addingTimeInterval(-3_600))
        let target = try #require(LiveActivityTarget.desired(snapshot: snapshot(running: true), pause: marker, now: now))
        #expect(!target.isPaused)
        #expect(PauseMarker.current(marker, running: true, at: now) == nil)
    }

    @Test func expiredPauseEndsTheActivity() {
        let old = PauseMarker(kind: .work, pausedAt: now.addingTimeInterval(-PauseMarker.maxAge - 1))
        #expect(LiveActivityTarget.desired(snapshot: snapshot(running: false), pause: old, now: now) == nil)
        let fresh = PauseMarker(kind: .work, pausedAt: now.addingTimeInterval(-PauseMarker.maxAge + 60))
        #expect(LiveActivityTarget.desired(snapshot: snapshot(running: false), pause: fresh, now: now) != nil)
    }

    @Test func totalsAndPlanOfAnotherDayAreIgnored() throws {
        var old = snapshot(running: true, plannedEnd: now, plannedSeconds: 1_000)
        old.day = "2026-10-18"
        let target = try #require(LiveActivityTarget.desired(snapshot: old, pause: nil, now: now))
        #expect(target.workedSeconds == 0 && target.plannedSeconds == nil && target.plannedEnd == nil)
    }

    @Test func markerStoreRoundTrip() {
        let suite = "la1.test.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = PauseMarkerStore(suiteName: suite)
        #expect(store.read() == nil)
        let marker = PauseMarker(kind: .school, pausedAt: Date(timeIntervalSince1970: 1_800_000_000))
        store.write(marker)
        #expect(store.read() == marker)
        store.clear()
        #expect(store.read() == nil)
    }

    // MARK: Progress

    @Test func progressTicksFromTheFinishedWorkOfToday() throws {
        let target = LiveActivityTarget(kind: .work, startedAt: now, workedSeconds: 7_200, plannedSeconds: 28_800)
        #expect(target.workedSeconds(at: now) == 7_200)
        #expect(target.workedSeconds(at: now.addingTimeInterval(1_800)) == 9_000)
        #expect(target.fraction(at: now) == 0.25)
        let interval = try #require(target.progressInterval)
        #expect(interval.lowerBound == now.addingTimeInterval(-7_200) && interval.upperBound == interval.lowerBound.addingTimeInterval(28_800))
        // The ticking text and the bar must agree with `workedSeconds(at:)` at any moment.
        #expect(Int(now.addingTimeInterval(600).timeIntervalSince(target.workedOrigin)) == target.workedSeconds(at: now.addingTimeInterval(600)))
    }

    @Test func progressIsClampedAndOptional() {
        let over = LiveActivityTarget(kind: .work, startedAt: now, workedSeconds: 30_000, plannedSeconds: 28_800)
        #expect(over.fraction(at: now) == 1)
        let none = LiveActivityTarget(kind: .work, startedAt: now, workedSeconds: 100)
        #expect(none.fraction(at: now) == nil && none.progressInterval == nil)
        let zero = LiveActivityTarget(kind: .work, startedAt: now, plannedSeconds: 0)
        #expect(zero.fraction(at: now) == nil)
    }

    @Test func pausedProgressStandsStill() {
        let paused = LiveActivityTarget(kind: .work, startedAt: now, pausedAt: now, workedSeconds: 14_400, plannedSeconds: 28_800)
        #expect(paused.workedSeconds(at: now.addingTimeInterval(3_600)) == 14_400)
        #expect(paused.fraction(at: now.addingTimeInterval(3_600)) == 0.5)
        #expect(paused.progressInterval == nil)
    }

    // MARK: End of day

    @Test func plannedEndWinsOverTheEstimate() {
        let end = now.addingTimeInterval(5 * 3600)
        let target = LiveActivityTarget(kind: .work, startedAt: now, workedSeconds: 3_600, plannedSeconds: 28_800, plannedEnd: end)
        #expect(target.end(at: now) == .planned(end))
    }

    @Test func estimateIsWhenTheTargetIsReachedIfWorkContinues() {
        let target = LiveActivityTarget(kind: .work, startedAt: now, workedSeconds: 3_600, plannedSeconds: 28_800)
        #expect(target.end(at: now) == .estimated(now.addingTimeInterval(25_200)))
        // The estimate is fixed to the segment: it does not drift while time passes.
        #expect(target.end(at: now.addingTimeInterval(1_000)) == .estimated(now.addingTimeInterval(25_200)))
    }

    @Test func reachedTargetAndMissingPlan() {
        #expect(LiveActivityTarget(kind: .work, startedAt: now, workedSeconds: 28_800, plannedSeconds: 28_800).end(at: now) == .reached)
        #expect(LiveActivityTarget(kind: .work, startedAt: now, workedSeconds: 100).end(at: now) == nil)
    }

    @Test func pausedHasNoEstimateButKeepsThePlannedEnd() {
        let paused = LiveActivityTarget(kind: .work, startedAt: now, pausedAt: now, workedSeconds: 3_600, plannedSeconds: 28_800)
        #expect(paused.end(at: now) == nil)
        var withPlan = paused
        withPlan.plannedEnd = now.addingTimeInterval(4 * 3600)
        #expect(withPlan.end(at: now) == .planned(now.addingTimeInterval(4 * 3600)))
    }

    // MARK: Plan day

    @Test func plannedDayFromPlanTimes() throws {
        let plan = PlanDay(date: "2026-10-19", mode: .office, plannedStart: "08:00", plannedEnd: "16:30", plannedBreakMinutes: 30)
        let planned = PlannedDay(plan: plan, zone: zone)
        let end = try #require(planned.end)
        #expect(DayCalendar(timeZone: zone).hourAndMinute(of: end) == (16, 30))
        #expect(planned.seconds == 8 * 3600)
        #expect(PlannedDay(plan: PlanDay(date: "2026-10-19", mode: .home, plannedStart: "08:00", plannedEnd: "16:30", plannedSeconds: 27_000), zone: zone).seconds == 27_000)
    }

    @Test func plannedDayIgnoredWithoutTimesOrOnADayOff() {
        #expect(PlannedDay(plan: nil, zone: zone) == PlannedDay())
        #expect(PlannedDay(plan: PlanDay(date: "2026-10-19", mode: .office), zone: zone) == PlannedDay())
        #expect(PlannedDay(plan: PlanDay(date: "2026-10-19", mode: .off, plannedStart: "08:00", plannedEnd: "16:00"), zone: zone) == PlannedDay())
        #expect(PlannedDay(plan: PlanDay(date: "2026-10-19", mode: .office, plannedEnd: "25:99"), zone: zone) == PlannedDay())
    }

    @Test func planDayDecodesOldAndNewServers() throws {
        let decoder = JSONCoding.makeDecoder()
        let old = try decoder.decode(PlanDay.self, from: Data(#"{"date":"2026-10-19","mode":"office","placeId":null,"note":null}"#.utf8))
        #expect(old.plannedEnd == nil && old.plannedSeconds == nil)
        let new = try decoder.decode(PlanDay.self, from: Data(#"{"date":"2026-10-19","mode":"home","plannedStart":"08:00","plannedEnd":"16:30","plannedBreakMinutes":30,"plannedSeconds":28800}"#.utf8))
        #expect(new.plannedEnd == "16:30" && new.plannedSeconds == 28_800 && new.plannedBreakMinutes == 30)
    }

    @Test func snapshotCarriesThePlanAndDecodesWithoutIt() throws {
        let plan = PlanDay(date: "2026-10-19", mode: .office, plannedStart: "08:00", plannedEnd: "16:30", plannedBreakMinutes: 30)
        let made = WidgetSnapshot.make(running: nil, day: nil, account: nil, segments: [], zone: zone, now: now, plan: plan)
        #expect(made.plannedEnd != nil && made.plannedSeconds == 28_800)
        let legacy = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(WidgetSnapshot.empty))
        #expect(legacy.plannedEnd == nil && legacy.plannedSeconds == nil)
    }

    // MARK: Button presses

    @Test func pauseStopsTheSegmentAndRemembersTheKind() throws {
        let plan = TimerPress.plan(.pause, snapshot: snapshot(running: true, startedMinutesAgo: 30, kind: .travel), marker: nil, now: now)
        #expect(plan.isApplied)
        #expect(plan.queued?.command == .stop && plan.queued?.queuedAt == now)
        #expect(plan.marker == .set(PauseMarker(kind: .travel, pausedAt: now)))
        let after = try #require(plan.snapshot)
        #expect(!after.isRunning && after.todaySeconds == 7_200 + 1_800)
        // The optimistic state yields the paused activity straight away.
        let target = try #require(LiveActivityTarget.desired(snapshot: after, pause: PauseMarker(kind: .travel, pausedAt: now), now: now))
        #expect(target.isPaused && target.workedSeconds == 9_000 && target.kind == .travel)
    }

    @Test func resumeStartsANewSegmentOfTheSameKind() throws {
        let marker = PauseMarker(kind: .school, pausedAt: now.addingTimeInterval(-900))
        let plan = TimerPress.plan(.resume, snapshot: snapshot(running: false), marker: marker, now: now)
        #expect(plan.queued?.command == .start(.school) && plan.queued?.queuedAt == now)
        #expect(plan.marker == .clear)
        let after = try #require(plan.snapshot)
        #expect(after.isRunning && after.kind == .school && after.startedAt == now)
        // The gap [pausedAt, now] is not part of any segment: nothing invented.
        #expect(after.todaySeconds == 7_200)
    }

    @Test func stopWhileRunningStopsAndClears() {
        let plan = TimerPress.plan(.stop, snapshot: snapshot(running: true), marker: nil, now: now)
        #expect(plan.queued?.command == .stop && plan.marker == .clear && plan.snapshot?.isRunning == false)
    }

    @Test func stopWhilePausedOnlyEndsThePause() {
        let marker = PauseMarker(kind: .work, pausedAt: now.addingTimeInterval(-60))
        let plan = TimerPress.plan(.stop, snapshot: snapshot(running: false), marker: marker, now: now)
        #expect(plan.isApplied && plan.queued == nil && plan.marker == .clear)
    }

    @Test func pressesThatMakeNoSenseAreIgnored() {
        #expect(TimerPress.plan(.pause, snapshot: snapshot(running: false), marker: nil, now: now).ignored == .notRunning)
        #expect(TimerPress.plan(.resume, snapshot: snapshot(running: false), marker: nil, now: now).ignored == .nothingToResume)
        #expect(TimerPress.plan(.resume, snapshot: snapshot(running: false), marker: PauseMarker(kind: .work, pausedAt: now.addingTimeInterval(-PauseMarker.maxAge - 5)), now: now).ignored == .nothingToResume)
        let running = TimerPress.plan(.resume, snapshot: snapshot(running: true), marker: PauseMarker(kind: .work, pausedAt: now), now: now)
        #expect(running.ignored == .alreadyRunning && running.marker == .clear && running.queued == nil)
        #expect(TimerPress.plan(.start, snapshot: snapshot(running: true), marker: nil, now: now).ignored == .alreadyRunning)
        #expect(TimerPress.plan(.stop, snapshot: snapshot(running: false), marker: nil, now: now).ignored == .notRunning)
    }

    @Test func startQueuesAWorkSegmentAndClearsAPause() {
        let plan = TimerPress.plan(.start, snapshot: snapshot(running: false), marker: nil, now: now)
        #expect(plan.queued?.command == .start(.work) && plan.marker == .clear && plan.snapshot?.isRunning == true)
    }

    // MARK: Queue and reconcile

    @Test func pausePressesGoThroughTheSharedQueueInOrder() async {
        let queue = TimerActionQueue(fileURL: nil)
        let paused = TimerPress.plan(.pause, snapshot: snapshot(running: true), marker: nil, now: now, eventId: UUID())
        await queue.enqueue(paused.queued!)
        let resumed = TimerPress.plan(.resume, snapshot: paused.snapshot, marker: PauseMarker(kind: .work, pausedAt: now), now: now.addingTimeInterval(600))
        await queue.enqueue(resumed.queued!)
        let commands = await queue.pending.map(\.command)
        #expect(commands == [.stop, .start(.work)])
        // A second "Pause" press while the stop is still queued is a no-op for the queue (same command twice).
        #expect(await queue.enqueue(.init(command: .start(.work), queuedAt: now)) == false)
    }

    @Test func reconcilerUpdatesInsteadOfRequestingOnPauseAndResume() throws {
        let running = try #require(LiveActivityTarget.desired(snapshot: snapshot(running: true), pause: nil, now: now))
        let paused = try #require(LiveActivityTarget.desired(snapshot: snapshot(running: false, worked: 9_000), pause: PauseMarker(kind: .work, pausedAt: now), now: now))
        // Running -> paused re-points the one activity (works in the background); nothing is requested.
        let toPause = LiveActivityReconciler.plan(desired: paused, existing: [.init(id: "a", target: running)])
        #expect(toPause.keep == "a" && toPause.update == paused && toPause.start == nil && toPause.end.isEmpty)
        // Paused -> running likewise, and applying the plan makes the next plan a no-op.
        let toRun = LiveActivityReconciler.plan(desired: running, existing: [.init(id: "a", target: paused)])
        #expect(toRun.keep == "a" && toRun.update == running && toRun.start == nil)
        #expect(LiveActivityReconciler.plan(desired: running, existing: [.init(id: "a", target: running)]).isNoOp)
        // Stop while paused ends it.
        #expect(LiveActivityReconciler.plan(desired: nil, existing: [.init(id: "a", target: paused)]).end == ["a"])
    }

    @Test func targetSurvivesTheContentStateRoundTrip() throws {
        let target = LiveActivityTarget(kind: .travel, startedAt: now, pausedAt: now, workedSeconds: 5, plannedSeconds: 6, plannedEnd: now, accentHex: "#112233")
        #expect(try JSONDecoder().decode(LiveActivityTarget.self, from: JSONEncoder().encode(target)) == target)
    }
}
