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

    @Test func eventsWrittenByTimetrackAreNeverContext() {
        let prefs = CalendarPreferences(selectedCalendarIDs: ["work", "tt"])
        let own = DeviceEvent(id: "own", calendarID: "tt", title: "Urlaub (geplant)", start: at("2026-10-19", 0), end: at("2026-10-19", 23, 59), isAllDay: true, isWrittenByTimetrack: true)
        #expect(DeviceEventFilter.events(on: "2026-10-19", in: [event("a"), own], preferences: prefs, calendar: berlin).map(\.id) == ["a"])
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
}
