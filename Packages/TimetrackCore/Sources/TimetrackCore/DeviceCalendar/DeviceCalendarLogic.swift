import Foundation

/// Which device events are shown for a local day.
public enum DeviceEventFilter {
    /// Events of the selected calendars that touch `day`, all-day first, then by start. Declined and cancelled events are hidden.
    /// The calendar Timetrack writes itself (`preferences.timetrackCalendarID`) is never shown again as context.
    public static func events(on day: LocalDay, in events: [DeviceEvent], preferences: CalendarPreferences, calendar: DayCalendar) -> [DeviceEvent] {
        guard let interval = calendar.interval(of: day) else { return [] }
        let result = events.filter { event in
            guard preferences.selectedCalendarIDs.contains(event.calendarID), event.calendarID != preferences.timetrackCalendarID else { return false }
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
        let first = calendar.day(for: event.start)
        guard event.end > event.start else { return first...first }
        let last = calendar.day(for: event.end.addingTimeInterval(-1))
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

// MARK: - Write-back of planned work days

/// A planned work day as an all-day event in the dedicated Timetrack calendar. The plan has no clock times, so none are invented.
public struct PlannedWorkEvent: Sendable, Equatable {
    public let day: LocalDay
    public let mode: PlanMode
    public let title: String

    public init(day: LocalDay, mode: PlanMode, title: String) {
        self.day = day
        self.mode = mode
        self.title = title
    }
}

/// An event Timetrack wrote earlier (recognised by its marker URL, see `PlanMarker`).
public struct WrittenEvent: Sendable, Equatable {
    public let eventID: String
    public let day: LocalDay
    public let title: String

    public init(eventID: String, day: LocalDay, title: String) {
        self.eventID = eventID
        self.day = day
        self.title = title
    }
}

public enum WriteOperation: Sendable, Equatable {
    case create(PlannedWorkEvent)
    case update(eventID: String, PlannedWorkEvent)
    case delete(eventID: String, day: LocalDay)
}

public enum PlanMarker {
    public static let scheme = "timetrack"
    public static let host = "plan"

    public static func url(for day: LocalDay) -> URL? { URL(string: "\(scheme)://\(host)/\(day)") }

    /// The day of a marker URL; nil for anything not written by Timetrack.
    public static func day(from url: URL?) -> LocalDay? {
        guard let url, url.scheme == scheme, url.host == host else { return nil }
        let day = url.lastPathComponent
        return LocalDays.parse(day) == nil ? nil : day
    }
}

public enum PlanWriteBackPlanner {
    /// Only days that actually mean "I work": office, home, customer, school. Days off and unknown modes are not written.
    public static func isWritten(_ mode: PlanMode) -> Bool { [.office, .home, .customer, .school].contains(mode) }

    public static func desired(from planDays: [LocalDay: PlanDay], from: LocalDay, to: LocalDay, title: (PlanMode) -> String) -> [PlannedWorkEvent] {
        planDays.values
            .filter { $0.date >= from && $0.date <= to && isWritten($0.mode) }
            .sorted { $0.date < $1.date }
            .map { PlannedWorkEvent(day: $0.date, mode: $0.mode, title: title($0.mode)) }
    }

    /// Minimal operations that make the written events of `[from, to]` match `desired`. Events outside the range and events without
    /// Timetrack's marker are never touched; duplicates for one day are removed.
    public static func operations(desired: [PlannedWorkEvent], existing: [WrittenEvent], from: LocalDay, to: LocalDay) -> [WriteOperation] {
        var operations: [WriteOperation] = []
        var kept: [LocalDay: WrittenEvent] = [:]
        for event in existing where event.day >= from && event.day <= to {
            if kept[event.day] == nil { kept[event.day] = event } else { operations.append(.delete(eventID: event.eventID, day: event.day)) }
        }
        let wanted = Dictionary(desired.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        for day in wanted.keys.sorted() {
            guard let target = wanted[day] else { continue }
            if let current = kept[day] {
                if current.title != target.title { operations.append(.update(eventID: current.eventID, target)) }
            } else {
                operations.append(.create(target))
            }
        }
        for (day, event) in kept where wanted[day] == nil { operations.append(.delete(eventID: event.eventID, day: day)) }
        return operations.sorted { sortKey($0) < sortKey($1) }
    }

    private static func sortKey(_ operation: WriteOperation) -> String {
        switch operation {
        case .create(let event): "\(event.day)-1"
        case .update(_, let event): "\(event.day)-2"
        case .delete(let id, let day): "\(day)-3-\(id)"
        }
    }
}
