import Foundation

/// Pure edit operations on the ordered block list of one plan day (P13). The result is always chronologically ordered; callers
/// validate with `WeekPlan.blocksProblem` before saving.
public enum PlanBlockEditing {
    public static let defaultLengthMinutes = 60
    public static let minimumSplitMinutes = 10
    private static let lastMinute = 23 * 60 + 59

    /// Appends a block after the last one (one hour, clamped to the end of the day), or 08:00-12:00 for an empty list.
    /// Returns the list unchanged when the day has no room left or the maximum count is reached.
    public static func adding(to blocks: [PlanTimeBlock], kind: PlanBlockKind) -> [PlanTimeBlock] {
        guard blocks.count < PlanBlocks.maxCount else { return blocks }
        let start = blocks.last.flatMap(\.endMinutes) ?? 8 * 60
        guard start < lastMinute else { return blocks }
        let end = min(lastMinute, start + (blocks.isEmpty ? 4 * 60 : defaultLengthMinutes))
        return blocks + [PlanTimeBlock(start: WeekPlan.formatClock(start), end: WeekPlan.formatClock(end), kind: kind)]
    }

    /// Splits block `index` in the middle (rounded to 5 minutes) into two blocks of the same kind, place and note. Splitting a block
    /// shorter than 10 minutes does nothing.
    public static func splitting(_ blocks: [PlanTimeBlock], at index: Int) -> [PlanTimeBlock] {
        guard blocks.indices.contains(index), blocks.count < PlanBlocks.maxCount,
              let start = blocks[index].startMinutes, let end = blocks[index].endMinutes, end - start >= minimumSplitMinutes else { return blocks }
        var middle = start + ((end - start) / 2 / 5) * 5
        if middle <= start { middle = start + (end - start) / 2 }
        var first = blocks[index], second = blocks[index]
        first.end = WeekPlan.formatClock(middle)
        second.start = WeekPlan.formatClock(middle)
        var result = blocks
        result.replaceSubrange(index...index, with: [first, second])
        return result
    }

    /// Removes block `index`.
    public static func deleting(_ blocks: [PlanTimeBlock], at index: Int) -> [PlanTimeBlock] {
        guard blocks.indices.contains(index) else { return blocks }
        var result = blocks
        result.remove(at: index)
        return result
    }

    /// Merges block `index` with the next one: begin of the first, end of the second, kind/place of the first. A gap between them is absorbed.
    public static func mergingWithNext(_ blocks: [PlanTimeBlock], at index: Int) -> [PlanTimeBlock] {
        guard blocks.indices.contains(index), blocks.indices.contains(index + 1) else { return blocks }
        var merged = blocks[index]
        merged.end = blocks[index + 1].end
        let notes = [blocks[index].note, blocks[index + 1].note].compactMap { $0 }.filter { !$0.isEmpty }
        merged.note = notes.isEmpty ? nil : String(notes.joined(separator: " / ").prefix(PlanBlocks.maxNoteLength))
        var result = blocks
        result.replaceSubrange(index...(index + 1), with: [merged])
        return result
    }

    /// Whether block `index` can be merged with the next one.
    public static func canMerge(_ blocks: [PlanTimeBlock], at index: Int) -> Bool { blocks.indices.contains(index) && blocks.indices.contains(index + 1) }

    public static func canSplit(_ blocks: [PlanTimeBlock], at index: Int) -> Bool {
        guard blocks.indices.contains(index), blocks.count < PlanBlocks.maxCount, let s = blocks[index].startMinutes, let e = blocks[index].endMinutes else { return false }
        return e - s >= minimumSplitMinutes
    }

    /// Sorts by begin (stable), used after a time picker moved a block across its neighbour.
    public static func sorted(_ blocks: [PlanTimeBlock]) -> [PlanTimeBlock] {
        blocks.enumerated().sorted { a, b in
            let l = a.element.startMinutes ?? 0, r = b.element.startMinutes ?? 0
            return l == r ? a.offset < b.offset : l < r
        }.map(\.element)
    }

    /// Gaps between consecutive blocks in minutes (index i = gap after block i), 0 for touching blocks.
    public static func gapMinutes(_ blocks: [PlanTimeBlock]) -> [Int] {
        guard blocks.count > 1 else { return [] }
        return (0..<(blocks.count - 1)).map { i in
            guard let end = blocks[i].endMinutes, let next = blocks[i + 1].startMinutes else { return 0 }
            return max(0, next - end)
        }
    }
}
