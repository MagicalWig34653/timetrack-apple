import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Editor of one Berichtsheft entry. Saves by itself shortly after every change (see `ReportEntryEditor`); "Fertig" saves what is
/// pending and closes. Input is never dropped: when saving fails the sheet stays open and says so.
struct ReportEntrySheet: View {
    let store: ReportsStore
    @State private var editor: ReportEntryEditor
    @Environment(\.dismiss) private var dismiss
    @SwiftUI.FocusState private var focus: Field?
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    @State private var closing = false

    enum Field { case learningField, duration, notes }

    init(store: ReportsStore, entry: ReportEntry?, day: LocalDay) {
        self.store = store
        _editor = State(initialValue: ReportEntryEditor(store: store, entry: entry, day: day))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    stateBanner
                    dateCard
                    fieldCard
                    durationCard
                    notesCard
                    if !editor.isNew {
                        Button(role: .destructive) { confirmDelete = true } label: { Label(BH.s("entry.delete"), systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.ttSecondary).accessibilityIdentifier("reports.entry.delete")
                    }
                }
                .padding(TT.Space.l).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .ttScreenBackground()
            .navigationTitle(BH.s(editor.isNew ? "editor.title_new" : "editor.title_edit"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(BH.s("editor.done")) { Task { await finish() } }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(closing)
                        .accessibilityIdentifier("reports.entry.done")
                }
                ToolbarItem(placement: .principal) { SaveStateLabel(state: editor.state) }
            }
            .interactiveDismissDisabled(editor.hasUnsavedChanges)
            .confirmationDialog(BH.s("entry.delete_confirm", editor.fieldName.isEmpty ? BH.s("entry.this") : editor.fieldName), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(BH.s("entry.delete"), role: .destructive) { Task { await deleteEntry() } }
            }
            .confirmationDialog(BH.s("editor.discard_title"), isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button(BH.s("editor.discard"), role: .destructive) { editor.cancel(); dismiss() }
                Button(BH.s("editor.keep_editing"), role: .cancel) {}
            } message: { Text(verbatim: BH.s("editor.discard_message")) }
        }
        .onDisappear { editor.cancel() }
        .task {
            if !store.fieldsLoaded { await store.loadLearningFields() }
            if editor.isNew { focus = .learningField }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    // MARK: Parts

    @ViewBuilder private var stateBanner: some View {
        switch editor.state {
        case .failed(let failure):
            VStack(alignment: .leading, spacing: TT.Space.s) {
                HintBanner(LocalizedStringKey(BH.s(failure.isNetworkError ? "state.offline" : "state.failed", failure.germanDescription)), symbol: "exclamationmark.triangle.fill")
                Button(BH.s("state.retry")) { Task { await editor.flush() } }.buttonStyle(.ttSecondary).frame(minHeight: 44)
                    .accessibilityIdentifier("reports.entry.retry")
            }
        case .conflict(let current):
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Text(verbatim: BH.s("conflict.title")).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                Text(verbatim: BH.s("conflict.text")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                if let current {
                    Text(verbatim: BH.s("conflict.current", current.learningField, DurationFormat.hoursMinutes(current.durationSeconds))).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    Button(BH.s("conflict.reload")) { editor.useServerVersion() }.buttonStyle(.ttSecondary).frame(minHeight: 44)
                        .accessibilityIdentifier("reports.entry.reload")
                }
                Button(BH.s("conflict.keep_mine")) { Task { await editor.keepMine() } }.buttonStyle(.ttSecondary).frame(minHeight: 44)
                    .accessibilityIdentifier("reports.entry.keep")
            }
            .padding(TT.Space.m).background(TT.warning.opacity(0.12), in: .rect(cornerRadius: TT.Radius.control, style: .continuous))
        case .gone:
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Text(verbatim: BH.s("gone.title")).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                Text(verbatim: BH.s("gone.text")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                Button(BH.s("gone.save_new")) { Task { await editor.saveAsNew() } }.buttonStyle(.ttSecondary).frame(minHeight: 44)
            }
            .padding(TT.Space.m).background(TT.warning.opacity(0.12), in: .rect(cornerRadius: TT.Radius.control, style: .continuous))
        default:
            EmptyView()
        }
    }

    private var dateCard: some View {
        Card {
            DatePicker(BH.s("editor.date"), selection: dayBinding($editor.date, calendar: store.calendar), displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "de_DE"))
                .environment(\.timeZone, store.calendar.timeZone)
                .frame(minHeight: 44)
                .accessibilityIdentifier("reports.entry.date")
        }
    }

