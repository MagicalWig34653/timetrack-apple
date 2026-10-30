import Foundation
import Testing
@testable import TimetrackCore

/// U2: geometry and edit operations of the graphical week planner.
@Suite struct PlanGridTests {
    private func draft(_ blocks: [(String, String, PlanBlockKind)], mode: PlanMode? = .office) -> DayDraft {
        DayDraft(date: "2026-11-02", mode: mode, blocks: blocks.map { PlanTimeBlock(start: $0.0, end: $0.1, kind: $0.2) })
    }

    @Test func pointerSnapsToFifteenMinutesInsideTheVisibleHours() {
        // 6 h start, 60 pt per hour: y = 125 pt -> 08:05 -> 08:00; y = 130 -> 08:10 -> 08:15.
        #expect(PlanGrid.minutes(atY: 125, startHour: 6, hourHeight: 60) == 8 * 60)
        #expect(PlanGrid.minutes(atY: 130, startHour: 6, hourHeight: 60) == 8 * 60 + 15)
        #expect(PlanGrid.minutes(atY: -50, startHour: 6, hourHeight: 60) == 6 * 60, "clamped above")
        #expect(PlanGrid.minutes(atY: 5000, startHour: 6, hourHeight: 60) == PlanGrid.lastMinute, "the day ends at 23:59")
        #expect(PlanGrid.y(forMinutes: 8 * 60, startHour: 6, hourHeight: 60) == 120)
    }

    @Test func paintingGrowsATapToTheMinimumAndIgnoresDragDirection() {
        #expect(PlanGrid.paintRange(anchor: 600, current: 600) == MinuteRange(start: 600, end: 615))
        #expect(PlanGrid.paintRange(anchor: 720, current: 600) == MinuteRange(start: 600, end: 720))
        let nearEnd = PlanGrid.paintRange(anchor: PlanGrid.lastMinute - 5, current: PlanGrid.lastMinute - 5)
        #expect(nearEnd.end == PlanGrid.lastMinute && nearEnd.duration >= PlanGrid.minBlockMinutes)
    }

    @Test func moveKeepsTheDurationAndStaysInTheDay() {
        let range = MinuteRange(start: 480, end: 600)
        #expect(PlanGrid.move(range, by: 40) == MinuteRange(start: 525, end: 645), "snapped to 15 minutes")
        #expect(PlanGrid.move(range, by: -9999).start == 0)
        let late = PlanGrid.move(range, by: 9999)
        #expect(late.end == PlanGrid.lastMinute && late.duration == 120)
    }

    @Test func resizeStopsAtMinimumAndNeighbours() {
        let range = MinuteRange(start: 480, end: 600)
        let bounds = MinuteRange(start: 450, end: 660)
        #expect(PlanGrid.resize(range, edge: .end, to: 480, bounds: bounds) == MinuteRange(start: 480, end: 495), "no flipping")
        #expect(PlanGrid.resize(range, edge: .end, to: 900, bounds: bounds).end == 660)
        #expect(PlanGrid.resize(range, edge: .start, to: 0, bounds: bounds).start == 450)
        #expect(PlanGrid.resize(range, edge: .start, to: 700, bounds: bounds).start == 585)
        #expect(PlanGrid.resize(range, edge: .end, to: 607, step: 5, bounds: bounds).end == 605)
    }

    @Test func visibleHoursWidenAroundBlocks() {
        #expect(PlanGrid.visibleHours([]) == (6, 21))
        let wide = PlanGrid.visibleHours([MinuteRange(start: 4 * 60 + 30, end: 22 * 60 + 15)])
        #expect(wide.start == 4 && wide.end == 23)
    }

    @Test func paintingCarvesExistingBlocksAndTheNewOneWins() {
        let day = draft([("08:00", "17:00", .office)])
        let placed = PlanGridEdit.paint(day, range: MinuteRange(start: 12 * 60, end: 13 * 60), kind: .school)!
        #expect(placed.replaced)
        #expect(placed.draft.blocks.map { "\($0.start)-\($0.end) \($0.kind)" } == ["08:00-12:00 office", "12:00-13:00 school", "13:00-17:00 office"])
        #expect(placed.index == 1)
        #expect(WeekPlan.blocksProblem(placed.draft.blocks) == nil)
    }

    @Test func paintingOnAnEmptyDaySetsTheModeFromTheKind() {
        let empty = DayDraft(date: "2026-11-02")
        #expect(PlanGridEdit.paint(empty, range: MinuteRange(start: 540, end: 600), kind: .home)!.draft.mode == .home)
        #expect(PlanGridEdit.paint(empty, range: MinuteRange(start: 540, end: 600), kind: .travel)!.draft.mode == .office)
        let free = DayDraft(date: "2026-11-02", mode: .off, note: "frei")
        let placed = PlanGridEdit.paint(free, range: MinuteRange(start: 540, end: 600), kind: .work)!
        #expect(placed.draft.mode == .office && placed.draft.note == "frei", "a free day becomes a plan day, the note stays")
    }

    @Test func movingCarvesTheTargetAndKeepsKindAndNote() {
        var day = draft([("08:00", "10:00", .office), ("11:00", "13:00", .customer)])
        day.blocks[0].note = "Standup"
        let moved = PlanGridEdit.move(day, at: 0, to: MinuteRange(start: 12 * 60, end: 14 * 60))!
        #expect(moved.draft.blocks.map(\.start) == ["11:00", "12:00"])
        #expect(moved.draft.blocks[0].end == "12:00", "the customer block is trimmed")
        #expect(moved.draft.blocks[1].note == "Standup" && moved.draft.blocks[1].kind == .office)
    }

    @Test func resizeNeverOverlapsAndEraseEmptiesTheDay() {
        let day = draft([("08:00", "10:00", .office), ("10:30", "12:00", .home)])
        let longer = PlanGridEdit.resize(day, at: 0, edge: .end, to: 12 * 60)!
        #expect(longer.blocks[0].end == "10:30")
        let none = PlanGridEdit.erase(PlanGridEdit.erase(day, at: 0), at: 0)
        #expect(none.mode == nil && none.blocks.isEmpty)
        #expect(PlanGridEdit.neighbourBounds(day.blocks, at: 1) == MinuteRange(start: 600, end: PlanGrid.lastMinute))
    }

    @Test func tooManyBlocksAreRefused() {
        var day = DayDraft(date: "2026-11-02", mode: .office)
        for i in 0..<PlanBlocks.maxCount {
            day = PlanGridEdit.paint(day, range: MinuteRange(start: i * 40, end: i * 40 + 30), kind: .work)!.draft
        }
        #expect(PlanGridEdit.paint(day, range: MinuteRange(start: 1350, end: 1380), kind: .work) == nil)
    }

    @Test func copyKeepsEverythingButTheDate() {
        let day = draft([("08:00", "12:00", .school)], mode: .school)
        let copy = PlanGridEdit.copy(day, to: "2026-11-03")
        #expect(copy.date == "2026-11-03" && copy.blocks == day.blocks && copy.mode == .school)
    }
}
