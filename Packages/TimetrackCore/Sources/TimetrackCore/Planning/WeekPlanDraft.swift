import Foundation

/// Editing model of the week planner (K1, ADR-0021), mirrors the PWA's `plan-draft.ts`. The server stays the only place
/// that derives the authoritative planned seconds; `plannedSeconds` here only drives the live preview while editing.
public struct DayDraft: Sendable, Hashable, Identifiable {
    public var date: LocalDay
    /// nil = nothing planned for this day.
    public var mode: PlanMode?
    /// `HH:mm` or empty.
    public var start: String
    public var end: String
    public var breakMinutes: Int
    public var note: String
    /// Carried through unchanged: the planner has no place picker.
    public var placeId: UUID?
    public var id: LocalDay { date }

    public init(date: LocalDay, mode: PlanMode? = nil, start: String = "", end: String = "", breakMinutes: Int = 0, note: String = "", placeId: UUID? = nil) {
        self.date = date
        self.mode = mode
        self.start = start
        self.end = end
        self.breakMinutes = breakMinutes
        self.note = note
        self.placeId = placeId
    }

    public var hasTimes: Bool { WeekPlan.parseClock(start) != nil && WeekPlan.parseClock(end) != nil }
}

public struct WindowSuggestion: Sendable, Hashable {
    public enum Source: Sendable, Hashable { case history, fallback }
    public var start: String
    public var end: String
    public var breakMinutes: Int
    /// History = average of the last weeks, fallback = 08:00 plus the day's target.
    public var source: Source

    public init(start: String, end: String, breakMinutes: Int, source: Source) {
        self.start = start
        self.end = end
        self.breakMinutes = breakMinutes
        self.source = source
    }
}

public enum DraftProblem: Sendable, Hashable {
    case timesRequired, endBeforeStart, breakInvalid
}

public enum WeekPlan {
    public static let stepMinutes = 15
    public static let maxBreakMinutes = 600
    private static let defaultStart = 8 * 60
    private static let defaultBreak = 30

    // MARK: Clock

    public static func parseClock(_ value: String) -> Int? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    public static func formatClock(_ minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 23 * 60 + 59)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    private static func round(_ minutes: Double, to step: Int) -> Int { Int((minutes / Double(step)).rounded()) * step }

    // MARK: Validation and derived values

    /// Why a draft cannot be saved. Rows without a mode and rows with mode off are always valid; a mode without any times is a rough plan.
    public static func problem(_ draft: DayDraft) -> DraftProblem? {
        guard let mode = draft.mode, mode != .off else { return nil }
        if draft.start.isEmpty && draft.end.isEmpty && draft.breakMinutes == 0 { return nil }
        guard let start = parseClock(draft.start), let end = parseClock(draft.end) else { return .timesRequired }
        if end <= start { return .endBeforeStart }
        if draft.breakMinutes < 0 || draft.breakMinutes > maxBreakMinutes { return .breakInvalid }
        return nil
    }

    /// Planned seconds as the server derives them (end - start - break, never negative); nil without usable times.
    public static func plannedSeconds(_ draft: DayDraft) -> Int? {
        guard let mode = draft.mode, mode != .off, let start = parseClock(draft.start), let end = parseClock(draft.end), end > start else { return nil }
        return max(0, (end - start - max(0, draft.breakMinutes)) * 60)
    }

    // MARK: Conversion

    public static func draft(from day: PlanWeekDay) -> DayDraft {
        guard let plan = day.plan else { return DayDraft(date: day.date) }
        return DayDraft(date: day.date, mode: plan.mode == .unknown ? nil : plan.mode, start: plan.plannedStart ?? "", end: plan.plannedEnd ?? "",
                        breakMinutes: plan.plannedBreakMinutes ?? 0, note: plan.note ?? "", placeId: plan.placeId)
    }

    /// The request entry of a draft; nil when nothing is planned. Times are only sent for working modes with both times set.
    public static func entry(from draft: DayDraft) -> PlanWeekEntry? {
        guard let mode = draft.mode else { return nil }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        var input = PlanDayInput(mode: mode, placeId: draft.placeId, note: note.isEmpty ? nil : note)
        if mode != .off, draft.hasTimes {
            input.plannedStart = draft.start
            input.plannedEnd = draft.end
            input.plannedBreakMinutes = draft.breakMinutes
        }
        return PlanWeekEntry(date: draft.date, input: input)
    }

    /// The PUT body: every planned row, including the stored plan of blocked days (`replace` would delete it otherwise).
    public static func request(_ drafts: [DayDraft]) -> PlanWeekInput {
        PlanWeekInput(replace: true, days: drafts.compactMap(entry(from:)))
    }

    // MARK: Suggestions

