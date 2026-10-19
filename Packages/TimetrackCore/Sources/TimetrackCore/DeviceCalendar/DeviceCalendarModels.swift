import Foundation

/// What the app may do with the device calendars (EventKit). Mirrors `EKAuthorizationStatus` without importing EventKit.
public enum CalendarAccess: String, Sendable, Equatable {
    case notDetermined, denied, restricted, writeOnly, full

    /// EventKit hands out read access only together with write access ("full access"); write-only access cannot read events.
    public var canRead: Bool { self == .full }
    public var canWrite: Bool { self == .full || self == .writeOnly }
}

public struct DeviceCalendarInfo: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let accountTitle: String
    /// `RRGGBB`, nil when the system gives no colour.
    public let colorHex: String?
    public let allowsWrite: Bool

    public init(id: String, title: String, accountTitle: String, colorHex: String? = nil, allowsWrite: Bool = true) {
        self.id = id
        self.title = title
        self.accountTitle = accountTitle
        self.colorHex = colorHex
        self.allowsWrite = allowsWrite
    }
}

/// One calendar event read from the device.
///
/// Privacy: deliberately NOT `Codable`/`Encodable`. Titles and locations stay on the device and must never be serialised into
/// a request to the backend (see `DeviceCalendarTests`).
public struct DeviceEvent: Sendable, Equatable, Hashable, Identifiable {
    /// Stable per occurrence (recurring events share the system identifier, so the start is part of it).
    public let id: String
    public let calendarID: String
    public let title: String
    public let location: String?
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let isDeclined: Bool
    public let isCancelled: Bool
    /// True for events Timetrack wrote itself (marker URL). They are never shown again as context.
    public let isWrittenByTimetrack: Bool

    public init(id: String, calendarID: String, title: String, location: String? = nil, start: Date, end: Date, isAllDay: Bool = false,
                isDeclined: Bool = false, isCancelled: Bool = false, isWrittenByTimetrack: Bool = false) {
        self.isWrittenByTimetrack = isWrittenByTimetrack
        self.id = id
        self.calendarID = calendarID
        self.title = title
        self.location = location
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.isCancelled = isCancelled
    }
}

/// What Timetrack does with one calendar. Chosen per calendar, per device.
public enum CalendarMode: String, Codable, Sendable, CaseIterable {
    /// Neither read nor written.
    case off
    /// Events are shown as context in the day view; nothing is written.
    case read
    /// Like `read`, and Timetrack also writes planned vacation and sick days (optionally plan days) into it.
    case readWrite

    public var reads: Bool { self != .off }
    public var writes: Bool { self == .readWrite }
}

/// Per-device calendar settings. Opt-in everywhere: nothing is read or written until a calendar is switched on.
public struct CalendarPreferences: Codable, Sendable, Equatable {
    /// Mode per calendar identifier; calendars not listed are `off`.
    public private(set) var modes: [String: CalendarMode] = [:]
    public var showAllDay = true
    /// Identifier of the calendar Timetrack created itself (it is an ordinary calendar for the mode choice).
    public var timetrackCalendarID: String?
    /// Which kinds of entries are written into the read+write calendars.
    public var writePlanDays = false
    public var writeAbsences = true

    public init(modes: [String: CalendarMode] = [:], showAllDay: Bool = true, timetrackCalendarID: String? = nil, writePlanDays: Bool = false, writeAbsences: Bool = true) {
        self.modes = modes.filter { $0.value != .off }
        self.showAllDay = showAllDay
        self.timetrackCalendarID = timetrackCalendarID
        self.writePlanDays = writePlanDays
        self.writeAbsences = writeAbsences
    }

    /// Convenience: the given calendars read-only.
    public init(selectedCalendarIDs: Set<String>, showAllDay: Bool = true, timetrackCalendarID: String? = nil) {
        self.init(modes: Dictionary(uniqueKeysWithValues: selectedCalendarIDs.map { ($0, CalendarMode.read) }), showAllDay: showAllDay, timetrackCalendarID: timetrackCalendarID)
    }

    public func mode(for id: String) -> CalendarMode { modes[id] ?? .off }
    /// Calendars whose events are shown (read and read+write).
    public var selectedCalendarIDs: Set<String> { Set(modes.filter { $0.value.reads }.keys) }
    public var writeCalendarIDs: Set<String> { Set(modes.filter { $0.value.writes }.keys) }
    public var writeEnabled: Bool { !writeCalendarIDs.isEmpty && (writePlanDays || writeAbsences) }

    public mutating func setMode(_ mode: CalendarMode, for id: String) {
        if mode == .off { modes[id] = nil } else { modes[id] = mode }
    }

    /// Forgets calendars that no longer exist.
    public mutating func retain(_ ids: Set<String>) { modes = modes.filter { ids.contains($0.key) } }

    private enum CodingKeys: String, CodingKey { case modes, showAllDay, timetrackCalendarID, writePlanDays, writeAbsences, selectedCalendarIDs, writeEnabled }

    /// Reads the E1 format too (`selectedCalendarIDs` + one global `writeEnabled`): selected calendars become `read`; a switched-on
    /// write-back moves the Timetrack calendar to `readWrite` and keeps writing plan days, as before.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showAllDay = try c.decodeIfPresent(Bool.self, forKey: .showAllDay) ?? true
        timetrackCalendarID = try c.decodeIfPresent(String.self, forKey: .timetrackCalendarID)
        if let stored = try c.decodeIfPresent([String: CalendarMode].self, forKey: .modes) {
            modes = stored.filter { $0.value != .off }
            writePlanDays = try c.decodeIfPresent(Bool.self, forKey: .writePlanDays) ?? false
            writeAbsences = try c.decodeIfPresent(Bool.self, forKey: .writeAbsences) ?? true
        } else {
            let legacy = try c.decodeIfPresent(Set<String>.self, forKey: .selectedCalendarIDs) ?? []
            var migrated = Dictionary(uniqueKeysWithValues: legacy.map { ($0, CalendarMode.read) })
            let wasWriting = try c.decodeIfPresent(Bool.self, forKey: .writeEnabled) ?? false
            if wasWriting, let id = timetrackCalendarID { migrated[id] = .readWrite }
            modes = migrated
            writePlanDays = wasWriting
            writeAbsences = true
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modes, forKey: .modes)
        try c.encode(showAllDay, forKey: .showAllDay)
        try c.encodeIfPresent(timetrackCalendarID, forKey: .timetrackCalendarID)
        try c.encode(writePlanDays, forKey: .writePlanDays)
        try c.encode(writeAbsences, forKey: .writeAbsences)
    }
}
