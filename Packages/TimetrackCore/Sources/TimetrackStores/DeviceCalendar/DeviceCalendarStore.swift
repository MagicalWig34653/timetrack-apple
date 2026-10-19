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
    /// Events in the Timetrack calendar that carry Timetrack's marker URL.
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
/// Read-only by default: events are only read for calendars the user selected, and the store writes only after the user enabled
/// writing, and then only into the dedicated Timetrack calendar. Event data never leaves the device.
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

    /// Calendars the user can pick (Timetrack's own calendar is not offered as a source of context).
    public var selectableCalendars: [DeviceCalendarInfo] { calendars.filter { $0.id != preferences.timetrackCalendarID } }
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
        let known = Set(calendars.map(\.id))
        let pruned = preferences.selectedCalendarIDs.intersection(known)
        if pruned != preferences.selectedCalendarIDs {
            preferences.selectedCalendarIDs = pruned
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

    public func setSelected(_ id: String, _ selected: Bool) {
        if selected { preferences.selectedCalendarIDs.insert(id) } else { preferences.selectedCalendarIDs.remove(id) }
        storage.save(preferences)
        changeCount += 1
    }

    public func setShowAllDay(_ value: Bool) {
        preferences.showAllDay = value
        storage.save(preferences)
        changeCount += 1
    }

    /// Switches writing on or off. Switching on needs full access (asked now if still missing) and creates the Timetrack calendar.
    public func setWriteEnabled(_ enabled: Bool) async {
        message = nil
        guard enabled else {
            preferences.writeEnabled = false
            storage.save(preferences)
            return
        }
        if !access.canWrite { await requestAccess() }
        guard access.canWrite else {
            preferences.writeEnabled = false
            storage.save(preferences)
            return
        }
        do {
            preferences.timetrackCalendarID = try provider.ensureTimetrackCalendar(existingID: preferences.timetrackCalendarID)
            preferences.writeEnabled = true
            // The new calendar must not become a context source by accident.
            if let id = preferences.timetrackCalendarID { preferences.selectedCalendarIDs.remove(id) }
        } catch {
            preferences.writeEnabled = false
            message = "Der Kalender „Timetrack“ konnte nicht angelegt werden."
        }
        storage.save(preferences)
        refresh()
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

    // MARK: Writing (only when enabled)

    /// Makes the Timetrack calendar match the plan for `[from, to]`. Does nothing unless writing is enabled and permitted.
    @discardableResult
    public func syncPlan(_ planDays: [LocalDay: PlanDay], from: LocalDay, to: LocalDay, calendar: DayCalendar, title: (PlanMode) -> String) -> CalendarWriteResult {
        access = provider.access
        guard preferences.writeEnabled, access.canWrite, let calendarID = preferences.timetrackCalendarID,
              let start = calendar.interval(of: from)?.start, let end = calendar.interval(of: to)?.end else {
            lastWrite = .skipped
            return .skipped
        }
        let desired = PlanWriteBackPlanner.desired(from: planDays, from: from, to: to, title: title)
        let existing = provider.writtenEvents(calendarID: calendarID, from: start, to: end)
        let operations = PlanWriteBackPlanner.operations(desired: desired, existing: existing, from: from, to: to)
        guard !operations.isEmpty else {
            lastWrite = .written(created: 0, updated: 0, deleted: 0)
            return .written(created: 0, updated: 0, deleted: 0)
        }
        do {
            try provider.apply(operations, calendarID: calendarID, calendar: calendar)
            let result = CalendarWriteResult.written(
                created: operations.filter { if case .create = $0 { true } else { false } }.count,
                updated: operations.filter { if case .update = $0 { true } else { false } }.count,
                deleted: operations.filter { if case .delete = $0 { true } else { false } }.count)
            lastWrite = result
            message = nil
            return result
        } catch {
            lastWrite = .failed
            message = "Der Plan konnte nicht in den Kalender „Timetrack“ geschrieben werden."
            return .failed
        }
    }

    private func storeChanged() {
        refresh()
        changeCount += 1
    }
}
