import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

private let berlin = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

private func at(_ day: LocalDay, _ hour: Int, _ minute: Int = 0) -> Date { berlin.instant(day: day, hour: hour, minute: minute)! }

private func event(_ id: String, calendar: String = "work", title: String = "Termin", day: LocalDay = "2026-10-19", from: (Int, Int) = (10, 0), to: (Int, Int) = (11, 0),
                   allDay: Bool = false, declined: Bool = false, cancelled: Bool = false) -> DeviceEvent {
    DeviceEvent(id: id, calendarID: calendar, title: title, location: "Raum 5", start: at(day, from.0, from.1), end: at(day, to.0, to.1),
                isAllDay: allDay, isDeclined: declined, isCancelled: cancelled)
}

private let selectWork = CalendarPreferences(selectedCalendarIDs: ["work"])

@Suite("Device event filter")
struct DeviceEventFilterTests {
    @Test func onlySelectedCalendars() {
        let events = [event("a"), event("b", calendar: "private")]
        let shown = DeviceEventFilter.events(on: "2026-10-19", in: events, preferences: selectWork, calendar: berlin)
        #expect(shown.map(\.id) == ["a"])
    }

    @Test func nothingWithoutSelection() {
        #expect(DeviceEventFilter.events(on: "2026-10-19", in: [event("a")], preferences: CalendarPreferences(), calendar: berlin).isEmpty)
    }

    @Test func hidesDeclinedAndCancelled() {
        let events = [event("ok"), event("no", declined: true), event("gone", cancelled: true)]
        #expect(DeviceEventFilter.events(on: "2026-10-19", in: events, preferences: selectWork, calendar: berlin).map(\.id) == ["ok"])
    }

    @Test func dayBoundariesAreHalfOpen() {
        let endsAtMidnight = DeviceEvent(id: "late", calendarID: "work", title: "x", start: at("2026-10-18", 22), end: at("2026-10-19", 0))
        let startsAtMidnight = DeviceEvent(id: "early", calendarID: "work", title: "x", start: at("2026-10-19", 0), end: at("2026-10-19", 1))
        let events = [endsAtMidnight, startsAtMidnight]
        #expect(DeviceEventFilter.events(on: "2026-10-19", in: events, preferences: selectWork, calendar: berlin).map(\.id) == ["early"])
        #expect(DeviceEventFilter.events(on: "2026-10-18", in: events, preferences: selectWork, calendar: berlin).map(\.id) == ["late"])
    }

    @Test func multiDayEventAppearsOnEveryDay() {
        let trip = DeviceEvent(id: "trip", calendarID: "work", title: "Messe", start: at("2026-10-19", 18), end: at("2026-10-21", 12))
        for day in ["2026-10-19", "2026-10-20", "2026-10-21"] {
            #expect(DeviceEventFilter.events(on: day, in: [trip], preferences: selectWork, calendar: berlin).count == 1)
        }
        #expect(DeviceEventFilter.events(on: "2026-10-22", in: [trip], preferences: selectWork, calendar: berlin).isEmpty)
    }

    @Test func allDayFirstAndEndInclusiveDay() {
        // EventKit ends an all-day event on 23:59:59 of its last day.
        let holiday = DeviceEvent(id: "ad", calendarID: "work", title: "Urlaub", start: at("2026-10-19", 0), end: at("2026-10-20", 23, 59), isAllDay: true)
        let meeting = event("m", from: (9, 0), to: (10, 0))
        let shown = DeviceEventFilter.events(on: "2026-10-20", in: [meeting, holiday], preferences: selectWork, calendar: berlin)
        #expect(shown.map(\.id) == ["ad"]) // the meeting is on the 19th
        let both = DeviceEventFilter.events(on: "2026-10-19", in: [meeting, holiday], preferences: selectWork, calendar: berlin)
        #expect(both.map(\.id) == ["ad", "m"])
        #expect(DeviceEventFilter.events(on: "2026-10-21", in: [holiday], preferences: selectWork, calendar: berlin).isEmpty)
    }

    @Test func allDaySwitchedOff() {
        let allDay = DeviceEvent(id: "ad", calendarID: "work", title: "x", start: at("2026-10-19", 0), end: at("2026-10-19", 23, 59), isAllDay: true)
        var prefs = selectWork
        prefs.showAllDay = false
        #expect(DeviceEventFilter.events(on: "2026-10-19", in: [allDay], preferences: prefs, calendar: berlin).isEmpty)
    }

