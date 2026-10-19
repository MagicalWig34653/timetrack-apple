import Foundation

// `GET /vacation/suggestions` (contract v0.22.0, ADR-0025). The endpoint is read-only; booking goes through `POST /absences`.

public enum VacationSuggestionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case bridge
    case holidayCluster = "holiday_cluster"
    case schoolHolidayExtension = "school_holiday_extension"
    case longBreak = "long_break"
    case unknown

    public init(from decoder: Decoder) throws {
        self = VacationSuggestionKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public enum VacationConflictType: String, Codable, Sendable, Hashable, CaseIterable {
    /// Sickness or other absence.
    case absence
    /// Planned vocational-school day.
    case schoolDay = "school_day"
    /// Planned work.
    case plan
    /// Vacation that is already entered (costs nothing, lies inside the window).
    case alreadyVacation = "already_vacation"
    case unknown

    public init(from decoder: Decoder) throws {
        self = VacationConflictType(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    /// Conflicts the user must acknowledge before booking. Already entered vacation is only informative.
    public var needsAcknowledgement: Bool { self != .alreadyVacation }
}

public struct VacationConflict: Codable, Sendable, Hashable {
    public let date: LocalDay
    public let type: VacationConflictType
}

public struct SuggestionHoliday: Codable, Sendable, Hashable {
    public let date: LocalDay
    public let name: String
}

public struct SuggestionSchoolHoliday: Codable, Sendable, Hashable {
    public let startDate: LocalDay
    public let endDate: LocalDay
    public let name: String
}

public struct VacationBudget: Codable, Sendable, Hashable {
    public let entitlementDays: Double
    public let takenDays: Double
    public let plannedDays: Double
    public let remainingDays: Double
}

public struct VacationSuggestion: Codable, Sendable, Hashable, Identifiable {
    /// Stable hash of start, end and vacation dates (16 hex characters).
    public let id: String
    public let kind: VacationSuggestionKind
    /// First and last free day of the window (weekends and holidays included).
    public let start: LocalDay
    public let end: LocalDay
    /// Work days that cost vacation (whole days).
    public let vacationDates: [LocalDay]
    public let vacationDaysNeeded: Int
    public let totalDaysOff: Int
    /// `totalDaysOff / vacationDaysNeeded`, rounded to two decimals.
    public let efficiency: Double
    public let holidays: [SuggestionHoliday]
    public let schoolHolidays: [SuggestionSchoolHoliday]
    public let conflicts: [VacationConflict]
    /// Checked per suggestion on its own, not cumulatively across the list.
    public let fitsBudget: Bool
    /// Days left in the year of `start` after this suggestion (may be negative).
    public let remainingAfter: Double
}

public struct VacationSuggestions: Codable, Sendable, Hashable {
    public let from: LocalDay
    public let to: LocalDay
    public let budget: VacationBudget
    public let suggestions: [VacationSuggestion]
}

/// Query of `GET /vacation/suggestions`.
public struct VacationSuggestionQuery: Sendable, Hashable {
    public var from: LocalDay?
    public var to: LocalDay?
    public var maxVacationDays: Int?
    public var minDaysOff: Int?
    public var limit: Int?

    public init(from: LocalDay? = nil, to: LocalDay? = nil, maxVacationDays: Int? = nil, minDaysOff: Int? = nil, limit: Int? = nil) {
        self.from = from
        self.to = to
        self.maxVacationDays = maxVacationDays
        self.minDaysOff = minDaysOff
        self.limit = limit
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let from { items.append(URLQueryItem(name: "from", value: from)) }
        if let to { items.append(URLQueryItem(name: "to", value: to)) }
        if let maxVacationDays { items.append(URLQueryItem(name: "maxVacationDays", value: String(maxVacationDays))) }
        if let minDaysOff { items.append(URLQueryItem(name: "minDaysOff", value: String(minDaysOff))) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        return items
    }
}
