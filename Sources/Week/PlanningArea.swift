import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// PL1: the planning area ("Arbeitszeitplanung"): coming weeks at a glance, entry points to the week planner, the vacation planner
// and plan shares. Shared by macOS (sidebar item) and iOS (menu in the week planner). Strings: table "PlanningArea".

enum PA {
    static func s(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, tableName: "PlanningArea", bundle: .main, value: key, comment: "")
        return args.isEmpty ? format : String(format: format, arguments: args)
    }
    static func t(_ key: String, _ args: CVarArg...) -> Text {
        let format = NSLocalizedString(key, tableName: "PlanningArea", bundle: .main, value: key, comment: "")
        return Text(verbatim: args.isEmpty ? format : String(format: format, arguments: args))
    }
    /// "1 Tag offen" / "3 Tage offen" style: `key.one` for 1, `key.other` otherwise.
    static func plural(_ key: String, _ count: Int) -> String { s(count == 1 ? key + ".one" : key + ".other", count) }
}

extension PlanCoverage {
    var tone: TTTone {
        switch self {
        case .unplanned: .warning
        case .partial: .warning
        case .complete: .success
        }
    }
}

struct PlanningHubScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let client = model.apiClient {
                let cache = WeekStoreCache.shared
                PlanningHubView(horizon: cache.horizonStore(client, calendar: model.dayCalendar), planner: cache.planStore(client, calendar: model.dayCalendar))
            }
        }
        .navigationTitle(PA.s("hub.title"))
    }
}

struct PlanningHubView: View {
    let horizon: PlanHorizonStore
    let planner: WeekPlanStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openPlanWeek) private var openPlanWeek
    @State private var openedWeek: LocalDay?
    @State private var pendingWeek: LocalDay?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                if let error = horizon.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await horizon.load() } } }
                if horizon.isUnavailable {
                    Text(verbatim: PA.s("hub.unavailable")).font(TTFont.body).foregroundStyle(TT.textSecondary)
                } else {
                    Text(verbatim: PA.s("hub.hint")).font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
                    weeks
                }
                more
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .task { await horizon.load() }
        .refreshable { await horizon.load() }
        .navigationDestination(item: $openedWeek) { monday in WeekPlannerScreen(monday: monday) }
        .alert(W.s("leave.title"), isPresented: Binding(get: { pendingWeek != nil }, set: { if !$0 { pendingWeek = nil } })) {
            Button(W.s("leave.discard"), role: .destructive) {
                if let target = pendingWeek { planner.discard(); show(target) }
                pendingWeek = nil
            }
            Button(W.s("leave.keep"), role: .cancel) { pendingWeek = nil }
        } message: { W.t("leave.message") }
    }

    /// iOS: the week opens in the planning mode of the Zeit screen; elsewhere (Mac) it is pushed as a planner screen.
    private func show(_ monday: LocalDay) {
        if let openPlanWeek { openPlanWeek(monday) } else { openedWeek = monday }
    }

    private func open(_ monday: LocalDay) {
        if planner.isDirty && planner.monday != monday { pendingWeek = monday } else { show(monday) }
    }

    // MARK: Coming weeks

    private var weeks: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            HStack {
                Text(verbatim: PA.s("hub.weeks")).font(TTFont.label).foregroundStyle(TT.textSecondary)
                Spacer(minLength: 0)
                if horizon.openWeeks > 0 { Text(verbatim: PA.plural("hub.weeks_open", horizon.openWeeks)).font(TTFont.meta).foregroundStyle(TT.warning) }
            }
            if horizon.entries.isEmpty && horizon.isLoading {
                SkeletonList(rows: 4)
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(horizon.entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider().padding(.leading, TT.Space.l) }
                            row(entry)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func row(_ entry: PlanHorizonStore.Entry) -> some View {
        switch entry {
        case .loaded(let row):
            Button { open(row.monday) } label: { HorizonRowView(row: row, isCurrent: row.monday == horizon.currentMonday, calendar: horizon.calendar) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("planning.week.\(row.isoWeek)")
        case .failed(let monday, let isoWeek):
            Button { open(monday) } label: {
                HStack {
                    Text(verbatim: PA.s("hub.row.kw", IsoWeek.number(of: isoWeek) ?? 0)).font(TTFont.body).foregroundStyle(TT.textPrimary)
                    Spacer(minLength: 0)
                    StatusChip(verbatim: PA.s("hub.row.failed"), tone: .danger)
                }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Other planning tools

    private var more: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Text(verbatim: PA.s("hub.more")).font(TTFont.label).foregroundStyle(TT.textSecondary)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink { VacationPlannerView() } label: {
                        ToolRow(symbol: "sparkles", tint: TT.kindVacation, title: PA.s("hub.vacation"), text: PA.s("hub.vacation_text"))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("planning.vacation")
                    Divider().padding(.leading, TT.Space.l)
                    NavigationLink { SharingScreen() } label: {
                        ToolRow(symbol: "person.2.fill", tint: TT.kindWork, title: PA.s("hub.shares"), text: PA.s("hub.shares_text"))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("planning.shares")
                }
            }
        }
    }
}

private struct ToolRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(spacing: TT.Space.m) {
            KindGlyph(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(TTFont.body).foregroundStyle(TT.textPrimary)
                Text(verbatim: text).font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary).accessibilityHidden(true)
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
    }
}

private struct HorizonRowView: View {
    let row: PlanHorizonRow
    let isCurrent: Bool
    let calendar: DayCalendar

    private var chip: String {
        if row.plannableDays == 0 { return PA.s("hub.cov.nothing") }
        return switch row.coverage {
        case .unplanned: PA.s("hub.cov.unplanned")
        case .partial: PA.plural("hub.cov.partial", row.openDays)
        case .complete: PA.s("hub.cov.complete")
        }
    }

    var body: some View {
        HStack(spacing: TT.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: TT.Space.xs) {
                    Text(verbatim: PA.s("hub.row.kw", row.weekNumber)).font(TTFont.body).foregroundStyle(TT.textPrimary)
                    if isCurrent { Text(verbatim: PA.s("hub.row.this_week")).font(TTFont.meta).foregroundStyle(Color.accentColor) }
                }
                Text(verbatim: weekRangeText(start: row.monday, end: row.sunday, calendar: calendar)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                Text(verbatim: PA.s("hub.row.planned", DurationFormat.hoursMinutes(row.plannedSeconds), DurationFormat.hoursMinutes(row.targetSeconds)))
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                if row.blockedDays > 0 {
                    Text(verbatim: PA.plural("hub.row.blocked", row.blockedDays)).font(TTFont.meta).foregroundStyle(TT.textTertiary)
                }
            }
            Spacer(minLength: 0)
            StatusChip(verbatim: chip, tone: row.plannableDays == 0 ? .neutral : row.coverage.tone)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary).accessibilityHidden(true)
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
