import Foundation

// N4 (contract 0.32.0, ADR-0029): company days. Fixed month/day rules per account (24.12. and 31.12. by default) that count as
// a work day (`none`), a half day (`half`: target halved, the day stays a work day) or a holiday (`full`).

public enum CompanyDayTreatment: Codable, Sendable, Hashable {
    case none, half, full
    /// A value a newer server may send; kept verbatim so a settings round trip never rewrites it.
    case other(String)

    public static let selectable: [CompanyDayTreatment] = [.none, .half, .full]

    public var rawValue: String {
        switch self {
        case .none: "none"
        case .half: "half"
        case .full: "full"
        case .other(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "none": self = .none
        case "half": self = .half
        case "full": self = .full
        default: self = .other(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// German label for pickers ("Keine", "Halber Tag", "Ganzer Tag").
    public var pickerTitle: String {
        switch self {
        case .none: "Keine"
        case .half: "Halber Tag"
        case .full: "Ganzer Tag"
        case .other: "Unbekannt"
        }
    }

    /// Suffix appended to the day's name: "Heiligabend (halber Tag)". Full days read like any holiday.
    public var titleSuffix: String? {
        switch self {
        case .half: "halber Tag"
        default: nil
        }
    }

    /// `half` keeps the day a work day with a halved target, so it is not a full holiday.
    public var isHalfDay: Bool { self == .half }
}

public enum CompanyDayText {
    /// "Heiligabend (halber Tag)" for half days, the plain name otherwise.
    public static func title(name: String, treatment: CompanyDayTreatment?) -> String {
        guard let suffix = treatment?.titleSuffix else { return name }
        return "\(name) (\(suffix))"
    }
}

extension CompanyDayText {
    /// Accessible explanation like the PWA's `holidayHint`: "Heiligabend – halber Betriebstag, Soll halbiert".
    public static func hint(name: String, treatment: CompanyDayTreatment?) -> String {
        switch treatment {
        case .half: "\(name) – halber Betriebstag, Soll halbiert"
        case .full: "\(name) – Betriebstag, wie ein Feiertag"
        default: name
        }
    }
}

/// What a day of the week planner/list says about its holiday or company day (AUD3-B, ADR-0029).
public struct HolidayNote: Sendable, Hashable {
    public let name: String
    public let treatment: CompanyDayTreatment?

    public init(name: String, treatment: CompanyDayTreatment?) {
        self.name = name
        self.treatment = treatment
    }

    /// A half company day stays a work day: target halved, at most half a vacation day.
    public var isHalfDay: Bool { treatment?.isHalfDay == true }
    /// Chip text: "Heiligabend ½" for half days, the plain name otherwise.
    public var badge: String { isHalfDay ? "\(name) ½" : name }
    public var hint: String { CompanyDayText.hint(name: name, treatment: treatment) }

    /// Notes for the seven days from `monday` out of the year lists of `GET /calendar/holidays` (kind holiday only).
    /// A full holiday wins over a half company day on the same date.
    public static func notes(from monday: LocalDay, in holidays: [CalendarDay]) -> [LocalDay: HolidayNote] {
        var result: [LocalDay: HolidayNote] = [:]
        for offset in 0..<7 {
            guard let day = LocalDays.adding(offset, to: monday) else { continue }
            let matching = holidays.filter { $0.kind == .holiday && $0.startDate <= day && day <= $0.endDate }
            guard let chosen = matching.first(where: { !$0.isHalfDay }) ?? matching.first else { continue }
            result[day] = HolidayNote(name: chosen.name, treatment: chosen.companyTreatment)
        }
        return result
    }
}

/// One fixed month/day rule of `VacationSettings.companyDays`.
public struct CompanyDayRule: Codable, Sendable, Hashable, Identifiable {
    public var month: Int
    public var day: Int
    public var treatment: CompanyDayTreatment
    /// Display name; nil/empty makes the server use Heiligabend, Silvester or "Betriebsfreier Tag".
    public var name: String?

    public var id: String { String(format: "%02d-%02d", month, day) }

    public init(month: Int, day: Int, treatment: CompanyDayTreatment, name: String? = nil) {
        self.month = month
        self.day = day
        self.treatment = treatment
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case month, day, treatment, name }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(month, forKey: .month)
        try c.encode(day, forKey: .day)
        try c.encode(treatment, forKey: .treatment)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        try c.encode(trimmed?.isEmpty == false ? trimmed : nil, forKey: .name)
    }

    public var isChristmasEve: Bool { month == 12 && day == 24 }
    public var isNewYearsEve: Bool { month == 12 && day == 31 }
    /// The two rules the server always lists; they cannot be removed, only set to "Keine".
    public var isBuiltInSlot: Bool { isChristmasEve || isNewYearsEve }

    /// The name shown to the user, with the server's defaults when none is set.
    public var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if isChristmasEve { return "Heiligabend" }
        if isNewYearsEve { return "Silvester" }
        return "Betriebsfreier Tag"
    }

    public var dateText: String { String(format: "%02d.%02d.", day, month) }
}

/// Editing rules for the list of company days (limits mirror the server: at most 12 rules, name up to 80 characters).
public enum CompanyDayRules {
    public static let maxRules = 12
    public static let maxNameLength = 80

    public enum Problem: Equatable, Sendable {
        case invalidDate, leapDay, duplicate, tooMany, nameTooLong

        public var germanMessage: String {
            switch self {
            case .invalidDate: "Bitte ein gültiges Datum als Tag.Monat. eingeben, z. B. 12.06."
            case .leapDay: "Der 29.02. ist nicht möglich."
            case .duplicate: "Für dieses Datum gibt es bereits eine Regel."
            case .tooMany: "Es sind höchstens 12 Regeln möglich."
            case .nameTooLong: "Der Name darf höchstens 80 Zeichen lang sein."
            }
        }
    }

    /// The two rules every account shows, set to "Keine".
    public static var defaults: [CompanyDayRule] {
        [CompanyDayRule(month: 12, day: 24, treatment: .none), CompanyDayRule(month: 12, day: 31, treatment: .none)]
    }

    /// `rules` as the server list, with 24.12. and 31.12. always present and sorted by date.
    public static func normalized(_ rules: [CompanyDayRule]?) -> [CompanyDayRule] {
        var result = rules ?? []
        for fixed in defaults where !result.contains(where: { $0.month == fixed.month && $0.day == fixed.day }) { result.append(fixed) }
        return result.sorted { ($0.month, $0.day) < ($1.month, $1.day) }
    }

    /// Parses "12.06." or "12.06" into month/day; nil when it is not a calendar date of a leap year.
    public static func parseDate(_ text: String) -> (month: Int, day: Int)? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2, let day = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month), day >= 1 else { return nil }
        let lengths = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= lengths[month - 1] ? (month, day) : nil
    }

    /// Checks a new own rule against the existing list; nil means it can be added.
    public static func problem(adding month: Int, day: Int, name: String?, to rules: [CompanyDayRule]) -> Problem? {
        if month == 2 && day == 29 { return .leapDay }
        guard parseDate(String(format: "%d.%d.", day, month)) != nil else { return .invalidDate }
        if rules.contains(where: { $0.month == month && $0.day == day }) { return .duplicate }
        if rules.count >= maxRules { return .tooMany }
        if (name?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > maxNameLength { return .nameTooLong }
        return nil
    }

    /// Sets the treatment of the rule at `month`/`day`; the rule is created when missing.
    public static func setting(_ treatment: CompanyDayTreatment, month: Int, day: Int, in rules: [CompanyDayRule]) -> [CompanyDayRule] {
        var result = rules
        if let index = result.firstIndex(where: { $0.month == month && $0.day == day }) {
            result[index].treatment = treatment
        } else {
            result.append(CompanyDayRule(month: month, day: day, treatment: treatment))
        }
        return normalized(result)
    }

    /// Own rules (everything except 24.12. and 31.12.).
    public static func ownRules(_ rules: [CompanyDayRule]) -> [CompanyDayRule] { rules.filter { !$0.isBuiltInSlot } }
}
