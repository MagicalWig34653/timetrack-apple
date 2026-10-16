import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Read-only vacation overview (module `planning`). All numbers are computed by the backend.
struct VacationView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let store = model.planning {
                VacationContent(store: store)
            } else {
                ScrollView { EmptyState(symbol: "beach.umbrella", title: "vacation.disabled").padding(TT.Space.l) }.ttScreenBackground()
            }
        }
        .navigationTitle("sidebar.vacation")
    }
}

private struct VacationContent: View {
    let store: PlanningStore
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                yearSwitcher
                if let error = store.error { ErrorBannerView(error: error) { Task { await store.load() } } }
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: TT.Space.xl) {
                        balance.frame(maxWidth: 440)
                        absences
                    }
                } else {
                    balance
                    absences
                }
            }
            .padding(.horizontal, TT.Space.l)
            .padding(.vertical, TT.Space.s)
            .frame(maxWidth: sizeClass == .regular ? 1100 : TT.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    private var yearSwitcher: some View {
        HStack {
            Button { Task { await store.shiftYears(-1) } } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
                .accessibilityLabel(Text("vacation.previous_year"))
            Spacer()
            Text(verbatim: String(store.year)).font(TTFont.sectionTitle).monospacedDigit().foregroundStyle(TT.textPrimary)
            Spacer()
            Button { Task { await store.shiftYears(1) } } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
                .accessibilityLabel(Text("vacation.next_year"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, TT.Space.s)
    }

    @ViewBuilder private var balance: some View {
        if let balance = store.balance {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                SectionHeader("vacation.balance")
                Card {
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: TT.Space.l)) : AnyLayout(HStackLayout(spacing: TT.Space.xl))
                    layout {
                        let total = balance.entitlementHalfDays + balance.carryOverHalfDays + balance.adjustmentHalfDays
                        ProgressRing(progress: total > 0 ? Double(max(balance.availableHalfDays, 0)) / Double(total) : 0, lineWidth: 12, tint: TT.kindVacation) {
                            Image(systemName: "beach.umbrella.fill").font(.title2).foregroundStyle(TT.kindVacation)
                        }
                        .frame(width: 96, height: 96)
                        VStack(alignment: .leading, spacing: TT.Space.xs) {
                            Text("vacation.available").font(TTFont.label).foregroundStyle(TT.textSecondary)
                            Text("vacation.days \(HalfDayFormat.days(balance.availableHalfDays))")
                                .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(TT.textPrimary)
                            Text("vacation.after_planned_short \(HalfDayFormat.days(balance.availableAfterPlannedHalfDays))")
                                .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                ListCard {
                    row("vacation.entitlement", balance.entitlementHalfDays)
                    if balance.carryOverHalfDays != 0 { row("vacation.carry_over", balance.carryOverHalfDays) }
                    if balance.adjustmentHalfDays != 0 { row("vacation.adjustment", balance.adjustmentHalfDays) }
                    row("vacation.booked", balance.bookedHalfDays)
                    row("vacation.planned", balance.plannedHalfDays)
                }
            }
        } else if store.isLoading {
            SkeletonList(rows: 3)
        }
    }

    private var absences: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            SectionHeader("vacation.absences") { if !store.absences.isEmpty { Text(verbatim: "\(store.absences.count)") } }
            if store.absences.isEmpty && !store.isLoading {
                Card { EmptyState(symbol: "calendar", title: "vacation.none") }
            } else {
                ListCard {
                    ForEach(store.absences) { AbsenceRow(absence: $0, calendar: model.dayCalendar) }
                }
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ halfDays: Int) -> some View {
        FormRow(title) { Text("vacation.days \(HalfDayFormat.days(halfDays))").monospacedDigit() }
    }
}

private struct AbsenceRow: View {
    let absence: Absence
    let calendar: DayCalendar

    var body: some View {
        HStack(spacing: TT.Space.m) {
            KindGlyph(symbol: absence.kind.ttSymbol, tint: absence.kind.ttTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(absence.kind.ttTitle).font(TTFont.body).foregroundStyle(TT.textPrimary)
                Text(verbatim: range).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
            Spacer(minLength: TT.Space.s)
            VStack(alignment: .trailing, spacing: 4) {
                StatusChip(statusKey, tone: statusTone)
                if absence.kind == .vacation {
                    Text("vacation.days \(HalfDayFormat.days(absence.countedHalfDays))").font(TTFont.numeralSmall).foregroundStyle(TT.textSecondary)
                }
            }
        }
        .padding(.horizontal, TT.Space.l)
        .padding(.vertical, TT.Space.m)
        .accessibilityElement(children: .combine)
    }

    private var statusTone: TTTone {
        switch absence.status {
        case .approved, .taken: .success
        case .planned, .requested: .accent
        case .rejected, .cancelled: .danger
        case .unknown: .neutral
        }
    }

    private var range: String {
        absence.startDate == absence.endDate
            ? dayTitle(absence.startDate, calendar: calendar)
            : "\(dayTitle(absence.startDate, calendar: calendar)) – \(dayTitle(absence.endDate, calendar: calendar))"
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
