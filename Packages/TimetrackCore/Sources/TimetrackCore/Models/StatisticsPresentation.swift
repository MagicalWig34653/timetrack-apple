import Foundation

/// Range presets of the statistics screen (WM2). `resolve` yields an inclusive day range the server accepts (at most 1100 days).
public enum StatisticsRangePreset: String, Sendable, CaseIterable, Identifiable, Hashable {
    case last4Weeks, last3Months, last12Months, thisYear, sinceStart, custom
    public var id: String { rawValue }

    /// Granularity that suits the preset best.
    public var defaultGranularity: StatisticsGranularity {
        switch self {
        case .last4Weeks: .day
        case .last3Months, .thisYear: .week
        case .last12Months, .sinceStart: .month
        case .custom: .week
        }
    }

    /// Inclusive range ending today. `accountStart` is only used by `sinceStart`; `custom` keeps the given range (clamped).
    public func resolve(today: LocalDay, accountStart: LocalDay? = nil, custom: (from: LocalDay, to: LocalDay)? = nil) -> (from: LocalDay, to: LocalDay) {
        let maxBack = StatisticsGranularity.maxDays - 1
        func back(_ days: Int) -> LocalDay { LocalDays.adding(-days, to: today) ?? today }
        let result: (LocalDay, LocalDay)
        switch self {
        case .last4Weeks: result = (back(27), today)
        case .last3Months: result = (back(90), today)
        case .last12Months: result = (back(364), today)
        case .thisYear: result = ("\(today.prefix(4))-01-01", today)
        case .sinceStart: result = (accountStart ?? back(364), today)
        case .custom: result = custom ?? (back(90), today)
        }
        var (from, to) = result
        if to < from { swap(&from, &to) }
        if let span = LocalDays.daysBetween(from, to), span > maxBack { from = LocalDays.adding(-maxBack, to: to) ?? from }
        return (from, to)
    }
}

extension StatisticsGranularity {
    /// Granularities that make sense for a range of `days` days: day buckets only up to 93 days, month buckets from about a month on.
    public static func allowed(forDays days: Int) -> [StatisticsGranularity] {
        var result: [StatisticsGranularity] = []
        if days <= maxDaysForDay { result.append(.day) }
        if days >= 7 { result.append(.week) }
        if days >= 28 { result.append(.month) }
        return result.isEmpty ? [.day] : result
    }

    /// `preferred` when allowed, otherwise the closest allowed one (coarser first).
    public static func resolved(_ preferred: StatisticsGranularity, forDays days: Int) -> StatisticsGranularity {
        let allowed = allowed(forDays: days)
        if allowed.contains(preferred) { return preferred }
        return allowed.first { $0.coarseness >= preferred.coarseness } ?? allowed.last ?? .day
    }

    var coarseness: Int {
        switch self {
        case .day: 0
        case .week: 1
        case .month: 2
        }
    }
}

extension StatisticsBucket {
    private static let months = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
    private static let monthsLong = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]

    /// First day of the bucket as an instant (noon UTC, so every time zone keeps the same calendar day) for chart axes.
    public var startDate: Date { Self.noonUTC(from) }
    public var endDate: Date { Self.noonUTC(to) }

    static func noonUTC(_ day: LocalDay) -> Date {
        guard let p = LocalDays.parse(day) else { return .distantPast }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: p.year, month: p.month, day: p.day, hour: 12)) ?? .distantPast
    }

    /// Short axis/row title: `12.10.` (day), `KW 42` (week), `Okt` (month; with the year when it is not the same as `referenceYear`).
    public func shortTitle(granularity: StatisticsGranularity) -> String {
        switch granularity {
        case .day:
            guard let p = LocalDays.parse(from) else { return label }
            return "\(p.day).\(p.month)."
        case .week:
            if let week = label.split(separator: "W").last, let number = Int(week) { return "KW \(number)" }
            return label
        case .month:
            guard let p = LocalDays.parse(from) else { return label }
            return Self.months[p.month - 1]
        }
    }

    /// Spoken/long title: `Montag, 12.10.2026`-free variant `12.10.2026`, `KW 42 2026 (12.10. bis 18.10.)`, `Oktober 2026`.
    public func longTitle(granularity: StatisticsGranularity) -> String {
        guard let f = LocalDays.parse(from), let t = LocalDays.parse(to) else { return label }
        switch granularity {
        case .day: return "\(f.day).\(f.month).\(f.year)"
        case .week:
            let number = label.split(separator: "W").last.flatMap { Int($0) } ?? 0
            return "Kalenderwoche \(number), \(f.day).\(f.month). bis \(t.day).\(t.month).\(t.year)"
        case .month: return "\(Self.monthsLong[f.month - 1]) \(f.year)"
        }
    }

    /// Time worked in the bucket as the app shows it everywhere ("Gearbeitet"): actual plus credit.
    public var workedSeconds: Int { actualSeconds + creditSeconds }
}

