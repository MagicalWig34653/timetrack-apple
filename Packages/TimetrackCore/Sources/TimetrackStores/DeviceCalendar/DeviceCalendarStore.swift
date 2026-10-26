import Foundation
import Observation
import TimetrackCore

/// Platform access to the device calendars. EventKit implements it in the app; `InMemoryDeviceCalendarProvider` serves tests and
/// UI tests. Nothing behind this protocol talks to the backend.
@MainActor
public protocol DeviceCalendarProvider: AnyObject {
    var access: CalendarAccess { get }
    /// Asks the system for full access (the only level that can read events). Returns the resulting level.
    func requestFullAccess() async throws -> CalendarAccess
    func calendars() -> [DeviceCalendarInfo]
    func events(from: Date, to: Date, calendarIDs: Set<String>) -> [DeviceEvent]
    /// Finds or creates the dedicated "Timetrack" calendar and returns its identifier.
    func ensureTimetrackCalendar(existingID: String?) throws -> String
    /// Events in one calendar that carry Timetrack's marker URL (and only those).
    func writtenEvents(calendarID: String, from: Date, to: Date) -> [WrittenEvent]
    /// Applies the operations in one commit and returns the event identifier of every created or updated entry (by entry key),
    /// read after the commit because EventKit may assign or change identifiers on save.
    @discardableResult
    func apply(_ operations: [WriteOperation], calendarID: String, calendar: DayCalendar) throws -> [String: String]
    /// Called when the system reports changes to the calendar database.
    var onStoreChanged: (@MainActor () -> Void)? { get set }
}

/// Where `CalendarPreferences` live (per device, never synced to the backend).
public protocol CalendarPreferencesStorage: Sendable {
    func load() -> CalendarPreferences
    func save(_ preferences: CalendarPreferences)
}

/// Where the `CalendarLedger` lives (per device).
public protocol CalendarLedgerStorage: Sendable {
    func load() -> CalendarLedger
    func save(_ ledger: CalendarLedger)
}

public struct UserDefaultsCalendarLedgerStorage: CalendarLedgerStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "timetrack.calendar.ledger") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> CalendarLedger {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(CalendarLedger.self, from: $0) } ?? CalendarLedger()
    }

    public func save(_ ledger: CalendarLedger) {
        if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: key) }
    }
}

public final class MemoryCalendarLedgerStorage: CalendarLedgerStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value = CalendarLedger()
    public init() {}
    public func load() -> CalendarLedger { lock.withLock { value } }
    public func save(_ ledger: CalendarLedger) { lock.withLock { value = ledger } }
}

/// What a full reconciliation reads from the server. `APIClient` conforms (see below); tests use a fake.
public protocol CalendarSyncSource: Sendable {
    func calendarAbsences(from: LocalDay, to: LocalDay) async throws -> [Absence]
    func calendarPlanDays(from: LocalDay, to: LocalDay) async throws -> [PlanDay]
}

extension APIClient: CalendarSyncSource {
    public func calendarAbsences(from: LocalDay, to: LocalDay) async throws -> [Absence] { try await listAbsences(from: from, to: to) }
    public func calendarPlanDays(from: LocalDay, to: LocalDay) async throws -> [PlanDay] { try await listPlanDays(from: from, to: to) }
}

public struct UserDefaultsCalendarPreferencesStorage: CalendarPreferencesStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "timetrack.calendar.preferences") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> CalendarPreferences {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(CalendarPreferences.self, from: data) else { return CalendarPreferences() }
        return value
    }

    public func save(_ preferences: CalendarPreferences) {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: key) }
    }
}

public struct MemoryCalendarPreferencesStorage: CalendarPreferencesStorage, @unchecked Sendable {
    private final class Box: @unchecked Sendable { var value = CalendarPreferences() }
    private let box = Box()
    public init(_ initial: CalendarPreferences = CalendarPreferences()) { box.value = initial }
    public func load() -> CalendarPreferences { box.value }
    public func save(_ preferences: CalendarPreferences) { box.value = preferences }
}

