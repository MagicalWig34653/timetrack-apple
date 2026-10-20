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
