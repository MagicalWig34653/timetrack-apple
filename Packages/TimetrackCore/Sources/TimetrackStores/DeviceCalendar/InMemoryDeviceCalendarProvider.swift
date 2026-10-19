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

    public func apply(_ operations: [WriteOperation], calendarID: String, calendar: DayCalendar) throws {
        if failWrites { throw CocoaError(.fileWriteUnknown) }
        dayCalendar = calendar
        for operation in operations {
            switch operation {
            case .create(let entry):
                written["event-\(nextID)"] = WrittenRecord(calendarID: calendarID, entry: entry)
                nextID += 1
            case .update(let id, let entry):
                if written[id]?.calendarID == calendarID { written[id] = WrittenRecord(calendarID: calendarID, entry: entry) }
            case .delete(let id):
                if written[id]?.calendarID == calendarID { written[id] = nil }
            }
        }
    }
}
