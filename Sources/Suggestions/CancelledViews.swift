import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// SG1: "Storniert" (the bin of cancelled entries), shared by iOS/iPadOS (Mehr › Storniert) and macOS (sidebar). Restore is one tap;
// permanent deletion always shows a dry-run count first and needs the typed word. Strings live in `SG1.xcstrings`.

struct CancelledScreen: View {
    @Environment(AppModel.self) private var model
    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var purge: PurgeRequest?
    @State private var restoring: UUID?
    /// The entry whose last restore was refused; the explanation sits in its own card (the list may be scrolled far from the top).
    @State private var failedId: UUID?
    @State private var note: String?
    /// SG2: result of the last bulk restore (shown as a summary sheet when something was refused).
    @State private var report: RestoreReport?
    @State private var bulkRestoring = false

    struct RestoreReport: Identifiable {
        struct Line: Identifiable { let id: UUID; let title: String; let reason: String }
        let id = UUID()
        let restored: Int
        let failures: [Line]
    }

    struct PurgeRequest: Identifiable {
        let scope: PurgeScope
        let expected: Int?
        var id: String { "\(scope)" }
    }

    private var zone: TimeZone { model.dayCalendar.timeZone }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                if let store = model.cancelled {
                    content(store)
                }
            }
            .padding(TT.Space.l)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle(SG1.s("sg1.cancelled.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting, let store = model.cancelled, !store.items.isEmpty { bulkBar(store) }
        }
        .task { await model.cancelled?.load() }
        .refreshable { await model.cancelled?.load() }
        .sheet(item: $purge) { request in
            PurgeConfirmSheet(scope: request.scope) { summary in
                selection.removeAll()
                selecting = false
                note = SG1.s("sg1.cancelled.purged \(summary.segments)")
                Task { await refreshTime() }
            }
            .environment(model)
        }
        .sheet(item: $report) { report in RestoreReportSheet(report: report) }
        .accessibilityIdentifier("cancelled.screen")
    }

    @ViewBuilder private func content(_ store: CancelledStore) -> some View {
        SG1.t("sg1.cancelled.intro").font(TTFont.body).foregroundStyle(TT.textSecondary)
        if let note {
            Label { Text(verbatim: note) } icon: { Image(systemName: "checkmark.circle.fill") }
                .font(TTFont.meta).foregroundStyle(TT.success).accessibilityIdentifier("cancelled.note")
        }
        if let error = store.error {
            ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await store.load() } }
        }
        if store.isEmpty {
            EmptyState(symbol: "trash.slash", title: "sg1.cancelled.empty.title", message: "sg1.cancelled.empty.message")
        } else if !store.hasLoaded {
            SkeletonList(rows: 3)
        } else {
            ForEach(store.items) { item in card(item, store: store) }
            if store.hasMore {
                Button { Task { await store.loadMore() } } label: { SG1.t("sg1.cancelled.load_more").frame(maxWidth: .infinity) }
                    .buttonStyle(.ttSecondary).accessibilityIdentifier("cancelled.more")
            }
        }
    }

    private func failureText(_ failure: RestoreFailure) -> String {
        switch failure {
        case .overlap: SG1.s("sg1.cancelled.restore_failed.overlap")
        case .timerRunning: SG1.s("sg1.cancelled.restore_failed.timer")
        case .changedElsewhere: SG1.s("sg1.cancelled.restore_failed.changed")
        case .other(let error): error.germanDescription
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let store = model.cancelled, !store.items.isEmpty {
                if selecting {
                    Button { selecting = false; selection.removeAll() } label: { SG1.t("sg1.cancelled.select_done") }
                        .accessibilityIdentifier("cancelled.select_done")
                } else {
                    Menu {
                        Button { selecting = true } label: { Label { SG1.t("sg1.cancelled.select") } icon: { Image(systemName: "checkmark.circle") } }
                            .accessibilityIdentifier("cancelled.select")
                        Button(role: .destructive) { purge = PurgeRequest(scope: .all, expected: store.total) } label: {
                            Label { SG1.t("sg1.cancelled.purge_all") } icon: { Image(systemName: "trash") }
                        }
                        .accessibilityIdentifier("cancelled.purge_all")
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel(Text("Mehr"))
                    .accessibilityIdentifier("cancelled.menu")
                }
            }
        }
    }

    // MARK: Bulk bar (SG2)

    /// Selection actions in a bar above the tab bar / now bar (a bottom toolbar was hidden behind them on iPhone).
    private func bulkBar(_ store: CancelledStore) -> some View {
        let allSelected = !store.items.isEmpty && store.items.allSatisfy { selection.contains($0.id) }
        return VStack(spacing: TT.Space.s) {
            HStack {
                Text(verbatim: SG1.s("sg2.bulk.count \(selection.count)")).font(TTFont.body.weight(.semibold)).foregroundStyle(TT.textPrimary)
                    .accessibilityIdentifier("cancelled.selected_count")
                Spacer()
                Button {
                    selection = allSelected ? [] : Set(store.items.map(\.id))
                } label: { allSelected ? SG1.t("sg2.bulk.select_none") : SG1.t("sg1.cancelled.select_all") }
                    .accessibilityIdentifier("cancelled.select_all")
            }
            HStack(spacing: TT.Space.m) {
                Button { restoreSelected(store) } label: {
                    Text(verbatim: SG1.s("sg2.bulk.restore \(selection.count)")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.ttPrimary).disabled(selection.isEmpty || bulkRestoring || restoring != nil)
                .accessibilityIdentifier("cancelled.restore_selected")
                Button(role: .destructive) { purge = PurgeRequest(scope: .ids(Array(selection)), expected: selection.count) } label: {
                    Text(verbatim: SG1.s("sg2.bulk.purge \(selection.count)")).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(selection.isEmpty ? TT.textTertiary : TT.danger)
                .disabled(selection.isEmpty || bulkRestoring)
                .accessibilityIdentifier("cancelled.purge_selected")
            }
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cancelled.bulkbar")
    }

    private func restoreSelected(_ store: CancelledStore) {
        let chosen = store.items.filter { selection.contains($0.id) }
        guard !chosen.isEmpty, !bulkRestoring else { return }
        bulkRestoring = true
        note = nil
        failedId = nil
        Task {
            let result = await store.restore(chosen)
            let byId = Dictionary(uniqueKeysWithValues: chosen.map { ($0.id, $0) })
            let lines = result.failed.map { entry -> RestoreReport.Line in
                let segment = byId[entry.id]?.segment
                let title = segment.map {
                    "\(PlanFormat.longDay(model.dayCalendar.day(for: $0.startedAt), calendar: model.dayCalendar)), \($0.startedAt.clockText(in: zone))"
                } ?? ""
                return .init(id: entry.id, title: title, reason: failureText(entry.failure))
            }
            if !result.restored.isEmpty {
                note = SG1.s("sg2.bulk.restored \(result.restored.count)")
                await refreshTime()
            }
            // Refused entries stay selected so the user can retry them after fixing the conflict.
            selection = result.failedIds
            if result.isComplete { selecting = false } else { report = RestoreReport(restored: result.restored.count, failures: lines) }
            bulkRestoring = false
        }
    }

    // MARK: One entry

    private func card(_ item: CancelledSegment, store: CancelledStore) -> some View {
        let segment = item.segment
        let day = model.dayCalendar.day(for: segment.startedAt)
        let range = "\(segment.startedAt.clockText(in: zone)) – \(segment.endedAt.map { $0.clockText(in: zone) } ?? "…")"
        let duration = segment.endedAt.map { DurationFormat.hoursMinutes(Int($0.timeIntervalSince(segment.startedAt))) }
        let cancelledOn = item.cancelledAt.formatted(Date.FormatStyle(timeZone: zone).day().month(.abbreviated).year().hour().minute())
        let selected = selection.contains(item.id)
        return Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                HStack(alignment: .top, spacing: TT.Space.m) {
                    if selecting {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(selected ? TT.danger : TT.textTertiary).accessibilityHidden(true)
                    }
                    KindGlyph(symbol: segment.kind.ttSymbol, tint: segment.kind.ttTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: PlanFormat.longDay(day, calendar: model.dayCalendar)).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                        Text(verbatim: duration.map { "\(range) · \($0)" } ?? range).font(TTFont.numeral).foregroundStyle(TT.textPrimary)
                        Text(segment.kind.ttTitle).font(TTFont.meta).foregroundStyle(segment.kind.ttTint)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: TT.Space.xs) {
                    Text(verbatim: SG1.s("sg1.cancelled.on \(cancelledOn)")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    if let reason = item.cancelReason, !reason.isEmpty {
                        Text(verbatim: SG1.s("sg1.cancelled.reason \(reason)")).font(TTFont.body).foregroundStyle(TT.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        SG1.t("sg1.cancelled.no_reason").font(TTFont.meta).foregroundStyle(TT.textTertiary)
                    }
                }
                if failedId == item.id, let failure = store.restoreFailure {
                    HintCallout(text: failureText(failure), symbol: "exclamationmark.triangle.fill", tint: TT.warning)
                        .accessibilityIdentifier("cancelled.restore_failure")
                }
                if !selecting {
                    VStack(alignment: .leading, spacing: TT.Space.s) {
                        Button { restore(item, store: store) } label: { SG1.t("sg1.cancelled.restore").frame(maxWidth: .infinity) }
                            .buttonStyle(.ttPrimary).disabled(restoring != nil).accessibilityIdentifier("cancelled.restore")
                        Button(role: .destructive) { purge = PurgeRequest(scope: .ids([item.id]), expected: 1) } label: {
                            SG1.t("sg1.cancelled.purge").frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.plain).foregroundStyle(TT.danger).accessibilityIdentifier("cancelled.purge")
                    }
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            guard selecting else { return }
            if selected { selection.remove(item.id) } else { selection.insert(item.id) }
        }
        .accessibilityElement(children: selecting ? .combine : .contain)
        .accessibilityLabel(selecting ? Text(verbatim: "\(PlanFormat.longDay(day, calendar: model.dayCalendar)), \(range)") : Text(verbatim: ""))
        .accessibilityAddTraits(selecting ? (selected ? [.isButton, .isSelected] : .isButton) : [])
        .accessibilityIdentifier("cancelled.item")
    }

    private func restore(_ item: CancelledSegment, store: CancelledStore) {
        guard restoring == nil else { return }
        restoring = item.id
        note = nil
        failedId = nil
        Task {
            if await store.restore(item) {
                note = SG1.s("sg1.cancelled.restored")
                await refreshTime()
            } else if store.restoreFailure != nil {
                failedId = item.id
            }
            restoring = nil
        }
    }

    private func refreshTime() async {
        await model.today?.load()
        await model.timeList?.load()
        await model.review?.load()
    }
}

/// SG2: what a bulk restore did: how many came back and which entries were refused, with the reason.
private struct RestoreReportSheet: View {
    let report: CancelledScreen.RestoreReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    Text(verbatim: SG1.s("sg2.bulk.report.restored \(report.restored)")).font(TTFont.cardTitle).foregroundStyle(TT.success)
                    Text(verbatim: SG1.s("sg2.bulk.report.failed \(report.failures.count)")).font(TTFont.cardTitle).foregroundStyle(TT.warning)
                    ForEach(report.failures) { line in
                        VStack(alignment: .leading, spacing: TT.Space.xs) {
                            Text(verbatim: line.title).font(TTFont.body.weight(.semibold)).foregroundStyle(TT.textPrimary)
                            HintCallout(text: line.reason, symbol: "exclamationmark.triangle.fill", tint: TT.warning)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("cancelled.report.line")
                    }
                    SG1.t("sg2.bulk.report.hint").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
                .padding(TT.Space.l)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(SG1.s("sg2.bulk.report.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button { dismiss() } label: { SG1.t("sg1.cancelled.select_done") }.accessibilityIdentifier("cancelled.report.close") } }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 440, minHeight: 320)
        #endif
        .accessibilityIdentifier("cancelled.report")
    }
}

/// Small non-error callout with a symbol (restore conflicts: the user can fix them, nothing is broken).
private struct HintCallout: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: TT.Space.s) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            Text(verbatim: text).font(TTFont.meta).foregroundStyle(TT.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(TT.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: .rect(cornerRadius: TT.Radius.control, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: TT.Radius.control, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// The strong confirmation before anything is deleted for good: the dry-run numbers, a warning and a typed word.
struct PurgeConfirmSheet: View {
    let scope: PurgeScope
    let onDone: (PurgeSummary) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var preview: PurgeSummary?
    @State private var loadFailed = false
    /// X4: exactly what the dry-run counted (for "all": the ids read with the preview); the deletion sends these ids.
    @State private var confirmedScope: PurgeScope?
    @State private var typed = ""
    @State private var busy = false

    private var word: String { SG1.s("sg1.purge.word") }
    private var confirmed: Bool { typed.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare(word) == .orderedSame }
    private var canDelete: Bool { confirmed && !busy && (preview?.segments ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    if let preview {
                        if preview.segments == 0 {
                            SG1.t("sg1.purge.nothing").font(TTFont.body).foregroundStyle(TT.textSecondary)
                        } else {
                            summary(preview)
                            SG1.t("sg1.purge.warning").font(TTFont.body).foregroundStyle(TT.textSecondary)
                            VStack(alignment: .leading, spacing: TT.Space.s) {
                                Text(verbatim: SG1.s("sg1.purge.type_prompt \(word)")).font(TTFont.body.weight(.semibold)).foregroundStyle(TT.textPrimary)
                                TextField(word, text: $typed)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.characters)
                                    #endif
                                    .autocorrectionDisabled()
                                    .padding(TT.Space.m)
                                    .ttSurface(radius: TT.Radius.control)
                                    .accessibilityIdentifier("purge.word")
                            }
                        }
                    } else if loadFailed {
                        ErrorBanner(message: model.cancelled?.error?.germanDescription ?? SG1.s("sg1.purge.unreadable"), retryTitle: "common.retry") { Task { await count() } }
                    } else {
                        HStack(spacing: TT.Space.s) { ProgressView(); SG1.t("sg1.purge.counting").font(TTFont.body).foregroundStyle(TT.textSecondary) }
                    }
                    if let error = model.cancelled?.error, preview != nil {
                        ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { model.cancelled?.error = nil }
                    }
                }
                .padding(TT.Space.l)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(SG1.s("sg1.purge.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) { delete() } label: { SG1.t("sg1.purge.confirm") }
                        .disabled(!canDelete)
                        .accessibilityIdentifier("purge.confirm")
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 440, minHeight: 380)
        #endif
        .interactiveDismissDisabled(busy)
        .task { await count() }
        .onAppear { model.cancelled?.error = nil; TTHaptics.play(.confirmDestructive) }
        .accessibilityIdentifier("purge.sheet")
    }

    private func summary(_ preview: PurgeSummary) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Text(verbatim: SG1.plural(headline: preview.segments)).font(TTFont.cardTitle).foregroundStyle(TT.danger)
                .accessibilityAddTraits(.isHeader)
            SG1.t("sg1.purge.heading").font(TTFont.meta).foregroundStyle(TT.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: SG1.s("sg1.purge.entries \(preview.segments)"))
                if preview.revisions > 0 { Text(verbatim: SG1.s("sg1.purge.revisions \(preview.revisions)")) }
                if preview.suggestions > 0 { Text(verbatim: SG1.s("sg1.purge.suggestions \(preview.suggestions)")) }
                if preview.timerEvents > 0 { Text(verbatim: SG1.s("sg1.purge.timer_events \(preview.timerEvents)")) }
            }
            .font(TTFont.body).foregroundStyle(TT.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("purge.summary")
    }

    private func count() async {
        loadFailed = false
        preview = nil
        confirmedScope = nil
        if let resolved = await model.cancelled?.confirmationScope(for: scope) {
            confirmedScope = resolved
            preview = await model.cancelled?.preview(resolved)
        }
        loadFailed = preview == nil
    }

    private func delete() {
        guard canDelete, let confirmedScope else { return }
        busy = true
        Task {
            if let summary = await model.cancelled?.purge(confirmedScope) {
                onDone(summary)
                dismiss()
            }
            busy = false
        }
    }
}

extension SG1 {
    /// "2 Einträge werden endgültig gelöscht" (plural variants in the catalog).
    static func plural(headline count: Int) -> String { String(localized: "sg1.purge.headline \(count)", table: "SG1") }
}
