import Foundation

// MARK: - Writing to calendars (planned work days, planned vacation and sick days)

/// What Timetrack writes as an all-day event: a single plan day or a whole absence (one multi-day event). Only a generic title is
/// used; notes of an absence never reach the calendar.
public struct CalendarEntry: Sendable, Equatable {
    /// Stable identity, also the payload of the marker URL: `plan/<day>` or `absence/<uuid>`.
    public let key: String
    public let firstDay: LocalDay
    public let lastDay: LocalDay
    public let title: String

    public init(key: String, firstDay: LocalDay, lastDay: LocalDay, title: String) {
        self.key = key
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.title = title
    }
}

/// An event Timetrack wrote earlier (recognised by its marker URL, see `EntryMarker`).
public struct WrittenEvent: Sendable, Equatable {
    public let eventID: String
    public let key: String
    public let firstDay: LocalDay
    public let lastDay: LocalDay
    public let title: String

    public init(eventID: String, key: String, firstDay: LocalDay, lastDay: LocalDay, title: String) {
        self.eventID = eventID
        self.key = key
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.title = title
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
        let last = url.lastPathComponent
        switch host {
        case planHost: return LocalDays.parse(last) == nil ? nil : planKey(last)
        case absenceHost: return UUID(uuidString: last).map(absenceKey)
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
        case (.sick, .planned), (.sick, .approved), (.sick, .taken): "Krank"
        default: nil
        }
    }
}

public enum CalendarWritePlanner {
    /// Only days that actually mean "I work": office, home, customer, school. Days off and unknown modes are not written.
    public static func isWritten(_ mode: PlanMode) -> Bool { [.office, .home, .customer, .school].contains(mode) }

    public static func desiredPlanDays(from planDays: [LocalDay: PlanDay], from: LocalDay, to: LocalDay, title: (PlanMode) -> String) -> [CalendarEntry] {
        planDays.values
            .filter { $0.date >= from && $0.date <= to && isWritten($0.mode) }
            .sorted { $0.date < $1.date }
            .map { CalendarEntry(key: EntryMarker.planKey($0.date), firstDay: $0.date, lastDay: $0.date, title: title($0.mode)) }
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