public enum CalendarWriteResult: Sendable, Equatable {
    case written(created: Int, updated: Int, deleted: Int)
    case skipped
    case failed
}

/// State of the "Kalender" settings page and the read-only event context in the day view.
///
/// Per calendar the user chooses off / read / read+write. Events are only read from calendars set to read or read+write; the store
/// writes only into calendars set to read+write, and only events carrying Timetrack's marker are ever changed or removed.
/// Event data never leaves the device.
@MainActor
@Observable
public final class DeviceCalendarStore {
    public private(set) var access: CalendarAccess
    public private(set) var calendars: [DeviceCalendarInfo] = []
    public private(set) var preferences: CalendarPreferences
    public private(set) var isRequesting = false
    /// Increments whenever the system calendar database changed; views reload their events on it.
    public private(set) var changeCount = 0
    public private(set) var lastWrite: CalendarWriteResult?
    /// Number of events removed by the last "Von Timetrack geschriebene Termine entfernen".
    public private(set) var lastRemoval: Int?
    /// Short German message for the settings page (permission denied, write failed).
    public private(set) var message: String?

    private let provider: DeviceCalendarProvider
    private let storage: CalendarPreferencesStorage
    private let ledgerStorage: CalendarLedgerStorage
    private var ledger: CalendarLedger
    private var isSyncing = false
    private var syncRequested = false

    /// N2: windows of a full reconciliation. Absences reach a year back and two years ahead (so a vacation that moved or was
    /// cancelled is corrected no matter which month is open); plan days (optional, many) a month back and about four months ahead.
    public static let absenceWindowDaysBack = 366
    public static let absenceWindowDaysAhead = 731
    public static let planWindowDaysBack = 31
    public static let planWindowDaysAhead = 120

    /// `ledgerStorage` defaults to an in-memory ledger; the app passes `UserDefaultsCalendarLedgerStorage`.
    public init(provider: DeviceCalendarProvider, storage: CalendarPreferencesStorage = UserDefaultsCalendarPreferencesStorage(),
                ledgerStorage: CalendarLedgerStorage = MemoryCalendarLedgerStorage()) {
        self.provider = provider
        self.storage = storage
        self.ledgerStorage = ledgerStorage
        self.ledger = ledgerStorage.load()
        self.access = provider.access
        self.preferences = storage.load()
        provider.onStoreChanged = { [weak self] in self?.storeChanged() }
        refresh()
    }

    /// Calendars the user can pick (including Timetrack's own calendar, if it exists).
    public var selectableCalendars: [DeviceCalendarInfo] { calendars }
    public var writeCalendars: [DeviceCalendarInfo] { calendars.filter { preferences.mode(for: $0.id).writes } }
    /// Whether a calendar titled like the dedicated one already exists (then the "create" button is hidden).
    public var hasTimetrackCalendar: Bool { calendars.contains { $0.id == preferences.timetrackCalendarID } }
    public var hasSelection: Bool { !preferences.selectedCalendarIDs.isEmpty }
    public var showsEvents: Bool { access.canRead && hasSelection }

    public func isSelected(_ id: String) -> Bool { preferences.selectedCalendarIDs.contains(id) }

    /// Re-reads the permission state and the calendar list; forgets selected calendars that no longer exist.
    public func refresh() {
        access = provider.access
        guard access.canRead else {
            calendars = []
            return
        }
        calendars = provider.calendars()
        var pruned = preferences
        pruned.retain(Set(calendars.map(\.id)))
        if pruned != preferences {
            preferences = pruned
            storage.save(preferences)
        }
    }

