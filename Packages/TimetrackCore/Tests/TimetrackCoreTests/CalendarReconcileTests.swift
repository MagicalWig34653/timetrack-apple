import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// N2: events Timetrack wrote follow the server (changed, moved, cancelled, deleted), tested against an in-memory event store.

private let berlin = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
private let now = berlin.instant(day: "2026-10-26", hour: 12, minute: 0)!
private let idA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
private let idB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

private func absence(_ id: UUID, _ kind: AbsenceKind = .vacation, _ status: AbsenceStatus = .planned, _ from: LocalDay, _ to: LocalDay) -> Absence {
    Absence(id: id, kind: kind, startDate: from, endDate: to, status: status, countedHalfDays: 2)
}

/// The server as the store sees it; tests change `absences` between syncs.
private final class FakeSource: CalendarSyncSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _absences: [Absence] = []
    private var _plan: [PlanDay] = []
    private var _fail = false
    var absences: [Absence] { get { lock.withLock { _absences } } set { lock.withLock { _absences = newValue } } }
    var plan: [PlanDay] { get { lock.withLock { _plan } } set { lock.withLock { _plan = newValue } } }
    var fail: Bool { get { lock.withLock { _fail } } set { lock.withLock { _fail = newValue } } }
    func calendarAbsences(from: LocalDay, to: LocalDay) async throws -> [Absence] {
        if fail { throw CocoaError(.fileReadUnknown) }
        return absences.filter { $0.endDate >= from && $0.startDate <= to }
    }
    func calendarPlanDays(from: LocalDay, to: LocalDay) async throws -> [PlanDay] {
        if fail { throw CocoaError(.fileReadUnknown) }
        return plan.filter { $0.date >= from && $0.date <= to }
    }
}

@MainActor
@Suite("N2 calendar reconciliation")
struct CalendarReconcileTests {
    private let calendars = [DeviceCalendarInfo(id: "work", title: "Arbeit", accountTitle: "iCloud"), DeviceCalendarInfo(id: "family", title: "Familie", accountTitle: "iCloud")]

    private func makeStore(userEvents: [DeviceEvent] = [], ledger: CalendarLedgerStorage = MemoryCalendarLedgerStorage(), provider: InMemoryDeviceCalendarProvider? = nil)
        async -> (DeviceCalendarStore, InMemoryDeviceCalendarProvider, MemoryCalendarLedgerStorage) {
        let provider = provider ?? InMemoryDeviceCalendarProvider(access: .full, calendars: calendars, events: userEvents)
        let ledgerStorage = (ledger as? MemoryCalendarLedgerStorage) ?? MemoryCalendarLedgerStorage()
        let store = DeviceCalendarStore(provider: provider, storage: MemoryCalendarPreferencesStorage(), ledgerStorage: ledgerStorage)
        await store.setMode(.readWrite, for: "work")
        return (store, provider, ledgerStorage)
    }

    @discardableResult
    private func run(_ store: DeviceCalendarStore, _ source: FakeSource) async -> CalendarWriteResult {
        await store.syncAll(source: source, calendar: berlin, now: now) { "Arbeit: \($0.rawValue)" }
    }

    private func summary(_ provider: InMemoryDeviceCalendarProvider) -> [String] {
        provider.written.values.map { "\($0.entry.title) \($0.entry.firstDay)…\($0.entry.lastDay)" }.sorted()
    }

    @Test func createsThenChangedDatesStatusAndCancellationFollow() async {
        let source = FakeSource()
        let (store, provider, _) = await makeStore()
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-06")]
        #expect(await run(store, source) == .written(created: 1, updated: 0, deleted: 0))
        let firstID = provider.written.keys.first
        // Shortened, then approved, then moved: always the same event is updated.
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-04")]
        #expect(await run(store, source) == .written(created: 0, updated: 1, deleted: 0))
        source.absences = [absence(idA, .vacation, .approved, "2026-11-09", "2026-11-11")]
        await run(store, source)
        #expect(summary(provider) == ["Urlaub (genehmigt) 2026-11-09…2026-11-11"])
        #expect(provider.written.keys.first == firstID)
        // Cancelled: removed.
        source.absences = [absence(idA, .vacation, .cancelled, "2026-11-09", "2026-11-11")]
        #expect(await run(store, source) == .written(created: 0, updated: 0, deleted: 1))
        #expect(provider.written.isEmpty)
    }

    @Test func deletedOnServerRemovesTheEvent() async {
        let source = FakeSource()
        let (store, provider, _) = await makeStore()
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-06"), absence(idB, .sick, .planned, "2026-11-12", "2026-11-12")]
        await run(store, source)
        #expect(provider.written.count == 2)
        source.absences = [absence(idB, .sick, .planned, "2026-11-12", "2026-11-12")]
        await run(store, source)
        #expect(summary(provider) == ["Krank 2026-11-12…2026-11-12"])
    }

