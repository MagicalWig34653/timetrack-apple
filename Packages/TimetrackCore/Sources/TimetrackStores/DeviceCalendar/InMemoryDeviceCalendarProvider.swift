import Foundation
import TimetrackCore

/// A calendar provider without EventKit: for unit tests and for UI tests in the simulator (`TT_DEV_CALENDAR_FAKE`).
@MainActor
public final class InMemoryDeviceCalendarProvider: DeviceCalendarProvider {
    public var access: CalendarAccess
    /// What a permission request ends with.
    public var grantResult: CalendarAccess
    public var storedCalendars: [DeviceCalendarInfo]
    public var storedEvents: [DeviceEvent]
    public var timetrackCalendarID = "timetrack-calendar"
    public var failWrites = false
    public struct WrittenRecord: Sendable, Equatable {
        public let calendarID: String
        public let entry: CalendarEntry
    }
    public private(set) var written: [String: WrittenRecord] = [:] // event id -> record
    private var dayCalendar: DayCalendar?
    public private(set) var requestCount = 0
    public var onStoreChanged: (@MainActor () -> Void)?
    private var nextID = 1

    public init(access: CalendarAccess = .notDetermined, grantResult: CalendarAccess = .full, calendars: [DeviceCalendarInfo] = [], events: [DeviceEvent] = []) {
        self.access = access
        self.grantResult = grantResult
        self.storedCalendars = calendars
        self.storedEvents = events
    }

    public func requestFullAccess() async throws -> CalendarAccess {
        requestCount += 1
        access = grantResult
        return access
    }

    public func calendars() -> [DeviceCalendarInfo] { storedCalendars }

    public func events(from: Date, to: Date, calendarIDs: Set<String>) -> [DeviceEvent] {
        // Written events are visible like in a real calendar (flagged, so the context filter hides them again).
        var all = storedEvents
        if let dayCalendar {
            for (id, record) in written {
                guard let first = dayCalendar.interval(of: record.entry.firstDay), let last = dayCalendar.interval(of: record.entry.lastDay) else { continue }
                all.append(DeviceEvent(id: id, calendarID: record.calendarID, title: record.entry.title, start: first.start, end: last.end.addingTimeInterval(-1),
                                       isAllDay: true, isWrittenByTimetrack: true))
            }
        }
        return all.filter { calendarIDs.contains($0.calendarID) && $0.start < to && max($0.end, $0.start) >= from }
    }

    public func ensureTimetrackCalendar(existingID: String?) throws -> String {
        if !storedCalendars.contains(where: { $0.id == timetrackCalendarID }) {
            storedCalendars.append(DeviceCalendarInfo(id: timetrackCalendarID, title: "Timetrack", accountTitle: "Lokal"))
        }
        return timetrackCalendarID
    }

    public func writtenEvents(calendarID: String, from: Date, to: Date) -> [WrittenEvent] {
        written.filter { $0.value.calendarID == calendarID }
            .map { WrittenEvent(eventID: $0.key, key: $0.value.entry.key, firstDay: $0.value.entry.firstDay, lastDay: $0.value.entry.lastDay, title: $0.value.entry.title) }
            .sorted { ($0.firstDay, $0.eventID) < ($1.firstDay, $1.eventID) }
    }

    @discardableResult
    public func apply(_ operations: [WriteOperation], calendarID: String, calendar: DayCalendar) throws -> [String: String] {
        if failWrites { throw CocoaError(.fileWriteUnknown) }
        dayCalendar = calendar
        var assigned: [String: String] = [:]
        for operation in operations {
            switch operation {
            case .create(let entry):
                let id = "event-\(nextID)"
                written[id] = WrittenRecord(calendarID: calendarID, entry: entry)
                assigned[entry.key] = id
                nextID += 1
            case .update(let id, let entry):
                if written[id]?.calendarID == calendarID {
                    written[id] = WrittenRecord(calendarID: calendarID, entry: entry)
                    assigned[entry.key] = id
                }
            case .delete(let id):
                if written[id]?.calendarID == calendarID { written[id] = nil }
            }
        }
        return assigned
    }

    // MARK: Simulating what happens outside the app (tests, UI tests)

    /// The user deletes an event by hand in the Calendar app.
    public func userDeleteEvent(_ id: String) { written[id] = nil }

    /// The system hands out a new identifier for the same event (e.g. after an account sync).
    public func changeIdentifier(of id: String) {
        guard let record = written[id] else { return }
        written[id] = nil
        written["event-\(nextID)"] = record
        nextID += 1
    }

    /// The user (or a server) moves an event to other days.
    public func userMoveEvent(_ id: String, first: LocalDay, last: LocalDay) {
        guard let record = written[id] else { return }
        let entry = CalendarEntry(key: record.entry.key, firstDay: first, lastDay: last, title: record.entry.title)
        written[id] = WrittenRecord(calendarID: record.calendarID, entry: entry)
    }
}
