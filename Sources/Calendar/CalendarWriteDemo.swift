#if DEBUG
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Simulator/UI-test page (`TT_DEV_CALENDAR_WRITE`): the real "Kalender" settings page above a small demo panel that feeds the store a
/// vacation and a sick absence (the first with a private note that must never reach the calendar), syncs them into the in-memory
/// calendars and lists what was written. "Urlaub stornieren" removes the vacation from the list and syncs again.
struct CalendarWriteDemo: View {
    @Environment(\.deviceCalendar) private var store
    @State private var absences: [Absence] = []
    @State private var written = "–"
    @State private var generation = 0
    private let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin") ?? .current)

    var body: some View {
        NavigationStack { CalendarSettingsView() }
            .safeAreaInset(edge: .bottom) { panel }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            HStack {
                Button("Demo: synchronisieren") { sync(with: demoAbsences()) }.accessibilityIdentifier("demo.sync")
                Button("Urlaub stornieren") { sync(with: demoAbsences().filter { $0.kind != .vacation }) }.accessibilityIdentifier("demo.void")
                Button("Urlaub genehmigt") { sync(with: demoAbsences(vacationStatus: .approved)) }.accessibilityIdentifier("demo.approve")
            }
            .buttonStyle(.ttSecondary).font(.caption)
            Text(verbatim: written).font(.caption2.monospaced()).lineLimit(6).accessibilityIdentifier("demo.written")
        }
        .padding(TT.Space.m)
        .background(.regularMaterial)
    }

    private func demoAbsences(vacationStatus: AbsenceStatus = .planned) -> [Absence] {
        let today = calendar.day(for: .now)
        func day(_ offset: Int) -> LocalDay { LocalDays.adding(offset, to: today) ?? today }
        return [
            Absence(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!, kind: .vacation, startDate: day(7), endDate: day(10), status: vacationStatus,
                    note: "Arzttermin privat", countedHalfDays: 8),
            Absence(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!, kind: .sick, startDate: day(14), endDate: day(15), status: .planned, note: "Grippe", countedHalfDays: 4),
        ]
    }

    private func sync(with list: [Absence]) {
        guard let store else { return }
        let today = calendar.day(for: .now)
        let from = LocalDays.adding(-30, to: today) ?? today
        let to = LocalDays.adding(60, to: today) ?? today
        store.sync(planDays: [:], absences: list, from: from, to: to, calendar: calendar) { "Arbeit: \($0.rawValue)" }
        written = CalendarEnvironment.writtenSummary()
    }
}
#endif
