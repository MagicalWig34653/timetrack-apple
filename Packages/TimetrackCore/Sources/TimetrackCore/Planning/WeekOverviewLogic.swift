import Foundation

/// Presentation rules of the week overview; pure so they can be unit tested.
public enum WeekOverview {
    /// Bar widths 0...1 of actual, planned and target, all relative to the larger of the three.
    public static func barShares(_ day: TimeWeekDay) -> (actual: Double, planned: Double, target: Double) {
        let actual = day.hoursSeconds
        let planned = day.plannedSeconds ?? 0
        let scale = Double(max(day.targetSeconds, planned, actual, 1))
        func share(_ value: Int) -> Double { min(1, (Double(value) / scale * 1000).rounded() / 1000) }
        return (share(actual), share(planned), share(day.targetSeconds))
    }

    /// True for a week with nothing to show: no work, no marks, no plan.
    public static func isEmpty(_ days: [TimeWeekDay]) -> Bool {
        days.allSatisfy { $0.segmentsCount == 0 && $0.creditSeconds == 0 && $0.plannedSeconds == nil && ($0.mark == .work || $0.mark == .off) }
    }

    /// Days that are not plain work days, in the order vacation, sick, school, holiday (for the one-line sentence).
    public static func noteworthy(_ summary: TimeWeekSummary) -> [(mark: WeekMark, count: Double)] {
        var result: [(WeekMark, Double)] = []
        if summary.vacationDays > 0 { result.append((.vacation, summary.vacationDays)) }
        if summary.sickDays > 0 { result.append((.sick, Double(summary.sickDays))) }
        if summary.schoolDays > 0 { result.append((.school, Double(summary.schoolDays))) }
        if summary.holidayDays > 0 { result.append((.holiday, Double(summary.holidayDays))) }
        return result
    }

    /// Whether the planned time of a day is shown: the plan counts (more than zero) or the day is still ahead.
    public static func showsPlan(_ day: TimeWeekDay) -> Bool {
        guard let planned = day.plannedSeconds else { return false }
        return planned > 0 || day.isFuture
    }

    /// Planned versus actual hours of the whole week; nil when no day has a plan.
    public static func planComparison(_ days: [TimeWeekDay]) -> (planned: Int, actual: Int)? {
        guard days.contains(where: { $0.plannedSeconds != nil }) else { return nil }
        return (days.compactMap(\.plannedSeconds).reduce(0, +), days.reduce(0) { $0 + $1.hoursSeconds })
    }
}
