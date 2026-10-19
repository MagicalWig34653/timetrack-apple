import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Week planner: a rough plan per day (mode, begin, end, break), saved in one call. A plan never books time.
struct WeekPlannerView: View {
    let store: WeekPlanStore
    let overview: WeekStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var pendingShift: Int?
    @State private var notice: String?

    private var wide: Bool { sizeClass == .regular && !typeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                WeekNavigator(weekNumber: store.weekNumber, monday: store.monday, sunday: store.sunday, calendar: store.calendar,
                              isCurrent: store.monday == store.currentMonday,
                              previous: { requestShift(-1) }, next: { requestShift(1) }, current: { requestOpen(store.currentMonday) })
                if let error = store.error { WeekErrorBanner(error: error) { Task { await store.load() } } }
                if let notice { HintBanner(LocalizedStringKey(notice)) }
                if store.isUnavailable {
                    HintBanner("wk.week.plan_unavailable")
                } else if store.week != nil {
                    if store.isPast { HintBanner("wk.week.past_hint") }
                    totalCard
                    actions
                    rows
                } else if store.isLoading {
                    SkeletonList(rows: 4)
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: wide ? 1100 : TT.contentWidth).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { saveBar }
        .task { if store.week == nil { await store.load() } }
        .refreshable { if !store.isDirty { await store.load() } }
        .alert(W.s("leave.title"), isPresented: Binding(get: { pendingShift != nil }, set: { if !$0 { pendingShift = nil } })) {
            Button(W.s("leave.discard"), role: .destructive) {
                if let shift = pendingShift { store.discard(); Task { await store.shiftWeeks(shift) } }
                pendingShift = nil
            }
            Button(W.s("leave.keep"), role: .cancel) { pendingShift = nil }
        } message: { W.t("leave.message") }
    }

    private func requestShift(_ count: Int) {
        if store.isDirty { pendingShift = count } else { Task { await store.shiftWeeks(count) } }
    }

    private func requestOpen(_ monday: LocalDay) {
        if store.isDirty {
            let weeks = (LocalDays.daysBetween(store.monday, monday) ?? 0) / 7
            pendingShift = weeks
        } else { Task { await store.open(monday: monday) } }
    }

    // MARK: Total

