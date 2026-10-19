import Foundation
import Testing
@testable import TimetrackCore

@Suite("Live Activity progress: first start to planned end, no double counting (LA2)")
struct LiveActivityProgressTests {
    let zone = TimeZone(identifier: "Europe/Berlin")!
    func at(_ hour: Int, _ minute: Int = 0) -> Date { DayCalendar(timeZone: zone).instant(day: "2026-10-19", hour: hour, minute: minute)! }

    // MARK: Snapshot: finished work excludes the running segment

    @Test func snapshotCountsOnlyFinishedWorkBecauseTheServerEvaluatesTheOpenSegmentToNow() throws {
        // Server: 08:15 start, now 15:30 => the evaluated day already contains the open segment (7 h 15 min = 26 100 s).
        let now = at(15, 30)
        let running = Segment(id: UUID(), kind: .work, startedAt: at(12, 30))
        let finished = Segment(id: UUID(), kind: .work, startedAt: at(8, 15), endedAt: at(12, 0))
        let evaluated = (3 * 3600 + 45 * 60) + 3 * 3600 // finished 3:45 + open segment 3:00
        let day = DayEvaluation(date: "2026-10-19", targetSeconds: 28_800, evaluatedWorkSeconds: evaluated)
        let snapshot = WidgetSnapshot.make(running: running, day: day, account: nil, segments: [finished, running], zone: zone, now: now)
        #expect(snapshot.todaySeconds == 3 * 3600 + 45 * 60)
        #expect(snapshot.firstStart == at(8, 15))
        // The Live Activity clock (finished + running since start) now shows the real 6:45 instead of 9:45.
        let target = try #require(LiveActivityTarget.desired(snapshot: snapshot, pause: nil, now: now))
        #expect(target.workedSeconds(at: now) == 6 * 3600 + 45 * 60)
    }

    @Test func evaluationOlderThanNowIsSubtractedUpToThatMoment() {
        let running = Segment(id: UUID(), kind: .work, startedAt: at(12, 0))
        let day = DayEvaluation(date: "2026-10-19", targetSeconds: 28_800, evaluatedWorkSeconds: 3_600 + 600) // evaluated at 13:00
        let snapshot = WidgetSnapshot.make(running: running, day: day, account: nil, segments: [running], zone: zone, now: at(14, 0), evaluatedAt: at(13, 0))
        #expect(snapshot.todaySeconds == 600)
    }

    @Test func finishedWorkNeverGoesNegativeAndIdleDaysAreUntouched() {
        let running = Segment(id: UUID(), kind: .work, startedAt: at(12, 0))
        let tiny = DayEvaluation(date: "2026-10-19", targetSeconds: 0, evaluatedWorkSeconds: 60)
        #expect(WidgetSnapshot.make(running: running, day: tiny, account: nil, segments: [running], zone: zone, now: at(13, 0)).todaySeconds == 0)
        let idle = DayEvaluation(date: "2026-10-19", targetSeconds: 0, evaluatedWorkSeconds: 5_000)
        #expect(WidgetSnapshot.make(running: nil, day: idle, account: nil, segments: [], zone: zone, now: at(13, 0)).todaySeconds == 5_000)
    }

    @Test func watchDisplayFromLiveDataDropsTheRunningSegmentAsWell() {
        let start = at(12, 0)
        let display = TodayDisplay(source: .live, isRunning: true, kind: .work, startedAt: start, doneSeconds: 3_600 + 1_800, updatedAt: at(12, 30))
        #expect(WidgetSnapshot.make(display: display, zone: zone, now: at(12, 30)).todaySeconds == 3_600)
        let cached = TodayDisplay(source: .cached, isRunning: true, kind: .work, startedAt: start, doneSeconds: 3_600, updatedAt: at(12, 30))
        #expect(WidgetSnapshot.make(display: cached, zone: zone, now: at(13, 0)).todaySeconds == 3_600)
    }

