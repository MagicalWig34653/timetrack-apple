import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

private let berlin = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

private let idA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
private let idB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

private func absence(_ id: UUID, _ kind: AbsenceKind, _ status: AbsenceStatus, _ from: LocalDay, _ to: LocalDay, note: String? = nil) -> Absence {
    Absence(id: id, kind: kind, startDate: from, endDate: to, status: status, note: note, countedHalfDays: 2)
}

private func entry(_ id: UUID, _ title: String, _ from: LocalDay, _ to: LocalDay) -> CalendarEntry {
    CalendarEntry(key: EntryMarker.absenceKey(id), firstDay: from, lastDay: to, title: title)
}

@Suite("Calendar entries and markers")
struct CalendarEntryTests {
    @Test func absenceTitlesAreGenericAndStatusDependent() {
        #expect(AbsenceCalendarTitle.title(kind: .vacation, status: .planned) == "Urlaub (geplant)")
        #expect(AbsenceCalendarTitle.title(kind: .vacation, status: .approved) == "Urlaub (genehmigt)")
        #expect(AbsenceCalendarTitle.title(kind: .vacation, status: .taken) == "Urlaub")
        #expect(AbsenceCalendarTitle.title(kind: .sick, status: .planned) == "Krank")
        #expect(AbsenceCalendarTitle.title(kind: .sick, status: .taken) == "Krank")
    }

    @Test func otherKindsAndInactiveStatesAreNotWritten() {
        for status in [AbsenceStatus.requested, .rejected, .cancelled, .unknown] {
            #expect(AbsenceCalendarTitle.title(kind: .vacation, status: status) == nil)
            #expect(AbsenceCalendarTitle.title(kind: .sick, status: status) == nil)
        }
        for kind in [AbsenceKind.excused, .other, .unknown] {
            #expect(AbsenceCalendarTitle.title(kind: kind, status: .planned) == nil)
        }
    }

    @Test func desiredAbsencesCarryNoNotes() {
        let list = [absence(idA, .vacation, .planned, "2026-10-20", "2026-10-23", note: "Arzttermin privat"), absence(idB, .sick, .taken, "2026-10-26", "2026-10-26", note: "Grippe")]
        let desired = CalendarWritePlanner.desiredAbsences(list, from: "2026-10-01", to: "2026-10-31")
        #expect(desired == [entry(idA, "Urlaub (geplant)", "2026-10-20", "2026-10-23"), entry(idB, "Krank", "2026-10-26", "2026-10-26")])
        #expect(!desired.contains { $0.title.contains("Arzt") || $0.title.contains("Grippe") })
    }

    @Test func desiredAbsencesRespectRangeAndSkipOtherKinds() {
        let list = [absence(idA, .vacation, .approved, "2026-09-01", "2026-09-05"), absence(idB, .other, .planned, "2026-10-05", "2026-10-06"),
                    absence(UUID(), .vacation, .planned, "2026-10-28", "2026-11-04")]
        let desired = CalendarWritePlanner.desiredAbsences(list, from: "2026-10-01", to: "2026-10-31")
        #expect(desired.map(\.lastDay) == ["2026-11-04"], "a span that ends after the range is still written whole")
    }

    @Test func markerRoundTrip() {
        #expect(EntryMarker.key(from: EntryMarker.url(forKey: EntryMarker.planKey("2026-10-19"))) == "plan/2026-10-19")
        #expect(EntryMarker.key(from: EntryMarker.url(forKey: EntryMarker.absenceKey(idA))) == EntryMarker.absenceKey(idA))
        #expect(EntryMarker.key(from: URL(string: "https://example.org/2026-10-19")) == nil)
        #expect(EntryMarker.key(from: URL(string: "timetrack://plan/not-a-day")) == nil)
        #expect(EntryMarker.key(from: URL(string: "timetrack://absence/not-a-uuid")) == nil)
        #expect(EntryMarker.key(from: URL(string: "timetrack://other/2026-10-19")) == nil)
        #expect(EntryMarker.key(from: nil) == nil)
    }

    @Test func planDaysKeepE1Rules() {
        let days: [LocalDay: PlanDay] = ["2026-10-19": PlanDay(date: "2026-10-19", mode: .office, note: "privat: Arzt"), "2026-10-20": PlanDay(date: "2026-10-20", mode: .off)]
        let desired = CalendarWritePlanner.desiredPlanDays(from: days, from: "2026-10-19", to: "2026-10-31") { "Arbeit: \($0.rawValue)" }
        #expect(desired == [CalendarEntry(key: "plan/2026-10-19", firstDay: "2026-10-19", lastDay: "2026-10-19", title: "Arbeit: office")])
    }
}

