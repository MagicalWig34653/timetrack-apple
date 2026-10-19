import Foundation

/// Filters of the vacation planner (ADR-0025). `from`, `to`, `maxVacationDays` and `minDaysOff` are applied by the server;
/// `minEfficiency` and `count` only filter the received list on the device.
public struct VacationPlannerFilters: Codable, Sendable, Hashable {
    public var from: LocalDay
    public var to: LocalDay
    public var maxVacationDays: Int
    public var minDaysOff: Int
    public var minEfficiency: Double
    public var count: Int

    /// Efficiency below this is a filler window (a few vacation days for hardly more days off) and hidden by default.
    public static let defaultMinEfficiency = 2.0
    /// The backend answers at most 100 suggestions; the planner always requests all of them.
    public static let fetchLimit = 100

    public init(from: LocalDay, to: LocalDay, maxVacationDays: Int = 10, minDaysOff: Int = 4, minEfficiency: Double = defaultMinEfficiency, count: Int = 10) {
        self.from = from
        self.to = to
        self.maxVacationDays = maxVacationDays
        self.minDaysOff = minDaysOff
        self.minEfficiency = minEfficiency
        self.count = count
    }

    /// Today until the end of next year (the server default).
    public static func defaults(today: LocalDay) -> VacationPlannerFilters {
        let year = LocalDays.parse(today)?.year ?? 2026
        return VacationPlannerFilters(from: today, to: LocalDays.format(year: year + 1, month: 12, day: 31))
    }

    public var isValid: Bool {
        Self.rangeValid(from: from, to: to) && (1...60).contains(maxVacationDays) && (1...60).contains(minDaysOff)
            && (1...100).contains(count) && minEfficiency >= 1 && minEfficiency <= 10
    }

    /// Server rule: `to` not before `from`, at most 18 months apart.
    public static func rangeValid(from: LocalDay, to: LocalDay) -> Bool {
        guard let start = LocalDays.parse(from), LocalDays.parse(to) != nil, to >= from else { return false }
        return to <= addMonthsKeepingDay(start, months: 18)
    }

    private static func addMonthsKeepingDay(_ p: (year: Int, month: Int, day: Int), months: Int) -> LocalDay {
        let index = p.year * 12 + (p.month - 1) + months
        let year = index / 12
        let month = index % 12 + 1
        let firstOfNext = LocalDays.format(year: month == 12 ? year + 1 : year, month: month == 12 ? 1 : month + 1, day: 1)
        let lastDay = LocalDays.adding(-1, to: firstOfNext).flatMap(LocalDays.parse)?.day ?? 28
        return LocalDays.format(year: year, month: month, day: min(p.day, lastDay))
    }

    /// The query for the server; the display-only filters are not part of it.
    public var query: VacationSuggestionQuery {
        VacationSuggestionQuery(from: from, to: to, maxVacationDays: maxVacationDays, minDaysOff: minDaysOff, limit: Self.fetchLimit)
    }

    /// Whether `other` needs a new request (the server-side part differs).
    public func needsFetch(comparedTo other: VacationPlannerFilters) -> Bool {
        from != other.from || to != other.to || maxVacationDays != other.maxVacationDays || minDaysOff != other.minDaysOff
    }

    /// A remembered value that is broken, or whose range already ended, falls back to the defaults; a start in the past moves to today.
    public func sanitized(today: LocalDay) -> VacationPlannerFilters {
        let fallback = Self.defaults(today: today)
        var merged = self
        if merged.to < today {
            merged.from = fallback.from
            merged.to = fallback.to
        } else if merged.from < today {
            merged.from = today
        }
        return merged.isValid ? merged : fallback
    }
}

public enum VacationPlanner {
    /// Best `count` suggestions with at least `minEfficiency`; `hidden` is the number removed by the efficiency filter.
    public static func visible(_ all: [VacationSuggestion], minEfficiency: Double, count: Int) -> (shown: [VacationSuggestion], hidden: Int) {
        let kept = all.filter { $0.efficiency >= minEfficiency }
        return (Array(kept.prefix(max(0, count))), all.count - kept.count)
    }

    public struct Block: Sendable, Hashable {
        public let start: LocalDay
        public let end: LocalDay
        public let dates: [LocalDay]
    }

