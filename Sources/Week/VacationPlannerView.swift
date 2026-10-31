import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Urlaubsplanung: ranked suggestions of `GET /vacation/suggestions`. Nothing is booked until the user confirms a suggestion.
struct VacationPlannerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let client = model.apiClient, model.isEnabled(.planning) {
                VacationPlannerContent(store: WeekStoreCache.shared.vacationStore(client, calendar: model.dayCalendar))
            } else {
                ScrollView { EmptyState(symbol: "beach.umbrella", title: "vacation.disabled").padding(TT.Space.l) }.ttScreenBackground()
            }
        }
        .navigationTitle(W.s("vp.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Entry card in the Urlaub tab.
struct VacationPlannerLink: View {
    var body: some View {
        NavigationLink { VacationPlannerView() } label: {
            HStack(spacing: TT.Space.m) {
                KindGlyph(symbol: "sparkles", tint: TT.kindVacation)
                VStack(alignment: .leading, spacing: 2) {
                    W.t("vp.open").font(TTFont.body).foregroundStyle(TT.textPrimary)
                    W.t("vp.open_text").font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary).accessibilityHidden(true)
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vacation.planner.open")
    }
}

private struct VacationPlannerContent: View {
    let store: VacationPlannerStore
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var taking: VacationSuggestion?
    @State private var notice: String?
    @State private var noticeIsWarning = false
    @State private var filtersOpen = false
    @State private var requestFor: Absence? // AUD3-B: request PDF for an absence this screen just created

    private var wide: Bool { sizeClass == .regular && !typeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                W.t("vp.description").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                if let notice {
                    HStack(alignment: .top, spacing: TT.Space.s) {
                        Image(systemName: noticeIsWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").foregroundStyle(noticeIsWarning ? TT.warning : TT.success).accessibilityHidden(true)
                        Text(verbatim: notice).font(TTFont.body).foregroundStyle(TT.textPrimary)
                    }
                    .accessibilityIdentifier("vp.notice")
                    requestActions
                }
                if let error = store.error { WeekErrorBanner(error: error) { Task { await store.load() } } }
                if store.isUnavailable { HintBanner("wk.vp.unavailable") }
                if let data = store.data { budget(data.budget) }
                filters
                results
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: wide ? 1100 : TT.contentWidth).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .task {
            store.onBooked = { [weak model] in Task { await model?.planning?.load(); await model?.calendar?.load() } }
            if store.data == nil { await store.load() }
        }
        .refreshable { await store.load() }
        .sheet(item: $taking) { suggestion in
            TakeSheet(store: store, suggestion: suggestion) { result in
                taking = nil
                switch result {
                case .booked(let blocks, let first, let last):
                    noticeIsWarning = false
                    notice = blocks == 1 ? W.s("vp.done_one", PlanFormat.shortDay(first, calendar: store.calendar), PlanFormat.shortDay(last, calendar: store.calendar))
                        : W.s("vp.done", blocks, PlanFormat.shortDay(first, calendar: store.calendar), PlanFormat.shortDay(last, calendar: store.calendar))
                case .partial(let done, let total, let error):
                    noticeIsWarning = true
                    notice = W.s("vp.partial", done, total, error.germanDescription)
                default: break
                }
            }
        }
    }

    /// AUD3-B (as in the PWA planner): one "Urlaubsantrag erstellen" button per absence created by "Übernehmen".
    @ViewBuilder private var requestActions: some View {
        let created = VacationRequestEligibility.eligible(in: store.createdAbsences)
        if let planning = model.planning, !created.isEmpty {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                ForEach(created) { absence in
                    Button { requestFor = absence } label: {
                        Label(created.count == 1 ? "Urlaubsantrag erstellen" : "Urlaubsantrag erstellen: \(PlanFormat.range(absence.startDate, absence.endDate, calendar: store.calendar))", systemImage: "doc.text")
                    }
                    .buttonStyle(.ttSecondary)
                    .accessibilityIdentifier("vp.request")
                }
            }
            .sheet(item: $requestFor) { VacationRequestSheet(planning: planning, absence: $0) }
        }
    }

    // MARK: Budget

    private func budget(_ budget: VacationBudget) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            SectionHeader("wk.vp.budget_title \(String(store.budgetYear))")
            Card {
                VStack(alignment: .leading, spacing: TT.Space.s) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 120), spacing: TT.Space.m, alignment: .top)], alignment: .leading, spacing: TT.Space.m) {
                        SummaryTile(title: W.s("vp.entitlement"), value: weekDecimal(budget.entitlementDays))
                        SummaryTile(title: W.s("vp.taken"), value: weekDecimal(budget.takenDays))
                        SummaryTile(title: W.s("vp.planned"), value: weekDecimal(budget.plannedDays))
                        SummaryTile(title: W.s("vp.remaining"), value: weekDecimal(budget.remainingDays), tint: budget.remainingDays < 0 ? TT.danger : TT.textPrimary)
                    }
                    W.t("vp.budget_note").font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("vp.budget")
            }
        }
    }

    // MARK: Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Button { withAnimation(.smooth) { filtersOpen.toggle() } } label: {
                HStack {
                    SectionHeader("wk.vp.filters")
                    Spacer(minLength: 0)
                    Image(systemName: filtersOpen ? "chevron.up" : "chevron.down").foregroundStyle(TT.textSecondary).accessibilityHidden(true)
                }
                .frame(minHeight: 44).contentShape(.rect)
            }
            .buttonStyle(.plain).accessibilityIdentifier("vp.filters.toggle")
            if !filtersOpen { Text(verbatim: filterSummary).font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true) }
            if filtersOpen {
                Card {
                    VStack(alignment: .leading, spacing: TT.Space.s) {
                        DatePicker(W.s("vp.from"), selection: dayBinding(Binding(get: { store.filters.from }, set: { store.filters.from = $0 }), calendar: store.calendar), displayedComponents: .date)
                            .frame(minHeight: 44).accessibilityIdentifier("vp.from")
                        DatePicker(W.s("vp.to"), selection: dayBinding(Binding(get: { store.filters.to }, set: { store.filters.to = $0 }), calendar: store.calendar), displayedComponents: .date)
                            .frame(minHeight: 44).accessibilityIdentifier("vp.to")
                        Stepper(value: Binding(get: { store.filters.maxVacationDays }, set: { store.filters.maxVacationDays = $0 }), in: 1...60) { W.t("vp.max_days", store.filters.maxVacationDays).monospacedDigit() }
                            .frame(minHeight: 44).accessibilityIdentifier("vp.max_days")
                        Stepper(value: Binding(get: { store.filters.minDaysOff }, set: { store.filters.minDaysOff = $0 }), in: 1...60) { W.t("vp.min_off", store.filters.minDaysOff).monospacedDigit() }
                            .frame(minHeight: 44).accessibilityIdentifier("vp.min_off")
                        Stepper(value: Binding(get: { store.filters.minEfficiency }, set: { store.filters.minEfficiency = $0 }), in: 1...10, step: 0.5) { W.t("vp.min_factor", weekDecimal(store.filters.minEfficiency)).monospacedDigit() }
                            .frame(minHeight: 44).accessibilityIdentifier("vp.min_factor")
                        W.t("vp.min_factor_hint").font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
                        Stepper(value: Binding(get: { store.filters.count }, set: { store.filters.count = $0 }), in: 1...100) { W.t("vp.count", store.filters.count).monospacedDigit() }
                            .frame(minHeight: 44).accessibilityIdentifier("vp.count")
                        if !VacationPlannerFilters.rangeValid(from: store.filters.from, to: store.filters.to) { W.t("vp.range_invalid").font(TTFont.meta).foregroundStyle(TT.danger) }
                        HStack(spacing: TT.Space.s) {
                            Button { Task { await store.reset() } } label: { W.t("vp.reset") }.buttonStyle(.ttSecondary).accessibilityIdentifier("vp.reset")
                            Button { Task { await store.load() } } label: { W.t("vp.apply") }.buttonStyle(.ttPrimary)
                                .disabled(!store.filters.isValid || store.isLoading).accessibilityIdentifier("vp.apply")
                        }
                        W.t("vp.saved_hint").font(TTFont.meta).foregroundStyle(TT.textTertiary)
                    }
                }
            }
        }
    }

    private var filterSummary: String {
        let f = store.filters
        return W.s("vp.filter_summary", PlanFormat.shortDay(f.from, calendar: store.calendar), PlanFormat.shortDay(f.to, calendar: store.calendar), f.maxVacationDays, f.minDaysOff, weekDecimal(f.minEfficiency))
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        if store.isLoading && store.data == nil {
            SkeletonList(rows: 3)
        } else if store.data != nil {
            let view = store.view
            VStack(alignment: .leading, spacing: TT.Space.m) {
                if store.isStale { HintBanner("wk.vp.stale") }
                if view.shown.isEmpty {
                    Card { EmptyState(symbol: "magnifyingglass", title: view.hidden > 0 ? "wk.vp.empty_hidden" : "wk.vp.empty") }
                } else {
                    SectionHeader("wk.vp.results") { Text(verbatim: "\(view.shown.count)") }
                    if wide {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: TT.Space.m, alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: TT.Space.m) { cards(view.shown) }
                    } else {
                        VStack(spacing: TT.Space.m) { cards(view.shown) }
                    }
                }
                if view.hidden > 0 {
                    HStack(spacing: TT.Space.s) {
                        Text(verbatim: view.hidden == 1 ? W.s("vp.hidden_one", weekDecimal(store.filters.minEfficiency)) : W.s("vp.hidden", view.hidden, weekDecimal(store.filters.minEfficiency))).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        Button { store.filters.minEfficiency = 1 } label: { W.t("vp.show_all").frame(minHeight: 44) }.buttonStyle(.borderless).accessibilityIdentifier("vp.show_all")
                    }
                }
            }
        }
    }

    @ViewBuilder private func cards(_ list: [VacationSuggestion]) -> some View {
        ForEach(list) { suggestion in
            SuggestionCard(suggestion: suggestion, calendar: store.calendar, year: store.budgetYear) { taking = suggestion }
        }
    }
}