    private var totalCard: some View {
        let totals = store.totals
        let progress = totals.targetSeconds > 0 ? min(1, Double(totals.plannedSeconds) / Double(totals.targetSeconds)) : (totals.plannedSeconds > 0 ? 1 : 0)
        return Card {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                W.t("plan.total_label").font(TTFont.label).foregroundStyle(TT.textSecondary)
                W.t("plan.total_text", DurationFormat.hoursMinutes(totals.plannedSeconds), DurationFormat.hoursMinutes(totals.targetSeconds))
                    .font(TTFont.stat).foregroundStyle(TT.textPrimary).lineLimit(2).minimumScaleFactor(0.6).accessibilityIdentifier("plan.total")
                ProgressBar(progress: progress)
                StatusChip(verbatim: differenceText(totals.differenceSeconds), tone: totals.differenceSeconds == 0 ? .success : (totals.differenceSeconds < 0 ? .warning : .accent))
                Text(verbatim: suggestionText).font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func differenceText(_ seconds: Int) -> String {
        seconds == 0 ? W.s("plan.diff_equal") : W.s(seconds < 0 ? "plan.diff_under" : "plan.diff_over", DurationFormat.hoursMinutes(abs(seconds)))
    }

    private var suggestionText: String {
        let s = store.suggestion
        return s.source == .history ? W.s("plan.suggestion_history", s.start, s.end, s.breakMinutes) : W.s("plan.suggestion_fallback", s.start, s.breakMinutes)
    }

    // MARK: Quick actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            SectionHeader("wk.plan.actions")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 150), spacing: TT.Space.s)], spacing: TT.Space.s) {
                Button { notice = nil; store.applyStandard() } label: { W.t("plan.action_standard") }.accessibilityIdentifier("plan.standard")
                Button { Task { await copy() } } label: { W.t("plan.action_copy") }.accessibilityIdentifier("plan.copy")
                Button { notice = nil; store.applySame() } label: { W.t("plan.action_same") }.accessibilityIdentifier("plan.same")
                Button { notice = nil; store.applyClear() } label: { W.t("plan.action_clear") }.accessibilityIdentifier("plan.clear")
            }
            .buttonStyle(.ttSecondary)
        }
    }

    private func copy() async {
        switch await store.copyLastWeek() {
        case .copied: notice = nil
        case .emptySource: notice = "wk.week.copy_empty"
        case .failed: break
        }
    }

    // MARK: Rows

    @ViewBuilder private var rows: some View {
        let content = ForEach(Array(store.days.enumerated()), id: \.element.id) { index, day in
            if store.drafts.indices.contains(index) {
                PlanDayRow(day: day, draft: store.drafts[index], problem: store.showProblems ? store.problem(at: index) : nil, calendar: store.calendar,
                           onMode: { store.setMode(index, $0) }, onChange: { store.update(index, $0) })
            }
        }
        if wide {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: TT.Space.m, alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: TT.Space.m) { content }
        } else {
            VStack(spacing: TT.Space.m) { content }
        }
    }

    // MARK: Save bar

    private var dirtyLabel: some View {
        W.t(store.isDirty ? "plan.dirty" : "plan.clean").font(TTFont.meta).foregroundStyle(store.isDirty ? TT.warning : TT.textSecondary)
            .accessibilityIdentifier("plan.dirty_state")
    }

    @ViewBuilder private var saveButtons: some View {
        if store.isDirty { Button { notice = nil; store.discard() } label: { W.t("plan.discard") }.buttonStyle(.ttSecondary).frame(maxWidth: 150).accessibilityIdentifier("plan.discard") }
        Button { Task { await store.save() } } label: { W.t(store.isSaving ? "plan.saving" : "plan.save") }
            .buttonStyle(.ttPrimary).frame(maxWidth: 200).disabled(!store.isDirty || store.isSaving).accessibilityIdentifier("plan.save")
    }

    private var saveBar: some View {
        VStack(spacing: TT.Space.xs) {
            if store.error != nil || store.showProblems && store.hasProblem {
                if store.showProblems && store.hasProblem { W.t("plan.fix_problems").font(TTFont.meta).foregroundStyle(TT.danger) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TT.Space.m) { dirtyLabel.fixedSize(); Spacer(minLength: 0); saveButtons }
                VStack(alignment: .leading, spacing: TT.Space.s) { dirtyLabel; HStack(spacing: TT.Space.m) { saveButtons } }
            }
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .opacity(store.week == nil ? 0 : 1)
    }
}

private struct PlanDayRow: View {
    let day: PlanWeekDay
    let draft: DayDraft
    let problem: DraftProblem?
    let calendar: DayCalendar
    let onMode: (PlanMode?) -> Void
    let onChange: (DayDraft) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var planned: Int? { day.isBlocked ? 0 : WeekPlan.plannedSeconds(draft) }
    private var timed: Bool { draft.mode != nil && draft.mode != .off }

