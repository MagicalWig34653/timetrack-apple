import Foundation

// MARK: - Writing to calendars (planned work days, planned vacation and sick days)

/// What Timetrack writes as an event: a plan day without blocks (all-day), one plan block (timed, P13) or a whole absence (one
/// multi-day all-day event). Only a generic title is used; notes and places of plan blocks and absences never reach the calendar.
public struct CalendarEntry: Sendable, Equatable {
    /// Stable identity, also the payload of the marker URL: `plan/<day>`, `plan/<day>/<n>` (n-th block, 1-based) or `absence/<uuid>`.
    public let key: String
    public let firstDay: LocalDay
    public let lastDay: LocalDay
    public let title: String
    /// Minutes since local midnight of `firstDay` for a timed event (a plan block); both nil = all-day.
    public let startMinute: Int?
    public let endMinute: Int?

    public init(key: String, firstDay: LocalDay, lastDay: LocalDay, title: String, startMinute: Int? = nil, endMinute: Int? = nil) {
        self.key = key
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.title = title
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public var isTimed: Bool { startMinute != nil && endMinute != nil }
}

/// An event Timetrack wrote earlier (recognised by its marker URL, see `EntryMarker`).
public struct WrittenEvent: Sendable, Equatable {
    public let eventID: String
    public let key: String
    public let firstDay: LocalDay
    public let lastDay: LocalDay
    public let title: String
    /// Local start and end minute of a timed event (plan block); nil for all-day events.
    public let startMinute: Int?
    public let endMinute: Int?

    public init(eventID: String, key: String, firstDay: LocalDay, lastDay: LocalDay, title: String, startMinute: Int? = nil, endMinute: Int? = nil) {
        self.eventID = eventID
        self.key = key
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.title = title
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    /// Builds the record of a device event, reading its instants in `calendar`'s zone (the zone the events were WRITTEN in, i.e. the
    /// work model's; the device zone would shift minutes and day borders while travelling).
    public static func reading(eventID: String, key: String, title: String, isAllDay: Bool, start: Date, end: Date, calendar: DayCalendar) -> WrittenEvent {
        if !isAllDay, key.split(separator: "/").count == 3 {
            // P13: a plan block is a timed event on one day.
            let from = calendar.hourAndMinute(of: start), to = calendar.hourAndMinute(of: end)
            let day = calendar.day(for: start)
            return WrittenEvent(eventID: eventID, key: key, firstDay: day, lastDay: day, title: title,
                                startMinute: from.hour * 60 + from.minute, endMinute: to.hour * 60 + to.minute)
        }
        let days = DeviceEventFilter.allDayDays(start: start, end: end, calendar: calendar)
        return WrittenEvent(eventID: eventID, key: key, firstDay: days.lowerBound, lastDay: days.upperBound, title: title)
    }
}

public enum WriteOperation: Sendable, Equatable {
    case create(CalendarEntry)
    case update(eventID: String, CalendarEntry)
    case delete(eventID: String)
}

/// The marker URL on every event Timetrack writes. Anything without it is never modified or deleted.
public enum EntryMarker {
    public static let scheme = "timetrack"
    public static let planHost = "plan"
    public static let absenceHost = "absence"

    public static func planKey(_ day: LocalDay) -> String { "\(planHost)/\(day)" }
    /// Key of the n-th plan block of a day (`plan/<day>/<n>`, n starts at 1).
    public static func planBlockKey(_ day: LocalDay, number: Int) -> String { "\(planHost)/\(day)/\(number)" }
    public static func absenceKey(_ id: UUID) -> String { "\(absenceHost)/\(id.uuidString)" }

    public static func url(forKey key: String) -> URL? { URL(string: "\(scheme)://\(key)") }

    /// The notes text of an event Timetrack writes: a short German hint plus the marker URL. Some calendar servers drop the URL field,
    /// so the marker is also kept here (N2) and read back from either place. No user data is stored in it.
    public static func notes(forKey key: String) -> String {
        "Von Timetrack geschrieben. Änderungen bitte in Timetrack vornehmen.\n\(scheme)://\(key)"
    }

    /// The key from the URL field, or else from a marker token inside the notes; nil for anything not written by Timetrack.
    public static func key(from url: URL?, notes: String?) -> String? {
        if let key = key(from: url) { return key }
        guard let notes else { return nil }
        for token in notes.split(whereSeparator: \.isWhitespace) where token.hasPrefix("\(scheme)://") {
            if let key = key(from: URL(string: String(token))) { return key }
        }
        return nil
    }

