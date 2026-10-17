import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// What the absence editor needs from a store; lets the Urlaub tab and the calendar share one editor.
struct AbsenceEditorActions {
    var calendar: DayCalendar
    var today: LocalDay
    var save: (AbsenceInput, Absence?) async -> Bool
    var delete: (Absence) async -> Bool
    var cancel: (Absence) async -> Bool
    var error: () -> TimetrackError?
    var clearError: () -> Void
}

extension AbsenceEditorActions {
    @MainActor init(planning store: PlanningStore) {
        self.init(calendar: store.calendar, today: store.today,
                  save: { await store.saveAbsence($0, editing: $1) != nil },
                  delete: { await store.deleteAbsence($0) },
                  cancel: { absence in
                      var input = AbsenceInput(absence)
                      input.status = .cancelled
                      return await store.saveAbsence(input, editing: absence) != nil
                  },
                  error: { store.error }, clearError: { store.error = nil })
    }

    @MainActor init(calendar store: CalendarStore) {
        self.init(calendar: store.calendar, today: store.today,
                  save: { await store.saveAbsence($0, editing: $1) != nil },
                  delete: { await store.deleteAbsence($0) },
                  cancel: { await store.cancelAbsence($0) },
                  error: { store.error }, clearError: { store.error = nil })
    }
}

/// Create or edit one absence (vacation, sick, excused, other). The consumption is computed by the server after saving.
struct AbsenceEditorSheet: View {
    let request: AbsenceRequest
    let actions: AbsenceEditorActions
    @Environment(\.dismiss) private var dismiss

    @State private var kind: AbsenceKind = .vacation
    @State private var start: LocalDay = ""
    @State private var end: LocalDay = ""
    @State private var halfStart = false
    @State private var halfEnd = false
    @State private var status: AbsenceStatus = .planned
    @State private var statusTouched = false
    @State private var note = ""
    @State private var documentStatus: DocumentStatus = .notNeeded
    @State private var submittedOn: LocalDay = ""
    @State private var hasReference = false
    @State private var referenceStart: LocalDay = ""
    @State private var referenceEnd: LocalDay = ""
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var confirmCancel = false
    @State private var loaded = false

