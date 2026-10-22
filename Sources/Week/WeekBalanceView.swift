import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Z2: the week's balance (Zeitkonto, target to date, plan against actual, averages, absence counts) as the expandable part of the
/// week header of the "Zeit" screen. Previously a separate screen that repeated the week list's days and sums; the figures that only
/// this view has are all that remain.
struct WeekBalanceDetails: View {
    let week: TimeWeek
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let s = week.summary
        VStack(alignment: .leading, spacing: TT.Space.m) {
            let columns = [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 140), spacing: TT.Space.m, alignment: .top)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: TT.Space.m) {
                SummaryTile(title: W.s("sum.target"), value: DurationFormat.hoursMinutes(s.targetSeconds), caption: s.targetToDateSeconds < s.targetSeconds ? W.s("sum.target_to_date", DurationFormat.hoursMinutes(s.targetToDateSeconds)) : W.s("sum.target_full"))
                SummaryTile(title: W.s("sum.balance"), value: DurationFormat.signed(s.balanceSeconds), caption: W.s(s.targetToDateSeconds < s.targetSeconds ? "sum.balance_running" : "sum.balance_past"),
                            tint: s.balanceSeconds < 0 ? TT.warning : (s.balanceSeconds > 0 ? TT.success : TT.textPrimary))
                SummaryTile(title: W.s("sum.account"), value: DurationFormat.signed(s.accountBalanceAfterSeconds), caption: W.s("sum.account_before", DurationFormat.signed(s.accountBalanceBeforeSeconds)))
            }
            if let comparison = WeekOverview.planComparison(week.days) {
                W.t("sum.plan_line", DurationFormat.hoursMinutes(comparison.planned), DurationFormat.hoursMinutes(comparison.actual)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
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
