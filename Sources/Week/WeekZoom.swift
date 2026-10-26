#if os(iOS)
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// Z2: the week zoom of the "Zeit" screen: strip of the seven days, week summary, day sections with their entries.

/// What a day section can do. The month zoom offers the same actions as buttons below the day; both end in the same sheets.
struct DayActions {
    var add: (LocalDay) -> Void
    var edit: (Segment, LocalDay) -> Void
    var void: (Segment, LocalDay) -> Void
    var absence: (AbsenceKind, LocalDay) -> Void
    var plan: (LocalDay) -> Void
    var customDay: (LocalDay) -> Void
}

/// The seven days of the week as a strip: the anchor day is marked, a tap moves the anchor (and scrolls the list to it).
struct WeekStrip: View {
    let weekStart: LocalDay
    let days: [DayEvaluation]
    let selected: LocalDay
    let today: LocalDay
    let namespace: Namespace.ID
    let select: (LocalDay) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let day = LocalDays.adding(offset, to: weekStart) ?? weekStart
                let isSelected = day == selected
                let isToday = day == today
                let mark = days.first { $0.date == day }?.mark
                VStack(spacing: 4) {
                    Text(verbatim: String(PlanFormat.weekdayHeaders[offset].prefix(2))).font(TTFont.eyebrow).foregroundStyle(TT.textTertiary)
                    Text(verbatim: String(LocalDays.parse(day)?.day ?? 0))
                        .font(.system(.title3, weight: isSelected || isToday ? .semibold : .regular)).monospacedDigit()
                        .frame(width: 36, height: 36)
                        .foregroundStyle(isSelected ? (isToday ? Color.white : TT.surface) : (isToday ? Color.accentColor : ((LocalDays.isoWeekday(day) ?? 1) >= 6 ? TT.textSecondary : TT.textPrimary)))
                        .background {
                            if isSelected { Circle().fill(isToday ? Color.accentColor : TT.textPrimary).matchedGeometryEffect(id: "selection", in: namespace) }
                        }
                    Circle().fill(mark.map { markDot($0) } ?? .clear).frame(width: 6, height: 6)
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture { select(day) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: MonthDayCell.longDay(day)))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("strip.\(day)")
            }
        }
    }

    private func markDot(_ mark: DayMarkKind) -> Color {
        switch mark {
        case .unmarked, .unknown: .clear
        default: markTint(mark)
        }
    }
}

/// The days of the shown week with their entries (the Erfassungs- und Korrekturansicht), led by the week summary.
struct WeekDayList: View {
    let store: TimeListStore
    let week: WeekStore?
    let selected: LocalDay
    let canPlan: Bool
    let canAct: Bool
    let startPlanning: () -> Void
    let actions: DayActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            List {
                WeekSummaryCard(store: store, week: week, canPlan: canPlan, startPlanning: startPlanning)
                    .listRowBackground(Color.clear).listRowInsets(.init(top: 0, leading: 0, bottom: 4, trailing: 0)).listRowSeparator(.hidden)
                if let error = store.error {
                    ErrorBannerView(error: error) { Task { await store.load() } }
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                if store.days.isEmpty && store.isLoading {
                    SkeletonList(rows: 3).listRowBackground(Color.clear).listRowInsets(.init()).listRowSeparator(.hidden)
                }
                ForEach(store.days) { day in
                    let compactEmpty = day.isPlainEmpty
                    Section {
                        // One ForEach with stable unique ids per section (no static row next to it): keeps the List diff consistent.
                        ForEach(compactEmpty ? [] : day.timeRows) { row in
                            switch row {
                            case .empty:
                                EmptyDayRow(day: day).listRowInsets(.init()).listRowBackground(TT.surface)
                            case .segment(let segment, _):
                                SegmentRow(segment: segment, zone: store.calendar.timeZone)
                                    .onTapGesture { actions.edit(segment, day.date) }
                                    .listRowInsets(.init()).listRowBackground(TT.surface)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("time.void") { actions.void(segment, day.date) }.tint(.red)
                                        Button("time.edit") { actions.edit(segment, day.date) }.tint(.accentColor)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        if segment.needsReview && !segment.isRunning {
                                            Button { Task { await store.acknowledge(segment) } } label: { Label(p15Key("review.acknowledge.short"), systemImage: "checkmark.seal") }.tint(.green)
                                        }
                                    }
                                    .accessibilityAction(named: Text("time.edit")) { actions.edit(segment, day.date) }
                                    .accessibilityAction(named: Text("time.void")) { actions.void(segment, day.date) }
                                    .accessibilityActions {
                                        if segment.needsReview && !segment.isRunning {
                                            Button(p15("review.acknowledge")) { Task { await store.acknowledge(segment) } }
                                        }
                                    }
                            }
                        }
                    } header: {
                        DayHeader(day: day, calendar: store.calendar, isToday: day.date == store.calendar.day(for: .now), isFuture: day.date > store.calendar.day(for: .now), isSelected: day.date == selected, isEmpty: compactEmpty,
                                  plan: week?.week?.days.first { $0.date == day.date }, canAct: canAct, actions: actions)
                    } footer: {
                        // P15: informative warnings and school lessons live in the footer, outside the row diff of the section.
                        if day.hasLegalNotes {
                            LegalDayNotes(day: day) { await store.setSchoolLessons($0, on: day.date) }
                                .padding(.top, TT.Space.xs)
                        }
                    }
                    .id(day.date)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(TT.Space.s)
            .contentMargins(.top, TT.Space.xs, for: .scrollContent)
            // Data refreshes must not compete with row animations (A9: crash in the collection view's batch update).
            .transaction(value: store.days) { $0.animation = nil }
            .refreshable { await store.load(); await week?.load(); TTHaptics.play(.softTap) }
            .onChange(of: selected) { _, day in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { proxy.scrollTo(day, anchor: .top) }
            }
        }
    }
}

