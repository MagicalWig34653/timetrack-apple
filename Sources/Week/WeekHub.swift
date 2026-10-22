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
    private var horizon: PlanHorizonStore?
    private var sharing: SharingStore?

    private func reset(for client: APIClient) {
        let id = ObjectIdentifier(client)
        if owner != id { owner = id; week = nil; plan = nil; vacation = nil; horizon = nil; sharing = nil }
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

    func horizonStore(_ client: APIClient, calendar: DayCalendar) -> PlanHorizonStore {
        reset(for: client)
        if let horizon { return horizon }
        let created = PlanHorizonStore(client: client, calendar: calendar)
        horizon = created
        return created
    }

    func sharingStore(_ client: APIClient, calendar: DayCalendar, ownHandle: String?) -> SharingStore {
        reset(for: client)
        if let sharing { return sharing }
        let created = SharingStore(client: client, calendar: calendar, ownHandle: ownHandle)
        created.onOutcome = { TTHaptics.handle($0) }
        sharing = created
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

/// The week planner as a pushed screen with its own week navigation. Used on macOS (planning area) and where a planner is opened without
/// the "Zeit" screen; on iOS/iPadOS the planner is the editing mode of the week zoom (Z2) and the area hands the week over to it.
struct WeekPlannerScreen: View {
    var monday: LocalDay?
    @Environment(AppModel.self) private var model
    @State private var pendingShift: Int?

    var body: some View {
        Group {
            if let client = model.apiClient {
                let cache = WeekStoreCache.shared
                let store = cache.planStore(client, calendar: model.dayCalendar)
                VStack(spacing: 0) {
                    WeekNavigator(weekNumber: store.weekNumber, monday: store.monday, sunday: store.sunday, calendar: store.calendar,
                                  isCurrent: store.monday == store.currentMonday,
                                  previous: { requestShift(store, -1) }, next: { requestShift(store, 1) }, current: { requestOpen(store, store.currentMonday) })
                        .padding(.horizontal, TT.Space.l)
                    WeekPlannerView(store: store, overview: cache.weekStore(client, calendar: model.dayCalendar))
                }
                .task { if let monday, store.monday != LocalDays.mondayOfWeek(containing: monday) { await store.open(monday: monday) } }
                .alert(W.s("leave.title"), isPresented: Binding(get: { pendingShift != nil }, set: { if !$0 { pendingShift = nil } })) {
                    Button(W.s("leave.discard"), role: .destructive) {
                        if let shift = pendingShift { store.discard(); Task { await store.shiftWeeks(shift) } }
                        pendingShift = nil
                    }
                    Button(W.s("leave.keep"), role: .cancel) { pendingShift = nil }
                } message: { W.t("leave.message") }
            }
        }
        .navigationTitle(W.s("segment.plan"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func requestShift(_ store: WeekPlanStore, _ count: Int) {
        if store.isDirty { pendingShift = count } else { Task { await store.shiftWeeks(count) } }
    }

    private func requestOpen(_ store: WeekPlanStore, _ target: LocalDay) {
        if store.isDirty { pendingShift = (LocalDays.daysBetween(store.monday, target) ?? 0) / 7 } else { Task { await store.open(monday: target) } }
    }
}

/// Z2 (iOS): the "Zeit" screen takes over opening a week in the planner, so the planning area does not push a second planner.
private struct OpenPlanWeekKey: EnvironmentKey { static let defaultValue: (@MainActor (LocalDay) -> Void)? = nil }
extension EnvironmentValues {
    var openPlanWeek: (@MainActor (LocalDay) -> Void)? {
        get { self[OpenPlanWeekKey.self] }
        set { self[OpenPlanWeekKey.self] = newValue }
    }
}
