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
            let provider = fakeProvider()
            fake = provider
            return DeviceCalendarStore(provider: provider, storage: MemoryCalendarPreferencesStorage())
        }
        #endif
        return DeviceCalendarStore(provider: EventKitProvider(), ledgerStorage: UserDefaultsCalendarLedgerStorage())
    }

    #if DEBUG
    /// The in-memory provider of the current run (UI-test pages read what was written from it).
    @MainActor private static var fake: InMemoryDeviceCalendarProvider?

    /// One line per event written into the fake calendars: title, first...last day, calendar. Never contains notes.
    @MainActor
    static func writtenSummary() -> String {
        guard let fake else { return "–" }
        let names = Dictionary(fake.storedCalendars.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let lines = fake.written.values
            .sorted { ($0.entry.firstDay, $0.calendarID) < ($1.entry.firstDay, $1.calendarID) }
            .map { "\($0.entry.title) | \(names[$0.calendarID] ?? $0.calendarID) | \($0.entry.lastDay > $0.entry.firstDay ? "\($0.entry.firstDay)…\($0.entry.lastDay)" : $0.entry.firstDay)" }
        return lines.isEmpty ? "leer" : lines.joined(separator: "\n")
    }

    @MainActor
    private static func fakeProvider() -> InMemoryDeviceCalendarProvider {
        let calendars = [
            DeviceCalendarInfo(id: "work", title: "Arbeit", accountTitle: "iCloud", colorHex: "3478F6"),
            DeviceCalendarInfo(id: "family", title: "Familie", accountTitle: "iCloud", colorHex: "34C759"),
            DeviceCalendarInfo(id: "school", title: "Berufsschule", accountTitle: "Exchange", colorHex: "FF9500"),
            DeviceCalendarInfo(id: "holidays", title: "Feiertage", accountTitle: "Abonnements", colorHex: "AF52DE", allowsWrite: false),
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