/// Week figures once: actual against target with progress; the balance (Zeitkonto, target to date, plan, averages) unfolds below.
struct WeekSummaryCard: View {
    let store: TimeListStore
    let week: WeekStore?
    let canPlan: Bool
    let startPlanning: () -> Void
    @State private var expanded = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let done = store.weekEvaluatedSeconds
        let target = store.weekTargetSeconds
        Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                ProgressBar(progress: target > 0 ? Double(done) / Double(target) : 0)
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: TT.Space.xs)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                layout {
                    Text(verbatim: DurationFormat.hoursMinutes(done)).font(TTFont.stat).foregroundStyle(TT.textPrimary).lineLimit(1).minimumScaleFactor(0.5)
                    Text("time.of_target \(DurationFormat.hoursMinutes(target))").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    if !typeSize.isAccessibilitySize { Spacer() }
                    if target > 0 { weekChip(done: done, target: target) }
                }
                .accessibilityElement(children: .combine)
                if expanded, let loaded = week?.week {
                    Divider()
                    WeekBalanceDetails(week: loaded).transition(.opacity.combined(with: .move(edge: .top)))
                } else if expanded, week?.isUnavailable == true {
                    HintBanner("wk.week.unavailable")
                }
                ViewThatFits(in: .horizontal) { footer(spacing: TT.Space.m, vertical: false); footer(spacing: TT.Space.xs, vertical: true) }
            }
        }
    }

    @ViewBuilder private func footer(spacing: CGFloat, vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
        layout {
            Group {
                Button { withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { expanded.toggle() } } label: {
                        HStack(spacing: 4) {
                            Z2.t(expanded ? "balance.hide" : "balance.show")
                            Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0)).imageScale(.small)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    .accessibilityIdentifier("time.week_details")
                    Spacer()
                    if canPlan {
                        Button(action: startPlanning) { Label(W.s("segment.plan"), systemImage: "calendar.badge.checkmark").frame(minHeight: 44) }
                            .buttonStyle(.borderless).font(TTFont.meta).accessibilityIdentifier("week.plan")
                    }
            }
        }
    }
}

extension WeekSummaryCard {
    /// F10: a week that is not over yet is not "behind": show what is left in a neutral tone; only a finished week warns.
    @ViewBuilder fileprivate func weekChip(done: Int, target: Int) -> some View {
        let over = store.weekEnd < store.calendar.day(for: .now)
        if over || done >= target {
            StatusChip(verbatim: DurationFormat.signed(done - target), tone: deltaTone(done - target))
        } else {
            StatusChip(verbatim: Z2.s("week.open_left \(DurationFormat.hoursMinutes(target - done))"), tone: .neutral)
        }
    }
}

extension DayEvaluation {
    /// No entries and no mark: shown as one compact line in the header instead of a card.
    var isPlainEmpty: Bool {
        guard timeRows.count == 1, case .empty = timeRows[0] else { return false }
        return mark == nil || mark == .unmarked || mark == .unknown
    }
}

struct EmptyDayRow: View {
    let day: DayEvaluation

