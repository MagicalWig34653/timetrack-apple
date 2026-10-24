import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// SG1: the automation's suggestions as a decision list, shared by iOS/iPadOS ("Zu prüfen" sheet, Mehr) and macOS (sidebar "Vorschläge").
// Nothing is ever booked silently: every suggestion needs a tap on "Übernehmen" (or "Anpassen" then "Übernehmen").
// Wording (docs/glossary-ui.md): "Vorschlag" = something the automation proposes; "zu prüfen" = the count of everything that waits for a
// decision (suggestions plus flagged entries). Strings live in `SG1.xcstrings`.

enum SG1 {
    static func s(_ key: String.LocalizationValue) -> String { String(localized: key, table: "SG1") }
    static func t(_ key: LocalizedStringKey) -> Text { Text(key, tableName: "SG1") }
}

extension TimeSuggestion.Kind {
    var sg1Symbol: String {
        switch self {
        case .start: "play.circle.fill"
        case .end: "stop.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var sg1Tint: Color {
        switch self {
        case .start: TT.success
        case .end: TT.warning
        case .unknown: TT.textTertiary
        }
    }

    var sg1TitleKey: LocalizedStringKey {
        switch self {
        case .start: "sg1.kind.start"
        case .end: "sg1.kind.end"
        case .unknown: "sg1.kind.unknown"
        }
    }
}

extension SuggestionEntry {
    func placeName(_ places: [UUID: Place]) -> String? { placeId.flatMap { places[$0]?.name } }

    /// Why the automation proposes this, in plain German.
    func reasonText(places: [UUID: Place]) -> String {
        let place = placeName(places)
        switch kind {
        case .start: return place.map { SG1.s("sg1.reason.start.place \($0)") } ?? SG1.s("sg1.reason.start")
        case .end: return place.map { SG1.s("sg1.reason.end.place \($0)") } ?? SG1.s("sg1.reason.end")
        case .unknown: return SG1.s("sg1.reason.unknown")
        }
    }

    func whenText(zone: TimeZone) -> String {
        switch kind {
        case .start: return suggestion.proposedStartedAt.map { SG1.s("sg1.when.start \($0.clockText(in: zone))") } ?? SG1.s("sg1.when.none")
        case .end: return suggestion.proposedEndedAt.map { SG1.s("sg1.when.end \($0.clockText(in: zone))") } ?? SG1.s("sg1.when.none")
        case .unknown: return SG1.s("sg1.when.none")
        }
    }

    func acceptTitle(zone: TimeZone) -> String {
        switch kind {
        case .start: return SG1.s("sg1.action.accept.start \((suggestion.proposedStartedAt ?? .now).clockText(in: zone))")
        case .end: return SG1.s("sg1.action.accept.end \((suggestion.proposedEndedAt ?? .now).clockText(in: zone))")
        case .unknown: return SG1.s("sg1.adjust.accept")
        }
    }
}

/// Header, intro, one card per suggestion and the bulk actions. Embedded in a scroll view by the caller.
struct SuggestionsSection: View {
    let review: ReviewStore
    @Environment(AppModel.self) private var model
    @State private var adjusting: SuggestionEntry?
    @State private var busy = false
    @State private var bulk: BulkKind?
    @State private var note: String?

    enum BulkKind: Identifiable { case accept, reject; var id: Int { self == .accept ? 0 : 1 } }

    private var zone: TimeZone { model.dayCalendar.timeZone }
    private var places: [UUID: Place] { model.today?.places ?? [:] }

