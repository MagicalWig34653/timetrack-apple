import Foundation
import TimetrackCore
import TimetrackStores

enum CalendarEnvironment {
    /// The app's device-calendar store. Creating it never asks for permission.
    @MainActor
    static func makeStore() -> DeviceCalendarStore {
        #if DEBUG
        // Simulator/UI-test convenience: an in-memory calendar with sample events instead of EventKit (no system permission sheet).
        if ProcessInfo.processInfo.environment["TT_DEV_CALENDAR_FAKE"] == "1" {
            return DeviceCalendarStore(provider: fakeProvider(), storage: MemoryCalendarPreferencesStorage())
        }
        #endif
        return DeviceCalendarStore(provider: EventKitProvider())
    }

    #if DEBUG
    @MainActor
    private static func fakeProvider() -> InMemoryDeviceCalendarProvider {
        let calendars = [
            DeviceCalendarInfo(id: "work", title: "Arbeit", accountTitle: "iCloud", colorHex: "3478F6"),
            DeviceCalendarInfo(id: "family", title: "Familie", accountTitle: "iCloud", colorHex: "34C759"),
            DeviceCalendarInfo(id: "school", title: "Berufsschule", accountTitle: "Exchange", colorHex: "FF9500"),
        ]
        let zone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let dayCalendar = DayCalendar(timeZone: zone)
        let today = dayCalendar.day(for: .now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date { dayCalendar.instant(day: today, hour: hour, minute: minute) ?? .now }
        let events = [
            DeviceEvent(id: "e1", calendarID: "work", title: "Team-Besprechung", location: "Raum 4", start: at(9), end: at(10, 30)),
            DeviceEvent(id: "e2", calendarID: "school", title: "Berufsschule Informatik", start: at(12), end: at(15, 15)),
            DeviceEvent(id: "e3", calendarID: "family", title: "Zahnarzt", start: at(17), end: at(17, 45)),
            DeviceEvent(id: "e4", calendarID: "work", title: "Betriebsausflug", start: at(0), end: at(23, 59), isAllDay: true),
        ]
        return InMemoryDeviceCalendarProvider(access: .notDetermined, grantResult: .full, calendars: calendars, events: events)
    }
    #endif
}
