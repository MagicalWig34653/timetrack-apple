import Foundation
import TimetrackCore

/// A calendar month (Z2). Used as page identity of the month pager and as cache key of the prefetch window.
public struct MonthKey: Hashable, Comparable, Sendable, Identifiable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        let index = year * 12 + (month - 1)
        self.year = Self.floorDiv(index, 12)
        self.month = index - Self.floorDiv(index, 12) * 12 + 1
    }

    public init(index: Int) { self.init(year: 0, month: index + 1) }

    public init?(day: LocalDay) {
        guard let parts = LocalDays.parse(day) else { return nil }
        self.init(year: parts.year, month: parts.month)
    }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }

    /// Months since year 0; stable, contiguous and usable as scroll position id.
    public var index: Int { year * 12 + (month - 1) }
    public var id: Int { index }
    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool { lhs.index < rhs.index }

    public func adding(_ months: Int) -> MonthKey { MonthKey(index: index + months) }
    public var firstDay: LocalDay { LocalDays.format(year: year, month: month, day: 1) }

    /// The six Monday-first weeks (42 days) that cover the month. Always six rows: the page height never changes between months.
    public var gridDays: [LocalDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return [] }
        let weekday = calendar.component(.weekday, from: first) // 1 = Sunday
        let lead = weekday == 1 ? 6 : weekday - 2
        let start = first.addingTimeInterval(TimeInterval(-lead * 86_400))
        return (0..<42).map { offset in
            let c = calendar.dateComponents([.year, .month, .day], from: start.addingTimeInterval(TimeInterval(offset * 86_400)))
            return LocalDays.format(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
        }
    }

    /// First and last day of the grid (inclusive) without building all 42 strings twice.
    public var gridRange: (from: LocalDay, to: LocalDay) {
        let days = gridDays
        return (days.first ?? firstDay, days.last ?? firstDay)
    }
}

/// Small marks under a day number.
public enum MonthMarker: Hashable, Sendable {
    case absence(AbsenceKind)
    case holiday
    case plan(PlanMode)
}

/// One cell of the month grid: everything the view needs, computed once (never in the scroll path).
public struct MonthCell: Hashable, Sendable, Identifiable {
    public let day: LocalDay
    public let dayNumber: Int
    public let inMonth: Bool
    public let isWeekend: Bool
    public let isHoliday: Bool
    public let markers: [MonthMarker]
    public let info: CalendarDayInfo
    public var id: LocalDay { day }
}

/// Immutable, `Sendable` render model of one month page. Built when data changes; paging only reads it.
public struct MonthSnapshot: Hashable, Sendable, Identifiable {
    public let key: MonthKey
    public let cells: [MonthCell]
    /// ISO week number per grid row (6 entries).
    public let weekNumbers: [Int]
    public var id: MonthKey { key }

    public var rows: [[MonthCell]] { stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) } }

    public static func build(key: MonthKey, holidays: [CalendarDay], absences: [Absence], planDays: [LocalDay: PlanDay]) -> MonthSnapshot {
        let days = key.gridDays
        let range = (days.first ?? "", days.last ?? "")
        // Only entries touching the grid take part in the per-cell scan.
        let relevantHolidays = holidays.filter { $0.endDate >= range.0 && $0.startDate <= range.1 }
        let relevantAbsences = absences.filter { $0.endDate >= range.0 && $0.startDate <= range.1 }
        let cells = days.map { day -> MonthCell in
            var info = CalendarDayInfo(day: day)
            for entry in relevantHolidays where entry.covers(day) {
                if entry.kind == .schoolHoliday { info.schoolHolidays.append(entry) } else { info.holidays.append(entry) }
            }
            info.absences = relevantAbsences.filter { $0.startDate <= day && day <= $0.endDate }
            info.plan = planDays[day]
            var markers: [MonthMarker] = info.absences.prefix(2).map { .absence($0.kind) }
            if info.isHoliday { markers.append(.holiday) }
            if let plan = info.plan { markers.append(.plan(plan.mode)) }
            let parts = LocalDays.parse(day)
            return MonthCell(day: day, dayNumber: parts?.day ?? 0, inMonth: parts?.year == key.year && parts?.month == key.month,
                             isWeekend: (LocalDays.isoWeekday(day) ?? 1) >= 6, isHoliday: info.isHoliday, markers: Array(markers.prefix(3)), info: info)
        }
        let weeks = stride(from: 0, to: days.count, by: 7).map { LocalDays.isoWeek(of: days[$0]) ?? 0 }
        return MonthSnapshot(key: key, cells: cells, weekNumbers: weeks)
    }
}
