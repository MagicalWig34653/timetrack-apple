import Accessibility
import Charts
import SwiftUI
import TimetrackCore
import TimetrackDesign

/// Formatting and chart helpers of the statistics screen (WM2).
enum StatsFormat {
    static func hours(_ seconds: Int) -> Double { Double(seconds) / 3600 }
    static func hm(_ seconds: Int) -> String { DurationFormat.hoursMinutes(seconds) }
    static func signed(_ seconds: Int) -> String { DurationFormat.signed(seconds).replacingOccurrences(of: "-", with: "−") }
    static func spoken(_ seconds: Int) -> String {
        let text = DurationFormat.spoken(abs(seconds), locale: Locale(identifier: "de_DE"))
        return seconds < 0 ? "minus \(text)" : text
    }

    static func days(_ value: Double) -> String {
        let text = value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "de_DE")))
        return value == 1 ? "1 Tag" : "\(text) Tage"
    }

    static func unit(_ granularity: StatisticsGranularity) -> Calendar.Component {
        switch granularity {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    /// Axis label for a bucket start: `12.10.`, `KW 42`, `Okt`.
    static func axisLabel(_ date: Date, _ granularity: StatisticsGranularity) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let c = calendar.dateComponents([.day, .month, .weekOfYear], from: date)
        switch granularity {
        case .day: return "\(c.day ?? 0).\(c.month ?? 0)."
        case .week: return "KW \(c.weekOfYear ?? 0)"
        case .month: return ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"][max(0, (c.month ?? 1) - 1)]
        }
    }

    static func hoursLabel(_ value: Double, signed: Bool = false) -> String {
        let text = abs(value).formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "de_DE")))
        let sign = value < 0 ? "−" : (signed && value > 0 ? "+" : "")
        return "\(sign)\(text) h"
    }
}

extension StatisticsKind {
    var color: Color {
        switch self {
        case .work: TT.kindWork
        case .travel: TT.kindTravel
        case .school: TT.kindSchool
        }
    }

    var symbol: String {
        switch self {
        case .work: "briefcase"
        case .travel: "car"
        case .school: "graduationcap"
        }
    }
}

extension StatisticsAbsenceKind {
    var color: Color {
        switch self {
        case .vacation: TT.kindVacation
        case .sick: TT.kindSick
        case .excused: TT.kindExcused
        case .holiday: TT.kindHoliday
        case .school: TT.kindSchool
        }
    }
}

/// Audio graph and VoiceOver description of one chart: categories on x, numeric values on y, one or more series.
struct StatsChartDescriptor: AXChartDescriptorRepresentable {
    struct Series {
        let name: String
        let values: [Double]
        let isContinuous: Bool
    }

    let title: String
    let summary: String
    let categories: [String]
    let yTitle: String
    let series: [Series]
    /// How a value is spoken (`1,5` -> "1 Stunde, 30 Minuten").
    let spokenValue: (Double) -> String

    func makeChartDescriptor() -> AXChartDescriptor {
        let all = series.flatMap(\.values)
        var low = min(all.min() ?? 0, 0)
        var high = max(all.max() ?? 1, 0)
        if low == high { high = low + 1 }
        if high - low < 0.0001 { low -= 0.5; high += 0.5 }
        let x = AXCategoricalDataAxisDescriptor(title: "Zeitraum", categoryOrder: categories)
        let y = AXNumericDataAxisDescriptor(title: yTitle, range: low...high, gridlinePositions: []) { spokenValue($0) }
        let descriptors = series.map { item in
            AXDataSeriesDescriptor(name: item.name, isContinuous: item.isContinuous, dataPoints: zip(categories, item.values).map { AXDataPoint(x: $0, y: $1) })
        }
        return AXChartDescriptor(title: title, summary: summary, xAxis: x, yAxis: y, additionalAxes: [], series: descriptors)
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {}
}

/// Card with title, one-line summary (also what VoiceOver reads first), the chart and a collapsible value table.
struct ChartCard<Content: View>: View {
    let title: String
    let summary: String
    let id: String
    /// Rows of the value table (title, value text).
    var rows: [(title: String, value: String)] = []
    @ViewBuilder let content: Content
    @State private var showsValues = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                VStack(alignment: .leading, spacing: TT.Space.xxs) {
                    Text(verbatim: title).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary).accessibilityAddTraits(.isHeader)
                    Text(verbatim: summary).font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                content
                if !rows.isEmpty {
                    DisclosureGroup(isExpanded: $showsValues) {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(verbatim: row.title).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                                    Spacer(minLength: TT.Space.s)
                                    Text(verbatim: row.value).font(TTFont.numeralSmall).foregroundStyle(TT.textPrimary).multilineTextAlignment(.trailing)
                                }
                                .padding(.vertical, 3)
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.top, TT.Space.xs)
                    } label: {
                        Text(wmKey("wm.stats.values")).font(TTFont.label).foregroundStyle(TT.textSecondary)
                    }
                    .accessibilityIdentifier("\(id).values")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

/// Floating callout for a chart selection.
struct SelectionCallout: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).font(TTFont.eyebrow).foregroundStyle(TT.textSecondary)
            ForEach(lines, id: \.self) { Text(verbatim: $0).font(TTFont.numeralSmall).foregroundStyle(TT.textPrimary) }
        }
        .padding(.horizontal, TT.Space.s).padding(.vertical, TT.Space.xs)
        .background(TT.surfaceRaised, in: .rect(cornerRadius: TT.Radius.chip, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: TT.Radius.chip, style: .continuous).strokeBorder(TT.cardBorder, lineWidth: 1) }
    }
}
