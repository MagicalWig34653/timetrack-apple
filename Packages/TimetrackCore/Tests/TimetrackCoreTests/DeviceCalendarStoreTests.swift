import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

private let berlin = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

private func event(_ id: String, calendar: String = "work", day: LocalDay = "2026-10-19", from: (Int, Int) = (10, 0), to: (Int, Int) = (11, 0)) -> DeviceEvent {
    DeviceEvent(id: id, calendarID: calendar, title: "Termin", location: "Raum 5", start: berlin.instant(day: day, hour: from.0, minute: from.1)!, end: berlin.instant(day: day, hour: to.0, minute: to.1)!)
}

@MainActor
@Suite("Device calendar store")
struct DeviceCalendarStoreTests {
    private func makeStore(access: CalendarAccess = .notDetermined, grant: CalendarAccess = .full, events: [DeviceEvent] = [], prefs: CalendarPreferences = CalendarPreferences())
        -> (DeviceCalendarStore, InMemoryDeviceCalendarProvider, MemoryCalendarPreferencesStorage) {
        let provider = InMemoryDeviceCalendarProvider(access: access, grantResult: grant,
                                                      calendars: [DeviceCalendarInfo(id: "work", title: "Arbeit", accountTitle: "iCloud"), DeviceCalendarInfo(id: "private", title: "Privat", accountTitle: "iCloud")],
                                                      events: events)
        let storage = MemoryCalendarPreferencesStorage(prefs)
        return (DeviceCalendarStore(provider: provider, storage: storage), provider, storage)
    }

    @Test func startsWithoutRequestingAnything() {
        let (store, provider, _) = makeStore()
        #expect(store.access == .notDetermined)
        #expect(provider.requestCount == 0)
        #expect(!store.preferences.writeEnabled)
        #expect(store.events(on: "2026-10-19", calendar: berlin).isEmpty)
    }

    @Test func requestGrantsAndListsCalendars() async {
        let (store, provider, _) = makeStore()
        await store.requestAccess()
        #expect(provider.requestCount == 1)
        #expect(store.access == .full)
        #expect(store.selectableCalendars.map(\.id) == ["work", "private"])
    }

    @Test func deniedShowsMessageAndNoCalendars() async {
        let (store, _, _) = makeStore(grant: .denied)
        await store.requestAccess()
        #expect(store.access == .denied)
        #expect(store.message != nil)
        #expect(store.calendars.isEmpty)
    }

    @Test func eventsAppearOnlyAfterSelection() async {
        let (store, _, storage) = makeStore(access: .full, events: [event("a"), event("b", calendar: "private")])
        #expect(store.events(on: "2026-10-19", calendar: berlin).isEmpty)
        store.setSelected("work", true)
        #expect(store.events(on: "2026-10-19", calendar: berlin).map(\.id) == ["a"])
        #expect(storage.load().selectedCalendarIDs == ["work"])
        store.setSelected("work", false)
        #expect(store.events(on: "2026-10-19", calendar: berlin).isEmpty)
    }

    @Test func writeOnlyAccessCannotRead() {
        let (store, _, _) = makeStore(access: .writeOnly, events: [event("a")], prefs: CalendarPreferences(selectedCalendarIDs: ["work"]))
        #expect(!store.showsEvents)
        #expect(store.events(on: "2026-10-19", calendar: berlin).isEmpty)
    }

    @Test func staleSelectionIsPruned() {
        let (store, _, storage) = makeStore(access: .full, prefs: CalendarPreferences(selectedCalendarIDs: ["work", "deleted"]))
        #expect(store.preferences.selectedCalendarIDs == ["work"])
        #expect(storage.load().selectedCalendarIDs == ["work"])
    }

    @Test func eventCountsPerDay() {
        let (store, _, _) = makeStore(access: .full, events: [event("a"), event("b", from: (13, 0), to: (14, 0)), event("c", day: "2026-10-21")], prefs: CalendarPreferences(selectedCalendarIDs: ["work"]))
        #expect(store.eventCounts(from: "2026-10-19", to: "2026-10-25", calendar: berlin) == ["2026-10-19": 2, "2026-10-21": 1])
    }

    @Test func storeChangeNotificationBumpsCounter() {
        let (store, provider, _) = makeStore(access: .full)
        let before = store.changeCount
        provider.onStoreChanged?()
        #expect(store.changeCount == before + 1)
    }
}
