import SwiftUI
import TimetrackCore
import TimetrackStores

struct TimeView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        Group {
            if let store = model.timeList {
                TimeContent(store: store)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("sidebar.time")
    }
}

private struct EditorRequest: Identifiable {
    let id = UUID()
    let segment: Segment?
    let day: LocalDay
}

private struct TimeContent: View {
    let store: TimeListStore
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var editor: EditorRequest?
    @State private var voiding: Segment?

    var body: some View {
        List {
            if let error = store.error {
                HStack {
                    error.messageText
                    Spacer()
                    Button("common.retry") { Task { await store.load() } }
                }
                .foregroundStyle(.red)
            }
            ForEach(store.days) { day in
                Section {
                    let segments = (day.segments ?? []).filter { !$0.voided }.sorted { $0.startedAt < $1.startedAt }
                    if segments.isEmpty {
                        Text(day.mark.map(markKey) ?? "time.no_entries").foregroundStyle(.secondary)
                    }
                    ForEach(segments) { segment in
                        SegmentRow(segment: segment, zone: store.calendar.timeZone)
                            .contentShape(.rect)
                            .onTapGesture(count: 2) { editor = EditorRequest(segment: segment, day: day.date) }
                            .contextMenu {
                                Button("time.edit") { editor = EditorRequest(segment: segment, day: day.date) }
                                Button("time.void", role: .destructive) { voiding = segment }
                            }
                    }
                } header: {
                    DayHeader(day: day, calendar: store.calendar) { editor = EditorRequest(segment: nil, day: day.date) }
                }
            }
        }
        .overlay { if store.days.isEmpty && store.isLoading { ProgressView() } }
        .task { await store.load() }
        .onChange(of: ui.newEntryRequest) { editor = EditorRequest(segment: nil, day: store.calendar.day(for: .now)) }
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await store.shiftWeeks(-1) } } label: { Label("time.previous_week", systemImage: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("time.this_week") { Task { await store.goToCurrentWeek() } }
                Button { Task { await store.shiftWeeks(1) } } label: { Label("time.next_week", systemImage: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button { editor = EditorRequest(segment: nil, day: store.calendar.day(for: .now)) } label: { Label("command.new_entry", systemImage: "plus") }
                    .help(Text("command.new_entry"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("time.week_range \(dayTitle(store.weekStart, calendar: store.calendar)) \(dayTitle(store.weekEnd, calendar: store.calendar))")
                Spacer()
                Text("time.week_total \(DurationFormat.hoursMinutes(store.weekEvaluatedSeconds)) \(DurationFormat.hoursMinutes(store.weekTargetSeconds))").monospacedDigit()
            }
            .font(.callout)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.bar)
        }
        .sheet(item: $editor) { request in
            SegmentEditor(store: store, segment: request.segment, day: request.day)
        }
        .sheet(item: $voiding) { segment in
            VoidSheet(store: store, segment: segment)
        }
    }

    private func markKey(_ mark: DayMarkKind) -> LocalizedStringKey {
        switch mark {
        case .holiday: "mark.holiday"
        case .vacation: "mark.vacation"
        case .sick: "mark.sick"
        case .excused: "mark.excused"
        case .schoolCredit: "mark.school_credit"
        case .unmarked, .unknown: "time.no_entries"
        }
    }
}

private struct DayHeader: View {
    let day: DayEvaluation
    let calendar: DayCalendar
    let add: () -> Void

    var body: some View {
        HStack {
            Text(dayTitle(day.date, calendar: calendar)).font(.headline)
            if day.provisional { Text("common.provisional").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Text("time.day_total \(DurationFormat.hoursMinutes(day.evaluatedWorkSeconds + day.creditSeconds)) \(DurationFormat.hoursMinutes(day.targetSeconds))")
                .monospacedDigit().font(.callout).foregroundStyle(.secondary)
            Text(DurationFormat.signed(day.deltaSeconds)).monospacedDigit().font(.callout)
                .foregroundStyle(day.deltaSeconds < 0 ? Color.orange : Color.green)
            Button(action: add) { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("time.add_to_day \(dayTitle(day.date, calendar: calendar))"))
        }
    }
}

private struct SegmentEditor: View {
    let store: TimeListStore
    let segment: Segment?
    let day: LocalDay
    @Environment(\.dismiss) private var dismiss

    @State private var kind: SegmentKind = .work
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var hasEnd = true
    @State private var note = ""
    @State private var reason = ""
    @State private var saving = false

    private var isEditing: Bool { segment != nil }
    private var valid: Bool {
        (!hasEnd || end > start) && (!isEditing || !reason.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        Form {
            Picker("editor.kind", selection: $kind) {
                ForEach(SegmentKind.selectable, id: \.self) { Text($0.titleKey).tag($0) }
            }
            DatePicker("editor.start", selection: $start, displayedComponents: [.date, .hourAndMinute])
            Toggle("editor.has_end", isOn: $hasEnd).disabled(segment?.endedAt != nil)
            if hasEnd { DatePicker("editor.end", selection: $end, displayedComponents: [.date, .hourAndMinute]) }
            TextField("editor.note", text: $note, axis: .vertical).lineLimit(1...3)
            if isEditing {
                TextField("editor.reason", text: $reason).accessibilityIdentifier("editor.reason")
                Text("editor.reason.hint").font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.error { error.messageText.foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("common.cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("common.save") { Task { await save() } }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid || saving)
            }
        }
        .formStyle(.grouped)
        .environment(\.timeZone, store.calendar.timeZone)
        .frame(width: 440)
        .padding()
        .onAppear(perform: load)
    }

    private func load() {
        store.error = nil
        if let segment {
            kind = segment.kind
            start = segment.startedAt
            end = segment.endedAt ?? segment.startedAt.addingTimeInterval(3600)
            hasEnd = segment.endedAt != nil
            note = segment.note ?? ""
        } else {
            start = store.calendar.instant(day: day, hour: 8, minute: 0) ?? .now
            end = store.calendar.instant(day: day, hour: 16, minute: 0) ?? .now
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok: Bool
        if let segment {
            // Only changed fields are sent; the backend keeps the raw times and adds a revision with the reason.
            let correction = SegmentCorrection(
                startedAt: start != segment.startedAt ? start : nil,
                endedAt: hasEnd && end != segment.endedAt ? end : nil,
                kind: kind != segment.kind ? kind : nil,
                note: trimmedNote != (segment.note ?? "") ? trimmedNote : nil,
                reason: reason.trimmingCharacters(in: .whitespaces))
            ok = await store.correct(segment, correction)
        } else {
            ok = await store.create(SegmentInput(kind: kind, startedAt: start, endedAt: hasEnd ? end : nil, note: trimmedNote.isEmpty ? nil : trimmedNote))
        }
        if ok { dismiss() }
    }
}

private struct VoidSheet: View {
    let store: TimeListStore
    let segment: Segment
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    var body: some View {
        Form {
            Text("void.title").font(.headline)
            TextField("editor.reason", text: $reason).accessibilityIdentifier("void.reason")
            if let error = store.error { error.messageText.foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("common.cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("time.void", role: .destructive) {
                    Task { if await store.void(segment, reason: reason.trimmingCharacters(in: .whitespaces)) { dismiss() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
        .onAppear { store.error = nil }
    }
}
