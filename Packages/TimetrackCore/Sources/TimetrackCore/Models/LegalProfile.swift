import Foundation

// P15: legal profiles of a work model (contract 0.29.0+, ADR-0028). The profile only drives the informative hints of the backend
// (`breakHints`, `legalWarnings`); recorded times are never rejected, and an empty warning list is never "compliant".

/// Known profile ids. Unknown ids from newer servers stay usable as raw strings.
public enum LegalProfileID {
    public static let adult = "arbzg-adult-de"
    public static let minor = "jarbschg-minor-de"
    public static let all = [adult, minor]
}

/// `GET /legal-profiles`: one profile with its rules and sources.
public struct LegalProfile: Codable, Sendable, Hashable, Identifiable {
    public struct BreakRule: Codable, Sendable, Hashable {
        public let afterSeconds: Int
        public let requiredSeconds: Int
    }

    public struct School: Codable, Sendable, Hashable {
        public let fullDayLessons: Int?
        public let fullDayCreditSeconds: Int?
        public let fullDaysPerWeek: Int?
        public let blockWeekLessons: Int?
        public let blockWeekDays: Int?
        public let blockWeekCreditSeconds: Int?
        public let noWorkBeforeMinutes: Int?
    }

    public let id: String
    public let name: String
    public let breakRules: [BreakRule]
    public let minimumBreakPartSeconds: Int?
    public let maximumContinuousSeconds: Int?
    public let maxDailySeconds: Int?
    public let maxWeeklySeconds: Int?
    public let maxWorkdaysPerWeek: Int?
    public let minimumRestSeconds: Int?
    public let restrictedWeekdays: [Int]?
    public let school: School?
    public let sources: [String]
    public let informationalOnly: Bool?

    public init(id: String, name: String, breakRules: [BreakRule] = [], minimumBreakPartSeconds: Int? = nil, maximumContinuousSeconds: Int? = nil,
                maxDailySeconds: Int? = nil, maxWeeklySeconds: Int? = nil, maxWorkdaysPerWeek: Int? = nil, minimumRestSeconds: Int? = nil,
                restrictedWeekdays: [Int]? = nil, school: School? = nil, sources: [String] = [], informationalOnly: Bool? = true) {
        self.id = id; self.name = name; self.breakRules = breakRules; self.minimumBreakPartSeconds = minimumBreakPartSeconds
        self.maximumContinuousSeconds = maximumContinuousSeconds; self.maxDailySeconds = maxDailySeconds; self.maxWeeklySeconds = maxWeeklySeconds
        self.maxWorkdaysPerWeek = maxWorkdaysPerWeek; self.minimumRestSeconds = minimumRestSeconds; self.restrictedWeekdays = restrictedWeekdays
        self.school = school; self.sources = sources; self.informationalOnly = informationalOnly
    }

    /// Profiles with a school section ask for the number of lessons per school day (`schoolLessonCount`).
    public var recordsSchoolLessons: Bool { school != nil }

    /// Offline fallback for servers without `GET /legal-profiles` (404): the two known ids with German names and no rule details.
    public static let fallback: [LegalProfile] = [
        LegalProfile(id: LegalProfileID.adult, name: "Arbeitszeitgesetz (Erwachsene)"),
        LegalProfile(id: LegalProfileID.minor, name: "Jugendarbeitsschutzgesetz (unter 18)", school: School(
            fullDayLessons: 6, fullDayCreditSeconds: 28_800, fullDaysPerWeek: 1, blockWeekLessons: 25, blockWeekDays: 5,
            blockWeekCreditSeconds: 144_000, noWorkBeforeMinutes: 540)),
    ]

    /// Short German summary of the rules the backend reports, e.g. `8 h pro Tag, 40 h pro Woche, höchstens 5 Arbeitstage, 12 h Ruhezeit`.
    public var ruleSummary: String {
        var parts: [String] = []
        if let day = maxDailySeconds { parts.append("\(Self.hours(day)) pro Tag") }
        if let week = maxWeeklySeconds { parts.append("\(Self.hours(week)) pro Woche") }
        if let days = maxWorkdaysPerWeek { parts.append("höchstens \(days) Arbeitstage pro Woche") }
        if let rest = minimumRestSeconds { parts.append("\(Self.hours(rest)) Ruhezeit") }
        return parts.joined(separator: ", ")
    }

    private static func hours(_ seconds: Int) -> String {
        let value = Double(seconds) / 3600
        return value == value.rounded() ? "\(Int(value)) h" : String(format: "%.1f h", value).replacingOccurrences(of: ".", with: ",")
    }
}

/// `legalWarnings` entry of a day evaluation.
public struct LegalWarning: Codable, Sendable, Hashable {
    /// Contract codes: `daily_limit`, `weekly_limit`, `five_day_week`, `rest_period`, `weekend_work`, `work_after_full_school_day`, `work_before_school`.
    public let code: String

    public init(code: String) { self.code = code }

    /// German text; unknown codes fall back to a neutral sentence (the list is informational and may grow on the server).
    public var germanText: String {
        switch code {
        case "daily_limit": "Tagesgrenze überschritten"
        case "weekly_limit": "Wochengrenze überschritten"
        case "five_day_week": "Mehr als fünf Arbeitstage in dieser Woche"
        case "rest_period": "Ruhezeit zum Vortag unterschritten"
        case "weekend_work": "Wochenendarbeit – Ausnahmen prüfen"
        case "work_after_full_school_day": "Arbeit nach vollem Berufsschultag"
        case "work_before_school": "Arbeit vor 9 Uhr am Berufsschultag"
        default: "Weiterer Hinweis des Servers"
        }
    }
}

extension BreakHint {
    /// German text for the contract codes (adult and minor profile); unknown codes get a neutral sentence.
    public var germanText: String {
        switch code {
        case "break_missing_30": "Pause von 30 Minuten fehlt"
        case "break_missing_45": "Pause von 45 Minuten fehlt"
        case "break_missing_60": "Pause von 60 Minuten fehlt"
        case "break_part_too_short": "Ein Pausenteil ist kürzer als 15 Minuten"
        case "work_over_6h_without_break": "Mehr als 6 Stunden ohne Pause"
        case "work_over_4h30_without_break": "Mehr als 4,5 Stunden ohne Pause"
        default: "Pausenhinweis des Servers"
        }
    }
}

/// Notice that always accompanies profile choices and warnings.
public enum LegalNotice {
    public static let informationalOnly = "Informative Hinweise, keine Rechtsberatung. Eine leere Hinweisliste bedeutet nicht, dass alles rechtskonform ist."
}