// MARK: - Card

private extension VacationSuggestionKind {
    var symbol: String {
        switch self {
        case .bridge: "arrow.left.and.right"
        case .holidayCluster: "party.popper.fill"
        case .schoolHolidayExtension: "graduationcap.fill"
        case .longBreak, .unknown: "beach.umbrella.fill"
        }
    }
    var label: String { W.s("kind.\(self == .unknown ? "long_break" : rawValue)") }
}

extension VacationConflictType {
    var label: String { W.s("conflict.\(self == .unknown ? "plan" : rawValue)") }
    var symbol: String {
        switch self {
        case .schoolDay: "graduationcap.fill"
        case .absence: "cross.case.fill"
        case .plan, .unknown: "briefcase.fill"
        case .alreadyVacation: "beach.umbrella.fill"
        }
    }
}

private struct SuggestionCard: View {
    let suggestion: VacationSuggestion
    let calendar: DayCalendar
    let year: Int
    let take: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var requirements: VacationPlanner.Requirements { VacationPlanner.requirements(for: suggestion) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: TT.Space.s) { badges }
                    VStack(alignment: .leading, spacing: TT.Space.xs) { badges }
                }
                Text(verbatim: PlanFormat.range(suggestion.start, suggestion.end, calendar: calendar)).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                    .accessibilityIdentifier("vp.range")
                Text(verbatim: W.s("vp.summary", vacationText, offText)).font(TTFont.body).foregroundStyle(TT.textPrimary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("vp.summary")
                if !suggestion.holidays.isEmpty {
                    ForEach(suggestion.holidays, id: \.date) { holiday in
                        Label { Text(verbatim: "\(holiday.name), \(PlanFormat.shortDay(holiday.date, calendar: calendar))") } icon: { Image(systemName: "party.popper.fill").foregroundStyle(TT.kindHoliday) }
                            .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    }
                }
                ForEach(suggestion.schoolHolidays, id: \.startDate) { holiday in
                    Label { Text(verbatim: "\(holiday.name), \(PlanFormat.range(holiday.startDate, holiday.endDate, calendar: calendar))") } icon: { Image(systemName: "graduationcap.fill").foregroundStyle(TT.kindSchool) }
                        .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
                DayStrip(cells: VacationPlanner.cells(for: suggestion), calendar: calendar)
                vacationDates
                conflicts
                budgetLine
                Button(action: take) { W.t("vp.take") }.buttonStyle(.ttPrimary).accessibilityIdentifier("vp.take")
            }
        }
        .overlay { if !requirements.conflicts.isEmpty { RoundedRectangle(cornerRadius: TT.Radius.card, style: .continuous).strokeBorder(TT.warning.opacity(0.7), lineWidth: 1.5) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vp.card")
    }

    @ViewBuilder private var badges: some View {
        StatusChip(verbatim: suggestion.kind.label, tone: .custom(TT.kindVacation), symbol: suggestion.kind.symbol)
        StatusChip(verbatim: W.s("vp.factor", weekDecimal(suggestion.efficiency)), tone: .accent)
        if !suggestion.fitsBudget { StatusChip(verbatim: W.s("vp.no_budget"), tone: .danger, symbol: "exclamationmark.circle.fill") }
    }

    private var vacationText: String { W.s(suggestion.vacationDaysNeeded == 1 ? "vp.vacation_one" : "vp.vacation_other", suggestion.vacationDaysNeeded) }
    private var offText: String { W.s("vp.off_days", suggestion.totalDaysOff) }

    private var vacationDates: some View {
        let dates = suggestion.vacationDates.sorted().map { PlanFormat.shortDay($0, calendar: calendar) }.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 2) {
            W.t("vp.exact_days").font(TTFont.meta.weight(.semibold)).foregroundStyle(TT.textSecondary)
            Text(verbatim: dates).font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var conflicts: some View {
        if !requirements.conflicts.isEmpty {
            VStack(alignment: .leading, spacing: TT.Space.xs) {
                Label { W.t("vp.conflicts_title").font(TTFont.label) } icon: { Image(systemName: "exclamationmark.triangle.fill") }.foregroundStyle(TT.warning)
                ForEach(requirements.conflicts, id: \.type) { group in
                    Label { Text(verbatim: "\(group.type.label): \(group.dates.map { PlanFormat.shortDay($0, calendar: calendar) }.joined(separator: ", "))") } icon: { Image(systemName: group.type.symbol) }
                        .font(TTFont.meta).foregroundStyle(TT.textPrimary)
                }
            }
            .padding(TT.Space.m).frame(maxWidth: .infinity, alignment: .leading)
            .background(TT.warning.opacity(0.12), in: .rect(cornerRadius: TT.Radius.control))
            .accessibilityElement(children: .combine).accessibilityIdentifier("vp.conflicts")
        }
        let booked = VacationPlanner.alreadyBookedDates(suggestion)
        if !booked.isEmpty {
            Label { Text(verbatim: "\(W.s("conflict.already_vacation")): \(booked.map { PlanFormat.shortDay($0, calendar: calendar) }.joined(separator: ", "))") } icon: { Image(systemName: "beach.umbrella.fill") }
                .font(TTFont.meta).foregroundStyle(TT.textSecondary)
        }
    }

    private var budgetLine: some View {
        let remaining = suggestion.remainingAfter
        return Group {
            if suggestion.fitsBudget {
                Label { W.t("vp.remaining_after", weekDays(remaining)) } icon: { Image(systemName: "checkmark.circle") }.foregroundStyle(TT.textSecondary)
            } else {
                Label { W.t("vp.over_budget", weekDays(abs(remaining)), String(year)) } icon: { Image(systemName: "exclamationmark.circle.fill") }.foregroundStyle(TT.danger)
            }
        }
        .font(TTFont.meta).fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("vp.budget_line")
    }
}

/// One cell per calendar day of the window; every state has a symbol or letter besides its colour.
private struct DayStrip: View {
    let cells: [VacationPlanner.Cell]
    let calendar: DayCalendar

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 44), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(cells) { cell in
                    VStack(spacing: 1) {
                        Text(verbatim: weekdayLetter(cell.weekday)).font(.system(size: 10, weight: .medium)).foregroundStyle(TT.textTertiary)
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill(cell.kind))
                            if cell.conflict != nil { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(TT.warning, lineWidth: 2) }
                            VStack(spacing: 0) {
                                Text(verbatim: "\(cell.day)").font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                                Image(systemName: symbol(cell.kind)).font(.system(size: 8))
                            }
                            .foregroundStyle(cell.kind == .free || cell.kind == .weekend ? TT.textSecondary : TT.textPrimary)
                        }
                        .frame(height: 34)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: label(cell)))
                }
            }
            .accessibilityIdentifier("vp.strip")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TT.Space.m) { legend }
                VStack(alignment: .leading, spacing: 2) { legend }
            }
            .font(.caption2).foregroundStyle(TT.textSecondary)
        }
    }

    @ViewBuilder private var legend: some View {
        legendItem(.vacation, "vp.legend_vacation")
        legendItem(.holiday, "vp.legend_holiday")
        legendItem(.weekend, "vp.legend_free")
        legendItem(.booked, "vp.legend_booked")
    }

    private func legendItem(_ kind: VacationPlanner.CellKind, _ key: String) -> some View {
        HStack(spacing: 3) { Image(systemName: symbol(kind)); W.t(key) }
    }

    private func fill(_ kind: VacationPlanner.CellKind) -> Color {
        switch kind {
        case .vacation: TT.kindVacation.opacity(0.28)
        case .holiday: TT.kindHoliday.opacity(0.30)
        case .booked: TT.kindExcused.opacity(0.25)
        case .weekend: TT.textSecondary.opacity(0.12)
        case .free: TT.textSecondary.opacity(0.05)
        }
    }

    private func symbol(_ kind: VacationPlanner.CellKind) -> String {
        switch kind {
        case .vacation: "beach.umbrella.fill"
        case .holiday: "party.popper.fill"
        case .booked: "checkmark"
        case .weekend: "moon.zzz.fill"
        case .free: "minus"
        }
    }

    private func weekdayLetter(_ weekday: Int) -> String { ["M", "D", "M", "D", "F", "S", "S"][max(0, min(6, weekday - 1))] }

    private func label(_ cell: VacationPlanner.Cell) -> String {
        let kind: String
        switch cell.kind {
        case .vacation: kind = W.s("cell.vacation")
        case .holiday: kind = W.s("cell.holiday", cell.holidayName ?? "")
        case .booked: kind = W.s("cell.booked")
        case .weekend, .free: kind = W.s("cell.free")
        }
        let warning = cell.conflict.map { ". " + W.s("cell.conflict", $0.label) } ?? ""
        return "\(PlanFormat.longDay(cell.date, calendar: calendar)): \(kind)\(warning)"
    }
}

