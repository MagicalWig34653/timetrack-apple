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
    /// Day-level place (legacy, carried through unchanged).
    public var placeId: UUID?
    /// P13 (API 0.35.0): the ordered plan blocks. When not empty they win over `start`/`end`/`breakMinutes` (which stay empty for
    /// block drafts); gaps between blocks are the breaks. Always empty when the server does not know blocks.
    public var blocks: [PlanTimeBlock]
    public var id: LocalDay { date }

    public init(date: LocalDay, mode: PlanMode? = nil, start: String = "", end: String = "", breakMinutes: Int = 0, note: String = "", placeId: UUID? = nil,
                blocks: [PlanTimeBlock] = []) {
        self.blocks = blocks
        self.date = date
        self.mode = mode
        self.start = start
        self.end = end
        self.breakMinutes = breakMinutes
        self.note = note
        self.placeId = placeId
    }

    public var hasTimes: Bool { WeekPlan.parseClock(start) != nil && WeekPlan.parseClock(end) != nil }
    /// Any time information, from blocks or from the single window.
    public var hasAnyTimes: Bool { !blocks.isEmpty || hasTimes }
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
    /// P13: blocks overlap or are out of order (`plan_blocks_overlap`), more than 32 blocks, a block note above 200 characters.
    case blocksOverlap, tooManyBlocks, noteTooLong
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
        if !draft.blocks.isEmpty { return blocksProblem(draft.blocks) }
        if draft.start.isEmpty && draft.end.isEmpty && draft.breakMinutes == 0 { return nil }
        guard let start = parseClock(draft.start), let end = parseClock(draft.end) else { return .timesRequired }
        if end <= start { return .endBeforeStart }
        if draft.breakMinutes < 0 || draft.breakMinutes > maxBreakMinutes { return .breakInvalid }
        return nil
    }

    /// Why a block list cannot be sent; the server would answer `plan_time_invalid`, `plan_blocks_overlap` or `plan_blocks_invalid`.
    public static func blocksProblem(_ blocks: [PlanTimeBlock]) -> DraftProblem? {
        if blocks.count > PlanBlocks.maxCount { return .tooManyBlocks }
        var previousEnd = 0
        for block in blocks {
            guard let start = parseClock(block.start), let end = parseClock(block.end) else { return .timesRequired }
            if end <= start { return .endBeforeStart }
            if (block.note ?? "").count > PlanBlocks.maxNoteLength { return .noteTooLong }
            if start < previousEnd { return .blocksOverlap }
            previousEnd = end
        }
        return nil
    }

    /// Planned seconds as the server derives them (sum of the block durations, or end - start - break, never negative); nil without usable times.
    public static func plannedSeconds(_ draft: DayDraft) -> Int? {
        guard let mode = draft.mode, mode != .off else { return nil }
        if !draft.blocks.isEmpty { return draft.blocks.reduce(0) { $0 + $1.durationSeconds } }
        guard let start = parseClock(draft.start), let end = parseClock(draft.end), end > start else { return nil }
        return max(0, (end - start - max(0, draft.breakMinutes)) * 60)
    }

    // MARK: Conversion

    /// `multi` = the server knows blocks (API 0.35.0): the draft then carries the block list and leaves the single window empty,
    /// unless the day only has an old single window that no positive block can express (kept as it is).
    public static func draft(from day: PlanWeekDay) -> DayDraft { draft(from: day, multi: false) }

    public static func draft(from day: PlanWeekDay, multi: Bool) -> DayDraft {
        guard let plan = day.plan else { return DayDraft(date: day.date) }
        let mode: PlanMode? = plan.mode == .unknown ? nil : plan.mode
        if multi, !plan.blocks.isEmpty {
            return DayDraft(date: day.date, mode: mode, note: plan.note ?? "", placeId: plan.placeId, blocks: plan.blocks)
        }
        return DayDraft(date: day.date, mode: mode, start: plan.plannedStart ?? "", end: plan.plannedEnd ?? "",
                        breakMinutes: plan.plannedBreakMinutes ?? 0, note: plan.note ?? "", placeId: plan.placeId)
    }

    /// The request entry of a draft; nil when nothing is planned. With `multi`, blocks are sent as the complete ordered list (`[]` for
    /// mode off and days without times); otherwise only the old single window for working modes with both times set.
    public static func entry(from draft: DayDraft, multi: Bool = false) -> PlanWeekEntry? {
        guard let mode = draft.mode else { return nil }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        var input = PlanDayInput(mode: mode, placeId: draft.placeId, note: note.isEmpty ? nil : note)
        if multi, mode == .off {
            input.blocks = []
        } else if multi, !draft.blocks.isEmpty {
            input.blocks = sentBlocks(draft.blocks)
        } else if mode != .off, draft.hasTimes {
            input.plannedStart = draft.start
            input.plannedEnd = draft.end
            input.plannedBreakMinutes = draft.breakMinutes
        } else if multi {
            input.blocks = []
        }
        return PlanWeekEntry(date: draft.date, input: input)
    }

    /// The block list as it goes on the wire: chronological, notes trimmed (empty = null).
    public static func sentBlocks(_ blocks: [PlanTimeBlock]) -> [PlanTimeBlock] {
        PlanBlockEditing.sorted(blocks).map { block in
            var copy = block
            let trimmed = (block.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            copy.note = trimmed.isEmpty ? nil : trimmed
            return copy
        }
    }

    /// Input for saving one plan day from the day sheet (`PUT /plan/days/{date}` replaces the whole day). With `multi` the block list
    /// is sent (also `[]`); a stored old single window that no block can express is kept as it was. Without `multi` the stored
    /// window is sent along as before.
    public static func dayInput(mode: PlanMode, note: String?, stored: PlanDay?, blocks: [PlanTimeBlock], multi: Bool) -> PlanDayInput {
        var input = PlanDayInput(mode: mode, placeId: stored?.placeId, note: note)
        if multi {
            if mode == .off {
                input.blocks = []
            } else if !blocks.isEmpty {
                input.blocks = sentBlocks(blocks)
            } else if let stored, stored.blocks.isEmpty, stored.plannedStart != nil {
                input.plannedStart = stored.plannedStart
                input.plannedEnd = stored.plannedEnd
                input.plannedBreakMinutes = stored.plannedBreakMinutes
            } else {
                input.blocks = []
            }
        } else {
            input.plannedStart = stored?.plannedStart
            input.plannedEnd = stored?.plannedEnd
            input.plannedBreakMinutes = stored?.plannedBreakMinutes
        }
        return input
    }

    /// The PUT body: every planned row, including the stored plan of blocked days (`replace` would delete it otherwise).
    public static func request(_ drafts: [DayDraft], multi: Bool = false) -> PlanWeekInput {
        PlanWeekInput(replace: true, days: drafts.compactMap { entry(from: $0, multi: multi) })
    }

    // MARK: Blocks

    /// The block kind that matches a day mode (the default kind of new blocks).
    public static func defaultKind(for mode: PlanMode?) -> PlanBlockKind {
        switch mode {
        case .office: .office
        case .home: .home
        case .customer: .customer
        case .school: .school
        default: .work
        }
    }

    /// Blocks for a suggested window: one block, or two with the break as a gap in the middle (like the server converts an old break).
    public static func blocks(for window: WindowSuggestion, kind: PlanBlockKind) -> [PlanTimeBlock] {
        guard let start = parseClock(window.start), let end = parseClock(window.end), end > start else { return [] }
        let gap = max(0, window.breakMinutes)
        guard gap > 0, end - start > gap else { return [PlanTimeBlock(start: window.start, end: window.end, kind: kind)] }
        let first = start + ((end - start - gap) / 2 / 5) * 5
        return [PlanTimeBlock(start: formatClock(start), end: formatClock(first), kind: kind),
                PlanTimeBlock(start: formatClock(first + gap), end: formatClock(end), kind: kind)].filter { ($0.endMinutes ?? 0) > ($0.startMinutes ?? 0) }
    }

    /// Non-binding planning hints for a block list; the same rule as the server's `planHints` (profile arbzg-adult-de) so the draft
    /// shows them before saving: gaps of 15 minutes or more are breaks, school time is no working time.
    public static func hints(for blocks: [PlanTimeBlock]) -> [PlanHint] {
        let ranges = blocks.compactMap { block -> (Int, Int, PlanBlockKind)? in
            guard let s = block.startMinutes, let e = block.endMinutes, e > s else { return nil }
            return (s, e, block.kind)
        }.sorted { $0.0 < $1.0 }
        guard !ranges.isEmpty else { return [] }
        var work = 0, breaks = 0, run = 0, longest = 0
        var shortGap = false
        var previousEnd: Int?
        for (start, end, kind) in ranges {
            if let previousEnd, start > previousEnd {
                let gap = start - previousEnd
                if gap >= 15 {
                    breaks += gap
                    longest = max(longest, run)
                    run = 0
                } else {
                    shortGap = true
                }
            }
            if kind != .school {
                work += end - start
                run += end - start
            }
            previousEnd = end
        }
        longest = max(longest, run)
        var result: [PlanHint] = []
        let required = work > 540 ? 45 : (work > 360 ? 30 : 0)
        if required > breaks { result.append(.breakShort) }
        if longest > 360 { result.append(.workStretchLong) }
        if shortGap { result.append(.breakPartShort) }
        return result
    }

    /// Hints of a draft (working modes with blocks only).
    public static func hints(_ draft: DayDraft) -> [PlanHint] {
        guard let mode = draft.mode, mode != .off else { return [] }
        return hints(for: draft.blocks)
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
    public static func withMode(_ draft: DayDraft, _ mode: PlanMode?, suggestion: WindowSuggestion, targetSeconds: Int, multi: Bool = false) -> DayDraft {
        var result = draft
        result.mode = mode
        guard let mode, mode != .off else {
            result.start = ""
            result.end = ""
            result.breakMinutes = 0
            result.blocks = []
            return result
        }
        if multi {
            if !draft.blocks.isEmpty {
                // Blocks that had the old day's kind follow the new mode; blocks with another kind (school, travel) stay.
                let old = defaultKind(for: draft.mode), new = defaultKind(for: mode)
                if draft.mode != nil, draft.mode != .off, old != new {
                    result.blocks = draft.blocks.map { var b = $0; if b.kind == old { b.kind = new }; return b }
                }
                return result
            }
            result.blocks = blocks(for: window(for: suggestion, targetSeconds: targetSeconds), kind: defaultKind(for: mode))
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
    public static func standardWeek(days: [PlanWeekDay], current: [DayDraft], suggestion: WindowSuggestion, multi: Bool = false) -> [DayDraft] {
        zip(days, current).map { day, draft in
            if day.isBlocked { return draft }
            if !isWorkday(day) { return DayDraft(date: draft.date) }
            let window = window(for: suggestion, targetSeconds: day.targetSeconds)
            if multi { return DayDraft(date: draft.date, mode: .office, blocks: blocks(for: window, kind: .office)) }
            return DayDraft(date: draft.date, mode: .office, start: window.start, end: window.end, breakMinutes: window.breakMinutes)
        }
    }

    /// Copies the plan of another week day by day (Monday to Monday); blocked days keep their draft.
    public static func copyWeek(source: PlanWeek, days: [PlanWeekDay], current: [DayDraft], multi: Bool = false) -> [DayDraft] {
        current.enumerated().map { index, draft in
            guard index < days.count, !days[index].isBlocked else { return draft }
            guard index < source.days.count else { return DayDraft(date: draft.date) }
            var copy = self.draft(from: source.days[index], multi: multi)
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
            copy.blocks = model.blocks
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
