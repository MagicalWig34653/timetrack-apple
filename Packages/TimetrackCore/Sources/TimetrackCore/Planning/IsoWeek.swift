import Foundation

/// ISO 8601 week labels (`2026-W44`) as used by `/time/weeks/{isoWeek}` and `/plan/weeks/{isoWeek}`.
public enum IsoWeek {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Label of the ISO week that contains `day`; the ISO year can differ from the calendar year around New Year.
    public static func label(containing day: LocalDay) -> String? {
        guard let p = LocalDays.parse(day), let date = calendar.date(from: DateComponents(year: p.year, month: p.month, day: p.day)) else { return nil }
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    /// Monday of a label such as `2026-W44`; nil for malformed labels or weeks that do not exist (e.g. W53 in a 52-week year).
    public static func monday(of label: String) -> LocalDay? {
        let parts = label.split(separator: "-")
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 3, parts[1].first == "W",
              let year = Int(parts[0]), let week = Int(parts[1].dropFirst()), (1...53).contains(week) else { return nil }
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = 2 // Monday
        guard let date = calendar.date(from: components) else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let monday = LocalDays.format(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
        return self.label(containing: monday) == label ? monday : nil
    }

    /// Calendar week number (1...53) of a label.
    public static func number(of label: String) -> Int? {
        guard let monday = monday(of: label) else { return nil }
        return LocalDays.isoWeek(of: monday)
    }
}
