import Foundation

/// How far a coming week is planned (PL1: multi-week overview in the "Planung" area).
public enum PlanCoverage: Sendable, Hashable {
    /// No work day has a plan.
    case unplanned
    /// Some, but not all, plannable work days have a plan.
    case partial
    /// Every plannable work day has a plan (or the week has no plannable day).
    case complete
}

/// One line of the multi-week overview: totals of `GET /plan/weeks/{isoWeek}` plus how many work days still lack a plan.
public struct PlanHorizonRow: Sendable, Hashable, Identifiable {
    public let isoWeek: String
    public let monday: LocalDay
    public let sunday: LocalDay
    public let weekNumber: Int
    public let plannedSeconds: Int
    public let targetSeconds: Int
    /// Work days (target > 0) that no holiday or absence blocks.
    public let plannableDays: Int
    /// Of those, the days with a stored plan.
    public let plannedDays: Int
    /// Days a holiday, vacation, sickness or exemption overrules.
    public let blockedDays: Int
    public var id: String { isoWeek }

    public var openDays: Int { max(0, plannableDays - plannedDays) }
    public var differenceSeconds: Int { plannedSeconds - targetSeconds }

    public var coverage: PlanCoverage {
        if plannedDays == 0 && plannableDays > 0 { return .unplanned }
        if plannedDays == 0 && plannableDays == 0 { return .complete }
        return openDays > 0 ? .partial : .complete
    }
}

public enum PlanHorizon {
    /// The row for a loaded plan week. A day counts as planned when it has a plan entry; mode "off" counts too (deliberately free).
    public static func row(for week: PlanWeek) -> PlanHorizonRow {
        let plannable = week.days.filter { $0.targetSeconds > 0 && !$0.isBlocked }
        return PlanHorizonRow(
            isoWeek: week.week,
            monday: week.from,
            sunday: week.to,
            weekNumber: IsoWeek.number(of: week.week) ?? 0,
            plannedSeconds: week.totals.plannedSeconds,
            targetSeconds: week.totals.targetSeconds,
            plannableDays: plannable.count,
            plannedDays: plannable.filter { $0.plan != nil }.count,
            blockedDays: week.days.filter(\.isBlocked).count
        )
    }

    /// Mondays of `count` weeks starting with the week that contains `day`.
    public static func mondays(from day: LocalDay, count: Int) -> [LocalDay] {
        guard let first = LocalDays.mondayOfWeek(containing: day), count > 0 else { return [] }
        return (0..<count).compactMap { LocalDays.adding(7 * $0, to: first) }
    }
}

/// Input check for a new share (the server checks again).
public enum ShareFormProblem: Sendable, Hashable {
    case handleMissing, toSelf, noScope
}

public enum SharePolicy {
    public static func problem(handle: String, scopes: ShareScopes, ownHandle: String?) -> ShareFormProblem? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .handleMissing }
        if let ownHandle, trimmed.caseInsensitiveCompare(ownHandle) == .orderedSame { return .toSelf }
        if scopes.isEmpty { return .noScope }
        return nil
    }
}