    /// Vacation blocks to book for a suggestion: consecutive vacation dates form one block as long as only weekends, holidays or other
    /// free days lie between them. A day that is already booked as vacation splits the block (one absence must not overlap another).
    /// The absence covers the first to the last vacation date of the block; the server books work days only.
    public static func blocks(for suggestion: VacationSuggestion) -> [Block] {
        let booked = Set(suggestion.conflicts.filter { $0.type == .alreadyVacation }.map(\.date))
        var blocks: [(start: LocalDay, end: LocalDay, dates: [LocalDay])] = []
        for date in suggestion.vacationDates.sorted() {
            if var last = blocks.last, !spansBooked(from: last.end, to: date, booked: booked) {
                last.end = date
                last.dates.append(date)
                blocks[blocks.count - 1] = last
            } else {
                blocks.append((date, date, [date]))
            }
        }
        return blocks.map { Block(start: $0.start, end: $0.end, dates: $0.dates) }
    }

    private static func spansBooked(from: LocalDay, to: LocalDay, booked: Set<LocalDay>) -> Bool {
        guard var day = LocalDays.adding(1, to: from) else { return false }
        while day < to {
            if booked.contains(day) { return true }
            guard let next = LocalDays.adding(1, to: day) else { return false }
            day = next
        }
        return false
    }

    public struct ConflictGroup: Sendable, Hashable {
        public let type: VacationConflictType
        public let dates: [LocalDay]
    }

    /// What the user has to confirm before the suggestion is booked.
    public struct Requirements: Sendable, Hashable {
        /// Conflicts that warn (school day, absence, planned work), grouped by type with their days; already entered vacation is excluded.
        public let conflicts: [ConflictGroup]
        public let exceedsBudget: Bool
        public var needsConflictAcknowledgement: Bool { !conflicts.isEmpty }
        public var needsAny: Bool { needsConflictAcknowledgement || exceedsBudget }
    }

    public static func requirements(for suggestion: VacationSuggestion) -> Requirements {
        let order: [VacationConflictType] = [.schoolDay, .absence, .plan, .unknown]
        let groups = order.compactMap { type -> ConflictGroup? in
            let dates = Set(suggestion.conflicts.filter { $0.type == type }.map(\.date)).sorted()
            return dates.isEmpty ? nil : ConflictGroup(type: type, dates: dates)
        }
        return Requirements(conflicts: groups, exceedsBudget: !suggestion.fitsBudget)
    }

    /// Sorted unique days that are already entered as vacation inside the window.
    public static func alreadyBookedDates(_ suggestion: VacationSuggestion) -> [LocalDay] {
        Set(suggestion.conflicts.filter { $0.type == .alreadyVacation }.map(\.date)).sorted()
    }

    // MARK: Day strip

    public enum CellKind: Sendable, Hashable { case vacation, holiday, weekend, booked, free }

    public struct Cell: Sendable, Hashable, Identifiable {
        public let date: LocalDay
        public let kind: CellKind
        /// ISO weekday, Monday = 1.
        public let weekday: Int
        public let day: Int
        public let holidayName: String?
        /// A warning conflict on this day (never `alreadyVacation`).
        public let conflict: VacationConflictType?
        public var id: LocalDay { date }
    }

    /// One cell per calendar day from start to end for the day strip.
    public static func cells(for suggestion: VacationSuggestion) -> [Cell] {
        let vacation = Set(suggestion.vacationDates)
        let holidays = Dictionary(suggestion.holidays.map { ($0.date, $0.name) }, uniquingKeysWith: { first, _ in first })
        let booked = Set(suggestion.conflicts.filter { $0.type == .alreadyVacation }.map(\.date))
        var conflictOf: [LocalDay: VacationConflictType] = [:]
        for conflict in suggestion.conflicts where conflict.type != .alreadyVacation && conflictOf[conflict.date] == nil { conflictOf[conflict.date] = conflict.type }
        var cells: [Cell] = []
        var date = suggestion.start
        // Bounded by the server limit (at most 60 free days + margin) so a malformed range can never loop endlessly.
        while date <= suggestion.end, cells.count < 400 {
            let weekday = LocalDays.isoWeekday(date) ?? 1
            let kind: CellKind
            if holidays[date] != nil { kind = .holiday }
            else if vacation.contains(date) { kind = .vacation }
            else if booked.contains(date) { kind = .booked }
            else if weekday >= 6 { kind = .weekend }
            else { kind = .free }
            cells.append(Cell(date: date, kind: kind, weekday: weekday, day: LocalDays.parse(date)?.day ?? 0, holidayName: holidays[date], conflict: conflictOf[date]))
            guard let next = LocalDays.adding(1, to: date) else { break }
            date = next
        }
        return cells
    }
}
