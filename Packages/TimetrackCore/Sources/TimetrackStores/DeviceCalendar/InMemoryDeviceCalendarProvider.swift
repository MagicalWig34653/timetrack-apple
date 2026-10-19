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
    public private(set) var written: [String: PlannedWorkEvent] = [:] // event id -> event
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
        storedEvents.filter { calendarIDs.contains($0.calendarID) && $0.start < to && max($0.end, $0.start) >= from }
    }

    public func ensureTimetrackCalendar(existingID: String?) throws -> String {
        if !storedCalendars.contains(where: { $0.id == timetrackCalendarID }) {
            storedCalendars.append(DeviceCalendarInfo(id: timetrackCalendarID, title: "Timetrack", accountTitle: "Lokal"))
        }
        return timetrackCalendarID
    }

    public func writtenEvents(calendarID: String, from: Date, to: Date) -> [WrittenEvent] {
        written.map { WrittenEvent(eventID: $0.key, day: $0.value.day, title: $0.value.title) }.sorted { $0.day < $1.day }
    }

    public func apply(_ operations: [WriteOperation], calendarID: String, calendar: DayCalendar) throws {
        if failWrites { throw CocoaError(.fileWriteUnknown) }
        for operation in operations {
            switch operation {
            case .create(let event):
                written["event-\(nextID)"] = event
                nextID += 1
            case .update(let id, let event): written[id] = event
            case .delete(let id, _): written[id] = nil
            }
        }
    }
}
