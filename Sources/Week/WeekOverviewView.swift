import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// "Woche" overview: summary of one ISO week and a card per day with planned versus actual time.
struct WeekOverviewView: View {
    let store: WeekStore
    let planningEnabled: Bool
    let openPlanner: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    private var wide: Bool { sizeClass == .regular && !typeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                WeekNavigator(weekNumber: store.weekNumber, monday: store.monday, sunday: store.sunday, calendar: store.calendar, isCurrent: store.isCurrentWeek,
                              previous: { Task { await store.shiftWeeks(-1) } }, next: { Task { await store.shiftWeeks(1) } },
                              current: { Task { await store.goToCurrentWeek() } })
                if let error = store.error { WeekErrorBanner(error: error) { Task { await store.load() } } }
                if store.isUnavailable {
                    HintBanner("wk.week.unavailable")
                } else if let week = store.week {
                    summary(week)
                    if WeekOverview.isEmpty(week.days) {
                        Card { EmptyState(symbol: "calendar", title: "wk.week.empty_title", message: "wk.week.empty_text") }
                        if planningEnabled { Button { openPlanner() } label: { W.t("empty.plan") }.buttonStyle(.ttSecondary).accessibilityIdentifier("week.open_planner") }
                    } else if wide {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: TT.Space.m, alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: TT.Space.m) {
                            ForEach(week.days) { DayCard(day: $0, calendar: store.calendar) }
                        }
                    } else {
                        VStack(spacing: TT.Space.m) { ForEach(week.days) { DayCard(day: $0, calendar: store.calendar) } }
                    }
                } else if store.isLoading {
                    SkeletonList(rows: 4)
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: wide ? 1100 : TT.contentWidth).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    @ViewBuilder private func summary(_ week: TimeWeek) -> some View {
        let s = week.summary
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Card {
                VStack(alignment: .leading, spacing: TT.Space.m) {
                    let columns = [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 140), spacing: TT.Space.m, alignment: .top)]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: TT.Space.m) {
                        SummaryTile(title: W.s("sum.actual"), value: DurationFormat.hoursMinutes(s.hoursSeconds), caption: W.s("sum.actual_hint"))
                        SummaryTile(title: W.s("sum.target"), value: DurationFormat.hoursMinutes(s.targetSeconds), caption: s.targetToDateSeconds < s.targetSeconds ? W.s("sum.target_to_date", DurationFormat.hoursMinutes(s.targetToDateSeconds)) : W.s("sum.target_full"))
                        SummaryTile(title: W.s("sum.balance"), value: DurationFormat.signed(s.balanceSeconds), caption: W.s(s.targetToDateSeconds < s.targetSeconds ? "sum.balance_running" : "sum.balance_past"),
                                    tint: s.balanceSeconds < 0 ? TT.warning : (s.balanceSeconds > 0 ? TT.success : TT.textPrimary))
                        SummaryTile(title: W.s("sum.account"), value: DurationFormat.signed(s.accountBalanceAfterSeconds), caption: W.s("sum.account_before", DurationFormat.signed(s.accountBalanceBeforeSeconds)))
                    }
                    if let comparison = WeekOverview.planComparison(week.days) {
                        Divider()
                        W.t("sum.plan_line", DurationFormat.hoursMinutes(comparison.planned), DurationFormat.hoursMinutes(comparison.actual)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    }
                }
            }
            sentenceRow(s)
        }
        .accessibilityIdentifier("week.summary")
    }

    @ViewBuilder private func sentenceRow(_ s: TimeWeekSummary) -> some View {
        let notable = WeekOverview.noteworthy(s)
        if !notable.isEmpty || s.provisional || s.averageStart != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TT.Space.s) { chips(s, notable) }
                VStack(alignment: .leading, spacing: TT.Space.s) { chips(s, notable) }
            }
        }
    }

    @ViewBuilder private func chips(_ s: TimeWeekSummary, _ notable: [(mark: WeekMark, count: Double)]) -> some View {
        ForEach(notable, id: \.mark) { item in
            StatusChip(verbatim: W.s(item.count == 1 ? "chip.\(item.mark.rawValue).one" : "chip.\(item.mark.rawValue).other", weekDecimal(item.count)), tone: .custom(item.mark.tint), symbol: item.mark.symbol)
        }
        if let start = s.averageStart, let end = s.averageEnd { StatusChip(verbatim: W.s("chip.average", start, end), tone: .neutral, symbol: "clock") }
        if s.provisional { StatusChip(verbatim: W.s("day.provisional"), tone: .warning) }
    }
}

struct DayCard: View {
    let day: TimeWeekDay
    let calendar: DayCalendar
    @Environment(\.dynamicTypeSize) private var typeSize

    private var showsActual: Bool { !day.isFuture }
    private var zone: TimeZone { calendar.timeZone }

