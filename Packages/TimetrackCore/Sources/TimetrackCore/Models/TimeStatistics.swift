import Foundation

/// `GET /time/statistics` (contract v0.28.0): one bucket per day, ISO week or month with target, actual, balance, kinds, absences and breaks.
public enum StatisticsGranularity: String, Codable, Sendable, CaseIterable, Identifiable {
    case day, week, month
    public var id: String { rawValue }

    /// Longest range the server accepts for the whole request (`range_too_large` above 1100 days).
    public static let maxDays = 1100
    /// Day buckets get unreadable beyond roughly three months, so the app limits them.
    public static let maxDaysForDay = 93
}

public enum StatisticsBasis: String, Codable, Sendable, CaseIterable, Identifiable {
    case evaluated, raw
    public var id: String { rawValue }
}

public struct StatisticsKinds: Codable, Sendable, Hashable {
    public let work: Int
    public let school: Int
    public let travel: Int

    public init(work: Int = 0, school: Int = 0, travel: Int = 0) {
        self.work = work
        self.school = school
        self.travel = travel
    }

    public var total: Int { work + school + travel }
}

public struct StatisticsAbsences: Codable, Sendable, Hashable {
    public let vacation: Double
    public let sick: Double
    public let excused: Double
    public let holiday: Double
    public let school: Double

    public init(vacation: Double = 0, sick: Double = 0, excused: Double = 0, holiday: Double = 0, school: Double = 0) {
        self.vacation = vacation
        self.sick = sick
        self.excused = excused
        self.holiday = holiday
        self.school = school
    }
}

public struct StatisticsBucket: Codable, Sendable, Hashable, Identifiable {
    /// `2026-10-12` (day), `2026-W42` (week) or `2026-10` (month).
    public let label: String
    public let from: LocalDay
    public let to: LocalDay
    public let days: Int
    public let targetSeconds: Int
    public let targetToDateSeconds: Int
    public let actualSeconds: Int
    public let creditSeconds: Int
    public let evaluatedWorkSeconds: Int
    public let rawWorkSeconds: Int
    public let roundingSeconds: Int
    public let deltaSeconds: Int
    public let overtimeSeconds: Int
    public let undertimeSeconds: Int
    /// Running account balance at `balanceAsOf`; nil before the account starts.
    public let balanceSeconds: Int?
    public let balanceAsOf: LocalDay?
    public let kindSeconds: StatisticsKinds
    public let absences: StatisticsAbsences
    public let absenceDays: Double
    public let breakSeconds: Int
    public let breakDeductionSeconds: Int
    public let workDays: Int
    public let provisional: Bool

    public var id: String { label }

    public init(label: String, from: LocalDay, to: LocalDay, days: Int = 1, targetSeconds: Int = 0, targetToDateSeconds: Int? = nil, actualSeconds: Int = 0,
                creditSeconds: Int = 0, evaluatedWorkSeconds: Int = 0, rawWorkSeconds: Int = 0, roundingSeconds: Int = 0, deltaSeconds: Int = 0,
                overtimeSeconds: Int = 0, undertimeSeconds: Int = 0, balanceSeconds: Int? = nil, balanceAsOf: LocalDay? = nil,
                kindSeconds: StatisticsKinds = .init(), absences: StatisticsAbsences = .init(), absenceDays: Double = 0, breakSeconds: Int = 0,
                breakDeductionSeconds: Int = 0, workDays: Int = 0, provisional: Bool = false) {
        self.label = label
        self.from = from
        self.to = to
        self.days = days
        self.targetSeconds = targetSeconds
        self.targetToDateSeconds = targetToDateSeconds ?? targetSeconds
        self.actualSeconds = actualSeconds
        self.creditSeconds = creditSeconds
        self.evaluatedWorkSeconds = evaluatedWorkSeconds
        self.rawWorkSeconds = rawWorkSeconds
        self.roundingSeconds = roundingSeconds
        self.deltaSeconds = deltaSeconds
        self.overtimeSeconds = overtimeSeconds
        self.undertimeSeconds = undertimeSeconds
        self.balanceSeconds = balanceSeconds
        self.balanceAsOf = balanceAsOf
        self.kindSeconds = kindSeconds
        self.absences = absences
        self.absenceDays = absenceDays
        self.breakSeconds = breakSeconds
        self.breakDeductionSeconds = breakDeductionSeconds
        self.workDays = workDays
        self.provisional = provisional
    }
}

public struct StatisticsTotals: Codable, Sendable, Hashable {
    public let targetSeconds: Int
    public let targetToDateSeconds: Int
    public let actualSeconds: Int
    public let creditSeconds: Int
    public let deltaSeconds: Int
    public let overtimeSeconds: Int
    public let undertimeSeconds: Int
    public let breakSeconds: Int
    public let breakDeductionSeconds: Int
    public let kindSeconds: StatisticsKinds
    public let absenceDays: Double

    public init(targetSeconds: Int = 0, targetToDateSeconds: Int = 0, actualSeconds: Int = 0, creditSeconds: Int = 0, deltaSeconds: Int = 0,
                overtimeSeconds: Int = 0, undertimeSeconds: Int = 0, breakSeconds: Int = 0, breakDeductionSeconds: Int = 0,
                kindSeconds: StatisticsKinds = .init(), absenceDays: Double = 0) {
        self.targetSeconds = targetSeconds
        self.targetToDateSeconds = targetToDateSeconds
        self.actualSeconds = actualSeconds
        self.creditSeconds = creditSeconds
        self.deltaSeconds = deltaSeconds
        self.overtimeSeconds = overtimeSeconds
        self.undertimeSeconds = undertimeSeconds
        self.breakSeconds = breakSeconds
        self.breakDeductionSeconds = breakDeductionSeconds
        self.kindSeconds = kindSeconds
        self.absenceDays = absenceDays
    }
}

public struct TimeStatistics: Codable, Sendable, Hashable {
    public let from: LocalDay
    public let to: LocalDay
    public let granularity: StatisticsGranularity
    public let basis: StatisticsBasis
    public let timezone: String
    public let accountStart: LocalDay?
    /// Account balance at the end of the day before `from` (baseline of the curve); nil before the account starts.
    public let openingBalanceSeconds: Int?
    public let buckets: [StatisticsBucket]
    public let totals: StatisticsTotals

    public init(from: LocalDay, to: LocalDay, granularity: StatisticsGranularity, basis: StatisticsBasis, timezone: String = "Europe/Berlin",
                accountStart: LocalDay? = nil, openingBalanceSeconds: Int? = nil, buckets: [StatisticsBucket], totals: StatisticsTotals) {
        self.from = from
        self.to = to
        self.granularity = granularity
        self.basis = basis
        self.timezone = timezone
        self.accountStart = accountStart
        self.openingBalanceSeconds = openingBalanceSeconds
        self.buckets = buckets
        self.totals = totals
    }
}

/// Body of `POST /time/account/adjustments`.
public struct AccountAdjustmentInput: Encodable, Sendable, Equatable {
    public enum Kind: String, Encodable, Sendable { case opening, correction }
    public var kind: Kind
    public var date: LocalDay
    public var seconds: Int
    public var reason: String

    public init(kind: Kind, date: LocalDay, seconds: Int, reason: String) {
        self.kind = kind
        self.date = date
        self.seconds = seconds
        self.reason = reason
    }
}
