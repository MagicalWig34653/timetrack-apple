import SwiftUI
import TimetrackCore
import TimetrackStores

/// Read-only vacation overview (module `planning`). All numbers are computed by the backend.
struct VacationView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let store = model.planning {
                VacationContent(store: store)
            } else {
                ContentUnavailableView("vacation.disabled", systemImage: "beach.umbrella")
            }
        }
        .navigationTitle("sidebar.vacation")
    }
}

private struct VacationContent: View {
    let store: PlanningStore
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let error = store.error { ErrorBanner(error: error) { Task { await store.load() } }.listRowSeparator(.hidden) }
            if let balance = store.balance {
                Section("vacation.balance") {
                    row("vacation.available", balance.availableHalfDays, emphasized: true)
                    row("vacation.after_planned", balance.availableAfterPlannedHalfDays)
                    row("vacation.entitlement", balance.entitlementHalfDays)
                    if balance.carryOverHalfDays != 0 { row("vacation.carry_over", balance.carryOverHalfDays) }
                    if balance.adjustmentHalfDays != 0 { row("vacation.adjustment", balance.adjustmentHalfDays) }
                    row("vacation.booked", balance.bookedHalfDays)
                    row("vacation.planned", balance.plannedHalfDays)
                }
            }
            Section("vacation.absences") {
                if store.absences.isEmpty && !store.isLoading {
                    Text("vacation.none").foregroundStyle(.secondary)
                }
                ForEach(store.absences) { absence in
                    AbsenceRow(absence: absence, calendar: model.dayCalendar)
                }
            }
        }
        .overlay { if store.balance == nil && store.isLoading { ProgressView() } }
        .task { await store.load() }
        .refreshable { await store.load() }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { Task { await store.shiftYears(-1) } } label: { Label("vacation.previous_year", systemImage: "chevron.left") }
                Spacer()
                Text(verbatim: String(store.year)).font(.headline).monospacedDigit()
                Spacer()
                Button { Task { await store.shiftYears(1) } } label: { Label("vacation.next_year", systemImage: "chevron.right") }
            }
            .labelStyle(.iconOnly)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .glassEffect(in: .capsule)
            .padding(.horizontal, 16)
        }
    }

    private func row(_ title: LocalizedStringKey, _ halfDays: Int, emphasized: Bool = false) -> some View {
        LabeledContent(title) {
            Text("vacation.days \(HalfDayFormat.days(halfDays))")
                .monospacedDigit()
                .fontWeight(emphasized ? .semibold : .regular)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AbsenceRow: View {
    let absence: Absence
    let calendar: DayCalendar

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kindKey)
                Text(range).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(statusKey).font(.caption)
                if absence.kind == .vacation {
                    Text("vacation.days \(HalfDayFormat.days(absence.countedHalfDays))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var range: String {
        absence.startDate == absence.endDate
            ? dayTitle(absence.startDate, calendar: calendar)
            : "\(dayTitle(absence.startDate, calendar: calendar)) – \(dayTitle(absence.endDate, calendar: calendar))"
    }

    private var kindKey: LocalizedStringKey {
        switch absence.kind {
        case .vacation: "absence.vacation"
        case .sick: "absence.sick"
        case .excused: "absence.excused"
        case .other, .unknown: "absence.other"
        }
    }

    private var statusKey: LocalizedStringKey {
        switch absence.status {
        case .planned: "absence.status.planned"
        case .requested: "absence.status.requested"
        case .approved: "absence.status.approved"
        case .taken: "absence.status.taken"
        case .rejected: "absence.status.rejected"
        case .cancelled: "absence.status.cancelled"
        case .unknown: "absence.status.unknown"
        }
    }
}