    public func requestAccess() async {
        isRequesting = true
        defer { isRequesting = false }
        message = nil
        do {
            access = try await provider.requestFullAccess()
        } catch {
            access = provider.access
            message = "Der Zugriff konnte nicht angefragt werden."
        }
        if access == .denied || access == .restricted { message = "Der Zugriff ist in den iOS-Einstellungen ausgeschaltet." }
        refresh()
    }

    public func mode(for id: String) -> CalendarMode { preferences.mode(for: id) }

    /// Convenience for read-only selection: on = read (an existing read+write stays), off = off.
    public func setSelected(_ id: String, _ selected: Bool) {
        if selected {
            if preferences.mode(for: id) == .off { preferences.setMode(.read, for: id) }
        } else {
            preferences.setMode(.off, for: id)
        }
        storage.save(preferences)
        changeCount += 1
    }

    /// Sets what Timetrack does with one calendar. Read+write needs full access and a calendar that accepts changes; leaving
    /// read+write removes the events Timetrack wrote into that calendar (marker events only).
    public func setMode(_ mode: CalendarMode, for id: String, calendar dayCalendar: DayCalendar? = nil) async {
        message = nil
        let previous = preferences.mode(for: id)
        guard previous != mode else { return }
        if mode != .off, !access.canRead { await requestAccess() }
        guard mode == .off || access.canRead else { return }
        if mode.writes {
            guard calendars.first(where: { $0.id == id })?.allowsWrite == true else {
                message = "Dieser Kalender erlaubt keine Änderungen."
                return
            }
        }
        if previous.writes, !mode.writes {
            removeWritten(inCalendar: id, dayCalendar: dayCalendar ?? DayCalendar(timeZone: .current))
            forgetLedger(of: id)
        }
        preferences.setMode(mode, for: id)
        storage.save(preferences)
        changeCount += 1
    }

    public func setWritePlanDays(_ value: Bool) {
        preferences.writePlanDays = value
        storage.save(preferences)
    }

    public func setWriteAbsences(_ value: Bool) {
        preferences.writeAbsences = value
        storage.save(preferences)
    }

    public func setShowAllDay(_ value: Bool) {
        preferences.showAllDay = value
        storage.save(preferences)
        changeCount += 1
    }

    /// Creates (or finds) the optional dedicated calendar "Timetrack" and sets it to read+write. Asks for access if still missing.
    public func createTimetrackCalendar() async {
        message = nil
        if !access.canWrite { await requestAccess() }
        guard access.canWrite else { return }
        do {
            let id = try provider.ensureTimetrackCalendar(existingID: preferences.timetrackCalendarID)
            preferences.timetrackCalendarID = id
            preferences.setMode(.readWrite, for: id)
            storage.save(preferences)
            refresh()
            changeCount += 1
        } catch {
            message = "Der Kalender „Timetrack“ konnte nicht angelegt werden."
        }
    }

    // MARK: Reading

    /// Events of the selected calendars on one local day, empty without access or selection.
    public func events(on day: LocalDay, calendar: DayCalendar) -> [DeviceEvent] {
        guard showsEvents, let interval = calendar.interval(of: day) else { return [] }
        let raw = provider.events(from: interval.start, to: interval.end, calendarIDs: preferences.selectedCalendarIDs)
        return DeviceEventFilter.events(on: day, in: raw, preferences: preferences, calendar: calendar)
    }

    /// Number of shown events per day for a range (month-grid markers).
    public func eventCounts(from: LocalDay, to: LocalDay, calendar: DayCalendar) -> [LocalDay: Int] {
        guard showsEvents, let start = calendar.interval(of: from)?.start, let end = calendar.interval(of: to)?.end else { return [:] }
        let raw = provider.events(from: start, to: end, calendarIDs: preferences.selectedCalendarIDs)
        var counts: [LocalDay: Int] = [:]
        var day = from
        while day <= to {
            let count = DeviceEventFilter.events(on: day, in: raw, preferences: preferences, calendar: calendar).count
            if count > 0 { counts[day] = count }
            guard let next = LocalDays.adding(1, to: day) else { break }
            day = next
        }
        return counts
    }

