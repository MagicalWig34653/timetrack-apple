import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// SG1 (macOS): sidebar "Zu prüfen". Suggestions of the automation (accept / adjust / reject, also in bulk) and, below, the entries the
// automation flagged (Q1). Flagged entries can be confirmed or closed with the proposed end here; correcting or deleting one happens in
// "Zeit" (the button jumps there), so the editor exists only once on the Mac.
struct SuggestionsMacScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Environment(\.scenePhase) private var scenePhase
    @State private var busy = false

    private var zone: TimeZone { model.dayCalendar.timeZone }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                if let review = model.review {
                    SuggestionsSection(review: review)
                    if review.items.isEmpty {
                        if review.hasLoaded, review.suggestions.isEmpty {
                            EmptyState(symbol: "checkmark.circle", title: "sg1.empty.title", message: "sg1.empty.message")
                        } else if !review.hasLoaded {
                            SkeletonList(rows: 2)
                        }
                    } else {
                        if !review.suggestions.isEmpty { Eyebrow(verbatim: SG1.s("sg1.section.entries")).accessibilityAddTraits(.isHeader) }
                        Q1.t("q1.review.intro").font(TTFont.body).foregroundStyle(TT.textSecondary)
                        ForEach(review.items) { item in card(item, review: review) }
                    }
                    if let error = review.error {
                        ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await review.load() } }
                    }
                }
            }
            .padding(TT.Space.l)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle(Q1.s("q1.review.title"))
        .task { await model.review?.load() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await model.review?.load() } } }
        .accessibilityIdentifier("review.screen")
    }

    private func card(_ item: ReviewItem, review: ReviewStore) -> some View {
        let segment = item.segment
        let range = "\(segment.startedAt.clockText(in: zone)) – \(segment.endedAt.map { $0.clockText(in: zone) } ?? "…")"
        return Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                HStack(alignment: .top, spacing: TT.Space.m) {
                    KindGlyph(symbol: segment.kind.ttSymbol, tint: segment.kind.ttTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: PlanFormat.longDay(item.day, calendar: model.dayCalendar)).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                        Text(verbatim: range).font(TTFont.numeral).foregroundStyle(TT.textPrimary)
                        Text(segment.kind.ttTitle).font(TTFont.meta).foregroundStyle(segment.kind.ttTint)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: TT.Space.xs) {
                    Label { Text(item.reason.titleKey, tableName: "Q1") } icon: { Image(systemName: item.reason.symbol) }
                        .font(TTFont.body.weight(.semibold)).foregroundStyle(TT.warning)
                    Text(verbatim: item.reason.detail(zone: zone)).font(TTFont.body).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: TT.Space.s) {
                    if case .endMissingProposed(let end) = item.reason {
                        Button { run { await review.acceptProposal(item) } } label: { Text(verbatim: Q1.s("q1.action.accept \(end.clockText(in: zone))")) }
                            .buttonStyle(.ttPrimary).accessibilityIdentifier("review.accept")
                    }
                    Button { run { await review.confirm(item) } } label: {
                        item.reason == .endMissing || item.proposedEnd != nil ? Q1.t("q1.action.still_running") : Q1.t("q1.action.confirm")
                    }
                    .buttonStyle(.ttSecondary).accessibilityIdentifier("review.confirm")
                    Button { ui.selection = .time } label: { Text("sidebar.time") }
                        .buttonStyle(.ttSecondary).accessibilityIdentifier("review.open_time")
                    Spacer(minLength: 0)
                }
                .disabled(busy)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.item")
    }

    private func run(_ action: @escaping () async -> Bool) {
        guard !busy else { return }
        busy = true
        Task {
            _ = await action()
            await model.today?.load()
            busy = false
        }
    }
}
