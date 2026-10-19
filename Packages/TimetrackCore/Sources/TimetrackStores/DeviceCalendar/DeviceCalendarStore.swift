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
    func apply(_ operations: [WriteOperation], calendarID: String, calendar: DayCalendar) throws
    /// Called when the system reports changes to the calendar database.
    var onStoreChanged: (@MainActor () -> Void)? { get set }
}

/// Where `CalendarPreferences` live (per device, never synced to the backend).
public protocol CalendarPreferencesStorage: Sendable {
    func load() -> CalendarPreferences
    func save(_ preferences: CalendarPreferences)
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

    public init(provider: DeviceCalendarProvider, storage: CalendarPreferencesStorage = UserDefaultsCalendarPreferencesStorage()) {
        self.provider = provider
        self.storage = storage
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
        if previous.writes, !mode.writes { removeWritten(inCalendar: id, dayCalendar: dayCalendar ?? DayCalendar(timeZone: .current)) }
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
    /// for `[from, to]`. Does nothing without write access or without a read+write calendar. Only marker events are touched.
    @discardableResult
    public func sync(planDays: [LocalDay: PlanDay], absences: [Absence], from: LocalDay, to: LocalDay, calendar: DayCalendar, planTitle: (PlanMode) -> String) -> CalendarWriteResult {
        access = provider.access
        let targets = calendars.filter { preferences.mode(for: $0.id).writes && $0.allowsWrite }
        guard access.canWrite, !targets.isEmpty, let start = calendar.interval(of: from)?.start, let end = calendar.interval(of: to)?.end else {
            lastWrite = .skipped
            return .skipped
        }
        var desired: [CalendarEntry] = []
        if preferences.writePlanDays { desired += CalendarWritePlanner.desiredPlanDays(from: planDays, from: from, to: to, title: planTitle) }
        if preferences.writeAbsences { desired += CalendarWritePlanner.desiredAbsences(absences, from: from, to: to) }
        var created = 0, updated = 0, deleted = 0
        for target in targets {
            let existing = provider.writtenEvents(calendarID: target.id, from: start, to: end)
            let operations = CalendarWritePlanner.operations(desired: desired, existing: existing, from: from, to: to)
            guard !operations.isEmpty else { continue }
            do {
                try provider.apply(operations, calendarID: target.id, calendar: calendar)
                for operation in operations {
                    switch operation {
                    case .create: created += 1
                    case .update: updated += 1
                    case .delete: deleted += 1
                    }
                }
            } catch {
                lastWrite = .failed
                message = "Die Termine konnten nicht in den Kalender „\(target.title)“ geschrieben werden."
                return .failed
            }
        }
        message = nil
        let result = CalendarWriteResult.written(created: created, updated: updated, deleted: deleted)
        lastWrite = result
        return result
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
