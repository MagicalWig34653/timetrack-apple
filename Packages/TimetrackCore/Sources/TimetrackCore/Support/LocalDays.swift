import Foundation

/// Helpers for `YYYY-MM-DD` local days. Day arithmetic is calendar based in a fixed UTC calendar, so DST never shifts a label.
public enum LocalDays {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    public static func parse(_ day: LocalDay) -> (year: Int, month: Int, day: Int)? {
        let parts = day.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        // Reject non-existent days such as 2026-02-30.
        var components = DateComponents(year: y, month: m, day: d)
        components.calendar = utcCalendar
        guard let date = utcCalendar.date(from: components), utcCalendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: y, month: m, day: d) else { return nil }
        return (y, m, d)
    }

    public static func format(year: Int, month: Int, day: Int) -> LocalDay {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func adding(_ days: Int, to day: LocalDay) -> LocalDay? {
        guard let p = parse(day),
              let date = utcCalendar.date(from: DateComponents(year: p.year, month: p.month, day: p.day)),
              let moved = utcCalendar.date(byAdding: .day, value: days, to: date) else { return nil }
        let c = utcCalendar.dateComponents([.year, .month, .day], from: moved)
        return format(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    public static func daysBetween(_ from: LocalDay, _ to: LocalDay) -> Int? {
        guard let a = parse(from), let b = parse(to),
              let da = utcCalendar.date(from: DateComponents(year: a.year, month: a.month, day: a.day)),
              let db = utcCalendar.date(from: DateComponents(year: b.year, month: b.month, day: b.day)) else { return nil }
        return utcCalendar.dateComponents([.day], from: da, to: db).day
    }

    /// 1 = Monday ... 7 = Sunday, as in the work model.
    public static func isoWeekday(_ day: LocalDay) -> Int? {
        guard let p = parse(day), let date = utcCalendar.date(from: DateComponents(year: p.year, month: p.month, day: p.day)) else { return nil }
        let weekday = utcCalendar.component(.weekday, from: date) // 1 = Sunday
        return weekday == 1 ? 7 : weekday - 1
    }

    /// ISO 8601 calendar week (1...53) of a day (Monday start, week 1 contains the first Thursday).
    public static func isoWeek(of day: LocalDay) -> Int? {
        guard let p = parse(day) else { return nil }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let date = calendar.date(from: DateComponents(year: p.year, month: p.month, day: p.day)) else { return nil }
        return calendar.component(.weekOfYear, from: date)
    }

    public static func mondayOfWeek(containing day: LocalDay) -> LocalDay? {
        guard let weekday = isoWeekday(day) else { return nil }
        return adding(-(weekday - 1), to: day)
    }

    /// Splits an inclusive range into pieces of at most `maxDays` days (API limit 93 for `/time/days`).
    public static func chunks(from: LocalDay, to: LocalDay, maxDays: Int) throws -> [(from: LocalDay, to: LocalDay)] {
        guard let span = daysBetween(from, to), span >= 0 else { throw TimetrackError.decoding("Invalid day range") }
        var result: [(LocalDay, LocalDay)] = []
        var start = from
        while true {
            guard let limit = adding(maxDays - 1, to: start) else { throw TimetrackError.decoding("Invalid day range") }
            if limit >= to {
                result.append((start, to))
                break
            }
            result.append((start, limit))
            guard let next = adding(1, to: limit) else { throw TimetrackError.decoding("Invalid day range") }
            start = next
        }
        return result
    }
}

/// Converts between instants and local days in one time zone (the work model's).
public struct DayCalendar: Sendable {
    public let timeZone: TimeZone

    public init(timeZone: TimeZone) { self.timeZone = timeZone }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    public func day(for instant: Date) -> LocalDay {
        let c = calendar.dateComponents([.year, .month, .day], from: instant)
        return LocalDays.format(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    /// Start of the local day and start of the next one (half-open `[start, end)`).
    public func interval(of day: LocalDay) -> (start: Date, end: Date)? {
        guard let p = LocalDays.parse(day),
              let start = calendar.date(from: DateComponents(year: p.year, month: p.month, day: p.day)),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, end)
    }

    /// Instant for a wall-clock time on a local day (used by edit forms).
    public func instant(day: LocalDay, hour: Int, minute: Int) -> Date? {
        guard let p = LocalDays.parse(day) else { return nil }
        return calendar.date(from: DateComponents(year: p.year, month: p.month, day: p.day, hour: hour, minute: minute))
    }

    public func hourAndMinute(of instant: Date) -> (hour: Int, minute: Int) {
        let c = calendar.dateComponents([.hour, .minute], from: instant)
        return (c.hour ?? 0, c.minute ?? 0)
    }
}
