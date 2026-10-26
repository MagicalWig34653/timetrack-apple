import SwiftUI
import TimetrackCore
import TimetrackStores

/// N2: keeps the events Timetrack wrote into the device calendars in step with the server, no matter which screen is open.
/// Runs on launch, when the app becomes active, after every change of absences or plan days in the stores and when the calendar
/// settings change. Bursts are merged into one run; the store itself serialises runs and never changes anything when the server
/// could not be read.
@MainActor
final class CalendarAutoSync {
    static let shared = CalendarAutoSync()
    private var pending: Task<Void, Never>?

    func request(model: AppModel, deviceCalendar: DeviceCalendarStore, delay: Duration = .milliseconds(800)) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, model.phase == .signedIn, let client = model.apiClient, !deviceCalendar.preferences.writeCalendarIDs.isEmpty else { return }
            await deviceCalendar.syncAll(source: client, calendar: model.dayCalendar) { "Arbeit: \($0.plainName)" }
        }
    }
}

private struct CalendarAutoSyncModifier: ViewModifier {
    let model: AppModel
    let deviceCalendar: DeviceCalendarStore
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { CalendarAutoSync.shared.request(model: model, deviceCalendar: deviceCalendar, delay: .seconds(2)) }
            .onChange(of: scenePhase) { if scenePhase == .active { request() } }
            .onChange(of: model.phase) { if model.phase == .signedIn { request() } }
            .onChange(of: model.planning?.absences) { request() } // vacation planner: after every load/save/delete
            .onChange(of: model.calendar?.absences) { request() }
            .onChange(of: model.calendar?.planDays) { request() }
            .onChange(of: deviceCalendar.preferences) { request() }
    }

    private func request() { CalendarAutoSync.shared.request(model: model, deviceCalendar: deviceCalendar) }
}

extension View {
    /// N2: reconciles the calendar events Timetrack wrote with the server.
    func deviceCalendarSync(_ model: AppModel, _ deviceCalendar: DeviceCalendarStore) -> some View {
        modifier(CalendarAutoSyncModifier(model: model, deviceCalendar: deviceCalendar))
    }
}