    /// The key of a marker URL; nil for anything not written by Timetrack (or a malformed marker).
    public static func key(from url: URL?) -> String? {
        guard let url, url.scheme == scheme, let host = url.host else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        switch host {
        case planHost:
            if parts.count == 1, LocalDays.parse(parts[0]) != nil { return planKey(parts[0]) }
            if parts.count == 2, LocalDays.parse(parts[0]) != nil, let number = Int(parts[1]), number >= 1, String(number) == parts[1] {
                return planBlockKey(parts[0], number: number)
            }
            return nil
        case absenceHost: return parts.count == 1 ? UUID(uuidString: parts[0]).map(absenceKey) : nil
        default: return nil
        }
    }
}

/// Calendar titles for absences. Deliberately generic: no notes, no document status.
public enum AbsenceCalendarTitle {
    /// The title Timetrack writes for an absence, or nil when it is not written (other kinds, requested, rejected, cancelled).
    public static func title(kind: AbsenceKind, status: AbsenceStatus) -> String? {
        switch (kind, status) {
        case (.vacation, .planned): "Urlaub (geplant)"
        case (.vacation, .approved): "Urlaub (genehmigt)"
        case (.vacation, .taken): "Urlaub"
        case (.sick, .recorded), (.sick, .planned), (.sick, .approved), (.sick, .taken): "Krank"
        default: nil
        }
    }
}

public enum CalendarWritePlanner {
    /// Only days that actually mean "I work": office, home, customer, school. Days off and unknown modes are not written.
    public static func isWritten(_ mode: PlanMode) -> Bool { [.office, .home, .customer, .school].contains(mode) }

    /// Planned work days. A day with plan blocks (P13) becomes one timed event per block (`plan/<day>/<n>`, in time order, title by
    /// block kind, never place or note); a day without blocks stays one all-day event (`plan/<day>`).
    public static func desiredPlanDays(from planDays: [LocalDay: PlanDay], from: LocalDay, to: LocalDay, title: (PlanMode) -> String,
                                       blockTitle: (PlanBlockKind) -> String = PlanBlockKind.calendarTitle) -> [CalendarEntry] {
        planDays.values
            .filter { $0.date >= from && $0.date <= to && isWritten($0.mode) }
            .sorted { $0.date < $1.date }
            .flatMap { day -> [CalendarEntry] in
                let blocks = day.blocks.filter { ($0.startMinutes ?? 0) < ($0.endMinutes ?? 0) && $0.startMinutes != nil && $0.endMinutes != nil }
                    .sorted { ($0.startMinutes ?? 0) < ($1.startMinutes ?? 0) }
                guard !blocks.isEmpty else {
                    return [CalendarEntry(key: EntryMarker.planKey(day.date), firstDay: day.date, lastDay: day.date, title: title(day.mode))]
                }
                return blocks.enumerated().map { index, block in
                    CalendarEntry(key: EntryMarker.planBlockKey(day.date, number: index + 1), firstDay: day.date, lastDay: day.date,
                                  title: blockTitle(block.kind), startMinute: block.startMinutes, endMinute: block.endMinutes)
                }
            }
    }

    /// Planned/approved vacation and sick days as one event per absence. Absences that do not touch `[from, to]` are skipped.
    public static func desiredAbsences(_ absences: [Absence], from: LocalDay, to: LocalDay) -> [CalendarEntry] {
        absences
            .compactMap { absence -> CalendarEntry? in
                guard absence.endDate >= from, absence.startDate <= to, absence.endDate >= absence.startDate,
                      let title = AbsenceCalendarTitle.title(kind: absence.kind, status: absence.status) else { return nil }
                return CalendarEntry(key: EntryMarker.absenceKey(absence.id), firstDay: absence.startDate, lastDay: absence.endDate, title: title)
            }
            .sorted { ($0.firstDay, $0.key) < ($1.firstDay, $1.key) }
    }

    /// Minimal operations that make the written events overlapping `[from, to]` match `desired` (matched by key). Events outside the
    /// range and events without Timetrack's marker are never touched; duplicates of one key are removed. `managing` restricts
    /// the comparison to some key families (e.g. only absences) so the others are left alone.
    public static func operations(desired: [CalendarEntry], existing: [WrittenEvent], from: LocalDay, to: LocalDay, managing prefixes: [String] = [EntryMarker.planHost, EntryMarker.absenceHost]) -> [WriteOperation] {
        CalendarReconciler.plan(desired: desired, existing: existing, records: [:], from: from, to: to, managing: prefixes).operations
    }

    /// Deletes every given event (the "remove everything Timetrack wrote" button). Callers only pass marker-carrying events.
    public static func removalOperations(for existing: [WrittenEvent]) -> [WriteOperation] {
        existing.sorted { ($0.firstDay, $0.eventID) < ($1.firstDay, $1.eventID) }.map { .delete(eventID: $0.eventID) }
    }

    public static func sortKey(_ operation: WriteOperation) -> String {
        switch operation {
        case .create(let entry): "\(entry.firstDay)-1-\(entry.key)"
        case .update(let id, let entry): "\(entry.firstDay)-2-\(id)"
        case .delete(let id): "0000-3-\(id)"
        }
    }
}
