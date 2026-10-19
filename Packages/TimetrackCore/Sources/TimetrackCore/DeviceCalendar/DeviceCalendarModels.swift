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

    public init(id: String, calendarID: String, title: String, location: String? = nil, start: Date, end: Date, isAllDay: Bool = false,
                isDeclined: Bool = false, isCancelled: Bool = false) {
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

/// Per-device calendar settings. Opt-in everywhere: nothing is shown until calendars are chosen, nothing is written until enabled.
public struct CalendarPreferences: Codable, Sendable, Equatable {
    public var selectedCalendarIDs: Set<String> = []
    /// Writing planned work days to the dedicated "Timetrack" calendar. Off by default.
    public var writeEnabled = false
    public var showAllDay = true
    /// Identifier of the calendar Timetrack created (never a user's own calendar).
    public var timetrackCalendarID: String?

    public init(selectedCalendarIDs: Set<String> = [], writeEnabled: Bool = false, showAllDay: Bool = true, timetrackCalendarID: String? = nil) {
        self.selectedCalendarIDs = selectedCalendarIDs
        self.writeEnabled = writeEnabled
        self.showAllDay = showAllDay
        self.timetrackCalendarID = timetrackCalendarID
    }
}