// MARK: - Confirmation

private struct TakeSheet: View {
    let store: VacationPlannerStore
    let suggestion: VacationSuggestion
    let finish: (VacationPlannerStore.TakeResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ackConflicts = false
    @State private var ackBudget = false
    @State private var busy = false
    @State private var failure: TimetrackError?

    private var requirements: VacationPlanner.Requirements { VacationPlanner.requirements(for: suggestion) }
    private var blocks: [VacationPlanner.Block] { VacationPlanner.blocks(for: suggestion) }
    private var ready: Bool { (!requirements.needsConflictAcknowledgement || ackConflicts) && (!requirements.exceedsBudget || ackBudget) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    W.t(blocks.count == 1 ? "take.text_one" : "take.text", blocks.count).font(TTFont.body).foregroundStyle(TT.textPrimary)
                    ListCard {
                        ForEach(blocks, id: \.start) { block in
                            Text(verbatim: PlanFormat.range(block.start, block.end, calendar: store.calendar) + " (" + W.s(block.dates.count == 1 ? "vp.vacation_one" : "vp.vacation_other", block.dates.count) + ")")
                                .font(TTFont.body).foregroundStyle(TT.textPrimary).padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    W.t("take.cost_hint").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    if requirements.needsConflictAcknowledgement {
                        VStack(alignment: .leading, spacing: TT.Space.xs) {
                            ForEach(requirements.conflicts, id: \.type) { group in
                                Label { Text(verbatim: "\(group.type.label): \(group.dates.map { PlanFormat.shortDay($0, calendar: store.calendar) }.joined(separator: ", "))") } icon: { Image(systemName: group.type.symbol) }
                                    .font(TTFont.meta).foregroundStyle(TT.warning)
                            }
                        }
                        Toggle(isOn: $ackConflicts) { W.t("take.ack_conflicts") }.accessibilityIdentifier("take.ack_conflicts")
                    }
                    if requirements.exceedsBudget {
                        Label { W.t("take.budget_warning", weekDays(abs(suggestion.remainingAfter))) } icon: { Image(systemName: "exclamationmark.circle.fill") }.font(TTFont.meta).foregroundStyle(TT.danger)
                        Toggle(isOn: $ackBudget) { W.t("take.ack_budget") }.accessibilityIdentifier("take.ack_budget")
                    }
                    if let failure { ErrorBanner(message: failure.germanDescription, retryTitle: "common.dismiss") { self.failure = nil } }
                    Button { Task { await book() } } label: { W.t(busy ? "take.busy" : "take.confirm") }
                        .buttonStyle(.ttPrimary).disabled(!ready || busy).accessibilityIdentifier("take.confirm")
                }
                .padding(TT.Space.l).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(W.s("take.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() }.accessibilityIdentifier("take.cancel") } }
        }
        .presentationDetents([.medium, .large])
    }

    private func book() async {
        busy = true
        defer { busy = false }
        let result = await store.take(suggestion, acknowledgedConflicts: ackConflicts, acknowledgedBudget: ackBudget)
        switch result {
        case .failed(let error): failure = error
        default: finish(result)
        }
    }
}