@Suite("Calendar write planner")
struct CalendarWritePlannerTests {
    private func written(_ id: String, _ key: String, _ from: LocalDay, _ to: LocalDay, _ title: String) -> WrittenEvent {
        WrittenEvent(eventID: id, key: key, firstDay: from, lastDay: to, title: title)
    }

    @Test func createsUpdatesDeletes() {
        let keep = entry(idA, "Urlaub (geplant)", "2026-10-20", "2026-10-23")
        let changed = entry(idB, "Urlaub (genehmigt)", "2026-10-26", "2026-10-28")
        let fresh = entry(UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, "Krank", "2026-10-30", "2026-10-30")
        let existing = [written("e1", keep.key, "2026-10-20", "2026-10-23", "Urlaub (geplant)"), written("e2", changed.key, "2026-10-26", "2026-10-28", "Urlaub (geplant)"),
                        written("e3", EntryMarker.absenceKey(UUID()), "2026-10-05", "2026-10-06", "Krank")]
        let operations = CalendarWritePlanner.operations(desired: [keep, changed, fresh], existing: existing, from: "2026-10-01", to: "2026-10-31")
        #expect(operations.contains(.update(eventID: "e2", changed)))
        #expect(operations.contains(.create(fresh)))
        #expect(operations.contains(.delete(eventID: "e3")))
        #expect(operations.count == 3, "the unchanged absence needs no operation")
    }

    @Test func changedDatesUpdateTheSameEvent() {
        let moved = entry(idA, "Urlaub (geplant)", "2026-10-21", "2026-10-24")
        let existing = [written("e1", moved.key, "2026-10-20", "2026-10-23", "Urlaub (geplant)")]
        #expect(CalendarWritePlanner.operations(desired: [moved], existing: existing, from: "2026-10-01", to: "2026-10-31") == [.update(eventID: "e1", moved)])
    }

    @Test func voidedAbsenceIsRemoved() {
        let existing = [written("e1", EntryMarker.absenceKey(idA), "2026-10-20", "2026-10-23", "Urlaub (geplant)")]
        #expect(CalendarWritePlanner.operations(desired: [], existing: existing, from: "2026-10-01", to: "2026-10-31") == [.delete(eventID: "e1")])
    }

    @Test func idempotentWhenEqual() {
        let target = entry(idA, "Krank", "2026-10-20", "2026-10-21")
        let existing = [written("e1", target.key, "2026-10-20", "2026-10-21", "Krank")]
        #expect(CalendarWritePlanner.operations(desired: [target], existing: existing, from: "2026-10-01", to: "2026-10-31").isEmpty)
    }

    @Test func eventsOutsideTheRangeAreNeverTouched() {
        let existing = [written("old", EntryMarker.absenceKey(idA), "2026-09-14", "2026-09-18", "Urlaub")]
        #expect(CalendarWritePlanner.operations(desired: [], existing: existing, from: "2026-10-01", to: "2026-10-31").isEmpty)
    }

    @Test func duplicatesCollapse() {
        let target = entry(idA, "Krank", "2026-10-20", "2026-10-21")
        let existing = [written("x1", target.key, "2026-10-20", "2026-10-21", "Krank"), written("x2", target.key, "2026-10-20", "2026-10-21", "Krank")]
        #expect(CalendarWritePlanner.operations(desired: [target], existing: existing, from: "2026-10-01", to: "2026-10-31") == [.delete(eventID: "x2")])
    }

    @Test func managingRestrictsToKeyFamilies() {
        let existing = [written("p", "plan/2026-10-19", "2026-10-19", "2026-10-19", "Arbeit: office"), written("a", EntryMarker.absenceKey(idA), "2026-10-20", "2026-10-21", "Krank")]
        let onlyAbsences = CalendarWritePlanner.operations(desired: [], existing: existing, from: "2026-10-01", to: "2026-10-31", managing: [EntryMarker.absenceHost])
        #expect(onlyAbsences == [.delete(eventID: "a")])
    }

    @Test func removalDeletesEverythingGiven() {
        let existing = [written("b", "plan/2026-10-20", "2026-10-20", "2026-10-20", "x"), written("a", "plan/2026-10-19", "2026-10-19", "2026-10-19", "x")]
        #expect(CalendarWritePlanner.removalOperations(for: existing) == [.delete(eventID: "a"), .delete(eventID: "b")])
    }
}