    /// Suggested working window: average of the last weeks' averages (rounded to 15 min), else 08:00 plus the day's target.
    public static func suggestWindow(history: [TimeWeekSummary], targetSeconds: Int) -> WindowSuggestion {
        var starts: [Int] = []
        var ends: [Int] = []
        var breakSeconds = 0
        var workDays = 0
        for week in history {
            guard let start = week.averageStart.flatMap(parseClock), let end = week.averageEnd.flatMap(parseClock), end > start, week.workDays > 0 else { continue }
            starts.append(start)
            ends.append(end)
            breakSeconds += week.breakSeconds
            workDays += week.workDays
        }
        if !starts.isEmpty {
            let start = round(Double(starts.reduce(0, +)) / Double(starts.count), to: stepMinutes)
            let end = round(Double(ends.reduce(0, +)) / Double(ends.count), to: stepMinutes)
            let gap = workDays > 0 ? Double(breakSeconds) / Double(workDays) / 60 : 0
            // Gaps below 15 minutes are no real break; the usual half hour is the fallback.
            let breakMinutes = gap >= 15 ? min(maxBreakMinutes, round(gap, to: 5)) : (end - start >= 360 ? defaultBreak : 0)
            if end > start { return WindowSuggestion(start: formatClock(start), end: formatClock(end), breakMinutes: breakMinutes, source: .history) }
        }
        return fallbackWindow(targetSeconds: targetSeconds)
    }

    public static func fallbackWindow(targetSeconds: Int) -> WindowSuggestion {
        let breakMinutes = targetSeconds > 6 * 3600 ? defaultBreak : 0
        let end = round(Double(defaultStart) + Double(targetSeconds) / 60 + Double(breakMinutes), to: stepMinutes)
        return WindowSuggestion(start: formatClock(defaultStart), end: formatClock(min(end, 23 * 60 + 45)), breakMinutes: breakMinutes, source: .fallback)
    }

    /// Window to prefill for one day: the history suggestion, or the fallback derived from that day's own target.
    public static func window(for suggestion: WindowSuggestion, targetSeconds: Int) -> WindowSuggestion {
        suggestion.source == .history ? suggestion : fallbackWindow(targetSeconds: targetSeconds)
    }

    // MARK: Actions

    /// Changes the mode of a draft; picking a working mode on an empty row prefills the suggested times.
    public static func withMode(_ draft: DayDraft, _ mode: PlanMode?, suggestion: WindowSuggestion, targetSeconds: Int) -> DayDraft {
        var result = draft
        result.mode = mode
        guard let mode, mode != .off else {
            result.start = ""
            result.end = ""
            result.breakMinutes = 0
            return result
        }
        if !draft.start.isEmpty && !draft.end.isEmpty { return result }
        let window = window(for: suggestion, targetSeconds: targetSeconds)
        result.start = window.start
        result.end = window.end
        result.breakMinutes = window.breakMinutes
        return result
    }

    private static func isWorkday(_ day: PlanWeekDay) -> Bool { day.targetSeconds > 0 && !day.isBlocked }

    /// "Standardwoche": office on every workday of the work model with the suggested window, everything else cleared; blocked days keep their draft.
    public static func standardWeek(days: [PlanWeekDay], current: [DayDraft], suggestion: WindowSuggestion) -> [DayDraft] {
        zip(days, current).map { day, draft in
            if day.isBlocked { return draft }
            if !isWorkday(day) { return DayDraft(date: draft.date) }
            let window = window(for: suggestion, targetSeconds: day.targetSeconds)
            return DayDraft(date: draft.date, mode: .office, start: window.start, end: window.end, breakMinutes: window.breakMinutes)
        }
    }

    /// Copies the plan of another week day by day (Monday to Monday); blocked days keep their draft.
    public static func copyWeek(source: PlanWeek, days: [PlanWeekDay], current: [DayDraft]) -> [DayDraft] {
        current.enumerated().map { index, draft in
            guard index < days.count, !days[index].isBlocked else { return draft }
            guard index < source.days.count else { return DayDraft(date: draft.date) }
            var copy = self.draft(from: source.days[index])
            copy.date = draft.date
            return copy
        }
    }

    /// The first planned day is applied to all other workdays (mode, times, break, place); notes stay as they are.
    public static func sameForWorkdays(days: [PlanWeekDay], current: [DayDraft]) -> [DayDraft] {
        guard let model = zip(days, current).first(where: { $0.1.mode != nil && !$0.0.isBlocked })?.1 else { return current }
        return zip(days, current).map { day, draft in
            guard !day.isBlocked, isWorkday(day) else { return draft }
            var copy = draft
            copy.mode = model.mode
            copy.start = model.start
            copy.end = model.end
            copy.breakMinutes = model.breakMinutes
            copy.placeId = model.placeId
            return copy
        }
    }

    public static func clearWeek(days: [PlanWeekDay], current: [DayDraft]) -> [DayDraft] {
        zip(days, current).map { day, draft in day.isBlocked ? draft : DayDraft(date: draft.date) }
    }

    /// Live totals: blocked days count 0 planned; the target comes from the server.
    public static func totals(days: [PlanWeekDay], drafts: [DayDraft]) -> PlanWeekTotals {
        var planned = 0
        var target = 0
        for (day, draft) in zip(days, drafts) {
            target += day.targetSeconds
            if !day.isBlocked { planned += plannedSeconds(draft) ?? 0 }
        }
        return PlanWeekTotals(targetSeconds: target, plannedSeconds: planned, differenceSeconds: planned - target)
    }
}

/// Conversion between `HH:mm` strings and a `Date` for `DatePicker`s that show wall-clock time in UTC (no zone arithmetic).
public enum ClockPicker {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    public static var timeZone: TimeZone { TimeZone(identifier: "UTC") ?? .gmt }

    public static func date(minutes: Int) -> Date {
        calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: minutes / 60, minute: minutes % 60)) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    public static func minutes(of date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
