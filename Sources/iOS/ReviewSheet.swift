import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// Q1: the list behind "n zu prüfen". Each entry says why it needs a look, in plain German, and offers the fix actions:
// accept the automation's proposal / confirm ("Passt so"), adjust (editor) or delete. Strings live in `Q1.xcstrings`.

struct ReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ReviewEditRequest?
    @State private var voiding: ReviewItem?
    @State private var busy = false

    struct ReviewEditRequest: Identifiable {
        let item: ReviewItem
        var id: UUID { item.id }
    }

    private var zone: TimeZone { model.dayCalendar.timeZone }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    if let review = model.review {
                        // SG1: automation suggestions first (a decision each), then the flagged entries (Q1).
                        SuggestionsSection(review: review)
                        if review.items.isEmpty {
                            if review.hasLoaded { if review.suggestions.isEmpty { empty } } else { SkeletonList(rows: 2) }
                        } else {
                            if !review.suggestions.isEmpty { Eyebrow(verbatim: SG1.s("sg1.section.entries")).accessibilityAddTraits(.isHeader) }
                            Q1.t("q1.review.intro").font(TTFont.body).foregroundStyle(TT.textSecondary)
                            ForEach(review.items) { item in card(item, review: review) }
                            Q1.t("q1.review.footer").font(TTFont.meta).foregroundStyle(TT.textTertiary)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { dismiss() } } }
            .task { await model.review?.load() }
            .sheet(item: $editing, onDismiss: nil) { request in
                if let store = model.timeList {
                    SegmentEditor(store: store, segment: request.item.segment, day: request.item.day,
                                  endDefault: request.item.proposedEnd ?? defaultEnd(for: request.item), reasonDefault: Q1.s("q1.editor.reason"))
                        .presentationDetents([.fraction(0.75), .large])
                        .onDisappear { Task { await model.review?.afterEditing(request.item); await model.today?.load() } }
                }
            }
            .sheet(item: $voiding) { item in
                if let store = model.timeList {
                    VoidSheet(store: store, segment: item.segment)
                        .onDisappear { Task { await model.review?.afterEditing(item); await model.today?.load() } }
                }
            }
        }
        .accessibilityIdentifier("review.sheet")
    }

    private var empty: some View {
        VStack(spacing: TT.Space.s) {
            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(TT.success).accessibilityHidden(true)
            SG1.t("sg1.empty.title").font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
            SG1.t("sg1.empty.message").font(TTFont.meta).foregroundStyle(TT.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, TT.Space.xxl)
    }

    /// An entry without a proposal: one hour after the start, as the editor does for a new end. Editable, saved only with the reason.
    private func defaultEnd(for item: ReviewItem) -> Date { item.segment.startedAt.addingTimeInterval(3_600) }

    // MARK: - One entry

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
                    Text(verbatim: item.reason.detail(zone: zone)).font(TTFont.body).foregroundStyle(TT.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions(item, review: review)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.item")
    }

    @ViewBuilder private func actions(_ item: ReviewItem, review: ReviewStore) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            switch item.reason {
            case .endMissingProposed(let end):
                Button { run { await review.acceptProposal(item) } } label: { Text(verbatim: Q1.s("q1.action.accept \(end.clockText(in: zone))")).frame(maxWidth: .infinity) }
                    .buttonStyle(.ttPrimary).accessibilityIdentifier("review.accept")
                HStack(spacing: TT.Space.s) {
                    secondary("q1.action.adjust", id: "review.adjust") { editing = ReviewEditRequest(item: item) }
                    secondary("q1.action.still_running", id: "review.confirm") { run { await review.confirm(item) } }
                }
            case .endMissing:
                Button { editing = ReviewEditRequest(item: item) } label: { Q1.t("q1.action.set_end").frame(maxWidth: .infinity) }
                    .buttonStyle(.ttPrimary).accessibilityIdentifier("review.adjust")
                secondary("q1.action.still_running", id: "review.confirm") { run { await review.confirm(item) } }
            case .markedByAutomation:
                Button { run { await review.confirm(item) } } label: { Q1.t("q1.action.confirm").frame(maxWidth: .infinity) }
                    .buttonStyle(.ttPrimary).accessibilityIdentifier("review.confirm")
                secondary("q1.action.adjust", id: "review.adjust") { editing = ReviewEditRequest(item: item) }
            }
            Button(role: .destructive) { voiding = item } label: { Q1.t("q1.action.delete").frame(maxWidth: .infinity, minHeight: 36) }
                .buttonStyle(.plain).foregroundStyle(TT.danger).accessibilityIdentifier("review.delete")
        }
        .disabled(busy)
    }

    private func secondary(_ key: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(key, tableName: "Q1").frame(maxWidth: .infinity) }
            .buttonStyle(.ttSecondary).accessibilityIdentifier(id)
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

/// Q1: banner at the top of the "Zeit" tab while entries need a look. Tapping opens the same list.
struct ReviewBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var opened = false

    var body: some View {
        VStack(spacing: 0) {
            if let review = model.review, review.count > 0 {
                Button { opened = true } label: {
                    HStack(spacing: TT.Space.m) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(TT.warning).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: String(localized: "h3.review \(review.count)", table: "UX3")).font(TTFont.body.weight(.semibold)).foregroundStyle(TT.textPrimary)
                            Q1.t("q1.banner.subtitle").font(TTFont.meta).foregroundStyle(TT.textSecondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary).accessibilityHidden(true)
                    }
                    .padding(.horizontal, TT.Space.m).padding(.vertical, TT.Space.s)
                    .frame(minHeight: 44)
                    .ttSurface(radius: TT.Radius.card)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.s)
                .accessibilityHint(Text(LocalizedStringResource("q1.review.hint", table: "Q1")))
                .accessibilityIdentifier("time.review")
            }
        }
        .task { await model.review?.load() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await model.review?.load() } } }
        .sheet(isPresented: $opened) { ReviewSheet() }
    }
}