    var body: some View {
        HStack(spacing: TT.Space.m) {
            if let mark = day.mark, mark != .unmarked, mark != .unknown {
                KindGlyph(symbol: markSymbol(mark), tint: markTint(mark))
                Text(markKey(mark)).font(TTFont.body).foregroundStyle(TT.textPrimary)
            } else {
                Text("time.no_entries").font(TTFont.body).foregroundStyle(TT.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        .accessibilityElement(children: .combine)
    }
}

/// Section header of one day: title, plan line, actual/target, and the day's actions.
struct DayHeader: View {
    let day: DayEvaluation
    let calendar: DayCalendar
    let isToday: Bool
    let isFuture: Bool
    let isSelected: Bool
    let isEmpty: Bool
    let plan: TimeWeekDay?
    let canAct: Bool
    let actions: DayActions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let done = day.evaluatedWorkSeconds + day.creditSeconds
        let delta = DayDeltaPolicy.presentation(day: day.date, today: calendar.day(for: .now), doneSeconds: done,
                                                targetSeconds: day.targetSeconds, hasStarted: !(day.segments ?? []).isEmpty)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: TT.Space.xs)) : AnyLayout(HStackLayout(alignment: .center, spacing: TT.Space.s))
        layout {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: dayTitle(day.date, calendar: calendar)).font(TTFont.cardTitle).foregroundStyle(isSelected ? Color.accentColor : TT.textPrimary)
                    if isToday { StatusChip("time.today", tone: .accent) }
                }
                if let label = plan?.holidayLabel {
                    Label { Text(verbatim: label) } icon: { Image(systemName: "party.popper.fill").foregroundStyle(TT.kindHoliday) }
                        .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
                if let line = planLine { Text(verbatim: line).font(TTFont.meta).foregroundStyle(TT.textSecondary) }
                if isEmpty { Text(Z2.s("day.empty")).font(TTFont.meta).foregroundStyle(TT.textTertiary) }
                if day.provisional { Text("common.provisional").font(.caption2).foregroundStyle(TT.textSecondary) }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: TT.Space.xs) }
            if isFuture || (isEmpty && done == 0 && isToday) {
                if day.targetSeconds > 0 { Text(Z2.s("day.target_only \(DurationFormat.hoursMinutes(day.targetSeconds))")).font(TTFont.numeralSmall).foregroundStyle(TT.textTertiary) }
            } else if day.targetSeconds > 0 || done > 0 {
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                    Text("time.day_total \(DurationFormat.hoursMinutes(done)) \(DurationFormat.hoursMinutes(day.targetSeconds))")
                        .font(TTFont.numeralSmall).foregroundStyle(TT.textSecondary)
                    switch delta {
                    case .hidden: EmptyView()
                    case .open(let seconds):
                        Text(Z2.s("week.open_left \(DurationFormat.hoursMinutes(seconds))"))
                            .font(TTFont.numeralSmall).foregroundStyle(TT.textSecondary)
                    case .deficit(let seconds):
                        Text(verbatim: DurationFormat.signed(-seconds))
                            .font(TTFont.numeralSmall.weight(.semibold)).foregroundStyle(TT.warning)
                    case .surplus(let seconds):
                        Text(verbatim: DurationFormat.signed(seconds))
                            .font(TTFont.numeralSmall.weight(.semibold)).foregroundStyle(TT.success)
                    }
                }
            }
            actionMenu
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }

    /// "Büro · 8 Std. 24 Min. geplant" next to the actual time, so planned and recorded sit in one place.
    private var planLine: String? {
        guard let plan, plan.planMode != nil || plan.plannedSeconds != nil else { return nil }
        var parts: [String] = []
        if let mode = plan.planMode, mode != .unknown, mode != .off { parts.append(mode.plainName) }
        if let seconds = plan.plannedSeconds, seconds > 0 { parts.append(W.s("day.plan", DurationFormat.hoursMinutes(seconds))) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var actionMenu: some View {
        let title = dayTitle(day.date, calendar: calendar)
        if canAct {
            Menu {
                Button { actions.add(day.date) } label: { Label("plan.short.segment", systemImage: "clock.badge.plus") }
                Button { actions.plan(day.date) } label: { Label("plan.action.plan", systemImage: "calendar.badge.checkmark") }
                ForEach(AbsenceKind.selectable, id: \.self) { kind in
                    Button { actions.absence(kind, day.date) } label: { Label(kind.actionKey, systemImage: kind.ttSymbol) }
                }
                Button { actions.customDay(day.date) } label: { Label("plan.short.custom_day", systemImage: "flag") }
            } label: { Image(systemName: "plus.circle.fill").imageScale(.large).symbolRenderingMode(.hierarchical).frame(minWidth: 32, minHeight: 32) }
                .accessibilityLabel(Text("time.add_to_day \(title)")).accessibilityIdentifier("time.add.\(day.date)")
        } else {
            Button { actions.add(day.date) } label: { Image(systemName: "plus.circle.fill").imageScale(.large).symbolRenderingMode(.hierarchical) }
                .buttonStyle(.borderless).accessibilityLabel(Text("time.add_to_day \(title)"))
        }
    }
}
#endif