    // MARK: Writing (only into calendars set to read+write)

    /// Makes every read+write calendar match the plan days (if enabled) and the planned/approved vacation and sick days (if enabled)
    /// for `[from, to]` (absences and plan days use the same window). Does nothing without write access or without a read+write
    /// calendar. Only marker events are touched.
    @discardableResult
    public func sync(planDays: [LocalDay: PlanDay], absences: [Absence], from: LocalDay, to: LocalDay, calendar: DayCalendar, planTitle: (PlanMode) -> String) -> CalendarWriteResult {
        reconcile(planDays: planDays, absences: absences, absenceWindow: (from, to), planWindow: (from, to), calendar: calendar, planTitle: planTitle)
    }

    /// N2: reads the absences (and, if enabled, the plan days) of the wide windows from the server itself and reconciles every
    /// read+write calendar, independent of which screen or month is open. Nothing is changed when the server could not be read, so a
    /// network error can never delete events. Calls that arrive while a run is in progress cause exactly one more run afterwards.
    @discardableResult
    public func syncAll(source: CalendarSyncSource, calendar: DayCalendar, now: Date = .now, planTitle: @escaping (PlanMode) -> String) async -> CalendarWriteResult {
        if isSyncing {
            syncRequested = true
            return .skipped
        }
        isSyncing = true
        defer { isSyncing = false }
        var result = CalendarWriteResult.skipped
        repeat {
            syncRequested = false
            result = await runFullSync(source: source, calendar: calendar, now: now, planTitle: planTitle)
        } while syncRequested
        return result
    }

    private func runFullSync(source: CalendarSyncSource, calendar: DayCalendar, now: Date, planTitle: (PlanMode) -> String) async -> CalendarWriteResult {
        access = provider.access
        guard access.canWrite, calendars.contains(where: { preferences.mode(for: $0.id).writes && $0.allowsWrite }) else {
            lastWrite = .skipped
            return .skipped
        }
        let today = calendar.day(for: now)
        func shifted(_ days: Int) -> LocalDay { LocalDays.adding(days, to: today) ?? today }
        let absenceWindow = (from: shifted(-Self.absenceWindowDaysBack), to: shifted(Self.absenceWindowDaysAhead))
        let planWindow = (from: shifted(-Self.planWindowDaysBack), to: shifted(Self.planWindowDaysAhead))
        var absences: [Absence] = []
        var planDays: [LocalDay: PlanDay] = [:]
        do {
            if preferences.writeAbsences { absences = try await source.calendarAbsences(from: absenceWindow.from, to: absenceWindow.to) }
            if preferences.writePlanDays {
                for day in try await source.calendarPlanDays(from: planWindow.from, to: planWindow.to) { planDays[day.date] = day }
            }
        } catch {
            lastWrite = .skipped
            return .skipped
        }
        return reconcile(planDays: planDays, absences: absences, absenceWindow: absenceWindow, planWindow: planWindow, calendar: calendar, planTitle: planTitle)
    }