    @Test func farAwayAbsencesAreReconciledWithoutOpeningTheirMonth() async {
        let source = FakeSource()
        let (store, provider, _) = await makeStore()
        source.absences = [absence(idA, .vacation, .planned, "2027-07-05", "2027-07-16")]
        await run(store, source)
        source.absences = [absence(idA, .vacation, .planned, "2027-07-12", "2027-07-16")] // shortened eight months ahead
        await run(store, source)
        #expect(summary(provider) == ["Urlaub (geplant) 2027-07-12…2027-07-16"])
        // A past absence from three months ago that was deleted is removed as well.
        source.absences = [absence(idB, .vacation, .taken, "2026-07-20", "2026-07-24")]
        await run(store, source)
        source.absences = []
        await run(store, source)
        #expect(provider.written.isEmpty)
    }

    @Test func movedAcrossTheWindowKeepsTheEvent() async {
        let source = FakeSource()
        let (store, provider, _) = await makeStore()
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-06")]
        await run(store, source)
        source.absences = [absence(idA, .vacation, .planned, "2027-03-01", "2027-03-05")]
        await run(store, source)
        #expect(summary(provider) == ["Urlaub (geplant) 2027-03-01…2027-03-05"])
    }

    @Test func ledgerStoresTheEventIdentifierPerItem() async {
        let source = FakeSource()
        let (store, provider, ledger) = await makeStore()
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-06")]
        await run(store, source)
        let record = ledger.load().records(for: "work")[EntryMarker.absenceKey(idA)]
        #expect(record?.eventID == provider.written.keys.first)
        #expect(record?.firstDay == "2026-11-02")
        source.absences = []
        await run(store, source)
        #expect(ledger.load().records(for: "work").isEmpty)
    }

    @Test func manuallyDeletedEventStaysGoneUntilTheItemChanges() async {
        let source = FakeSource()
        let (store, provider, _) = await makeStore()
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-06")]
        await run(store, source)
        provider.userDeleteEvent(provider.written.keys.first!)
        #expect(await run(store, source) == .written(created: 0, updated: 0, deleted: 0)) // respected, not recreated
        #expect(provider.written.isEmpty)
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-05")] // changed on the server: written again
        #expect(await run(store, source) == .written(created: 1, updated: 0, deleted: 0))
        #expect(summary(provider) == ["Urlaub (geplant) 2026-11-02…2026-11-05"])
    }

    @Test func changedEventIdentifierIsFollowedWithoutDuplicates() async {
        let source = FakeSource()
        let (store, provider, ledger) = await makeStore()
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-06")]
        await run(store, source)
        provider.changeIdentifier(of: provider.written.keys.first!)
        source.absences = [absence(idA, .vacation, .approved, "2026-11-02", "2026-11-06")]
        #expect(await run(store, source) == .written(created: 0, updated: 1, deleted: 0))
        #expect(provider.written.count == 1)
        #expect(ledger.load().records(for: "work")[EntryMarker.absenceKey(idA)]?.eventID == provider.written.keys.first)
        // Unchanged content but a new identifier: the ledger is repaired, nothing is written.
        provider.changeIdentifier(of: provider.written.keys.first!)
        #expect(await run(store, source) == .written(created: 0, updated: 0, deleted: 0))
        #expect(ledger.load().records(for: "work")[EntryMarker.absenceKey(idA)]?.eventID == provider.written.keys.first)
    }

    @Test func lostLedgerIsRebuiltFromTheMarkersWithoutDuplicates() async {
        let source = FakeSource()
        let (store, provider, _) = await makeStore()
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-06"), absence(idB, .sick, .planned, "2026-11-12", "2026-11-12")]
        await run(store, source)
        // Reinstall: same calendar, empty ledger, and the vacation changed meanwhile; the sick day was cancelled.
        let (fresh, _, _) = await makeStore(provider: provider)
        source.absences = [absence(idA, .vacation, .planned, "2026-11-03", "2026-11-06"), absence(idB, .sick, .cancelled, "2026-11-12", "2026-11-12")]
        #expect(await run(fresh, source) == .written(created: 0, updated: 1, deleted: 1))
        #expect(summary(provider) == ["Urlaub (geplant) 2026-11-03…2026-11-06"])
    }

    @Test func foreignEventsAreNeverTouched() async {
        let source = FakeSource()
        let foreign = DeviceEvent(id: "x", calendarID: "work", title: "Urlaub (geplant)", start: berlin.instant(day: "2026-11-02", hour: 9, minute: 0)!, end: berlin.instant(day: "2026-11-02", hour: 10, minute: 0)!)
        let (store, provider, _) = await makeStore(userEvents: [foreign])
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-06")]
        await run(store, source)
        source.absences = []
        await run(store, source)
        #expect(provider.storedEvents.map(\.id) == ["x"]) // untouched
        #expect(provider.written.isEmpty)
    }

    @Test func calendarsNotSetToWriteAreNotTouched() async {
        let source = FakeSource()
        let (store, provider, _) = await makeStore()
        await store.setMode(.read, for: "family")
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-06")]
        await run(store, source)
        #expect(provider.written.values.allSatisfy { $0.calendarID == "work" })
    }

    @Test func serverErrorChangesNothing() async {
        let source = FakeSource()
        let (store, provider, _) = await makeStore()
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-06")]
        await run(store, source)
        source.fail = true
        #expect(await run(store, source) == .skipped)
        #expect(provider.written.count == 1)
    }

