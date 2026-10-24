import Charts
import SwiftUI
import TimetrackCore
import TimetrackDesign

private let chartHeight: CGFloat = 220

private func xAxis(_ granularity: StatisticsGranularity) -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: 5)) { value in
        AxisGridLine()
        AxisValueLabel(collisionResolution: .greedy(priority: 0)) {
            if let date = value.as(Date.self) { Text(verbatim: StatsFormat.axisLabel(date, granularity)) }
        }
    }
}

private func hoursAxis(signed: Bool = false) -> some AxisContent {
    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine()
        AxisValueLabel {
            if let hours = value.as(Double.self) { Text(verbatim: StatsFormat.hoursLabel(hours, signed: signed)) }
        }
    }
}

// MARK: - Zeitkonto-Verlauf

struct BalanceChartCard: View {
    let data: StatisticsChartData
    @Environment(\.ttTheme) private var theme
    @State private var selection: Date?

    private var granularity: StatisticsGranularity { data.granularity }
    private var summary: String {
        guard let first = data.balance.first, let last = data.balance.last, data.balance.count >= 2 else { return wm("wm.stats.balance_none") }
        return wm("wm.stats.balance_summary \(StatsFormat.signed(first.seconds)) \(StatsFormat.signed(last.seconds)) \(StatsFormat.signed(last.seconds - first.seconds))")
    }