    @Test func timetrackCalendarIsNeverContext() {
        var prefs = CalendarPreferences(selectedCalendarIDs: ["work", "tt"])
        prefs.timetrackCalendarID = "tt"
        let events = [event("a"), event("own", calendar: "tt")]
        #expect(DeviceEventFilter.events(on: "2026-10-19", in: events, preferences: prefs, calendar: berlin).map(\.id) == ["a"])
    }

    @Test func sortedByStart() {
        let events = [event("late", from: (15, 0), to: (16, 0)), event("early", from: (8, 0), to: (9, 0))]
        #expect(DeviceEventFilter.events(on: "2026-10-19", in: events, preferences: selectWork, calendar: berlin).map(\.id) == ["early", "late"])
    }

    @Test func daylightSavingDayStillContainsLateEvent() {
        // 2026-10-25 has 25 hours in Europe/Berlin.
        let late = event("late", day: "2026-10-25", from: (23, 0), to: (23, 30))
        #expect(DeviceEventFilter.events(on: "2026-10-25", in: [late], preferences: selectWork, calendar: berlin).count == 1)
    }
}

@Suite("Event to draft mapping")
struct EventDraftTests {
    @Test func draftTakesTimesAndNoKind() throws {
        let draft = try EventDraftMapper.draft(from: event("a", title: "Arzt", from: (10, 0), to: (11, 30)), on: "2026-10-19", calendar: berlin)
        #expect(draft.startedAt == at("2026-10-19", 10))
        #expect(draft.endedAt == at("2026-10-19", 11, 30))
        #expect(draft.kind == nil)
        #expect(draft.note.isEmpty)
    }

    @Test func draftWithoutKindCannotBeConfirmed() throws {
        let draft = try EventDraftMapper.draft(from: event("a"), on: "2026-10-19", calendar: berlin)
        #expect(throws: EventDraftError.kindMissing) { try EventDraftMapper.input(from: draft) }
    }

    @Test func confirmedDraftBecomesInputWithChosenKind() throws {
        var draft = try EventDraftMapper.draft(from: event("a"), on: "2026-10-19", calendar: berlin)
        draft.kind = .school
        draft.note = "  Berufsschule Block  "
        let input = try EventDraftMapper.input(from: draft)
        #expect(input.kind == .school)
        #expect(input.note == "Berufsschule Block")
        #expect(input.startedAt == draft.startedAt && input.endedAt == draft.endedAt)
    }

    @Test func editedIntervalMustStayPositive() throws {
        var draft = try EventDraftMapper.draft(from: event("a"), on: "2026-10-19", calendar: berlin)
        draft.kind = .work
        draft.endedAt = draft.startedAt
        #expect(throws: EventDraftError.emptyInterval) { try EventDraftMapper.input(from: draft) }
    }

    @Test func allDayEventsAreNotSuggested() {
        let allDay = DeviceEvent(id: "ad", calendarID: "work", title: "x", start: at("2026-10-19", 0), end: at("2026-10-19", 23, 59), isAllDay: true)
        #expect(throws: EventDraftError.allDayEvent) { try EventDraftMapper.draft(from: allDay, on: "2026-10-19", calendar: berlin) }
    }

    @Test func multiDayEventIsClampedToTheDay() throws {
        let trip = DeviceEvent(id: "trip", calendarID: "work", title: "Messe", start: at("2026-10-19", 18), end: at("2026-10-21", 12))
        let middle = try EventDraftMapper.draft(from: trip, on: "2026-10-20", calendar: berlin)
        #expect(middle.startedAt == at("2026-10-20", 0))
        #expect(middle.endedAt == at("2026-10-21", 0))
        let first = try EventDraftMapper.draft(from: trip, on: "2026-10-19", calendar: berlin)
        #expect(first.startedAt == at("2026-10-19", 18))
    }

    @Test func eventOnAnotherDayIsRejected() {
        #expect(throws: EventDraftError.notOnDay) { try EventDraftMapper.draft(from: event("a"), on: "2026-10-20", calendar: berlin) }
    }
}

@Suite("Device calendar privacy")
struct DeviceCalendarPrivacyTests {
    @Test func eventTypeCannotBeEncoded() {
        #expect(!(DeviceEvent.self is any Encodable.Type))
        #expect(!(DeviceCalendarInfo.self is any Encodable.Type))
    }

