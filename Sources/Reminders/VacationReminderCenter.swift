import Foundation
import Observation
import SwiftUI
import TimetrackCore
import TimetrackStores
import UserNotifications

/// R3: local reminders to submit planned vacation. The plan itself is the pure `VacationReminderPlanner` (TimetrackCore);
/// this class stores the settings (per device), asks for permission only on activation and reconciles the pending notifications.
@MainActor
@Observable
final class VacationReminderCenter {
    static let shared = VacationReminderCenter()
    nonisolated static let absenceKey = "vacationAbsenceId"
    nonisolated static let startKey = "vacationStart"
    private static let defaultsKey = "vacationReminders.settings.v1"

    private(set) var settings: VacationReminderSettings
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// Number of reminders currently pending (shown on the settings page).
    private(set) var scheduledCount = 0
    /// Set by a tap on a reminder; consumed by the Urlaub tab.
    var pendingTap: PendingTap?

    struct PendingTap: Equatable { let absenceID: UUID; let startDate: LocalDay }

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let center: UNUserNotificationCenter

    init(defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.center = center
        if let data = defaults.data(forKey: Self.defaultsKey), let stored = try? JSONDecoder().decode(VacationReminderSettings.self, from: data) {
            settings = stored
        } else {
            settings = VacationReminderSettings()
        }
    }

    var isAuthorized: Bool { [.authorized, .provisional, .ephemeral].contains(authorization) }

    func attach(_ model: AppModel) { self.model = model }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
        if settings.enabled, !isAuthorized { // permission was withdrawn in iOS Settings: the switch must not claim reminders that cannot fire
            update { $0.enabled = false }
        }
        await refreshCount()
    }

    // MARK: Settings

    /// Switching on asks for permission (first time only); a refusal keeps the switch off.
    func setEnabled(_ on: Bool) async {
        guard on else {
            update { $0.enabled = false }
            await sync()
            return
        }
        await refreshAuthorization()
        authorization = await NotificationPermission.requestIfNeeded() // OT1: shared with the overwork notifications
        guard isAuthorized else { update { $0.enabled = false }; return }
        update { $0.enabled = true }
        await sync()
    }

    func setLeadDay(_ days: Int, selected: Bool) async {
        update { value in
            var set = Set(value.leadDays)
            if selected { set.insert(days) } else { set.remove(days) }
            value.leadDays = set.sorted(by: >)
        }
        await sync()
    }

    func setTime(hour: Int, minute: Int) async {
        update { $0.hour = hour; $0.minute = minute }
        await sync()
    }

    private func update(_ change: (inout VacationReminderSettings) -> Void) {
        var copy = settings
        change(&copy)
        settings = copy
        if let data = try? JSONEncoder().encode(copy) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    // MARK: Scheduling

    /// Fetches the planned vacation of the next ~13 months itself (the Urlaub tab only holds one calendar year) and reconciles
    /// the pending reminders. A failed fetch keeps what is scheduled. Newer calls supersede older ones.
    func sync() async {
        syncTask?.cancel()
        let task = Task { await performSync() }
        syncTask = task
        await task.value
    }

    private func performSync() async {
        guard let model, model.phase == .signedIn, let client = model.apiClient else { return }
        authorization = await center.notificationSettings().authorizationStatus
        guard settings.enabled, isAuthorized, model.isEnabled(.planning) else {
            await removeAll()
            return
        }
        let calendar = model.dayCalendar
        let now = Date.now
        let today = calendar.day(for: now)
        guard let end = LocalDays.adding(400, to: today) else { return }
        let absences: [Absence]
        do { absences = try await client.listAbsences(from: today, to: end) } catch { return }
        guard !Task.isCancelled else { return }
        await apply(VacationReminderPlanner.plan(absences: absences, settings: settings, now: now, calendar: calendar))
    }

    private func apply(_ planned: [VacationReminderItem]) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let result = VacationReminderPlanner.reconcile(pendingIDs: pending, planned: planned)
        center.removePendingNotificationRequests(withIdentifiers: result.remove)
        for item in result.add {
            guard !Task.isCancelled else { return }
            try? await center.add(request(for: item))
        }
        await refreshCount()
    }

    /// Removes every reminder of this feature (switched off, signed out, permission gone). Other notifications stay.
    func removeAll() async {
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(VacationReminderItem.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(VacationReminderItem.idPrefix) })
        scheduledCount = 0
    }

    private func refreshCount() async {
        scheduledCount = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(VacationReminderItem.idPrefix) }.count
    }

    private func request(for item: VacationReminderItem) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.threadIdentifier = "de.linolaske.timetrack.vacation-reminder"
        content.userInfo = [Self.absenceKey: item.absenceID.uuidString, Self.startKey: item.startDate]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: item.timeZoneIdentifier) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
        var components = parts
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNNotificationRequest(identifier: item.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    // MARK: Tap

    /// A tap on a reminder: open the Urlaub tab at that absence.
    func handleTap(absenceID: String, startDate: String) {
        guard let id = UUID(uuidString: absenceID) else { return }
        pendingTap = PendingTap(absenceID: id, startDate: startDate)
        UIState.shared.selection = .vacation
    }
}

// MARK: - Sync hook

private struct VacationReminderSyncModifier: ViewModifier {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task {
                let center = VacationReminderCenter.shared
                center.attach(model)
                await center.refreshAuthorization()
                await center.sync()
            }
            .onChange(of: model.planning?.absences) { Task { await VacationReminderCenter.shared.sync() } } // after every load/save/delete
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task { await VacationReminderCenter.shared.refreshAuthorization(); await VacationReminderCenter.shared.sync() }
            }
            .onChange(of: model.phase) {
                switch model.phase {
                case .signedIn: Task { await VacationReminderCenter.shared.sync() }
                case .signedOut, .recoveryRestricted: Task { await VacationReminderCenter.shared.removeAll() }
                case .restoring, .offline: break
                }
            }
    }
}

extension View {
    /// R3: keeps the local vacation reminders in step with the account's absences.
    func vacationReminderSync(_ model: AppModel) -> some View { modifier(VacationReminderSyncModifier(model: model)) }
}

// MARK: - Open the tapped absence in the Urlaub tab

private struct VacationReminderOpenModifier: ViewModifier {
    let store: PlanningStore
    @Binding var request: AbsenceRequest?
    private var center: VacationReminderCenter { .shared }

    func body(content: Content) -> some View {
        content
            .task(id: center.pendingTap) { await openPending() }
    }

    private func openPending() async {
        guard let tap = center.pendingTap else { return }
        if let year = LocalDays.parse(tap.startDate)?.year, year != store.year {
            await store.shiftYears(year - store.year)
        } else if store.absences.isEmpty {
            await store.load()
        }
        center.pendingTap = nil
        if let absence = store.absences.first(where: { $0.id == tap.absenceID }) {
            request = AbsenceRequest(kind: absence.kind, start: absence.startDate, end: absence.endDate, editing: absence)
        }
    }
}

extension View {
    func vacationReminderOpen(store: PlanningStore, request: Binding<AbsenceRequest?>) -> some View {
        modifier(VacationReminderOpenModifier(store: store, request: request))
    }
}