@Suite("Calendar preferences")
struct CalendarPreferencesTests {
    @Test func modesPerCalendar() {
        var prefs = CalendarPreferences()
        #expect(prefs.mode(for: "a") == .off)
        prefs.setMode(.read, for: "a")
        prefs.setMode(.readWrite, for: "b")
        #expect(prefs.selectedCalendarIDs == ["a", "b"])
        #expect(prefs.writeCalendarIDs == ["b"])
        prefs.setMode(.off, for: "a")
        #expect(prefs.selectedCalendarIDs == ["b"])
    }

    @Test func roundTripKeepsModes() throws {
        var prefs = CalendarPreferences()
        prefs.setMode(.readWrite, for: "b")
        prefs.writePlanDays = true
        let data = try JSONEncoder().encode(prefs)
        #expect(!String(decoding: data, as: UTF8.self).contains("title"))
        #expect(try JSONDecoder().decode(CalendarPreferences.self, from: data) == prefs)
    }

    @Test func migratesE1Format() throws {
        let old = #"{"selectedCalendarIDs":["work"],"writeEnabled":true,"showAllDay":false,"timetrackCalendarID":"tt"}"#
        let prefs = try JSONDecoder().decode(CalendarPreferences.self, from: Data(old.utf8))
        #expect(prefs.mode(for: "work") == .read)
        #expect(prefs.mode(for: "tt") == .readWrite, "the previous write target keeps being written")
        #expect(prefs.writePlanDays, "plan days were what E1 wrote")
        #expect(!prefs.showAllDay)
    }

    @Test func migratedReadOnlyStaysReadOnly() throws {
        let old = #"{"selectedCalendarIDs":["work"],"writeEnabled":false,"showAllDay":true}"#
        let prefs = try JSONDecoder().decode(CalendarPreferences.self, from: Data(old.utf8))
        #expect(prefs.writeCalendarIDs.isEmpty)
        #expect(!prefs.writeEnabled)
    }

    @Test func nothingIsOnByDefault() {
        let prefs = CalendarPreferences()
        #expect(prefs.selectedCalendarIDs.isEmpty && prefs.writeCalendarIDs.isEmpty && !prefs.writeEnabled)
    }
}

@MainActor
@Suite("Calendar store: per-calendar modes and writing")
struct CalendarWriteStoreTests {
    private func makeStore(access: CalendarAccess = .full, prefs: CalendarPreferences = CalendarPreferences(), userEvents: [DeviceEvent] = [])
        -> (DeviceCalendarStore, InMemoryDeviceCalendarProvider, MemoryCalendarPreferencesStorage) {
        let calendars = [DeviceCalendarInfo(id: "work", title: "Arbeit", accountTitle: "iCloud"), DeviceCalendarInfo(id: "private", title: "Privat", accountTitle: "iCloud"),
                         DeviceCalendarInfo(id: "holidays", title: "Feiertage", accountTitle: "Abos", allowsWrite: false)]
        let provider = InMemoryDeviceCalendarProvider(access: access, calendars: calendars, events: userEvents)
        let storage = MemoryCalendarPreferencesStorage(prefs)
        return (DeviceCalendarStore(provider: provider, storage: storage), provider, storage)
    }

    private let vacation = absence(idA, .vacation, .planned, "2026-10-20", "2026-10-23", note: "geheim")
    private let sick = absence(idB, .sick, .planned, "2026-10-26", "2026-10-27")

    private func sync(_ store: DeviceCalendarStore, _ absences: [Absence], plan: [LocalDay: PlanDay] = [:]) -> CalendarWriteResult {
        store.sync(planDays: plan, absences: absences, from: "2026-10-01", to: "2026-10-31", calendar: berlin) { "Arbeit: \($0.rawValue)" }
    }

    @Test func nothingIsWrittenWithoutAReadWriteCalendar() async {
        let (store, provider, _) = makeStore()
        await store.setMode(.read, for: "work")
        #expect(sync(store, [vacation, sick]) == .skipped)
        #expect(provider.written.isEmpty)
    }

    @Test func writesOnlyIntoReadWriteCalendars() async {
        let (store, provider, _) = makeStore()
        await store.setMode(.readWrite, for: "work")
        await store.setMode(.read, for: "private")
        #expect(sync(store, [vacation, sick]) == .written(created: 2, updated: 0, deleted: 0))
        #expect(provider.written.values.allSatisfy { $0.calendarID == "work" })
        #expect(Set(provider.written.values.map(\.entry.title)) == ["Urlaub (geplant)", "Krank"])
    }