    private func reconcile(planDays: [LocalDay: PlanDay], absences: [Absence], absenceWindow: (from: LocalDay, to: LocalDay),
                           planWindow: (from: LocalDay, to: LocalDay), calendar: DayCalendar, planTitle: (PlanMode) -> String) -> CalendarWriteResult {
        access = provider.access
        let targets = calendars.filter { preferences.mode(for: $0.id).writes && $0.allowsWrite }
        let queryFrom = min(absenceWindow.from, planWindow.from), queryTo = max(absenceWindow.to, planWindow.to)
        guard access.canWrite, !targets.isEmpty, let start = calendar.interval(of: queryFrom)?.start, let end = calendar.interval(of: queryTo)?.end else {
            lastWrite = .skipped
            return .skipped
        }
        let desiredPlan = preferences.writePlanDays ? CalendarWritePlanner.desiredPlanDays(from: planDays, from: planWindow.from, to: planWindow.to, title: planTitle) : []
        let desiredAbsences = preferences.writeAbsences ? CalendarWritePlanner.desiredAbsences(absences, from: absenceWindow.from, to: absenceWindow.to) : []
        var created = 0, updated = 0, deleted = 0
        for target in targets {
            let existing = provider.writtenEvents(calendarID: target.id, from: start, to: end)
            var records = ledger.records(for: target.id)
            let absencePlan = CalendarReconciler.plan(desired: desiredAbsences, existing: existing, records: records, from: absenceWindow.from, to: absenceWindow.to, managing: [EntryMarker.absenceHost])
            let planPlan = CalendarReconciler.plan(desired: desiredPlan, existing: existing, records: records, from: planWindow.from, to: planWindow.to, managing: [EntryMarker.planHost])
            let operations = (absencePlan.operations + planPlan.operations).sorted { CalendarWritePlanner.sortKey($0) < CalendarWritePlanner.sortKey($1) }
            var assigned: [String: String] = [:]
            if !operations.isEmpty {
                do {
                    assigned = try provider.apply(operations, calendarID: target.id, calendar: calendar)
                } catch {
                    lastWrite = .failed
                    message = "Die Termine konnten nicht in den Kalender „\(target.title)“ geschrieben werden."
                    return .failed
                }
                for operation in operations {
                    switch operation {
                    case .create: created += 1
                    case .update: updated += 1
                    case .delete: deleted += 1
                    }
                }
            }
            for plan in [absencePlan, planPlan] {
                for key in plan.forget { records[key] = nil }
                for (key, record) in plan.adopt { records[key] = record }
                for operation in plan.operations {
                    switch operation {
                    case .create(let entry): records[entry.key] = CalendarLedgerRecord(eventID: assigned[entry.key] ?? "", entry: entry)
                    case .update(_, let entry): records[entry.key] = CalendarLedgerRecord(eventID: assigned[entry.key] ?? records[entry.key]?.eventID ?? "", entry: entry)
                    case .delete: break
                    }
                }
            }
            ledger.set(records, for: target.id)
        }
        ledgerStorage.save(ledger)
        message = nil
        let result = CalendarWriteResult.written(created: created, updated: updated, deleted: deleted)
        lastWrite = result
        return result
    }

    private func forgetLedger(of calendarID: String) {
        ledger.clear(calendar: calendarID)
        ledgerStorage.save(ledger)
    }

    /// Removes every event Timetrack wrote (marker URL) from all calendars that accept changes, within two years around today.
    /// Events without the marker are never touched. Returns how many events were removed.
    @discardableResult
    public func removeAllWritten(calendar: DayCalendar, now: Date = .now) -> Int {
        message = nil
        guard access.canWrite else { return 0 }
        var removed = 0
        for info in calendars where info.allowsWrite {
            removed += removeWritten(inCalendar: info.id, dayCalendar: calendar, now: now)
        }
        ledger = CalendarLedger()
        ledgerStorage.save(ledger)
        lastRemoval = removed
        lastWrite = nil
        changeCount += 1
        return removed
    }

    @discardableResult
    private func removeWritten(inCalendar id: String, dayCalendar: DayCalendar, now: Date = .now) -> Int {
        let start = now.addingTimeInterval(-2 * 366 * 86_400)
        let end = now.addingTimeInterval(2 * 366 * 86_400)
        let existing = provider.writtenEvents(calendarID: id, from: start, to: end)
        let operations = CalendarWritePlanner.removalOperations(for: existing)
        guard !operations.isEmpty else { return 0 }
        do {
            try provider.apply(operations, calendarID: id, calendar: dayCalendar)
            return operations.count
        } catch {
            message = "Die Termine konnten nicht entfernt werden."
            return 0
        }
    }

    private func storeChanged() {
        refresh()
        changeCount += 1
    }
}
