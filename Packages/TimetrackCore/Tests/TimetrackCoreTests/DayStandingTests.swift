import Foundation
import Testing
@testable import TimetrackCore

@Suite("Day standing and delta policy: no false deficit warnings (UX3)")
struct DayStandingTests {
    @Test func morningWithoutEntryHasNoDifference() {
        let standing = DayStanding(doneSeconds: 0, targetSeconds: 27_720, hasStarted: false)
        #expect(standing.status == .notStarted)
        #expect(standing.showsRing && standing.progress == 0)
    }

    @Test func freeDayHasNoRingAndNoRemainingTime() {
        let empty = DayStanding(doneSeconds: 0, targetSeconds: 0, hasStarted: false)
        #expect(empty.status == .noTarget && !empty.showsRing)
        // Work on a free day is still shown as worked time, but never as a difference to a target of 0:00.
        let worked = DayStanding(doneSeconds: 26_100, targetSeconds: 0, hasStarted: true)
        #expect(worked.status == .noTarget && !worked.showsRing && worked.progress == 0)
    }

    @Test func remainingReachedAndOver() {
        #expect(DayStanding(doneSeconds: 26_100, targetSeconds: 27_720, hasStarted: true).status == .remaining(1_620))
        #expect(DayStanding(doneSeconds: 27_700, targetSeconds: 27_720, hasStarted: true).status == .reached)
        #expect(DayStanding(doneSeconds: 28_440, targetSeconds: 27_720, hasStarted: true).status == .over(720))
        #expect(DayStanding(doneSeconds: 30_000, targetSeconds: 27_720, hasStarted: true).progress == 1)
    }

    @Test func aStartedDayWithZeroSecondsIsInProgress() {
        #expect(DayStanding(doneSeconds: 0, targetSeconds: 27_720, hasStarted: true).status == .remaining(27_720))
    }

    @Test func futureDaysNeverShowADifference() {
        #expect(DayDeltaPolicy.presentation(day: "2026-10-22", today: "2026-10-20", doneSeconds: 0, targetSeconds: 27_720, hasStarted: false) == .hidden)
    }

    @Test func todayIsNeverAWarning() {
        #expect(DayDeltaPolicy.presentation(day: "2026-10-20", today: "2026-10-20", doneSeconds: 0, targetSeconds: 27_720, hasStarted: false) == .hidden)
        #expect(DayDeltaPolicy.presentation(day: "2026-10-20", today: "2026-10-20", doneSeconds: 3_600, targetSeconds: 27_720, hasStarted: true) == .open(24_120))
        #expect(DayDeltaPolicy.presentation(day: "2026-10-20", today: "2026-10-20", doneSeconds: 28_800, targetSeconds: 27_720, hasStarted: true) == .surplus(1_080))
    }

    @Test func pastDaysKeepTheFinalDifference() {
        #expect(DayDeltaPolicy.presentation(day: "2026-10-19", today: "2026-10-20", doneSeconds: 26_100, targetSeconds: 27_720, hasStarted: true) == .deficit(1_620))
        #expect(DayDeltaPolicy.presentation(day: "2026-10-19", today: "2026-10-20", doneSeconds: 27_720, targetSeconds: 27_720, hasStarted: true) == .hidden)
        #expect(DayDeltaPolicy.presentation(day: "2026-10-17", today: "2026-10-20", doneSeconds: 0, targetSeconds: 0, hasStarted: false) == .hidden)
        // Work on a day without a target counts as surplus.
        #expect(DayDeltaPolicy.presentation(day: "2026-10-18", today: "2026-10-20", doneSeconds: 3_600, targetSeconds: 0, hasStarted: true) == .surplus(3_600))
    }

    @Test func syncStatusPrefersOfflineOverSending() {
        #expect(SyncStatus(pending: 0, networkError: false) == .ok)
        #expect(SyncStatus(pending: 2, networkError: false) == .sending(2))
        #expect(SyncStatus(pending: 2, networkError: true) == .offline(pending: 2))
        #expect(SyncStatus(pending: 0, networkError: true) == .offline(pending: 0))
    }
}

@Suite("Live Activity: a trip shows no workday bar (UX3)")
struct LiveActivityTravelTests {
    let zone = TimeZone(identifier: "Europe/Berlin")!
    func at(_ hour: Int, _ minute: Int = 0) -> Date { DayCalendar(timeZone: zone).instant(day: "2026-10-19", hour: hour, minute: minute)! }

    private func snapshot(kind: SegmentKind) -> WidgetSnapshot {
        let running = Segment(id: UUID(), kind: kind, startedAt: at(12, 0))
        let day = DayEvaluation(date: "2026-10-19", targetSeconds: 28_800, evaluatedWorkSeconds: 3_600)
        return WidgetSnapshot.make(running: running, day: day, account: nil, segments: [running], zone: zone, now: at(13, 0))
    }

    @Test func tripHasNoPlanBarEndOrEstimate() throws {
        let target = try #require(LiveActivityTarget.desired(snapshot: snapshot(kind: .travel), pause: nil, now: at(13, 0)))
        #expect(target.plannedSeconds == nil && target.plannedEnd == nil && target.dayStart == nil)
        #expect(target.progressInterval == nil && target.fraction(at: at(13, 0)) == nil && target.end(at: at(13, 0)) == nil)
    }

    @Test func workKeepsTheBar() throws {
        let target = try #require(LiveActivityTarget.desired(snapshot: snapshot(kind: .work), pause: nil, now: at(13, 0)))
        #expect(target.plannedSeconds == 28_800 && target.progressInterval != nil)
    }
}