    @Test func requestBodyNeverContainsTitleOrLocation() throws {
        let secret = "Arzttermin Dr. Geheim"
        var draft = try EventDraftMapper.draft(from: event("a", title: secret), on: "2026-10-19", calendar: berlin)
        draft.kind = .work
        let input = try EventDraftMapper.input(from: draft)
        let json = String(decoding: try JSONCoding.makeEncoder().encode(input), as: UTF8.self)
        #expect(!json.contains("Geheim"))
        #expect(!json.contains("Raum 5"))
        #expect(!json.contains("Arzt"))
        #expect(json.contains("\"kind\":\"work\""))
    }

    @Test func writtenPlanEventsCarryOnlyModeTitleNoNotes() {
        let desired = PlanWriteBackPlanner.desired(from: ["2026-10-19": PlanDay(date: "2026-10-19", mode: .office, note: "privat: Arzt")], from: "2026-10-19", to: "2026-10-19") { "Arbeit: \($0.rawValue)" }
        #expect(desired == [PlannedWorkEvent(day: "2026-10-19", mode: .office, title: "Arbeit: office")])
        #expect(!desired[0].title.contains("Arzt"))
    }

    @Test func preferencesStayOnDeviceFormat() throws {
        let data = try JSONEncoder().encode(CalendarPreferences(selectedCalendarIDs: ["a"], writeEnabled: true))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("title"))
        #expect(try JSONDecoder().decode(CalendarPreferences.self, from: data).writeEnabled)
    }
}

@Suite("Plan write-back planner")
struct PlanWriteBackTests {
    private func plan(_ day: LocalDay, _ mode: PlanMode) -> PlanDay { PlanDay(date: day, mode: mode) }
    private let title: (PlanMode) -> String = { "Arbeit: \($0.rawValue)" }

    @Test func onlyWorkModesAreWritten() {
        let days = ["2026-10-19": plan("2026-10-19", .office), "2026-10-20": plan("2026-10-20", .off), "2026-10-21": plan("2026-10-21", .unknown), "2026-10-22": plan("2026-10-22", .home)]
        let desired = PlanWriteBackPlanner.desired(from: days, from: "2026-10-19", to: "2026-10-31", title: title)
        #expect(desired.map(\.day) == ["2026-10-19", "2026-10-22"])
    }

    @Test func rangeLimitsDesired() {
        let days = ["2026-09-30": plan("2026-09-30", .office), "2026-10-01": plan("2026-10-01", .office)]
        #expect(PlanWriteBackPlanner.desired(from: days, from: "2026-10-01", to: "2026-10-31", title: title).map(\.day) == ["2026-10-01"])
    }

