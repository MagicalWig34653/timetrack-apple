import Foundation

/// U2: pure geometry and edit operations of the graphical week planner (a port of the PWA's `grid.ts` / `grid-edit.ts`, P11/P13).
/// Minutes are minutes since local midnight; a plan never crosses midnight. Nothing here touches UI or network.
public struct MinuteRange: Hashable, Sendable {
    public var start: Int
    public var end: Int
    public init(start: Int, end: Int) { self.start = start; self.end = end }
    public var duration: Int { end - start }
    public func overlaps(_ other: MinuteRange) -> Bool { start < other.end && other.start < end }
}

public enum PlanGrid {
    public static let snapMinutes = 15
    public static let fineMinutes = 5
    public static let minBlockMinutes = 15
    public static let lastMinute = 23 * 60 + 59
    public static let defaultStartHour = 6
    public static let defaultEndHour = 21

    public static func snap(_ minutes: Double, step: Int = snapMinutes) -> Int { Int((minutes / Double(step)).rounded()) * step }

    /// Snapped minutes for a vertical offset (points) inside the grid; the day's last minute is 23:59.
    public static func minutes(atY y: Double, startHour: Int, hourHeight: Double, step: Int = snapMinutes, endHour: Int = 24) -> Int {
        let raw = Double(startHour * 60) + y / hourHeight * 60
        return min(max(snap(raw, step: step), startHour * 60), min(endHour * 60, lastMinute))
    }

    public static func y(forMinutes minutes: Int, startHour: Int, hourHeight: Double) -> Double { Double(minutes - startHour * 60) / 60 * hourHeight }

    /// The range painted between two pointer minutes: order does not matter, a tap-sized range grows to the minimum.
    public static func paintRange(anchor: Int, current: Int, bounds: MinuteRange = MinuteRange(start: 0, end: lastMinute)) -> MinuteRange {
        var start = min(anchor, current), end = max(anchor, current)
        if end - start < minBlockMinutes { end = start + minBlockMinutes }
        if end > bounds.end {
            end = bounds.end
            start = min(start, end - minBlockMinutes)
        }
        start = max(start, bounds.start)
        return MinuteRange(start: start, end: end)
    }

    /// A range moved by a delta (snapped); the duration stays and the range stays inside the day.
    public static func move(_ range: MinuteRange, by delta: Int, step: Int = snapMinutes) -> MinuteRange {
        let start = min(max(range.start + snap(Double(delta), step: step), 0), lastMinute - range.duration)
        return MinuteRange(start: start, end: start + range.duration)
    }

    public enum Edge: Sendable { case start, end }

    /// One edge dragged to a minute: stops at the minimum duration instead of flipping, and at the bounds (the neighbours).
    public static func resize(_ range: MinuteRange, edge: Edge, to minute: Int, step: Int = snapMinutes,
                              bounds: MinuteRange = MinuteRange(start: 0, end: lastMinute)) -> MinuteRange {
        let target = snap(Double(minute), step: step)
        switch edge {
        case .start: return MinuteRange(start: min(max(target, bounds.start), range.end - minBlockMinutes), end: range.end)
        case .end: return MinuteRange(start: range.start, end: max(min(target, bounds.end), range.start + minBlockMinutes))
        }
    }

    /// Hours shown: the default window widened to whole hours around every block.
    public static func visibleHours(_ ranges: [MinuteRange], defaultStart: Int = defaultStartHour, defaultEnd: Int = defaultEndHour) -> (start: Int, end: Int) {
        var lo = defaultStart, hi = defaultEnd
        for range in ranges {
            lo = min(lo, range.start / 60)
            hi = max(hi, (range.end + 59) / 60)
        }
        lo = min(max(lo, 0), 23)
        return (lo, min(max(hi, lo + 1), 24))
    }
}

/// Edit operations on the block list of one day. Every result is chronologically ordered and never overlapping (a new block wins and
/// carves what it covers), like the PWA grid. Callers validate with `WeekPlan.blocksProblem` before saving.
public enum PlanGridEdit {
    public static func ranges(_ blocks: [PlanTimeBlock]) -> [(index: Int, range: MinuteRange)] {
        blocks.enumerated().compactMap { index, block in
            guard let s = block.startMinutes, let e = block.endMinutes, e > s else { return nil }
            return (index, MinuteRange(start: s, end: e))
        }
    }