    var body: some View {
        Card(padding: TT.Space.m) {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: weekDayTitle(day.date, calendar: calendar)).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                    Spacer(minLength: TT.Space.s)
                    if day.targetSeconds > 0 { W.t("plan.day_target", DurationFormat.hoursMinutes(day.targetSeconds)).font(TTFont.meta).foregroundStyle(TT.textSecondary) }
                }
                if let blocked = day.blockedBy {
                    HStack(alignment: .top, spacing: TT.Space.xs) {
                        Image(systemName: "lock.fill").imageScale(.small).foregroundStyle(TT.textSecondary).accessibilityHidden(true)
                        Text(verbatim: blocked.label + (day.plan != nil ? " " + W.s("blocked.kept") : "")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    }
                }
                modePicker
                if timed {
                    times
                    TextField(W.s("plan.note"), text: Binding(get: { draft.note }, set: { var d = draft; d.note = String($0.prefix(200)); onChange(d) }))
                        .ttField().accessibilityIdentifier("plan.note.\(day.date)")
                }
                if let problem { Label { W.t(problemKey(problem)) } icon: { Image(systemName: "exclamationmark.triangle.fill") }.font(TTFont.meta).foregroundStyle(TT.danger) }
                if timed, let planned, !day.isBlocked {
                    W.t("plan.planned_hours", DurationFormat.hoursMinutes(planned)).font(TTFont.numeral).foregroundStyle(TT.textPrimary)
                }
            }
        }
        .overlay { if problem != nil { RoundedRectangle(cornerRadius: TT.Radius.card, style: .continuous).strokeBorder(TT.danger, lineWidth: 1.5) } }
        .accessibilityIdentifier("plan.row.\(day.date)")
    }

    private func problemKey(_ problem: DraftProblem) -> String {
        switch problem {
        case .timesRequired: "plan.problem.times"
        case .endBeforeStart: "plan.problem.order"
        case .breakInvalid: "plan.problem.break"
        }
    }

    private var modePicker: some View {
        HStack {
            W.t("plan.mode").font(TTFont.label).foregroundStyle(TT.textSecondary)
            Spacer(minLength: TT.Space.s)
            Menu {
                Button { onMode(nil) } label: { W.t("plan.mode_none") }
                ForEach(PlanMode.selectable, id: \.self) { mode in
                    Button { onMode(mode) } label: { Label(mode.plainName, systemImage: mode.symbol) }
                }
            } label: {
                HStack(spacing: 6) {
                    if let mode = draft.mode, mode != .unknown { Image(systemName: mode.symbol).foregroundStyle(mode.tint) }
                    Text(verbatim: draft.mode.flatMap { $0 == .unknown ? nil : $0.plainName } ?? W.s("plan.mode_none"))
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("plan.mode.\(day.date)")
        }
    }

    private var times: some View {
        VStack(alignment: .leading, spacing: TT.Space.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TT.Space.m) { startPicker.fixedSize(); endPicker.fixedSize() }
                VStack(alignment: .leading, spacing: TT.Space.xs) { startPicker; endPicker }
            }
            Stepper(value: Binding(get: { draft.breakMinutes }, set: { var d = draft; d.breakMinutes = $0; onChange(d) }), in: 0...WeekPlan.maxBreakMinutes, step: 5) {
                W.t("plan.break", draft.breakMinutes).font(TTFont.body).monospacedDigit()
            }
            .frame(minHeight: 44)
        }
    }

    private var startPicker: some View {
        clockPicker("plan.start", value: draft.start, fallback: 8 * 60) { var d = draft; d.start = WeekPlan.formatClock($0); onChange(d) }
    }

    private var endPicker: some View {
        clockPicker("plan.end", value: draft.end, fallback: 16 * 60) { var d = draft; d.end = WeekPlan.formatClock($0); onChange(d) }
    }

    private func clockPicker(_ label: String, value: String, fallback: Int, set: @escaping (Int) -> Void) -> some View {
        HStack {
            W.t(label).font(TTFont.label).foregroundStyle(TT.textSecondary).lineLimit(1)
            DatePicker("", selection: Binding(get: { ClockPicker.date(minutes: WeekPlan.parseClock(value) ?? fallback) }, set: { set(ClockPicker.minutes(of: $0)) }),
                       displayedComponents: .hourAndMinute)
                .labelsHidden().environment(\.timeZone, ClockPicker.timeZone).environment(\.locale, Locale(identifier: "de_DE"))
                .opacity(value.isEmpty ? 0.5 : 1)
                .accessibilityLabel(W.t(label))
        }
        .frame(minHeight: 44)
    }
}