public struct BalancePoint: Sendable, Hashable, Identifiable {
    public let date: Date
    public let day: LocalDay
    public let seconds: Int
    public var id: LocalDay { day }
}

public struct PerformancePoint: Sendable, Hashable, Identifiable {
    public let bucket: StatisticsBucket
    public var id: String { bucket.label }
    public var date: Date { bucket.startDate }
    public var targetSeconds: Int { bucket.targetSeconds }
    public var workedSeconds: Int { bucket.workedSeconds }
    public var deltaSeconds: Int { bucket.deltaSeconds }
}

public enum StatisticsKind: String, Sendable, CaseIterable, Identifiable {
    case work, travel, school
    public var id: String { rawValue }
    public var germanName: String {
        switch self {
        case .work: "Arbeit"
        case .travel: "Fahrt"
        case .school: "Schule"
        }
    }
}

public enum StatisticsAbsenceKind: String, Sendable, CaseIterable, Identifiable {
    case vacation, sick, excused, holiday, school
    public var id: String { rawValue }
    public var germanName: String {
        switch self {
        case .vacation: "Urlaub"
        case .sick: "Krank"
        case .excused: "Freigestellt"
        case .holiday: "Feiertag"
        case .school: "Schule"
        }
    }
}

public struct KindSlice: Sendable, Hashable, Identifiable {
    public let kind: StatisticsKind
    public let seconds: Int
    /// 0...1 of all tracked time.
    public let share: Double
    public var id: String { kind.rawValue }
}

public struct KindPoint: Sendable, Hashable, Identifiable {
    public let bucketLabel: String
    public let date: Date
    public let kind: StatisticsKind
    public let seconds: Int
    public var id: String { bucketLabel + kind.rawValue }
}

public struct AbsencePoint: Sendable, Hashable, Identifiable {
    public let bucketLabel: String
    public let date: Date
    public let kind: StatisticsAbsenceKind
    public let days: Double
    public var id: String { bucketLabel + kind.rawValue }
}

public struct BreakPoint: Sendable, Hashable, Identifiable {
    public let bucketLabel: String
    public let date: Date
    public let actualSeconds: Int
    public let fixedSeconds: Int
    public var id: String { bucketLabel }
}

/// Everything the charts need, derived once from a `TimeStatistics` (pure, testable).
public struct StatisticsChartData: Sendable, Equatable {
    public let statistics: TimeStatistics
    public let balance: [BalancePoint]
    /// Buckets that start after today carry no result yet; they are left out of the performance charts.
    public let performance: [PerformancePoint]
    public let kindSlices: [KindSlice]
    public let kindSeries: [KindPoint]
    public let absenceSeries: [AbsencePoint]
    public let absenceTotals: [(kind: StatisticsAbsenceKind, days: Double)]
    public let breaks: [BreakPoint]