    @Test func createsUpdatesDeletes() {
        let desired = [PlannedWorkEvent(day: "2026-10-19", mode: .office, title: "A"), PlannedWorkEvent(day: "2026-10-20", mode: .home, title: "B"),
                       PlannedWorkEvent(day: "2026-10-21", mode: .home, title: "C")]
        let existing = [WrittenEvent(eventID: "e19", day: "2026-10-19", title: "A"), WrittenEvent(eventID: "e20", day: "2026-10-20", title: "old"),
                        WrittenEvent(eventID: "e22", day: "2026-10-22", title: "gone")]
        let operations = PlanWriteBackPlanner.operations(desired: desired, existing: existing, from: "2026-10-01", to: "2026-10-31")
        #expect(operations == [
            .update(eventID: "e20", desired[1]),
            .create(desired[2]),
            .delete(eventID: "e22", day: "2026-10-22"),
        ])
    }

    @Test func eventsOutsideTheRangeAreNeverDeleted() {
        let existing = [WrittenEvent(eventID: "old", day: "2026-09-15", title: "A")]
        #expect(PlanWriteBackPlanner.operations(desired: [], existing: existing, from: "2026-10-01", to: "2026-10-31").isEmpty)
    }

    @Test func duplicatesCollapse() {
        let desired = [PlannedWorkEvent(day: "2026-10-19", mode: .office, title: "A")]
        let existing = [WrittenEvent(eventID: "x1", day: "2026-10-19", title: "A"), WrittenEvent(eventID: "x2", day: "2026-10-19", title: "A")]
        #expect(PlanWriteBackPlanner.operations(desired: desired, existing: existing, from: "2026-10-01", to: "2026-10-31") == [.delete(eventID: "x2", day: "2026-10-19")])
    }

    @Test func markerRoundTrip() {
        #expect(PlanMarker.day(from: PlanMarker.url(for: "2026-10-19")) == "2026-10-19")
        #expect(PlanMarker.day(from: URL(string: "https://example.org/2026-10-19")) == nil)
        #expect(PlanMarker.day(from: URL(string: "timetrack://plan/not-a-day")) == nil)
        #expect(PlanMarker.day(from: nil) == nil)
    }
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
        let (store, _, _) = makeStore(access: .writeOnly, events: [event("a")], prefs: selectWork)
        #expect(!store.showsEvents)
        #expect(store.events(on: "2026-10-19", calendar: berlin).isEmpty)
    }

    @Test func staleSelectionIsPruned() {
        let (store, _, storage) = makeStore(access: .full, prefs: CalendarPreferences(selectedCalendarIDs: ["work", "deleted"]))
        #expect(store.preferences.selectedCalendarIDs == ["work"])
        #expect(storage.load().selectedCalendarIDs == ["work"])
    }

    @Test func eventCountsPerDay() {
        let (store, _, _) = makeStore(access: .full, events: [event("a"), event("b", from: (13, 0), to: (14, 0)), event("c", day: "2026-10-21")], prefs: selectWork)
        #expect(store.eventCounts(from: "2026-10-19", to: "2026-10-25", calendar: berlin) == ["2026-10-19": 2, "2026-10-21": 1])
    }

    @Test func syncDoesNothingWhileWritingIsOff() {
        let (store, provider, _) = makeStore(access: .full)
        let result = store.syncPlan(["2026-10-19": PlanDay(date: "2026-10-19", mode: .office)], from: "2026-10-01", to: "2026-10-31", calendar: berlin) { $0.rawValue }
        #expect(result == .skipped)
        #expect(provider.written.isEmpty)
    }

    @Test func enablingWriteWithoutAccessAsksAndCreatesCalendar() async {
        let (store, provider, _) = makeStore()
        await store.setWriteEnabled(true)
        #expect(provider.requestCount == 1)
        #expect(store.preferences.writeEnabled)
        #expect(store.preferences.timetrackCalendarID == "timetrack-calendar")
        #expect(!store.selectableCalendars.contains { $0.id == "timetrack-calendar" })
    }

    @Test func enablingWriteWithDeniedAccessStaysOff() async {
        let (store, provider, _) = makeStore(grant: .denied)
        await store.setWriteEnabled(true)
        #expect(!store.preferences.writeEnabled)
        #expect(provider.written.isEmpty)
    }

    @Test func syncWritesThenIsIdempotentThenRemoves() async {
        let (store, provider, _) = makeStore(access: .full)
        await store.setWriteEnabled(true)
        let plan = ["2026-10-19": PlanDay(date: "2026-10-19", mode: .office), "2026-10-20": PlanDay(date: "2026-10-20", mode: .home)]
        #expect(store.syncPlan(plan, from: "2026-10-01", to: "2026-10-31", calendar: berlin) { "Arbeit: \($0.rawValue)" } == .written(created: 2, updated: 0, deleted: 0))
        #expect(provider.written.count == 2)
        #expect(store.syncPlan(plan, from: "2026-10-01", to: "2026-10-31", calendar: berlin) { "Arbeit: \($0.rawValue)" } == .written(created: 0, updated: 0, deleted: 0))
        let reduced = ["2026-10-19": PlanDay(date: "2026-10-19", mode: .office)]
        #expect(store.syncPlan(reduced, from: "2026-10-01", to: "2026-10-31", calendar: berlin) { "Arbeit: \($0.rawValue)" } == .written(created: 0, updated: 0, deleted: 1))
        #expect(provider.written.count == 1)
    }

    @Test func failedWriteReportsAndKeepsReading() async {
        let (store, provider, _) = makeStore(access: .full)
        await store.setWriteEnabled(true)
        provider.failWrites = true
        let result = store.syncPlan(["2026-10-19": PlanDay(date: "2026-10-19", mode: .office)], from: "2026-10-01", to: "2026-10-31", calendar: berlin) { $0.rawValue }
        #expect(result == .failed)
        #expect(store.message != nil)
    }

    @Test func disablingWriteStopsSync() async {
        let (store, provider, _) = makeStore(access: .full)
        await store.setWriteEnabled(true)
        await store.setWriteEnabled(false)
        let result = store.syncPlan(["2026-10-19": PlanDay(date: "2026-10-19", mode: .office)], from: "2026-10-01", to: "2026-10-31", calendar: berlin) { $0.rawValue }
        #expect(result == .skipped)
        #expect(provider.written.isEmpty)
    }

    @Test func storeChangeNotificationBumpsCounter() {
        let (store, provider, _) = makeStore(access: .full)
        let before = store.changeCount
        provider.onStoreChanged?()
        #expect(store.changeCount == before + 1)
    }
}