    private var fieldCard: some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Text(verbatim: BH.s("editor.field")).font(TTFont.label).foregroundStyle(TT.textSecondary)
                HStack(spacing: TT.Space.s) {
                    TextField(BH.s("editor.field_placeholder"), text: $editor.fieldName)
                        .focused($focus, equals: .learningField)
                        .textFieldStyle(.plain).ttField()
                        .submitLabel(.next).onSubmit { focus = .duration }
                        .accessibilityIdentifier("reports.entry.field")
                    if !store.learningFields.isEmpty {
                        Menu {
                            ForEach(store.learningFields) { field in
                                Button { editor.select(field) } label: { Text(verbatim: field.displayName) }
                            }
                        } label: { Image(systemName: "list.bullet").frame(width: 44, height: 44).contentShape(.rect) }
                            .accessibilityLabel(Text(verbatim: BH.s("editor.field_pick")))
                            .accessibilityIdentifier("reports.entry.field_pick")
                    }
                }
                if editor.fieldId != nil {
                    Label(BH.s("editor.field_linked"), systemImage: "link").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                } else {
                    Text(verbatim: BH.s("editor.field_hint")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
                if editor.problems.contains(.fieldTooLong) { problem(BH.s("editor.field_too_long")) }
            }
        }
    }

    private var durationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Text(verbatim: BH.s("editor.duration")).font(TTFont.label).foregroundStyle(TT.textSecondary)
                TextField(BH.s("editor.duration_placeholder"), text: $editor.durationText)
                    .focused($focus, equals: .duration)
                    .textFieldStyle(.plain).ttField()
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                    .accessibilityIdentifier("reports.entry.duration")
                durationHint
            }
        }
    }

    @ViewBuilder private var durationHint: some View {
        if let parsed = editor.parsedDuration {
            let shown = DurationFormat.hoursMinutes(parsed.seconds)
            switch parsed.kind {
            case .empty: Text(verbatim: BH.s("editor.duration_hint")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            case .clock: Text(verbatim: BH.s("editor.duration_parsed", shown)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            case .decimal: Text(verbatim: BH.s("editor.duration_decimal", shown)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            case .hours: Text(verbatim: BH.s("editor.duration_hours", shown)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
        } else {
            problem(BH.s("editor.duration_invalid"))
        }
    }

    private var notesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Text(verbatim: BH.s("editor.notes")).font(TTFont.label).foregroundStyle(TT.textSecondary)
                TextEditor(text: $editor.notes)
                    .focused($focus, equals: .notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(TT.Space.s)
                    .background(TT.surfaceRaised, in: .rect(cornerRadius: TT.Radius.control, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: TT.Radius.control, style: .continuous).strokeBorder(TT.cardBorder, lineWidth: 1) }
                    .accessibilityLabel(Text(verbatim: BH.s("editor.notes")))
                    .accessibilityIdentifier("reports.entry.notes")
                if editor.problems.contains(.notesTooLong) {
                    problem(BH.s("editor.notes_too_long"))
                } else {
                    Text(verbatim: BH.s("editor.notes_count", editor.notes.count)).font(TTFont.meta).foregroundStyle(TT.textSecondary).monospacedDigit()
                }
            }
        }
    }

    private func problem(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle.fill").font(TTFont.meta).foregroundStyle(TT.danger)
    }

    // MARK: Actions

    private func finish() async {
        closing = true
        defer { closing = false }
        await editor.flush()
        switch editor.state {
        case .saved, .idle: dismiss()
        case .invalid where !editor.hasUnsavedChanges: dismiss()
        default: confirmDiscard = true
        }
    }

    private func deleteEntry() async {
        guard let entry = editor.entry else { return }
        editor.cancel()
        if await store.delete(entry) { dismiss() }
    }
}

/// Small status in the title area: shows that autosave works (or why not) without a modal.
struct SaveStateLabel: View {
    let state: ReportEntryEditor.SaveState

    var body: some View {
        Group {
            switch state {
            case .idle: Color.clear.frame(width: 1, height: 1)
            case .pending, .saving: Label(BH.s("state.saving"), systemImage: "arrow.triangle.2.circlepath")
            case .saved: Label(BH.s("state.saved"), systemImage: "checkmark.circle")
            case .invalid: Label(BH.s("state.invalid"), systemImage: "exclamationmark.circle").foregroundStyle(TT.warning)
            case .failed: Label(BH.s("state.not_saved"), systemImage: "exclamationmark.triangle").foregroundStyle(TT.warning)
            case .conflict, .gone: Label(BH.s("state.conflict"), systemImage: "exclamationmark.triangle").foregroundStyle(TT.warning)
            }
        }
        .font(TTFont.meta).foregroundStyle(TT.textSecondary)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .accessibilityIdentifier("reports.entry.state")
    }
}
