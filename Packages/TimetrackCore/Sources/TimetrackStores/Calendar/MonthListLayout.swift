import Foundation
import TimetrackCore

extension MonthKey {
    /// U2: Monday-first week rows that contain at least one day of the month (4 to 6).
    public var weekRows: Int {
        let days = gridDays
        guard days.count == 42 else { return 6 }
        return stride(from: 0, to: 42, by: 7).filter { start in days[start..<start + 7].contains { MonthKey(day: $0) == self } }.count
    }
}

/// U2: geometry of the vertical month list (month sections of fixed-height rows below a fixed-height header). Everything is
/// a pure function of the fixed heights, so the month at the top of the viewport follows from the scroll offset without
/// measuring views, and a jump target is an offset instead of a lazily resolved view.
public struct MonthListLayout: Sendable, Equatable {
    public let first: MonthKey
    public let count: Int
    public let rowHeight: Double
    public let headerHeight: Double
    /// Offset of the top of each section; one more entry than months (the end of the content).
    private let starts: [Double]

    public init(first: MonthKey, count: Int, rowHeight: Double, headerHeight: Double) {
        self.first = first
        self.count = max(1, count)
        self.rowHeight = rowHeight
        self.headerHeight = headerHeight
        var starts: [Double] = [0]
        for index in 0..<self.count {
            let key = first.adding(index)
            starts.append(starts[index] + headerHeight + Double(key.weekRows) * rowHeight)
        }
        self.starts = starts
    }

    public var keys: [MonthKey] { (0..<count).map { first.adding($0) } }
    public var last: MonthKey { first.adding(count - 1) }
    public var contentHeight: Double { starts[count] }

    public func contains(_ key: MonthKey) -> Bool { key >= first && key <= last }

    /// Top of a month's section, clamped into the list.
    public func offset(of key: MonthKey) -> Double { starts[min(max(key.index - first.index, 0), count - 1)] }

    /// The month whose section covers `offset` (which is the viewport top; the section header sticks there).
    public func key(atOffset offset: Double) -> MonthKey {
        var low = 0, high = count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return first.adding(low)
    }

    /// The month that a reader would call "the one on screen": the section covering a probe a little below the sticky header, so a month
    /// whose header just scrolled under the bar counts, but one that is only peeking in at the bottom does not.
    public func visibleKey(atOffset offset: Double, probe: Double? = nil) -> MonthKey {
        key(atOffset: offset + (probe ?? headerHeight + rowHeight * 0.5))
    }

    /// Row index (0-based) of a day inside its month section, for scrolling a week into view.
    public func offset(of day: LocalDay, rowOffset: Double = 0) -> Double? {
        guard let key = MonthKey(day: day), contains(key) else { return nil }
        let gridDays = key.gridDays
        guard let index = gridDays.firstIndex(of: day) else { return nil }
        let firstRow = stride(from: 0, to: 42, by: 7).first { start in gridDays[start..<start + 7].contains { MonthKey(day: $0) == key } } ?? 0
        let row = Double(index / 7 - firstRow / 7)
        return offset(of: key) + headerHeight + row * rowHeight + rowOffset
    }
}
