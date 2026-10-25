import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// "Arbeitsmodell": all versions of the work model; each can be corrected in place (contract v0.16.0) after a preview and a confirmation.
struct WorkModelsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var store: WorkModelStore?
    @State private var sheet: WorkModelSheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                Text("workmodel.intro").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                if let store {
                    if let error = store.error {
                        ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await store.load() } }
                    }
                    if !store.supportsCorrection && !store.models.isEmpty { HintBanner("workmodel.unsupported") }
                    if store.models.isEmpty && !store.isLoading { Card { EmptyState(symbol: "calendar.badge.clock", title: "workmodel.empty") } }
                    timeline(store)
                    Button { sheet = .new } label: { Label(wmKey("wm.new.button"), systemImage: "plus") }
                        .buttonStyle(.ttPrimary)
                        .accessibilityIdentifier("workmodel.new")
                } else {
                    SkeletonList(rows: 3)
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("workmodel.title")
        .task {
            if store == nil, let client = model.apiClient {
                let created = WorkModelStore(client: client)
                created.onOutcome = { TTHaptics.handle($0) }
                created.onSaved = { Task { await model.reloadWorkModel() } }
                store = created
            }
            await store?.load()
        }
        .sheet(item: $sheet) { sheet in
            if let store {
                switch sheet {
                case .edit(let version): WorkModelEditSheet(store: store, version: version, calendar: model.dayCalendar)
                case .new: WorkModelNewSheet(store: store, calendar: model.dayCalendar)
                case .end(let version): WorkModelEndSheet(store: store, version: version, calendar: model.dayCalendar)
                }
            }
        }
    }

    /// History, newest first: a rail with one dot per version, gaps between versions called out.
    @ViewBuilder private func timeline(_ store: WorkModelStore) -> some View {
        let versions = store.newestFirst
        let gaps = store.models.gaps
        let today = model.dayCalendar.day(for: .now)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                HStack(alignment: .top, spacing: TT.Space.m) {
                    TimelineRail(highlighted: version.validFrom <= today && (version.validTo.map { $0 >= today } ?? true), isLast: index == versions.count - 1)
                    WorkModelCard(model: version, today: today, canEdit: store.supportsCorrection, edit: { sheet = .edit(version) }, end: { sheet = .end(version) })
                        .padding(.bottom, TT.Space.m)
                }
                if let gap = gaps[version.id] { TimelineGapRow(from: gap.from, to: gap.to) }
            }
        }
    }
}

struct WorkModelCard: View {
    let model: WorkModel
    let today: LocalDay
    let canEdit: Bool
    let edit: () -> Void
    let end: () -> Void

    private var isCurrent: Bool { model.validFrom <= today && (model.validTo.map { $0 >= today } ?? true) }
    private var isFuture: Bool { model.validFrom > today }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                HStack(alignment: .firstTextBaseline, spacing: TT.Space.s) {
                    Text(verbatim: Self.range(model)).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                    if isCurrent { StatusChip("workmodel.current", tone: .accent) }
                    if isFuture { StatusChip("workmodel.future", tone: .neutral) }
                    Spacer(minLength: 0)
                }
                VStack(spacing: 0) {
                    row("workmodel.weekly", DurationFormat.hoursMinutes(model.weeklyTargetSeconds))
                    row("workmodel.workdays", Self.workdays(model.workdays))
                    row("workmodel.rounding", (model.roundingEnabled ?? true) ? "\(model.roundingMinutes ?? 15) min" : String(localized: "workmodel.off"))
                    row("workmodel.timezone", model.timezone ?? "Europe/Berlin")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: TT.Space.s) { actions }
                    VStack(alignment: .leading, spacing: TT.Space.s) { actions }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var actions: some View {
        if canEdit {
            Button { edit() } label: { Label("workmodel.edit", systemImage: "pencil") }
                .buttonStyle(.ttSecondary)
                .accessibilityIdentifier("workmodel.edit")
        }
        if model.validTo == nil {
            Button { end() } label: { Label(wmKey("wm.end.button"), systemImage: "calendar.badge.minus") }
                .buttonStyle(.ttSecondary)
                .accessibilityIdentifier("workmodel.end")
        }
    }

    private func row(_ key: LocalizedStringKey, _ value: String) -> some View {
        FormRow(key) { Text(verbatim: value).monospacedDigit() }.padding(.vertical, 2)
    }

    static func range(_ model: WorkModel) -> String {
        let from = display(model.validFrom)
        return model.validTo.map { "\(from) – \(display($0))" } ?? String(localized: "workmodel.range_open \(from)")
    }

    /// `2026-10-19` -> `19.10.2026`.
    static func display(_ day: LocalDay) -> String {
        let parts = day.split(separator: "-")
        return parts.count == 3 ? "\(parts[2]).\(parts[1]).\(parts[0])" : day
    }

    static func workdays(_ days: [Int]) -> String {
        let names = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        return days.sorted().compactMap { (1...7).contains($0) ? names[$0 - 1] : nil }.joined(separator: ", ")
    }
}