    var body: some View {
        Card(padding: TT.Space.m) {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                header
                if day.mark == .work || day.mark == .school || day.mark == .off && (day.hoursSeconds > 0 || day.plannedSeconds != nil) {
                    figures
                    bars
                    footer
                } else {
                    // Vacation, sick, holiday, excused: the mark is the story; credited hours still count.
                    if day.hoursSeconds > 0 { Text(verbatim: DurationFormat.hoursMinutes(day.hoursSeconds)).font(TTFont.numeral).foregroundStyle(TT.textSecondary) }
                    if let planned = day.plannedSeconds, planned > 0 { W.t("day.plan", DurationFormat.hoursMinutes(planned)).font(TTFont.meta).foregroundStyle(TT.textSecondary) }
                    absenceNotes
                }
            }
        }
        .overlay { if day.isToday { RoundedRectangle(cornerRadius: TT.Radius.card, style: .continuous).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityIdentifier("week.day.\(day.date)")
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: TT.Space.xs)) : AnyLayout(HStackLayout(spacing: TT.Space.s))
        return layout {
            KindGlyph(symbol: day.mark.symbol, tint: day.mark.tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: weekDayTitle(day.date, calendar: calendar)).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                Text(verbatim: day.mark.label).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: TT.Space.xs) }
            if day.isToday { StatusChip(verbatim: W.s("day.today"), tone: .accent) }
        }
    }

    private var figures: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: TT.Space.s))
        return layout {
            if showsActual {
                Text(verbatim: DurationFormat.hoursMinutes(day.hoursSeconds)).font(TTFont.statSmall).foregroundStyle(TT.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
            } else if let planned = day.plannedSeconds {
                Text(verbatim: DurationFormat.hoursMinutes(planned)).font(TTFont.statSmall).foregroundStyle(TT.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
            } else {
                W.t("day.future").font(TTFont.meta).foregroundStyle(TT.textTertiary)
            }
            if day.targetSeconds > 0 { W.t("day.target", DurationFormat.hoursMinutes(day.targetSeconds)).font(TTFont.meta).foregroundStyle(TT.textSecondary) }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if showsActual, let balance = day.balanceSeconds, day.targetSeconds > 0 || balance != 0 {
                StatusChip(verbatim: DurationFormat.signed(balance), tone: deltaTone(balance))
            }
        }
    }

    @ViewBuilder private var bars: some View {
        let shares = WeekOverview.barShares(day)
        if showsActual && day.hoursSeconds > 0 || WeekOverview.showsPlan(day) || day.targetSeconds > 0 {
            VStack(spacing: 4) {
                if showsActual { ProgressBar(progress: shares.actual, height: 8) }
                if WeekOverview.showsPlan(day) { ProgressBar(progress: shares.planned, tint: TT.kindTravel, height: 5) }
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsActual, let start = day.firstStart, let end = day.lastEnd {
                W.t("day.span", start.clockText(in: zone), end.clockText(in: zone)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            } else if showsActual && day.segmentsCount == 0 && day.targetSeconds > 0 {
                W.t("day.no_work").font(TTFont.meta).foregroundStyle(TT.textTertiary)
            }
            if day.plannedSeconds != nil || day.planMode != nil {
                HStack(spacing: 4) {
                    if let mode = day.planMode, mode != .off, mode != .unknown { Image(systemName: mode.symbol).imageScale(.small).foregroundStyle(mode.tint).accessibilityHidden(true) }
                    if let mode = day.planMode, mode != .unknown { Text(verbatim: mode.plainName) }
                    if let planned = day.plannedSeconds { W.t(day.planMode == nil ? "day.plan" : "day.plan_dot", DurationFormat.hoursMinutes(planned)) }
                }
                .font(TTFont.meta).foregroundStyle(TT.textSecondary).lineLimit(2)
            }
            if day.provisional && showsActual { W.t("day.provisional").font(.caption2).foregroundStyle(TT.warning) }
            absenceNotes
        }
    }

    @ViewBuilder private var absenceNotes: some View {
        ForEach(Array(day.absences.enumerated()), id: \.offset) { _, absence in
            if absence.halfDay { W.t("day.half_day", absence.kind.plainName).font(TTFont.meta).foregroundStyle(TT.textSecondary) }
        }
    }

    private var accessibilityText: String {
        var parts = [weekDayTitle(day.date, calendar: calendar), day.mark.label]
        if day.isFuture {
            if let planned = day.plannedSeconds { parts.append(W.s("aria.planned", DurationFormat.hoursMinutes(planned))) }
        } else {
            parts.append(W.s("aria.hours", DurationFormat.hoursMinutes(day.hoursSeconds)))
            if let balance = day.balanceSeconds { parts.append(W.s("aria.balance", DurationFormat.signed(balance))) }
        }
        if let mode = day.planMode, mode != .unknown { parts.append(mode.plainName) }
        return parts.joined(separator: ", ")
    }
}