    /// Free minutes around a block: where its edges may move without touching a neighbour.
    public static func neighbourBounds(_ blocks: [PlanTimeBlock], at index: Int) -> MinuteRange {
        var bounds = MinuteRange(start: 0, end: PlanGrid.lastMinute)
        guard let own = ranges(blocks).first(where: { $0.index == index })?.range else { return bounds }
        for (other, range) in ranges(blocks) where other != index {
            if range.end <= own.start { bounds.start = max(bounds.start, range.end) } else if range.start >= own.end { bounds.end = min(bounds.end, range.start) }
        }
        return bounds
    }

    /// The day mode that goes with a block kind: work and travel have none of their own and count as office.
    public static func mode(for kind: PlanBlockKind) -> PlanMode {
        switch kind {
        case .home: .home
        case .customer: .customer
        case .school: .school
        case .office, .work, .travel, .unknown: .office
        }
    }

    public struct Placed: Equatable, Sendable {
        public var draft: DayDraft
        /// Index of the placed block in the resulting list.
        public var index: Int
        /// Existing blocks were trimmed, split or removed.
        public var replaced: Bool
    }

    /// Puts a block into a day; the new block wins over what it overlaps (trimmed or split). Nil when the day would exceed the block limit.
    public static func place(_ draft: DayDraft, block: PlanTimeBlock) -> Placed? {
        guard let start = block.startMinutes, let end = block.endMinutes, end > start else { return nil }
        var base = draft
        if base.mode == .off { base = DayDraft(date: draft.date, mode: nil, note: draft.note) }
        var kept: [PlanTimeBlock] = []
        var replaced = false
        for existing in base.blocks {
            guard let s = existing.startMinutes, let e = existing.endMinutes, e > s, !(e <= start || s >= end) else { kept.append(existing); continue }
            replaced = true
            if s < start { var head = existing; head.end = WeekPlan.formatClock(start); kept.append(head) }
            if e > end { var tail = existing; tail.start = WeekPlan.formatClock(end); kept.append(tail) }
        }
        let blocks = PlanBlockEditing.sorted(kept + [block])
        guard blocks.count <= PlanBlocks.maxCount else { return nil }
        if base.mode == nil { base.mode = mode(for: block.kind) }
        base.blocks = blocks
        base.start = ""
        base.end = ""
        base.breakMinutes = 0
        let index = blocks.firstIndex { $0.start == block.start && $0.end == block.end && $0.kind == block.kind } ?? 0
        return Placed(draft: base, index: index, replaced: replaced)
    }

    /// Paints a new block of `kind` over `range`.
    public static func paint(_ draft: DayDraft, range: MinuteRange, kind: PlanBlockKind, placeId: UUID? = nil) -> Placed? {
        place(draft, block: PlanTimeBlock(start: WeekPlan.formatClock(range.start), end: WeekPlan.formatClock(range.end), kind: kind, placeId: placeId))
    }

    /// Moves a block to a new range; it wins over what it lands on (like a paint), keeping kind, place and note.
    public static func move(_ draft: DayDraft, at index: Int, to range: MinuteRange) -> Placed? {
        guard draft.blocks.indices.contains(index) else { return nil }
        var block = draft.blocks[index]
        block.start = WeekPlan.formatClock(range.start)
        block.end = WeekPlan.formatClock(range.end)
        var rest = draft
        rest.blocks.remove(at: index)
        return place(rest, block: block)
    }

    /// Resizes one edge, clamped by the neighbours and the minimum length.
    public static func resize(_ draft: DayDraft, at index: Int, edge: PlanGrid.Edge, to minute: Int, step: Int = PlanGrid.snapMinutes) -> DayDraft? {
        guard draft.blocks.indices.contains(index), let own = ranges(draft.blocks).first(where: { $0.index == index })?.range else { return nil }
        let resized = PlanGrid.resize(own, edge: edge, to: minute, step: step, bounds: neighbourBounds(draft.blocks, at: index))
        var result = draft
        result.blocks[index].start = WeekPlan.formatClock(resized.start)
        result.blocks[index].end = WeekPlan.formatClock(resized.end)
        return result
    }

    /// Removes a block; a day without blocks has no plan any more (note is kept for a following plan).
    public static func erase(_ draft: DayDraft, at index: Int) -> DayDraft {
        guard draft.blocks.indices.contains(index) else { return draft }
        var result = draft
        result.blocks.remove(at: index)
        if result.blocks.isEmpty { return DayDraft(date: draft.date, mode: nil, note: draft.note) }
        return result
    }

    /// Copies the plan of a day onto another date (mode, blocks, place, note).
    public static func copy(_ source: DayDraft, to date: LocalDay) -> DayDraft {
        var copy = source
        copy.date = date
        return copy
    }
}
