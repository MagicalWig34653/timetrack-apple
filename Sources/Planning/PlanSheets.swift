import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Hosts the small planning sheets (plan day, custom day, manual time entry).
struct PlanSheetHost: View {
    let sheet: PlanSheet
    let store: CalendarStore
    @Environment(AppModel.self) private var model

    var body: some View {
        switch sheet {
        case .plan(let day): PlanDaySheet(store: store, day: day)
        case .customDay(let day): CustomDaySheet(store: store, day: day)
        case .manualEntry(let day):
            if let list = model.timeList { ManualEntrySheet(store: store, list: list, day: day) }
        case .eventDraft(let day, let event):
            if let list = model.timeList { EventDraftSheet(store: store, list: list, day: day, event: event) }
        case .settings: EmptyView()
        }
    }
}

struct SheetFrame<Content: View>: View {
    let title: LocalizedStringKey
    let canSave: Bool
    let saving: Bool
    let identifier: String
    let save: () async -> Void
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) { content }
                    .padding(TT.Space.l).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(title).inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("common.save") { Task { await save() } }.disabled(!canSave || saving).accessibilityIdentifier("\(identifier).save") }
            }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }
}

struct PlanDaySheet: View {
    let store: CalendarStore
    let day: LocalDay
    @Environment(\.dismiss) private var dismiss
    @State private var mode: PlanMode = .office
    @State private var note = ""
    @State private var saving = false
    @State private var blocks: [PlanTimeBlock] = []
    @State private var places: [Place] = []
    @Environment(AppModel.self) private var model

    var body: some View {
        SheetFrame(title: "plan.sheet.plan", canSave: true, saving: saving, identifier: "plan", save: save) {
            Text(verbatim: PlanFormat.longDay(day, calendar: store.calendar)).font(TTFont.cardTitle)
            FormSection("plan.field.mode", footer: "plan.hint") {
                EditorRow {
                    Picker("plan.field.mode", selection: $mode) { ForEach(PlanMode.selectable, id: \.self) { Text($0.title).tag($0) } }
                        .pickerStyle(.menu).labelsHidden().accessibilityIdentifier("plan.mode")
                }
            }
            if model.planBlocksSupported, mode != .off {
                FormSection("Zeitblöcke", footer: "Ein Tag kann mehrere Blöcke haben, zum Beispiel Schule am Vormittag und Arbeit am Nachmittag. Lücken dazwischen gelten als Pausen.") {
                    PlanBlockEditor(blocks: $blocks, defaultKind: WeekPlan.defaultKind(for: mode), places: places, idPrefix: "plan.blocks").padding(TT.Space.m)
                    PlanHintsView(hints: WeekPlan.hints(for: blocks)).padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.m)
                }
            }
            FormSection("plan.field.note") { TextField("plan.field.note_placeholder", text: $note, axis: .vertical).lineLimit(1...3).padding(TT.Space.l).accessibilityIdentifier("plan.note") }
            if store.planDays[day] != nil {
                Button("plan.remove", role: .destructive) { Task { if await store.removePlan(day: day) { dismiss() } } }.buttonStyle(.ttSecondary).foregroundStyle(TT.danger)
            }
            if let error = store.error { ErrorBanner(message: error.germanMessage(in: .planBlocks), retryTitle: "common.dismiss") { store.error = nil } }
        }
        .task {
            if model.systemInfo.info == nil { await model.refreshSystemInfo() }
            if model.planBlocksSupported, places.isEmpty, let client = model.apiClient { places = ((try? await client.listPlaces()) ?? []).filter { !$0.archived } }
        }
        .onAppear {
            store.error = nil
            if let plan = store.planDays[day] { mode = plan.mode == .unknown ? .office : plan.mode; note = plan.note ?? ""; blocks = plan.blocks }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        // PUT replaces the whole day: planned times from the week planner (K1) must be sent along.
        let stored = store.planDays[day]
        let input = WeekPlan.dayInput(mode: mode, note: trimmed.isEmpty ? nil : trimmed, stored: stored, blocks: blocks, multi: model.planBlocksSupported)
        if await store.savePlan(day: day, input) { dismiss() }
    }
}

struct CustomDaySheet: View {
    let store: CalendarStore
    let day: LocalDay
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CalendarDayKind = .holiday
    @State private var name = ""
    @State private var start: LocalDay = ""
    @State private var end: LocalDay = ""
    @State private var saving = false

    var body: some View {
        SheetFrame(title: "plan.sheet.custom_day", canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && end >= start, saving: saving, identifier: "custom", save: save) {
            FormSection("plan.field.kind", footer: "custom_day.hint") {
                EditorRow {
                    Picker("plan.field.kind", selection: $kind) {
                        Text("custom_day.kind_holiday").tag(CalendarDayKind.holiday)
                        Text("custom_day.kind_school_holiday").tag(CalendarDayKind.schoolHoliday)
                    }
                    .pickerStyle(.menu).labelsHidden().accessibilityIdentifier("custom.kind")
                }
            }
            FormSection("custom_day.name") { TextField("custom_day.name", text: $name).padding(TT.Space.l).accessibilityIdentifier("custom.name") }
            FormSection("plan.field.period") {
                EditorRow { DatePicker("plan.field.from", selection: dayBinding($start, calendar: store.calendar), displayedComponents: .date) }
                EditorRow { DatePicker("plan.field.to", selection: dayBinding($end, calendar: store.calendar), in: PlanFormat.local(start, calendar: store.calendar)..., displayedComponents: .date) }
            }
            if let error = store.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.dismiss") { store.error = nil } }
        }
        .environment(\.timeZone, store.calendar.timeZone)
        .onAppear { store.error = nil; start = day; end = day }
        .onChange(of: start) { if end < start { end = start } }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        if await store.createCustomDay(CustomDayInput(kind: kind, startDate: start, endDate: end, name: String(name.trimmingCharacters(in: .whitespaces).prefix(80)))) { dismiss() }
    }
}

/// Manual time entry on a given date (uses `TimeListStore.create`, the same API as the Zeit tab).
struct ManualEntrySheet: View {
    let store: CalendarStore
    let list: TimeListStore
    let day: LocalDay
    @Environment(\.dismiss) private var dismiss
    @State private var kind: SegmentKind = .work
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var note = ""
    @State private var saving = false

    var body: some View {
        SheetFrame(title: "plan.sheet.segment", canSave: end > start, saving: saving, identifier: "segment", save: save) {
            Text(verbatim: PlanFormat.longDay(day, calendar: store.calendar)).font(TTFont.cardTitle)
            FormSection("editor.kind") { KindSelector(selection: $kind).padding(TT.Space.m) }
            FormSection("editor.time") {
                EditorRow { DatePicker("editor.start", selection: $start, displayedComponents: .hourAndMinute).accessibilityIdentifier("segment.start") }
                EditorRow { DatePicker("editor.end", selection: $end, displayedComponents: .hourAndMinute).accessibilityIdentifier("segment.end") }
            }
            FormSection("editor.note") { TextField("editor.note", text: $note, axis: .vertical).lineLimit(1...3).padding(TT.Space.l) }
            if let error = list.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.dismiss") { list.error = nil } }
        }
        .environment(\.timeZone, store.calendar.timeZone)
        .onAppear {
            list.error = nil
            start = store.calendar.instant(day: day, hour: 8, minute: 0) ?? .now
            end = store.calendar.instant(day: day, hour: 16, minute: 0) ?? .now
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if await list.create(SegmentInput(kind: kind, startedAt: start, endedAt: end, note: trimmed.isEmpty ? nil : trimmed)) {
            await store.loadDetail()
            dismiss()
        }
    }
}