    public init(statistics: TimeStatistics, today: LocalDay) {
        self.statistics = statistics
        let buckets = statistics.buckets

        var balance: [BalancePoint] = []
        if let opening = statistics.openingBalanceSeconds, let before = LocalDays.adding(-1, to: statistics.from) {
            balance.append(BalancePoint(date: StatisticsBucket.noonUTC(before), day: before, seconds: opening))
        }
        for bucket in buckets {
            guard let seconds = bucket.balanceSeconds, let asOf = bucket.balanceAsOf else { continue }
            balance.append(BalancePoint(date: StatisticsBucket.noonUTC(asOf), day: asOf, seconds: seconds))
        }
        self.balance = balance

        performance = buckets.filter { $0.from <= today }.map(PerformancePoint.init)

        let kinds = statistics.totals.kindSeconds
        let total = max(1, kinds.total)
        kindSlices = [
            KindSlice(kind: .work, seconds: kinds.work, share: Double(kinds.work) / Double(total)),
            KindSlice(kind: .travel, seconds: kinds.travel, share: Double(kinds.travel) / Double(total)),
            KindSlice(kind: .school, seconds: kinds.school, share: Double(kinds.school) / Double(total)),
        ].filter { $0.seconds > 0 }
        kindSeries = buckets.flatMap { bucket in
            [(StatisticsKind.work, bucket.kindSeconds.work), (.travel, bucket.kindSeconds.travel), (.school, bucket.kindSeconds.school)]
                .map { KindPoint(bucketLabel: bucket.label, date: bucket.startDate, kind: $0.0, seconds: $0.1) }
        }

        var absence: [AbsencePoint] = []
        var absenceSums: [StatisticsAbsenceKind: Double] = [:]
        for bucket in buckets {
            let a = bucket.absences
            for (kind, days) in [(StatisticsAbsenceKind.vacation, a.vacation), (.sick, a.sick), (.excused, a.excused), (.holiday, a.holiday), (.school, a.school)] where days > 0 {
                absence.append(AbsencePoint(bucketLabel: bucket.label, date: bucket.startDate, kind: kind, days: days))
                absenceSums[kind, default: 0] += days
            }
        }
        absenceSeries = absence
        absenceTotals = StatisticsAbsenceKind.allCases.compactMap { kind in absenceSums[kind].map { (kind, $0) } }

        breaks = buckets.map { BreakPoint(bucketLabel: $0.label, date: $0.startDate, actualSeconds: $0.breakSeconds, fixedSeconds: $0.breakDeductionSeconds) }
    }

    public static func == (lhs: StatisticsChartData, rhs: StatisticsChartData) -> Bool { lhs.statistics == rhs.statistics }

    public var hasBalance: Bool { balance.count >= 2 }
    public var hasAnyTime: Bool { statistics.totals.workedSeconds > 0 || statistics.totals.targetSeconds > 0 }
    public var hasBreaks: Bool { breaks.contains { $0.actualSeconds > 0 || $0.fixedSeconds > 0 } }
    public var granularity: StatisticsGranularity { statistics.granularity }

    /// The bucket a chart selection (any instant on the time axis) falls into; outside all buckets the nearest one.
    public func bucket(near date: Date) -> StatisticsBucket? {
        let buckets = statistics.buckets
        if let hit = buckets.first(where: { date >= $0.startDate.addingTimeInterval(-12 * 3600) && date < $0.endDate.addingTimeInterval(12 * 3600) }) { return hit }
        return buckets.min { abs($0.startDate.timeIntervalSince(date)) < abs($1.startDate.timeIntervalSince(date)) }
    }

    /// The balance point nearest to a chart selection.
    public func balancePoint(near date: Date) -> BalancePoint? {
        balance.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// Balance change over the range (last minus first point), nil with fewer than two points.
    public var balanceChange: Int? {
        guard let first = balance.first, let last = balance.last, balance.count >= 2 else { return nil }
        return last.seconds - first.seconds
    }
}

extension StatisticsTotals {
    public var workedSeconds: Int { actualSeconds + creditSeconds }
}