/// Correction of one version: prominent warning, form, live preview of the effect on the balance, explicit confirmation.
struct WorkModelEditSheet: View {
    let store: WorkModelStore
    let version: WorkModel
    let calendar: DayCalendar
    @Environment(\.dismiss) private var dismiss
    @State private var form: WorkModelForm
    @State private var confirmed = false
    @State private var saving = false
    @State private var showErrors = false

    init(store: WorkModelStore, version: WorkModel, calendar: DayCalendar) {
        self.store = store
        self.version = version
        self.calendar = calendar
        _form = State(initialValue: WorkModelForm(model: version))
    }

    private var canSave: Bool { confirmed && !saving && store.canSave(form: form) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    correctionPanel
                    WorkModelFormFields(form: $form, calendar: calendar)
                    if let error = store.error {
                        ErrorBanner(message: Self.message(error), retryTitle: "common.dismiss") { store.error = nil }
                    }
                    Button { Task { await save() } } label: { Text("workmodel.save") }
                        .buttonStyle(.ttDanger)
                        .disabled(!canSave)
                        .accessibilityIdentifier("workmodel.save")
                }
                .padding(TT.Space.l).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle("workmodel.edit_title").inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { store.resetPreview(); dismiss() } } }
        }
        .environment(\.timeZone, calendar.timeZone)
        .onAppear { store.error = nil; store.updatePreview(for: version, form: form) }
        .onChange(of: form) {
            confirmed = false
            store.updatePreview(for: version, form: form)
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 700)
        #endif
    }

    // MARK: Warning, preview, confirmation

    private var correctionPanel: some View {
        VStack(alignment: .leading, spacing: TT.Space.m) {
            HStack(alignment: .top, spacing: TT.Space.m) {
                Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(TT.danger).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: TT.Space.xs) {
                    Text("workmodel.warning_title").font(TTFont.cardTitle).foregroundStyle(TT.danger)
                    Text("workmodel.warning \(WorkModelCard.display(form.validFrom)) \(form.validTo.isEmpty ? String(localized: "workmodel.open_end") : WorkModelCard.display(form.validTo))")
                        .font(TTFont.label).foregroundStyle(TT.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workmodel.warning")
            previewBox
            Toggle(isOn: $confirmed) { Text("workmodel.confirm").font(TTFont.label).foregroundStyle(TT.textPrimary) }
                .accessibilityIdentifier("workmodel.confirm")
        }
        .padding(TT.Space.l)
        .background(TT.danger.opacity(0.10), in: .rect(cornerRadius: TT.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: TT.Radius.card, style: .continuous).strokeBorder(TT.danger.opacity(0.6), lineWidth: 2) }
    }

    @ViewBuilder private var previewBox: some View {
        VStack(alignment: .leading, spacing: TT.Space.xs) {
            Eyebrow("workmodel.preview_title")
            switch store.preview {
            case .idle, .loading:
                Text("workmodel.preview_loading").font(TTFont.meta).foregroundStyle(TT.textSecondary)
            case .invalid:
                Text("workmodel.preview_invalid").font(TTFont.meta).foregroundStyle(TT.textSecondary)
            case .failed(let error):
                Text(verbatim: Self.message(error)).font(TTFont.label).foregroundStyle(TT.danger)
            case .ready(let preview):
                Text(verbatim: Self.previewLine(preview)).font(TTFont.numeral).foregroundStyle(TT.textPrimary).accessibilityIdentifier("workmodel.preview.line")
                if preview.differenceSeconds == 0 { Text("workmodel.preview_none").font(TTFont.meta).foregroundStyle(TT.textSecondary) }
                if !preview.changedFieldNames.isEmpty {
                    Text("workmodel.preview_fields \(preview.changedFieldNames.joined(separator: ", "))").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
                if let previous = preview.previousValidTo {
                    Text("workmodel.preview_previous \(WorkModelCard.display(previous))").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
            }
        }
        .padding(TT.Space.m).frame(maxWidth: .infinity, alignment: .leading)
        .background(TT.surface, in: .rect(cornerRadius: TT.Radius.control, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// `Zeitkonto heute: vorher +1:00 -> nachher -0:30 (-1:30), betroffen: 48 Tage`.
    static func previewLine(_ preview: WorkModelPreview) -> String {
        let difference = preview.differenceSeconds == 0 ? "±0:00" : DurationFormat.signed(preview.differenceSeconds).replacingOccurrences(of: "-", with: "−")
        let days = preview.affectedDays == 1 ? "1 Tag" : "\(preview.affectedDays) Tage"
        return "Zeitkonto heute: vorher \(DurationFormat.signed(preview.balanceBeforeSeconds)) → nachher \(DurationFormat.signed(preview.balanceAfterSeconds)) (\(difference)), betroffen: \(days)"
    }

    static func message(_ error: TimetrackError) -> String {
        switch error.knownCode {
        case .modelOverlap: String(localized: "workmodel.error_overlap")
        case .staleVersion: String(localized: "workmodel.error_stale")
        default: error.germanDescription
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        if await store.save(model: version, form: form) != nil { dismiss() }
    }
}
