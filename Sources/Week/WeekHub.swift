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

enum TimeSegment: String, CaseIterable, Identifiable {
    case list, week, plan
    var id: String { rawValue }
    var title: String { W.s("segment.\(rawValue)") }
}

/// Segmented switch of the "Zeit" tab: day list (existing), week overview and week planner.
struct TimeSegmentPicker: View {
    @Binding var selection: TimeSegment
    let planningEnabled: Bool

    var body: some View {
        Picker(selection: $selection, label: Text(verbatim: "")) {
            ForEach(TimeSegment.allCases.filter { planningEnabled || $0 != .plan }) { Text(verbatim: $0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("time.segments")
        .frame(maxWidth: 420)
    }
}

/// Week overview and planner content for the "Zeit" tab.
struct WeekHub: View {
    @Binding var segment: TimeSegment
    @Environment(AppModel.self) private var model

    var body: some View {
        if let client = model.apiClient {
            let cache = WeekStoreCache.shared
            switch segment {
            case .plan where model.isEnabled(.planning):
                WeekPlannerView(store: cache.planStore(client, calendar: model.dayCalendar), overview: cache.weekStore(client, calendar: model.dayCalendar))
            default:
                WeekOverviewView(store: cache.weekStore(client, calendar: model.dayCalendar), planningEnabled: model.isEnabled(.planning)) { segment = .plan }
            }
        }
    }
}
