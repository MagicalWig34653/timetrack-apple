import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Keeps the week stores alive across tab visits so an unsaved plan is not lost when the user switches tabs or the iPad sidebar
/// replaces the detail view. A new client (sign-out / other account) gets fresh stores.
@MainActor
final class WeekStoreCache {
    static let shared = WeekStoreCache()
    private var owner: ObjectIdentifier?
    private var week: WeekStore?
    private var plan: WeekPlanStore?
    private var vacation: VacationPlannerStore?

    private func reset(for client: APIClient) {
        let id = ObjectIdentifier(client)
        if owner != id { owner = id; week = nil; plan = nil; vacation = nil }
    }

    func weekStore(_ client: APIClient, calendar: DayCalendar) -> WeekStore {
        reset(for: client)
        if let week { return week }
        let created = WeekStore(client: client, calendar: calendar)
        week = created
        return created
    }

    func planStore(_ client: APIClient, calendar: DayCalendar) -> WeekPlanStore {
        reset(for: client)
        if let plan { return plan }
        let created = WeekPlanStore(client: client, calendar: calendar)
        created.onOutcome = { TTHaptics.handle($0) }
        plan = created
        return created
    }

    func vacationStore(_ client: APIClient, calendar: DayCalendar) -> VacationPlannerStore {
        reset(for: client)
        if let vacation { return vacation }
        let created = VacationPlannerStore(client: client, calendar: calendar)
        created.onOutcome = { TTHaptics.handle($0) }
        vacation = created
        return created
    }
}

/// Week details pushed from the "Zeit" tab: the read-only week overview of the week the list shows. Planning is reachable from here
/// (and from the calendar's menu), not as a competing segment of the time list.
struct WeekDetailScreen: View {
    let day: LocalDay
    @Environment(AppModel.self) private var model
    @State private var planning = false

    var body: some View {
        Group {
            if let client = model.apiClient {
                let store = WeekStoreCache.shared.weekStore(client, calendar: model.dayCalendar)
                WeekOverviewView(store: store, planningEnabled: model.isEnabled(.planning)) { planning = true }
                    .task { await store.go(to: day) }
            }
        }
        .navigationTitle(W.s("detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.isEnabled(.planning) {
                ToolbarItem(placement: .primaryAction) {
                    Button { planning = true } label: { Label(W.s("segment.plan"), systemImage: "calendar.badge.checkmark") }
                        .accessibilityIdentifier("week.plan")
                }
            }
        }
        .navigationDestination(isPresented: $planning) { WeekPlannerScreen() }
    }
}

/// The week planner as a pushed screen (calendar menu and week details).
struct WeekPlannerScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let client = model.apiClient {
                let cache = WeekStoreCache.shared
                WeekPlannerView(store: cache.planStore(client, calendar: model.dayCalendar), overview: cache.weekStore(client, calendar: model.dayCalendar))
            }
        }
        .navigationTitle(W.s("segment.plan"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