    @Test func severalWriteCalendarsAllGetTheEntries() async {
        let (store, provider, _) = makeStore()
        await store.setMode(.readWrite, for: "work")
        await store.setMode(.readWrite, for: "private")
        #expect(sync(store, [vacation]) == .written(created: 2, updated: 0, deleted: 0))
        #expect(Set(provider.written.values.map(\.calendarID)) == ["work", "private"])
    }

    @Test func readWriteIsRefusedForCalendarsThatCannotBeChanged() async {
        let (store, _, _) = makeStore()
        await store.setMode(.readWrite, for: "holidays")
        #expect(store.mode(for: "holidays") == .off)
        #expect(store.message != nil)
        await store.setMode(.read, for: "holidays")
        #expect(store.mode(for: "holidays") == .read)
    }

    @Test func choosingReadWriteAsksForAccessWhenMissing() async {
        let (store, provider, _) = makeStore(access: .notDetermined)
        await store.setMode(.readWrite, for: "work")
        #expect(provider.requestCount == 1)
        #expect(store.mode(for: "work") == .readWrite)
    }

    @Test func deniedAccessKeepsCalendarOff() async {
        let provider = InMemoryDeviceCalendarProvider(access: .notDetermined, grantResult: .denied, calendars: [DeviceCalendarInfo(id: "work", title: "Arbeit", accountTitle: "iCloud")])
        let store = DeviceCalendarStore(provider: provider, storage: MemoryCalendarPreferencesStorage())
        await store.setMode(.readWrite, for: "work")
        #expect(store.mode(for: "work") == .off)
    }

    @Test func updateAndVoidFollowTheBackend() async {
        let (store, provider, _) = makeStore()
        await store.setMode(.readWrite, for: "work")
        _ = sync(store, [vacation, sick])
        let approved = absence(idA, .vacation, .approved, "2026-10-20", "2026-10-24")
        #expect(sync(store, [approved, sick]) == .written(created: 0, updated: 1, deleted: 0))
        #expect(provider.written.values.contains { $0.entry.title == "Urlaub (genehmigt)" && $0.entry.lastDay == "2026-10-24" })
        #expect(sync(store, [sick]) == .written(created: 0, updated: 0, deleted: 1), "voided/cancelled absences disappear from the list")
        #expect(provider.written.count == 1)
        #expect(sync(store, [sick]) == .written(created: 0, updated: 0, deleted: 0))
    }

    @Test func statusThatIsNotWrittenRemovesTheEvent() async {
        let (store, provider, _) = makeStore()
        await store.setMode(.readWrite, for: "work")
        _ = sync(store, [vacation])
        let rejected = absence(idA, .vacation, .rejected, "2026-10-20", "2026-10-23")
        #expect(sync(store, [rejected]) == .written(created: 0, updated: 0, deleted: 1))
        #expect(provider.written.isEmpty)
    }

    @Test func absenceAndPlanTogglesAreIndependent() async {
        let (store, provider, _) = makeStore()
        await store.setMode(.readWrite, for: "work")
        let plan: [LocalDay: PlanDay] = ["2026-10-19": PlanDay(date: "2026-10-19", mode: .office)]
        #expect(sync(store, [vacation], plan: plan) == .written(created: 1, updated: 0, deleted: 0), "plan days are off by default")
        store.setWritePlanDays(true)
        #expect(sync(store, [vacation], plan: plan) == .written(created: 1, updated: 0, deleted: 0))
        store.setWriteAbsences(false)
        #expect(sync(store, [vacation], plan: plan) == .written(created: 0, updated: 0, deleted: 1))
        #expect(provider.written.values.map(\.entry.key) == ["plan/2026-10-19"])
    }

    @Test func leavingReadWriteRemovesOnlyTimetrackEvents() async {
        let own = DeviceEvent(id: "u1", calendarID: "work", title: "Mein Urlaub", start: berlin.instant(day: "2026-10-20", hour: 0, minute: 0)!, end: berlin.instant(day: "2026-10-20", hour: 23, minute: 59)!, isAllDay: true)
        let (store, provider, _) = makeStore(userEvents: [own])
        await store.setMode(.readWrite, for: "work")
        _ = sync(store, [vacation])
        #expect(provider.written.count == 1)
        await store.setMode(.read, for: "work")
        #expect(provider.written.isEmpty)
        #expect(provider.storedEvents == [own], "the user's own events are untouched")
    }