    var body: some View {
        ChartCard(title: wm("wm.stats.balance"), summary: summary, id: "stats.balance",
                  rows: data.balance.map { (WorkModelCard.display($0.day), StatsFormat.signed($0.seconds)) }) {
            if data.hasBalance {
                Chart {
                    ForEach(data.balance) { point in
                        AreaMark(x: .value("Datum", point.date), y: .value("Zeitkonto", StatsFormat.hours(point.seconds)))
                            .foregroundStyle(LinearGradient(colors: [theme.accent.opacity(0.28), theme.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Datum", point.date), y: .value("Zeitkonto", StatsFormat.hours(point.seconds)))
                            .foregroundStyle(theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        if data.balance.count <= 40 {
                            PointMark(x: .value("Datum", point.date), y: .value("Zeitkonto", StatsFormat.hours(point.seconds)))
                                .foregroundStyle(theme.accent).symbolSize(28)
                        }
                    }
                    RuleMark(y: .value("Null", 0)).foregroundStyle(TT.textTertiary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    if let selection, let point = data.balancePoint(near: selection) {
                        RuleMark(x: .value("Auswahl", point.date)).foregroundStyle(TT.textTertiary.opacity(0.6))
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                SelectionCallout(title: WorkModelCard.display(point.day), lines: [StatsFormat.signed(point.seconds)])
                            }
                    }
                }
                .chartXSelection(value: $selection)
                .chartXAxis { xAxis(granularity) }
                .chartYAxis { hoursAxis(signed: true) }
                .frame(height: chartHeight)
                .accessibilityChartDescriptor(descriptor)
            } else {
                Text(wmKey("wm.stats.balance_none")).font(TTFont.meta).foregroundStyle(TT.textSecondary).frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    private var descriptor: StatsChartDescriptor {
        StatsChartDescriptor(title: wm("wm.stats.balance"), summary: summary, categories: data.balance.map { WorkModelCard.display($0.day) }, yTitle: "Zeitkonto",
                             series: [.init(name: "Zeitkonto", values: data.balance.map { StatsFormat.hours($0.seconds) }, isContinuous: true)],
                             spokenValue: { StatsFormat.spoken(Int($0 * 3600)) })
    }
}

// MARK: - Soll gegen Ist

struct TargetActualChartCard: View {
    let data: StatisticsChartData
    @Environment(\.ttTheme) private var theme
    @State private var selection: Date?

    private var granularity: StatisticsGranularity { data.granularity }
    private var totals: StatisticsTotals { data.statistics.totals }
    private var summary: String {
        wm("wm.stats.target_actual_summary \(StatsFormat.hm(totals.targetToDateSeconds)) \(StatsFormat.hm(totals.workedSeconds))")
    }

    var body: some View {
        ChartCard(title: wm("wm.stats.target_actual"), summary: summary, id: "stats.target",
                  rows: data.performance.map { ($0.bucket.longTitle(granularity: granularity), wm("wm.stats.row_target_actual \(StatsFormat.hm($0.targetSeconds)) \(StatsFormat.hm($0.workedSeconds))")) }) {
            Chart {
                ForEach(data.performance) { point in
                    BarMark(x: .value("Zeitraum", point.date, unit: StatsFormat.unit(granularity)), y: .value("Stunden", StatsFormat.hours(point.targetSeconds)))
                        .foregroundStyle(by: .value("Reihe", wm("wm.stats.series_target")))
                        .position(by: .value("Reihe", wm("wm.stats.series_target")))
                    BarMark(x: .value("Zeitraum", point.date, unit: StatsFormat.unit(granularity)), y: .value("Stunden", StatsFormat.hours(point.workedSeconds)))
                        .foregroundStyle(by: .value("Reihe", wm("wm.stats.series_worked")))
                        .position(by: .value("Reihe", wm("wm.stats.series_worked")))
                }
                if let selection, let bucket = data.bucket(near: selection) {
                    RuleMark(x: .value("Auswahl", bucket.startDate, unit: StatsFormat.unit(granularity)))
                        .foregroundStyle(TT.textTertiary.opacity(0.35))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            SelectionCallout(title: bucket.longTitle(granularity: granularity),
                                             lines: [wm("wm.stats.callout_target \(StatsFormat.hm(bucket.targetSeconds))"), wm("wm.stats.callout_worked \(StatsFormat.hm(bucket.workedSeconds))")])
                        }
                }
            }
            .chartForegroundStyleScale([wm("wm.stats.series_target"): TT.textTertiary.opacity(0.55), wm("wm.stats.series_worked"): theme.accent])
            .chartXSelection(value: $selection)
            .chartXAxis { xAxis(granularity) }
            .chartYAxis { hoursAxis() }
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: chartHeight)
            .accessibilityChartDescriptor(descriptor)
        }
    }

    private var descriptor: StatsChartDescriptor {
        StatsChartDescriptor(title: wm("wm.stats.target_actual"), summary: summary, categories: data.performance.map { $0.bucket.longTitle(granularity: granularity) }, yTitle: "Stunden",
                             series: [.init(name: wm("wm.stats.series_target"), values: data.performance.map { StatsFormat.hours($0.targetSeconds) }, isContinuous: false),
                                      .init(name: wm("wm.stats.series_worked"), values: data.performance.map { StatsFormat.hours($0.workedSeconds) }, isContinuous: false)],
                             spokenValue: { StatsFormat.spoken(Int($0 * 3600)) })
    }
}

// MARK: - Mehr- und Minderzeit

struct DeltaChartCard: View {
    let data: StatisticsChartData
    @State private var selection: Date?

    private var granularity: StatisticsGranularity { data.granularity }
    private var totals: StatisticsTotals { data.statistics.totals }
    private var summary: String {
        wm("wm.stats.delta_summary \(StatsFormat.signed(totals.deltaSeconds)) \(StatsFormat.hm(totals.overtimeSeconds)) \(StatsFormat.hm(totals.undertimeSeconds))")
    }

    var body: some View {
        ChartCard(title: wm("wm.stats.delta"), summary: summary, id: "stats.delta",
                  rows: data.performance.map { ($0.bucket.longTitle(granularity: granularity), StatsFormat.signed($0.deltaSeconds)) }) {
            Chart {
                ForEach(data.performance) { point in
                    BarMark(x: .value("Zeitraum", point.date, unit: StatsFormat.unit(granularity)), y: .value("Stunden", StatsFormat.hours(point.deltaSeconds)))
                        .foregroundStyle(point.deltaSeconds >= 0 ? TT.success : TT.danger)
                }
                RuleMark(y: .value("Null", 0)).foregroundStyle(TT.textTertiary).lineStyle(StrokeStyle(lineWidth: 1))
                if let selection, let bucket = data.bucket(near: selection) {
                    RuleMark(x: .value("Auswahl", bucket.startDate, unit: StatsFormat.unit(granularity)))
                        .foregroundStyle(TT.textTertiary.opacity(0.35))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            SelectionCallout(title: bucket.longTitle(granularity: granularity), lines: [StatsFormat.signed(bucket.deltaSeconds)])
                        }
                }
            }
            .chartXSelection(value: $selection)
            .chartXAxis { xAxis(granularity) }
            .chartYAxis { hoursAxis(signed: true) }
            .frame(height: chartHeight)
            .accessibilityChartDescriptor(descriptor)
        }
    }

    private var descriptor: StatsChartDescriptor {
        StatsChartDescriptor(title: wm("wm.stats.delta"), summary: summary, categories: data.performance.map { $0.bucket.longTitle(granularity: granularity) }, yTitle: "Stunden",
                             series: [.init(name: wm("wm.stats.delta"), values: data.performance.map { StatsFormat.hours($0.deltaSeconds) }, isContinuous: false)],
                             spokenValue: { StatsFormat.spoken(Int($0 * 3600)) })
    }
}

// MARK: - Verteilung nach Art

struct KindChartCard: View {
    let data: StatisticsChartData

    private var total: Int { data.statistics.totals.kindSeconds.total }
    private var summary: String {
        data.kindSlices.isEmpty ? wm("wm.stats.kinds_none")
            : data.kindSlices.map { wm("wm.stats.kind_part \($0.kind.germanName) \(StatsFormat.hm($0.seconds)) \(Int(($0.share * 100).rounded()))") }.joined(separator: ", ")
    }

    var body: some View {
        ChartCard(title: wm("wm.stats.kinds"), summary: summary, id: "stats.kinds",
                  rows: data.kindSlices.map { ($0.kind.germanName, "\(StatsFormat.hm($0.seconds)) · \(Int(($0.share * 100).rounded())) %") }) {
            if data.kindSlices.isEmpty {
                Text(wmKey("wm.stats.kinds_none")).font(TTFont.meta).foregroundStyle(TT.textSecondary).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: TT.Space.xl) { donut; legend }
                    VStack(spacing: TT.Space.l) { donut; legend }
                }
                .accessibilityChartDescriptor(descriptor)
            }
        }
    }

    private var donut: some View {
        Chart(data.kindSlices) { slice in
            SectorMark(angle: .value("Zeit", slice.seconds), innerRadius: .ratio(0.62), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(slice.kind.color)
        }
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let frame = proxy.plotFrame {
                    VStack(spacing: 0) {
                        Text(verbatim: StatsFormat.hm(total)).font(TTFont.statSmall).foregroundStyle(TT.textPrimary)
                        Text(wmKey("wm.stats.kinds_total")).font(TTFont.eyebrow).foregroundStyle(TT.textSecondary)
                    }
                    .position(x: geometry[frame].midX, y: geometry[frame].midY)
                }
            }
        }
        .frame(width: 170, height: 170)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            ForEach(data.kindSlices) { slice in
                HStack(spacing: TT.Space.s) {
                    Image(systemName: slice.kind.symbol).foregroundStyle(slice.kind.color).frame(width: 22).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: slice.kind.germanName).font(TTFont.label).foregroundStyle(TT.textPrimary)
                        Text(verbatim: "\(StatsFormat.hm(slice.seconds)) · \(Int((slice.share * 100).rounded())) %").font(TTFont.numeralSmall).foregroundStyle(TT.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var descriptor: StatsChartDescriptor {
        StatsChartDescriptor(title: wm("wm.stats.kinds"), summary: summary, categories: data.kindSlices.map(\.kind.germanName), yTitle: "Stunden",
                             series: [.init(name: wm("wm.stats.kinds"), values: data.kindSlices.map { StatsFormat.hours($0.seconds) }, isContinuous: false)],
                             spokenValue: { StatsFormat.spoken(Int($0 * 3600)) })
    }
}

// MARK: - Abwesenheiten

struct AbsenceChartCard: View {
    let data: StatisticsChartData

    private var granularity: StatisticsGranularity { data.granularity }
    private var summary: String {
        data.absenceTotals.isEmpty ? wm("wm.stats.absences_none")
            : data.absenceTotals.map { "\($0.kind.germanName) \(StatsFormat.days($0.days))" }.joined(separator: ", ")
    }

    var body: some View {
        ChartCard(title: wm("wm.stats.absences"), summary: summary, id: "stats.absences",
                  rows: data.absenceTotals.map { ($0.kind.germanName, StatsFormat.days($0.days)) }) {
            if data.absenceSeries.isEmpty {
                Text(wmKey("wm.stats.absences_none")).font(TTFont.meta).foregroundStyle(TT.textSecondary).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(data.absenceSeries) { point in
                    BarMark(x: .value("Zeitraum", point.date, unit: StatsFormat.unit(granularity)), y: .value("Tage", point.days))
                        .foregroundStyle(by: .value("Art", point.kind.germanName))
                }
                .chartForegroundStyleScale(domain: StatisticsAbsenceKind.allCases.map(\.germanName), range: StatisticsAbsenceKind.allCases.map(\.color))
                .chartXAxis { xAxis(granularity) }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel { if let days = value.as(Double.self) { Text(verbatim: days.formatted(.number.precision(.fractionLength(0...1)))) } }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: chartHeight)
                .accessibilityChartDescriptor(descriptor)
            }
        }
    }

    private var descriptor: StatsChartDescriptor {
        let buckets = data.statistics.buckets
        func values(_ pick: (StatisticsAbsences) -> Double) -> [Double] { buckets.map { pick($0.absences) } }
        return StatsChartDescriptor(title: wm("wm.stats.absences"), summary: summary, categories: buckets.map { $0.longTitle(granularity: granularity) }, yTitle: "Tage",
                                    series: data.absenceTotals.map { total in
                                        let pick: (StatisticsAbsences) -> Double = {
                                            switch total.kind {
                                            case .vacation: $0.vacation
                                            case .sick: $0.sick
                                            case .excused: $0.excused
                                            case .holiday: $0.holiday
                                            case .school: $0.school
                                            }
                                        }
                                        return .init(name: total.kind.germanName, values: values(pick), isContinuous: false)
                                    },
                                    spokenValue: { StatsFormat.days($0) })
    }
}

// MARK: - Pausen

struct BreakChartCard: View {
    let data: StatisticsChartData
    @State private var selection: Date?

    private var granularity: StatisticsGranularity { data.granularity }
    private var totals: StatisticsTotals { data.statistics.totals }
    private var summary: String {
        data.hasBreaks ? wm("wm.stats.breaks_summary \(StatsFormat.hm(totals.breakSeconds)) \(StatsFormat.hm(totals.breakDeductionSeconds))") : wm("wm.stats.breaks_none")
    }

    var body: some View {
        ChartCard(title: wm("wm.stats.breaks"), summary: summary, id: "stats.breaks",
                  rows: data.statistics.buckets.map { ($0.longTitle(granularity: granularity), wm("wm.stats.row_breaks \(StatsFormat.hm($0.breakSeconds)) \(StatsFormat.hm($0.breakDeductionSeconds))")) }) {
            if data.hasBreaks {
                Chart {
                    ForEach(data.breaks) { point in
                        BarMark(x: .value("Zeitraum", point.date, unit: StatsFormat.unit(granularity)), y: .value("Stunden", StatsFormat.hours(point.actualSeconds)))
                            .foregroundStyle(by: .value("Reihe", wm("wm.stats.series_breaks")))
                            .position(by: .value("Reihe", wm("wm.stats.series_breaks")))
                        BarMark(x: .value("Zeitraum", point.date, unit: StatsFormat.unit(granularity)), y: .value("Stunden", StatsFormat.hours(point.fixedSeconds)))
                            .foregroundStyle(by: .value("Reihe", wm("wm.stats.series_fixed_breaks")))
                            .position(by: .value("Reihe", wm("wm.stats.series_fixed_breaks")))
                    }
                    if let selection, let bucket = data.bucket(near: selection) {
                        RuleMark(x: .value("Auswahl", bucket.startDate, unit: StatsFormat.unit(granularity)))
                            .foregroundStyle(TT.textTertiary.opacity(0.35))
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                SelectionCallout(title: bucket.longTitle(granularity: granularity),
                                                 lines: [wm("wm.stats.callout_breaks \(StatsFormat.hm(bucket.breakSeconds))"), wm("wm.stats.callout_fixed \(StatsFormat.hm(bucket.breakDeductionSeconds))")])
                            }
                    }
                }
                .chartForegroundStyleScale([wm("wm.stats.series_breaks"): TT.kindTravel, wm("wm.stats.series_fixed_breaks"): TT.textTertiary.opacity(0.55)])
                .chartXSelection(value: $selection)
                .chartXAxis { xAxis(granularity) }
                .chartYAxis { hoursAxis() }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: chartHeight)
                .accessibilityChartDescriptor(descriptor)
            } else {
                Text(wmKey("wm.stats.breaks_none")).font(TTFont.meta).foregroundStyle(TT.textSecondary).frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    private var descriptor: StatsChartDescriptor {
        StatsChartDescriptor(title: wm("wm.stats.breaks"), summary: summary, categories: data.statistics.buckets.map { $0.longTitle(granularity: granularity) }, yTitle: "Stunden",
                             series: [.init(name: wm("wm.stats.series_breaks"), values: data.breaks.map { StatsFormat.hours($0.actualSeconds) }, isContinuous: false),
                                      .init(name: wm("wm.stats.series_fixed_breaks"), values: data.breaks.map { StatsFormat.hours($0.fixedSeconds) }, isContinuous: false)],
                             spokenValue: { StatsFormat.spoken(Int($0 * 3600)) })
    }
}
