import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// "Statistik": charts of the time account, target vs. worked, over-/undertime, kinds, absences and breaks for a chosen range (WM2, contract 0.28.0).
/// Older servers without `GET /time/statistics` get an explanation instead of an error.
struct StatisticsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var store: StatisticsStore?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                if let store {
                    StatisticsControls(store: store)
                    content(store)
                } else {
                    SkeletonList(rows: 4)
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle(wmKey("wm.stats.title"))
        .task {
            if store == nil, let client = model.apiClient { store = StatisticsStore(client: client, calendar: model.dayCalendar) }
            await store?.reload()
        }
        .refreshable { await store?.reload() }
    }

    @ViewBuilder private func content(_ store: StatisticsStore) -> some View {
        switch store.state {
        case .idle, .loading:
            if let data = store.data { results(data) } else { SkeletonList(rows: 4) }
        case .ready(let data):
            results(data)
        case .unsupported:
            Card { EmptyState(symbol: "chart.xyaxis.line", title: wmKey("wm.stats.unsupported_title"), message: wmKey("wm.stats.unsupported")) }
                .accessibilityIdentifier("stats.unsupported")
        case .failed(let error):
            ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await store.reload() } }
        }
    }

    @ViewBuilder private func results(_ data: StatisticsChartData) -> some View {
        if !data.hasAnyTime {
            Card { EmptyState(symbol: "chart.bar", title: wmKey("wm.stats.empty_title"), message: wmKey("wm.stats.empty")) }
                .accessibilityIdentifier("stats.empty")
        } else {
            SummaryTiles(data: data)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 620), spacing: TT.Space.l, alignment: .top)], alignment: .leading, spacing: TT.Space.l) {
                BalanceChartCard(data: data)
                TargetActualChartCard(data: data)
                DeltaChartCard(data: data)
                KindChartCard(data: data)
                AbsenceChartCard(data: data)
                BreakChartCard(data: data)
            }
            Text(wmKey(data.statistics.basis == .raw ? "wm.stats.basis_raw_note" : "wm.stats.basis_evaluated_note"))
                .font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Range, granularity and basis pickers.
private struct StatisticsControls: View {
    @Bindable var store: StatisticsStore
    @Environment(AppModel.self) private var model

    var body: some View {
        FormSection {
            EditorRow {
                Picker(wmKey("wm.stats.range"), selection: Binding(get: { store.preset }, set: { store.select($0); reload() })) {
                    ForEach(StatisticsRangePreset.allCases) { Text(verbatim: $0.germanName).tag($0) }
                }
                .accessibilityIdentifier("stats.range")
            }
            if store.preset == .custom {
                EditorRow {
                    DatePicker(wmKey("wm.stats.from"), selection: dayBinding(Binding(get: { store.customFrom }, set: { store.customFrom = $0; reload() }), calendar: model.dayCalendar), displayedComponents: .date)
                }
                EditorRow {
                    DatePicker(wmKey("wm.stats.to"), selection: dayBinding(Binding(get: { store.customTo }, set: { store.customTo = $0; reload() }), calendar: model.dayCalendar), displayedComponents: .date)
                }
            }
            EditorRow {
                Picker(wmKey("wm.stats.granularity"), selection: Binding(get: { store.granularity }, set: { store.granularity = $0; reload() })) {
                    ForEach(store.allowedGranularities) { Text(verbatim: $0.germanName).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("stats.granularity")
            }
            EditorRow {
                Picker(wmKey("wm.stats.basis"), selection: Binding(get: { store.basis }, set: { store.basis = $0; reload() })) {
                    ForEach(StatisticsBasis.allCases) { Text(verbatim: $0.germanName).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("stats.basis")
            }
        }
    }

    private func reload() { Task { await store.reload() } }
}

/// Four figures above the charts.
private struct SummaryTiles: View {
    let data: StatisticsChartData

    var body: some View {
        let totals = data.statistics.totals
        VStack(alignment: .leading, spacing: TT.Space.s) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: TT.Space.m)], spacing: TT.Space.m) {
            tile("wm.stats.tile_target", StatsFormat.hm(totals.targetToDateSeconds), id: "stats.tile.target")
            tile("wm.stats.tile_worked", StatsFormat.hm(totals.workedSeconds), id: "stats.tile.worked")
            tile("wm.stats.tile_delta", StatsFormat.signed(totals.deltaSeconds), id: "stats.tile.delta", tone: totals.deltaSeconds < 0 ? TT.danger : TT.textPrimary)
            tile("wm.stats.tile_balance", data.balance.last.map { StatsFormat.signed($0.seconds) } ?? "–", id: "stats.tile.balance")
        }
        // C3: balances and differences count through yesterday; today's difference is shown apart.
        if data.statistics.includesToday == false, let today = data.statistics.todayDeltaSeconds {
            Text(verbatim: u3String("c3.today_flows \(StatsFormat.signed(today))")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                .accessibilityIdentifier("stats.today")
        }
        }
    }

    private func tile(_ title: String.LocalizationValue, _ value: String, id: String, tone: Color = TT.textPrimary) -> some View {
        Card(padding: TT.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(wmKey(title)).font(TTFont.eyebrow).foregroundStyle(TT.textSecondary)
                Text(verbatim: value).font(TTFont.statSmall).foregroundStyle(tone).minimumScaleFactor(0.7).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

extension StatisticsRangePreset {
    var germanName: String {
        switch self {
        case .last4Weeks: wm("wm.stats.range_4w")
        case .last3Months: wm("wm.stats.range_3m")
        case .last12Months: wm("wm.stats.range_12m")
        case .thisYear: wm("wm.stats.range_year")
        case .sinceStart: wm("wm.stats.range_start")
        case .custom: wm("wm.stats.range_custom")
        }
    }
}

extension StatisticsGranularity {
    var germanName: String {
        switch self {
        case .day: wm("wm.stats.gran_day")
        case .week: wm("wm.stats.gran_week")
        case .month: wm("wm.stats.gran_month")
        }
    }
}

extension StatisticsBasis {
    var germanName: String {
        switch self {
        case .evaluated: wm("wm.stats.basis_evaluated")
        case .raw: wm("wm.stats.basis_raw")
        }
    }
}