    @Test func removeAllWrittenCleansEveryWritableCalendar() async {
        let (store, provider, _) = makeStore()
        await store.setMode(.readWrite, for: "work")
        await store.setMode(.readWrite, for: "private")
        _ = sync(store, [vacation, sick])
        #expect(provider.written.count == 4)
        #expect(store.removeAllWritten(calendar: berlin, now: berlin.instant(day: "2026-10-19", hour: 12, minute: 0)!) == 4)
        #expect(provider.written.isEmpty)
        #expect(store.lastRemoval == 4)
        #expect(store.removeAllWritten(calendar: berlin, now: berlin.instant(day: "2026-10-19", hour: 12, minute: 0)!) == 0)
    }

    @Test func writtenEventsDoNotEchoAsContext() async {
        let (store, _, _) = makeStore()
        await store.setMode(.readWrite, for: "work")
        _ = sync(store, [vacation])
        #expect(store.events(on: "2026-10-21", calendar: berlin).isEmpty, "Timetrack's own events are not shown again")
    }

    @Test func titleOfOtherCalendarsNeverEntersWrittenEntries() async {
        let secret = DeviceEvent(id: "s", calendarID: "private", title: "Geheimer Arzttermin", start: berlin.instant(day: "2026-10-21", hour: 9, minute: 0)!, end: berlin.instant(day: "2026-10-21", hour: 10, minute: 0)!)
        let (store, provider, _) = makeStore(userEvents: [secret])
        await store.setMode(.read, for: "private")
        await store.setMode(.readWrite, for: "work")
        _ = sync(store, [vacation, sick])
        #expect(provider.written.values.allSatisfy { !$0.entry.title.contains("Arzt") && !$0.entry.title.contains("geheim") })
    }

    @Test func failedWriteReports() async {
        let (store, provider, _) = makeStore()
        await store.setMode(.readWrite, for: "work")
        provider.failWrites = true
        #expect(sync(store, [vacation]) == .failed)
        #expect(store.message != nil)
    }

    @Test func createTimetrackCalendarMakesItReadWrite() async {
        let (store, provider, storage) = makeStore()
        await store.createTimetrackCalendar()
        #expect(store.preferences.timetrackCalendarID == "timetrack-calendar")
        #expect(store.mode(for: "timetrack-calendar") == .readWrite)
        #expect(store.hasTimetrackCalendar)
        _ = sync(store, [vacation])
        #expect(provider.written.values.allSatisfy { $0.calendarID == "timetrack-calendar" })
        #expect(storage.load().mode(for: "timetrack-calendar") == .readWrite)
    }

    @Test func modesArePersisted() async {
        let (store, _, storage) = makeStore()
        await store.setMode(.readWrite, for: "work")
        await store.setMode(.read, for: "private")
        #expect(storage.load().writeCalendarIDs == ["work"])
        #expect(storage.load().selectedCalendarIDs == ["work", "private"])
    }
}

/// AUD3 finding 4: written events must be read in the zone they were written in (work model), not the device zone.
@Suite struct WrittenEventZoneTests {
    private let berlin = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    private let tokyo = DayCalendar(timeZone: TimeZone(identifier: "Asia/Tokyo")!)

    @Test func timedBlockReadsBackIdenticallyInTheWritingZone() {
        let start = berlin.instant(day: "2026-10-19", hour: 8, minute: 30)!, end = berlin.instant(day: "2026-10-19", hour: 12, minute: 0)!
        let key = "plan/2026-10-19/0"
        let right = WrittenEvent.reading(eventID: "e", key: key, title: "", isAllDay: false, start: start, end: end, calendar: berlin)
        #expect(right.startMinute == 8 * 60 + 30 && right.endMinute == 12 * 60 && right.firstDay == "2026-10-19")
        // the device zone would see a shifted day and minutes: exactly the churn the zone parameter prevents
        let wrong = WrittenEvent.reading(eventID: "e", key: key, title: "", isAllDay: false, start: start, end: end, calendar: tokyo)
        #expect(wrong.startMinute != right.startMinute)
    }

    @Test func allDayAbsenceKeepsItsDaysInTheWritingZone() {
        let start = berlin.instant(day: "2026-10-19", hour: 0, minute: 0)!, end = berlin.instant(day: "2026-10-21", hour: 0, minute: 0)!
        let event = WrittenEvent.reading(eventID: "e", key: "absence/x", title: "", isAllDay: true, start: start, end: end, calendar: berlin)
        #expect(event.firstDay == "2026-10-19" && event.lastDay == "2026-10-20")
    }
}
