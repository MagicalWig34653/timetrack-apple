import Foundation

// Week overview (`GET /time/weeks/{isoWeek}`) and week plan (`GET/PUT /plan/weeks/{isoWeek}`), contract v0.17.0 (K1, ADR-0021).
// Unknown enum values decode as `.unknown` so a newer server never breaks the whole week.

public enum WeekMark: String, Codable, Sendable, Hashable, CaseIterable {
    case work, school, vacation, sick, holiday, excused, off, unknown

    public init(from decoder: Decoder) throws {
        self = WeekMark(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// Why a plan day does not count (`PlanWeekDay.blockedBy`). Any value, known or not, means blocked.
public enum PlanBlockedBy: String, Codable, Sendable, Hashable {
    case holiday, vacation, sick, excused, unknown

    public init(from decoder: Decoder) throws {
        self = PlanBlockedBy(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public struct TimeWeekAbsence: Codable, Sendable, Hashable {
    public let kind: AbsenceKind
    public let status: AbsenceStatus
    public let halfDay: Bool
}

public struct TimeWeekDay: Codable, Sendable, Hashable, Identifiable {
    public let date: LocalDay
    /// ISO weekday, Monday = 1.
    public let weekday: Int
    public let mark: WeekMark
    public let targetSeconds: Int
    public let plannedSeconds: Int?
    public let planMode: PlanMode?
    public let workSeconds: Int
    public let creditSeconds: Int
    public let rawWorkSeconds: Int
    /// Actual gaps between the day's segments (no invented breaks).
    public let breakSeconds: Int
    public let breakDeductionSeconds: Int
    public let travelSeconds: Int
    public let schoolSeconds: Int
    /// `work + credit - target`; nil after today.
    public let balanceSeconds: Int?
    public let firstStart: Date?
    public let lastEnd: Date?
    public let segmentsCount: Int
    public let absences: [TimeWeekAbsence]
    public let provisional: Bool
    public let isToday: Bool
    public let isFuture: Bool
    /// N4: name of the holiday or company day ("Heiligabend"), also on days without a target.
    public let holidayName: String?
    /// N4: `half` (mark stays `work`, target halved), `full` (mark `holiday`) or nil.
    public let companyDayTreatment: CompanyDayTreatment?
    public var id: LocalDay { date }

    /// "Heiligabend (halber Tag)" / "Neujahr"; nil without a holiday name.
    public var holidayLabel: String? { holidayName.map { CompanyDayText.title(name: $0, treatment: companyDayTreatment) } }

    /// Hours shown for a day: evaluated work plus credit (school credit, paid absence), like the Zeit list.
    public var hoursSeconds: Int { workSeconds + creditSeconds }
}

public struct TimeWeekLongestDay: Codable, Sendable, Hashable {
    public let date: LocalDay
    public let seconds: Int
}

public struct TimeWeekSummary: Codable, Sendable, Hashable {
    public let targetSeconds: Int
    public let targetToDateSeconds: Int
    public let workSeconds: Int
    public let creditSeconds: Int
    /// Sum of the day balances up to today.
    public let balanceSeconds: Int
    public let plannedSeconds: Int?
    public let accountBalanceBeforeSeconds: Int
    public let accountBalanceAfterSeconds: Int
    public let accountBalanceAsOf: LocalDay
    /// Half days count 0.5.
    public let vacationDays: Double
    public let sickDays: Int
    public let schoolDays: Int
    public let holidayDays: Int
    public let workDays: Int
    public let travelSeconds: Int
    public let breakSeconds: Int
    /// `HH:mm` local.
    public let averageStart: String?
    public let averageEnd: String?
    public let longestDay: TimeWeekLongestDay?
    public let provisional: Bool

    public var hoursSeconds: Int { workSeconds + creditSeconds }
}

public struct TimeWeek: Codable, Sendable, Hashable {
    public let week: String
    public let from: LocalDay
    public let to: LocalDay
    public let days: [TimeWeekDay]
    public let summary: TimeWeekSummary
}

// MARK: - Week plan

public struct PlanWeekDay: Codable, Sendable, Hashable, Identifiable {
    public let date: LocalDay
    public let weekday: Int
    public let targetSeconds: Int
    /// Effective planned seconds: 0 on a blocked day, nil without plan or without times.
    public let plannedSeconds: Int?
    public let blockedBy: PlanBlockedBy?
    public let plan: PlanDay?
    public var id: LocalDay { date }

    public var isBlocked: Bool { blockedBy != nil }
}

public struct PlanWeekTotals: Codable, Sendable, Hashable {
    public let targetSeconds: Int
    public let plannedSeconds: Int
    /// `plannedSeconds - targetSeconds`.
    public let differenceSeconds: Int

    public init(targetSeconds: Int, plannedSeconds: Int, differenceSeconds: Int) {
        self.targetSeconds = targetSeconds
        self.plannedSeconds = plannedSeconds
        self.differenceSeconds = differenceSeconds
    }
}

public struct PlanWeek: Codable, Sendable, Hashable {
    public let week: String
    public let from: LocalDay
    public let to: LocalDay
    public let days: [PlanWeekDay]
    public let totals: PlanWeekTotals
}

/// One day of `PUT /plan/weeks/{isoWeek}`: the day's date plus the same fields as `PlanDayInput`.
public struct PlanWeekEntry: Encodable, Sendable, Hashable {
    public var date: LocalDay
    public var input: PlanDayInput

    public init(date: LocalDay, input: PlanDayInput) {
        self.date = date
        self.input = input
    }

    private enum CodingKeys: String, CodingKey { case date }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try input.encode(to: encoder)
    }
}

/// Body of `PUT /plan/weeks/{isoWeek}`: all or nothing in one transaction; `replace` also deletes plans not listed.
public struct PlanWeekInput: Encodable, Sendable, Hashable {
    public var replace: Bool
    public var days: [PlanWeekEntry]

    public init(replace: Bool, days: [PlanWeekEntry]) {
        self.replace = replace
        self.days = days
    }
}
