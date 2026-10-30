#if os(iOS)
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// U2: the week zoom as a horizontally paging scroll view. Every week is a page, so the content follows the finger one to one, snaps by
/// velocity, bounces at the ends and shows the neighbour week next to the current one while dragging. The pages are lists themselves,
/// so the row swipe actions ("Als geprüft markieren", "Stornieren") keep working. Only the settled page changes the anchor
/// (`TimeFocus.shiftWeeks`), exactly like the arrow buttons.
struct WeekPages: View {
    let store: TimeListStore
    let week: WeekStore?
    let focus: TimeFocus
    /// Week index relative to the current week; set from outside for arrows and "Heute", written back when a swipe settles.
    @Binding var position: Int?
    let canPlan: Bool
    let canAct: Bool
    let startPlanning: () -> Void
    let actions: DayActions
    let openDay: (LocalDay) -> Void
    let settled: (Int) -> Void

    /// About five years in each direction; further jumps go through the planner or the month list.
    static let reach = 260

    static func index(of monday: LocalDay, anchor: LocalDay) -> Int {
        (LocalDays.daysBetween(anchor, monday) ?? 0) / 7
    }

    var body: some View {
        let anchor = LocalDays.mondayOfWeek(containing: store.calendar.day(for: .now)) ?? focus.weekStart
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(-Self.reach...Self.reach, id: \.self) { index in
                        let monday = LocalDays.adding(7 * index, to: anchor) ?? anchor
                        let current = monday == store.weekStart
                        WeekDayList(store: store, week: week, monday: monday, pageDays: current ? store.days : store.cachedDays(forWeek: monday), isCurrent: current,
                                    selected: focus.day, canPlan: canPlan, canAct: canAct, startPlanning: startPlanning, actions: actions, openDay: openDay)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .id(index)
                            .accessibilityHidden(!current)
                            .task(id: store.weekStart) {
                                // Neighbours are read ahead so the page that slides in is not empty.
                                if abs(index - (Self.index(of: store.weekStart, anchor: anchor))) == 1 { await store.prefetch(week: monday) }
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $position, anchor: .leading)
            .scrollIndicators(.hidden)
            .onChange(of: position) { _, new in if let new { settled(new) } }
        }
        .accessibilityIdentifier("week.pages")
    }
}
#endif
