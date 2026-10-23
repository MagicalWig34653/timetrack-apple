import Testing
import Foundation
@testable import TimetrackCore

@Suite("H3 DayOutlook")
struct DayOutlookTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)

    func segment(_ start: Double, _ end: Double?, kind: SegmentKind = .work) -> Segment {
        Segment(id: UUID(), kind: kind, startedAt: base.addingTimeInterval(start * 3600), endedAt: end.map { base.addingTimeInterval($0 * 3600) })
    }

    @Test func runningWorkCountsUpFromLoad() {
        let run = segment(0, nil)
        let now = base.addingTimeInterval(3600 + 600)
        let o = DayOutlook(now: now, running: run, segments: [run], doneAtLoad: 3600, loadedAt: base.addingTimeInterval(3600), targetSeconds: 8 * 3600)
        #expect(o.workedSeconds == 3600 + 600)
        #expect(o.remainingSeconds == 8 * 3600 - 4200)
        #expect(o.end == .estimated(now.addingTimeInterval(TimeInterval(8 * 3600 - 4200))))
    }

    @Test func travelDoesNotGrowWorkedTimeNorEstimate() {
        let run = segment(0, nil, kind: .travel)
        let o = DayOutlook(now: base.addingTimeInterval(7200), running: run, segments: [run], doneAtLoad: 1800, loadedAt: base.addingTimeInterval(3600), targetSeconds: 8 * 3600)
        #expect(o.workedSeconds == 1800)
        #expect(o.end == .unknown)
    }

    @Test func plannedEndWinsWhileInTheFuture() {
        let planned = base.addingTimeInterval(9 * 3600)
        let run = segment(0, nil)
        let o = DayOutlook(now: base.addingTimeInterval(3600), running: run, segments: [run], doneAtLoad: 3600, loadedAt: base.addingTimeInterval(3600), targetSeconds: 8 * 3600, plannedEnd: planned)
        #expect(o.end == .planned(planned))
        let late = DayOutlook(now: base.addingTimeInterval(10 * 3600), running: run, segments: [run], doneAtLoad: 5 * 3600, loadedAt: base.addingTimeInterval(10 * 3600), targetSeconds: 8 * 3600, plannedEnd: planned)
        #expect(late.end != .planned(planned))
    }

    @Test func reachedAndNoTarget() {
        let o = DayOutlook(now: base, running: nil, segments: [], doneAtLoad: 8 * 3600, loadedAt: base, targetSeconds: 8 * 3600)
        #expect(o.end == .reached)
        #expect(o.remainingSeconds == 0)
        let none = DayOutlook(now: base, running: nil, segments: [], doneAtLoad: 0, loadedAt: base, targetSeconds: 0)
        #expect(none.end == .unknown)
        #expect(none.remainingSeconds == nil)
    }

    @Test func breakDueBeforeSixHours() {
        let run = segment(0, nil)
        let o = DayOutlook(now: base.addingTimeInterval(2 * 3600), running: run, segments: [run], doneAtLoad: 2 * 3600, loadedAt: base.addingTimeInterval(2 * 3600), targetSeconds: 8 * 3600)
        #expect(o.breakStatus == .dueIn(seconds: 4 * 3600, required: 1800))
    }

    @Test func breakMissingAfterSixHoursWithoutGap() {
        let run = segment(0, nil)
        let o = DayOutlook(now: base.addingTimeInterval(7 * 3600), running: run, segments: [run], doneAtLoad: 7 * 3600, loadedAt: base.addingTimeInterval(7 * 3600), targetSeconds: 8 * 3600)
        #expect(o.breakStatus == .missing(required: 1800, taken: 0))
    }

    @Test func gapOfThirtyMinutesCountsAndShortGapDoesNot() {
        let a = segment(0, 4), b = segment(4.5, 4.9), c = segment(5, nil)
        let o = DayOutlook(now: base.addingTimeInterval(7 * 3600), running: c, segments: [a, b, c], doneAtLoad: 6 * 3600 + 600, loadedAt: base.addingTimeInterval(7 * 3600), targetSeconds: 8 * 3600)
        #expect(o.takenBreakSeconds == 1800)
        #expect(o.breakStatus == .taken(o.takenBreakSeconds))
    }

    @Test func nineHoursNeedFortyFiveMinutes() {
        let a = segment(0, 5), b = segment(5.5, nil)
        let o = DayOutlook(now: base.addingTimeInterval(10 * 3600), running: b, segments: [a, b], doneAtLoad: 9 * 3600 + 60, loadedAt: base.addingTimeInterval(10 * 3600), targetSeconds: 8 * 3600)
        #expect(o.breakStatus == .missing(required: 2700, taken: 1800))
    }

    @Test func pauseGapIsTheTimeSinceTheLastStop() {
        let a = segment(0, 2), v = segment(3, 4)
        let gap = PauseGap(running: nil, segments: [a, v])
        #expect(gap?.since == v.endedAt)
        #expect(gap?.seconds(at: base.addingTimeInterval(4.5 * 3600)) == 1800)
        #expect(PauseGap(running: segment(5, nil), segments: [a]) == nil)
        #expect(PauseGap(running: nil, segments: []) == nil)
    }
}