    var body: some View {
        if !review.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                Eyebrow(verbatim: SG1.s("sg1.section.suggestions")).accessibilityAddTraits(.isHeader)
                SG1.t("sg1.intro").font(TTFont.body).foregroundStyle(TT.textSecondary)
                ForEach(review.suggestions) { entry in card(entry) }
                if review.suggestions.count > 1 { bulkActions }
                if let note { Text(verbatim: note).font(TTFont.meta).foregroundStyle(TT.textSecondary).accessibilityIdentifier("suggestions.note") }
            }
            .sheet(item: $adjusting) { entry in
                SuggestionAdjustSheet(entry: entry) { start, end in
                    let ok = await review.accept(entry, startedAt: start, endedAt: end)
                    if ok { await model.today?.load() }
                    return ok
                }
                .environment(model)
            }
            .confirmationDialog(bulk == .accept ? SG1.s("sg1.bulk.accept.title") : SG1.s("sg1.bulk.reject.title"),
                                isPresented: Binding(get: { bulk != nil }, set: { if !$0 { bulk = nil } }), titleVisibility: .visible, presenting: bulk) { kind in
                if kind == .accept {
                    Button(SG1.s("sg1.action.accept_all \(review.suggestions.filter(\.canAccept).count)")) { runBulk(accept: true) }
                } else {
                    Button(SG1.s("sg1.action.reject_all"), role: .destructive) { runBulk(accept: false) }
                }
                Button("common.cancel", role: .cancel) {}
            } message: { kind in
                kind == .accept ? SG1.t("sg1.bulk.accept.message") : SG1.t("sg1.bulk.reject.message")
            }
        }
    }

    private func card(_ entry: SuggestionEntry) -> some View {
        let reason = entry.reasonText(places: places)
        let when = entry.whenText(zone: zone)
        return Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                HStack(alignment: .top, spacing: TT.Space.m) {
                    KindGlyph(symbol: entry.kind.sg1Symbol, tint: entry.kind.sg1Tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: PlanFormat.longDay(entry.day, calendar: model.dayCalendar)).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                        Text(verbatim: when).font(TTFont.numeral).foregroundStyle(TT.textPrimary)
                        Text(entry.kind.sg1TitleKey, tableName: "SG1").font(TTFont.meta).foregroundStyle(entry.kind.sg1Tint)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: TT.Space.xs) {
                    Text(verbatim: reason).font(TTFont.body).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
                    if let segment = entry.segment {
                        Text(verbatim: SG1.s("sg1.about.entry \(segment.kind.plainName) \(segment.startedAt.clockText(in: zone))"))
                            .font(TTFont.meta).foregroundStyle(TT.textTertiary)
                    }
                }
                actions(entry)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("suggestion.item")
    }

    @ViewBuilder private func actions(_ entry: SuggestionEntry) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            if entry.canAccept {
                Button { run(entry) { await review.accept(entry) } } label: { Text(verbatim: entry.acceptTitle(zone: zone)).frame(maxWidth: .infinity) }
                    .buttonStyle(.ttPrimary).accessibilityIdentifier("suggestion.accept")
            }
            HStack(spacing: TT.Space.s) {
                if entry.canAdjust {
                    Button { adjusting = entry } label: { SG1.t("sg1.action.adjust").frame(maxWidth: .infinity) }
                        .buttonStyle(.ttSecondary).accessibilityIdentifier("suggestion.adjust")
                }
                Button { run(entry) { await review.reject(entry) } } label: { SG1.t("sg1.action.reject").frame(maxWidth: .infinity) }
                    .buttonStyle(.ttSecondary).accessibilityIdentifier("suggestion.reject")
            }
        }
        .disabled(busy)
    }

    private var bulkActions: some View {
        HStack(spacing: TT.Space.s) {
            if review.suggestions.filter(\.canAccept).count > 1 {
                Button { bulk = .accept } label: {
                    Text(verbatim: SG1.s("sg1.action.accept_all \(review.suggestions.filter(\.canAccept).count)")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.ttSecondary).accessibilityIdentifier("suggestion.accept_all")
            }
            Button { bulk = .reject } label: { SG1.t("sg1.action.reject_all").frame(maxWidth: .infinity) }
                .buttonStyle(.ttSecondary).accessibilityIdentifier("suggestion.reject_all")
        }
        .disabled(busy)
    }

    private func run(_ entry: SuggestionEntry, _ action: @escaping () async -> Bool) {
        guard !busy else { return }
        busy = true
        note = nil
        Task {
            _ = await action()
            await model.today?.load()
            busy = false
        }
    }

    private func runBulk(accept: Bool) {
        guard !busy else { return }
        busy = true
        Task {
            if accept {
                let outcome = await review.acceptAll()
                note = outcome.failed > 0 ? SG1.s("sg1.bulk.result \(outcome.done) \(outcome.failed)") : nil
            } else {
                let outcome = await review.rejectAll()
                note = SG1.s("sg1.bulk.rejected \(outcome.done)")
            }
            await model.today?.load()
            busy = false
        }
    }
}

/// "Anpassen": change the times before booking. A start suggestion may get an end right away; an end suggestion only moves its end.
struct SuggestionAdjustSheet: View {
    let entry: SuggestionEntry
    /// Returns whether the booking went through (then the sheet closes); otherwise the store's error is shown.
    let onAccept: (Date?, Date?) async -> Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SuggestionDraft
    @State private var busy = false

    init(entry: SuggestionEntry, onAccept: @escaping (Date?, Date?) async -> Bool) {
        self.entry = entry
        self.onAccept = onAccept
        _draft = State(initialValue: SuggestionDraft(entry: entry))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    FormSection {
                        if entry.kind == .start {
                            DatePicker(selection: $draft.start, in: ...Date.now, displayedComponents: [.date, .hourAndMinute]) { SG1.t("sg1.adjust.start") }
                                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                                .accessibilityIdentifier("suggestion.adjust.start")
                            Toggle(isOn: $draft.hasEnd) { SG1.t("sg1.adjust.has_end") }
                                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                            if draft.hasEnd {
                                DatePicker(selection: $draft.end, in: draft.start..., displayedComponents: [.date, .hourAndMinute]) { SG1.t("sg1.adjust.end") }
                                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                            }
                        } else {
                            DatePicker(selection: $draft.end, displayedComponents: [.date, .hourAndMinute]) { SG1.t("sg1.adjust.end") }
                                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                                .accessibilityIdentifier("suggestion.adjust.end")
                        }
                    }
                    Text(footer, tableName: "SG1").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    if !draft.isValid() {
                        SG1.t("sg1.adjust.invalid").font(TTFont.meta).foregroundStyle(TT.danger)
                    }
                    if let error = model.review?.error {
                        ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { model.review?.error = nil }
                    }
                }
                .padding(TT.Space.l)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(SG1.s("sg1.adjust.nav"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { SG1.t("sg1.adjust.cancel") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !busy else { return }
                        busy = true
                        Task {
                            let overrides = draft.overrides
                            if await onAccept(overrides.startedAt, overrides.endedAt) { dismiss() }
                            busy = false
                        }
                    } label: { SG1.t("sg1.adjust.accept") }
                    .disabled(!draft.isValid() || busy)
                    .accessibilityIdentifier("suggestion.adjust.accept")
                }
            }
        }
        // Wall-clock time in the work model's zone, like the rest of the app.
        .environment(\.timeZone, model.dayCalendar.timeZone)
        .onAppear { model.review?.error = nil }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 440, minHeight: 360)
        #endif
        .accessibilityIdentifier("suggestion.adjust.sheet")
    }

    private var footer: LocalizedStringKey {
        entry.kind == .start ? "sg1.adjust.footer.start" : "sg1.adjust.footer.end"
    }
}
