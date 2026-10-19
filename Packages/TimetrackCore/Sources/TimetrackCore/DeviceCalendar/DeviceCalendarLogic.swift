import Foundation

/// Which device events are shown for a local day.
public enum DeviceEventFilter {
    /// Events of the selected calendars that touch `day`, all-day first, then by start. Declined and cancelled events are hidden.
    /// Events Timetrack wrote itself (marker URL) are never shown again as context, wherever they live.
    public static func events(on day: LocalDay, in events: [DeviceEvent], preferences: CalendarPreferences, calendar: DayCalendar) -> [DeviceEvent] {
        guard let interval = calendar.interval(of: day) else { return [] }
        let result = events.filter { event in
            guard preferences.selectedCalendarIDs.contains(event.calendarID), !event.isWrittenByTimetrack else { return false }
            guard !event.isDeclined, !event.isCancelled else { return false }
            if event.isAllDay {
                guard preferences.showAllDay else { return false }
                return allDayRange(of: event, calendar: calendar).contains(day)
            }
            if event.end <= event.start { return event.start >= interval.start && event.start < interval.end }
            return event.start < interval.end && event.end > interval.start
        }
        return result.sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            if $0.start != $1.start { return $0.start < $1.start }
            return ($0.title, $0.id) < ($1.title, $1.id)
        }
    }

    /// Local days an all-day event covers. EventKit ends all-day events at 23:59:59 of the last day (or at the next midnight).
    static func allDayRange(of event: DeviceEvent, calendar: DayCalendar) -> ClosedRange<LocalDay> {
        allDayDays(start: event.start, end: event.end, calendar: calendar)
    }

    /// Local days an all-day span covers; shared with the EventKit provider when it reads written events back.
    public static func allDayDays(start: Date, end: Date, calendar: DayCalendar) -> ClosedRange<LocalDay> {
        let first = calendar.day(for: start)
        guard end > start else { return first...first }
        let last = calendar.day(for: end.addingTimeInterval(-1))
        return last >= first ? first...last : first...first
    }
}

public enum EventDraftError: Error, Equatable, Sendable {
    /// All-day events carry no clock times; inventing times would invent an activity.
    case allDayEvent
    case emptyInterval
    case notOnDay
    case kindMissing
}

/// An editable proposal for a time segment derived from a calendar event. It is NOT a time entry: the user has to choose the kind
/// explicitly and confirm. The event title is deliberately not part of the draft.
public struct SegmentDraft: Sendable, Equatable {
    public var startedAt: Date
    public var endedAt: Date
    /// Nil until the user chooses (work / travel / school): the app never guesses what the appointment was.
    public var kind: SegmentKind?
    /// Free text typed by the user; never prefilled from the event.
    public var note: String

    public init(startedAt: Date, endedAt: Date, kind: SegmentKind? = nil, note: String = "") {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.kind = kind
        self.note = note
    }
}

public enum EventDraftMapper {
    /// Proposes the part of the event that lies on `day` (multi-day events are clamped to that day).
    public static func draft(from event: DeviceEvent, on day: LocalDay, calendar: DayCalendar) throws -> SegmentDraft {
        guard !event.isAllDay else { throw EventDraftError.allDayEvent }
        guard let interval = calendar.interval(of: day) else { throw EventDraftError.notOnDay }
        guard event.start < interval.end, event.end > interval.start else { throw EventDraftError.notOnDay }
        let start = max(event.start, interval.start)
        let end = min(event.end, interval.end)
        guard end > start else { throw EventDraftError.emptyInterval }
        return SegmentDraft(startedAt: start, endedAt: end)
    }

    /// Turns a confirmed draft into the request body. Requires an explicit kind and a positive interval; the note is the user's own text.
    public static func input(from draft: SegmentDraft) throws -> SegmentInput {
        guard let kind = draft.kind else { throw EventDraftError.kindMissing }
        guard draft.endedAt > draft.startedAt else { throw EventDraftError.emptyInterval }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return SegmentInput(kind: kind, startedAt: draft.startedAt, endedAt: draft.endedAt, note: note.isEmpty ? nil : note)
    }
}