    @Test func firstStartIgnoresVoidedSegmentsAndOldSnapshotsDecode() throws {
        let voided = Segment(id: UUID(), kind: .work, startedAt: at(6, 0), endedAt: at(6, 10), voided: true)
        let real = Segment(id: UUID(), kind: .work, startedAt: at(8, 15))
        let snapshot = WidgetSnapshot.make(running: real, day: nil, account: nil, segments: [real, voided], zone: zone, now: at(9, 0))
        #expect(snapshot.firstStart == at(8, 15))
        let json = #"{"isRunning":false,"kind":"work","todaySeconds":60,"day":"2026-10-16","timeZone":"Europe\/Berlin","updatedAt":1800000000}"#
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8)).firstStart == nil)
    }

    // MARK: Progress from first start to planned end

    func target(now: Date, paused: Bool = false, start: Date? = nil, end: Date? = nil, planned: Int? = 27_000) -> LiveActivityTarget {
        LiveActivityTarget(kind: .work, startedAt: now.addingTimeInterval(-600), pausedAt: paused ? now.addingTimeInterval(-600) : nil,
                           workedSeconds: 3_600, plannedSeconds: planned, plannedEnd: end, dayStart: start)
    }

    @Test func barRunsFromFirstStartToPlannedEnd() throws {
        // The reported case: planned end 19:00, it is 15:30 and the day started 08:15 => 7:15 of 10:45 = 67 %, not 93 %.
        let t = target(now: at(15, 30), start: at(8, 15), end: at(19, 0), planned: 38_700)
        let fraction = try #require(t.fraction(at: at(15, 30)))
        #expect(abs(fraction - 26_100.0 / 38_700.0) < 1e-9)
        #expect(fraction > 0.66 && fraction < 0.68)
        let interval = try #require(t.progressInterval)
        #expect(interval == at(8, 15)...at(19, 0))
    }

    @Test func barIsClampedBeforeTheStartAndAfterTheEnd() {
        let t = target(now: at(20, 0), start: at(8, 15), end: at(19, 0))
        #expect(t.fraction(at: at(20, 0)) == 1)
        #expect(t.fraction(at: at(7, 0)) == 0)
    }

    @Test func barKeepsMovingTowardsFeierabendWhilePaused() throws {
        let t = target(now: at(12, 0), paused: true, start: at(8, 0), end: at(16, 0))
        #expect(t.fraction(at: at(12, 0)) == 0.5)
        #expect(t.fraction(at: at(14, 0)) == 0.75)
        #expect(t.progressInterval == at(8, 0)...at(16, 0))
    }

    @Test func withoutFirstStartTheWorkedOriginStandsIn() throws {
        let now = at(12, 0)
        let t = target(now: now, end: at(16, 0)) // worked 3 600 s, running since 11:50 => origin 10:50
        #expect(t.progressInterval?.lowerBound == t.workedOrigin)
    }

    @Test func withoutPlannedEndTheBarFallsBackToWorkedAgainstPlannedLength() {
        let now = at(12, 0)
        let t = target(now: now, planned: 7_200)
        #expect(t.fraction(at: now) == (3_600.0 + 600.0) / 7_200.0)
        #expect(t.progressInterval == t.workedOrigin...t.workedOrigin.addingTimeInterval(7_200))
        let paused = target(now: now, paused: true, planned: 7_200)
        #expect(paused.fraction(at: now.addingTimeInterval(3_600)) == 0.5 && paused.progressInterval == nil)
    }

    @Test func startAfterThePlannedEndFallsBackToWorked() {
        let t = target(now: at(20, 0), start: at(19, 30), end: at(19, 0), planned: 7_200)
        #expect(t.fraction(at: at(20, 0)) == (3_600.0 + 600.0) / 7_200.0)
    }

    @Test func plannedSnapshotFieldsReachTheTarget() throws {
        var snapshot = WidgetSnapshot(isRunning: true, kind: .work, startedAt: at(12, 0), todaySeconds: 600, day: "2026-10-19", timeZone: zone.identifier,
                                      updatedAt: at(12, 0), targetSeconds: 28_800, plannedEnd: at(19, 0), plannedSeconds: 38_700)
        snapshot.firstStart = at(8, 15)
        let t = try #require(LiveActivityTarget.desired(snapshot: snapshot, pause: nil, now: at(12, 0)))
        #expect(t.dayStart == at(8, 15) && t.plannedEnd == at(19, 0))
        // Another day: nothing carries over.
        snapshot.day = "2026-10-18"
        #expect(LiveActivityTarget.desired(snapshot: snapshot, pause: nil, now: at(12, 0))?.dayStart == nil)
    }
}