    private var editing: Absence? { request.editing }
    private var valid: Bool { !start.isEmpty && end >= start && (!hasReference || referenceEnd >= referenceStart) && note.count <= 500 }
    private var zone: DayCalendar { actions.calendar }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    FormSection("plan.field.kind", footer: kind.detailKey) {
                        EditorRow {
                            Picker("plan.field.kind", selection: $kind) {
                                ForEach(AbsenceKind.selectable, id: \.self) { Text($0.ttTitle).tag($0) }
                            }
                            .pickerStyle(.menu).labelsHidden()
                            .accessibilityIdentifier("absence.kind")
                        }
                    }
                    FormSection("plan.field.period", footer: "plan.field.half_hint") {
                        EditorRow { DatePicker("plan.field.from", selection: dayBinding($start, calendar: zone), displayedComponents: .date).accessibilityIdentifier("absence.start") }
                        EditorRow { DatePicker("plan.field.to", selection: dayBinding($end, calendar: zone), in: PlanFormat.local(start, calendar: zone)..., displayedComponents: .date).accessibilityIdentifier("absence.end") }
                        EditorRow { Toggle("plan.field.half_start", isOn: $halfStart) }
                        EditorRow { Toggle("plan.field.half_end", isOn: $halfEnd) }
                    }
                    FormSection("plan.field.status", footer: kind == .vacation ? "plan.field.status_hint" : "plan.field.status_hint_other") {
                        EditorRow {
                            Picker("plan.field.status", selection: Binding(get: { status }, set: { status = $0; statusTouched = true })) {
                                ForEach(AbsenceStatus.options(for: kind, keeping: editing?.status), id: \.self) { Text($0.pickerKey).tag($0) }
                            }
                            .pickerStyle(.menu).labelsHidden()
                            .accessibilityIdentifier("absence.status")
                        }
                    }
                    if kind == .sick { documentSection }
                    FormSection("plan.field.note") {
                        TextField("plan.field.note_placeholder", text: $note, axis: .vertical).lineLimit(1...4)
                            .accessibilityIdentifier("absence.note").padding(TT.Space.l)
                    }
                    consumption
                    if let error = actions.error() {
                        ErrorBanner(message: error.germanDescription, retryTitle: "common.dismiss") { actions.clearError() }.accessibilityIdentifier("absence.error")
                    }
                    if editing != nil { destructive }
                }
                .padding(TT.Space.l)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(editing == nil ? kind.actionKey : "plan.editor.edit")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { Task { await save() } }.disabled(!valid || saving).accessibilityIdentifier("absence.save")
                }
            }
        }
        .environment(\.timeZone, zone.timeZone)
        .environment(\.calendar, Self.mondayCalendar(zone.timeZone))
        .onAppear(perform: load)
        .onChange(of: start) {
            if end < start { end = start }
            applyDefaultStatus()
        }
        .onChange(of: kind) {
            if !AbsenceStatus.options(for: kind, keeping: editing?.status).contains(status) { status = defaultStatus }
        }
        .confirmationDialog("plan.delete.title", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("plan.delete.confirm", role: .destructive) {
                guard let editing else { return }
                Task { if await actions.delete(editing) { dismiss() } }
            }
        } message: { Text("plan.delete.message") }
        .confirmationDialog("plan.cancel.title", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("plan.cancel.confirm", role: .destructive) {
                guard let editing else { return }
                Task { if await actions.cancel(editing) { dismiss() } }
            }
        } message: { Text("plan.cancel.message") }
    }

    private static func mondayCalendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private var documentSection: some View {
        FormSection("plan.field.documents", footer: "plan.field.documents_hint") {
            EditorRow {
                Picker("plan.field.document_status", selection: $documentStatus) {
                    ForEach([DocumentStatus.notNeeded, .pending, .submitted], id: \.self) { Text($0.pickerKey).tag($0) }
                }
                .pickerStyle(.menu).accessibilityIdentifier("absence.document")
            }
            if documentStatus == .submitted {
                EditorRow { DatePicker("plan.field.submitted_on", selection: dayBinding($submittedOn, calendar: zone), displayedComponents: .date) }
            }
            if documentStatus != .notNeeded {
                EditorRow { Toggle("plan.field.reference", isOn: $hasReference) }
                if hasReference {
                    EditorRow { DatePicker("plan.field.reference_from", selection: dayBinding($referenceStart, calendar: zone), displayedComponents: .date) }
                    EditorRow { DatePicker("plan.field.reference_to", selection: dayBinding($referenceEnd, calendar: zone), in: PlanFormat.local(referenceStart, calendar: zone)..., displayedComponents: .date) }
                }
            }
        }
    }

    @ViewBuilder private var consumption: some View {
        if kind == .vacation {
            if let editing {
                HintBanner(LocalizedStringKey("plan.counted.vacation \(PlanFormat.days(editing.countedHalfDays))"), symbol: "beach.umbrella.fill")
            } else {
                HintBanner("plan.counted.after_save", symbol: "beach.umbrella.fill")
            }
        } else if kind == .excused {
            HintBanner("plan.counted.excused", symbol: "checkmark.seal.fill")
        }
    }

    private var destructive: some View {
        VStack(spacing: TT.Space.s) {
            if editing?.status != .cancelled {
                Button("plan.cancel.action") { confirmCancel = true }.buttonStyle(.ttSecondary).accessibilityIdentifier("absence.cancel")
            }
            Button("plan.delete.action", role: .destructive) { confirmDelete = true }.buttonStyle(.ttSecondary).foregroundStyle(TT.danger)
                .accessibilityIdentifier("absence.delete")
        }
    }

    private var defaultStatus: AbsenceStatus { start <= actions.today ? .taken : .planned }

    private func applyDefaultStatus() {
        guard editing == nil, !statusTouched, loaded else { return }
        status = defaultStatus
    }

    private func load() {
        guard !loaded else { return }
        actions.clearError()
        kind = request.kind
        start = request.start
        end = request.end
        if let absence = editing {
            halfStart = absence.halfDayStart ?? false
            halfEnd = absence.halfDayEnd ?? false
            status = absence.status == .unknown ? .planned : absence.status
            statusTouched = true
            note = absence.note ?? ""
            documentStatus = absence.documentStatus == .unknown ? .notNeeded : (absence.documentStatus ?? .notNeeded)
            submittedOn = absence.documentSubmittedOn ?? actions.today
            hasReference = absence.documentReferenceStart != nil && absence.documentReferenceEnd != nil
            referenceStart = absence.documentReferenceStart ?? absence.startDate
            referenceEnd = absence.documentReferenceEnd ?? absence.endDate
        } else {
            status = defaultStatus
            submittedOn = actions.today
            referenceStart = request.start
            referenceEnd = request.end
        }
        loaded = true
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSick = kind == .sick
        let input = AbsenceInput(
            kind: kind, startDate: start, endDate: end, halfDayStart: halfStart, halfDayEnd: halfEnd, status: status,
            note: trimmed.isEmpty ? nil : trimmed,
            documentStatus: isSick ? documentStatus : .notNeeded,
            documentSubmittedOn: isSick && documentStatus == .submitted ? submittedOn : nil,
            documentReferenceStart: isSick && documentStatus != .notNeeded && hasReference ? referenceStart : nil,
            documentReferenceEnd: isSick && documentStatus != .notNeeded && hasReference ? referenceEnd : nil)
        if await actions.save(input, editing) { dismiss() }
    }
}

/// Presents the absence editor from a request binding.
private struct AbsenceEditorModifier: ViewModifier {
    @Binding var request: AbsenceRequest?
    let actions: AbsenceEditorActions

    func body(content: Content) -> some View {
        content.sheet(item: $request) { request in
            AbsenceEditorSheet(request: request, actions: actions)
                .presentationDetents([.large])
        }
    }
}

extension View {
    func absenceEditor(_ request: Binding<AbsenceRequest?>, actions: AbsenceEditorActions) -> some View {
        modifier(AbsenceEditorModifier(request: request, actions: actions))
    }
}

/// Menu entries "Urlaub eintragen", "Krank melden", ... for a prefilled period.
struct AbsenceQuickMenuItems: View {
    let start: LocalDay
    let end: LocalDay
    let onPick: (AbsenceRequest) -> Void

    var body: some View {
        ForEach(AbsenceKind.selectable, id: \.self) { kind in
            Button { onPick(AbsenceRequest(kind: kind, start: start, end: end)) } label: { Label(kind.actionKey, systemImage: kind.ttSymbol) }
                .accessibilityIdentifier("quick.\(kind.rawValue)")
        }
    }
}