    @Test func removedPlanDaysAreDeletedAndPlanWindowIsNarrower() async {
        let source = FakeSource()
        let (store, provider, _) = await makeStore()
        store.setWritePlanDays(true)
        source.plan = [PlanDay(date: "2026-10-27", mode: .office), PlanDay(date: "2026-11-03", mode: .home), PlanDay(date: "2027-06-01", mode: .home)]
        await run(store, source)
        #expect(provider.written.count == 2) // the day far ahead is outside the plan window
        source.plan = [PlanDay(date: "2026-11-03", mode: .home)]
        await run(store, source)
        #expect(provider.written.count == 1)
        store.setWritePlanDays(false)
        await run(store, source)
        #expect(provider.written.isEmpty)
    }

    @Test func stoppingToWriteForgetsTheLedger() async {
        let source = FakeSource()
        let (store, provider, ledger) = await makeStore()
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-06")]
        await run(store, source)
        await store.setMode(.read, for: "work", calendar: berlin)
        #expect(provider.written.isEmpty)
        #expect(ledger.load().records(for: "work").isEmpty)
        await store.setMode(.readWrite, for: "work")
        await run(store, source)
        #expect(provider.written.count == 1) // not mistaken for a manual deletion
    }

    @Test func removeAllClearsLedger() async {
        let source = FakeSource()
        let (store, provider, ledger) = await makeStore()
        source.absences = [absence(idA, .vacation, .planned, "2026-11-02", "2026-11-06")]
        await run(store, source)
        #expect(store.removeAllWritten(calendar: berlin, now: now) == 1)
        #expect(provider.written.isEmpty)
        #expect(ledger.load().calendars.isEmpty)
        #expect(await run(store, source) == .written(created: 1, updated: 0, deleted: 0))
    }
}

@Suite("N2 reconciler and markers")
struct CalendarReconcilerTests {
    private func written(_ id: String, _ key: String, _ first: LocalDay, _ last: LocalDay, _ title: String = "Urlaub (geplant)") -> WrittenEvent {
        WrittenEvent(eventID: id, key: key, firstDay: first, lastDay: last, title: title)
    }

    @Test func duplicateKeepsTheLedgerEvent() {
        let key = EntryMarker.absenceKey(idA)
        let entry = CalendarEntry(key: key, firstDay: "2026-11-02", lastDay: "2026-11-06", title: "Urlaub (geplant)")
        let plan = CalendarReconciler.plan(desired: [entry], existing: [written("a", key, "2026-11-02", "2026-11-06"), written("b", key, "2026-11-02", "2026-11-06")],
                                           records: [key: CalendarLedgerRecord(eventID: "b", entry: entry)], from: "2026-10-01", to: "2026-12-31")
        #expect(plan.operations == [.delete(eventID: "a")])
        #expect(plan.adopt.isEmpty)
    }

    @Test func familyOutsideManagingIsLeftAlone() {
        let planKey = EntryMarker.planKey("2026-11-03")
        let plan = CalendarReconciler.plan(desired: [], existing: [written("p", planKey, "2026-11-03", "2026-11-03", "Arbeit: Büro")], records: [:],
                                           from: "2026-10-01", to: "2026-12-31", managing: [EntryMarker.absenceHost])
        #expect(plan.operations.isEmpty)
    }

    @Test func eventsOutsideTheWindowAreLeftAlone() {
        let key = EntryMarker.absenceKey(idA)
        let plan = CalendarReconciler.plan(desired: [], existing: [written("old", key, "2020-01-01", "2020-01-05")], records: [:], from: "2026-10-01", to: "2026-12-31")
        #expect(plan.operations.isEmpty)
    }

    @Test func markerIsReadFromUrlOrNotes() {
        let key = EntryMarker.absenceKey(idA)
        #expect(EntryMarker.key(from: EntryMarker.url(forKey: key), notes: nil) == key)
        #expect(EntryMarker.key(from: nil, notes: EntryMarker.notes(forKey: key)) == key) // server dropped the URL field
        #expect(EntryMarker.key(from: nil, notes: "timetrack://absence/not-a-uuid") == nil)
        #expect(EntryMarker.key(from: nil, notes: "Treffen, siehe https://example.org/plan/2026-11-03") == nil)
        #expect(EntryMarker.key(from: URL(string: "https://example.org"), notes: nil) == nil)
        #expect(!EntryMarker.notes(forKey: key).contains("geheim"))
    }

    @Test func ledgerRoundTripsThroughJSON() throws {
        var ledger = CalendarLedger()
        ledger.set(["absence/x": CalendarLedgerRecord(eventID: "1", title: "Krank", firstDay: "2026-11-02", lastDay: "2026-11-02")], for: "work")
        let decoded = try JSONDecoder().decode(CalendarLedger.self, from: JSONEncoder().encode(ledger))
        #expect(decoded == ledger)
        let suite = "n2.test.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let storage = UserDefaultsCalendarLedgerStorage(defaults: UserDefaults(suiteName: suite)!)
        storage.save(ledger)
        #expect(storage.load() == ledger)
    }
}
