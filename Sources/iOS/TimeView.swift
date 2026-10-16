import SwiftUI
import TimetrackCore
import TimetrackStores

struct TimeView: View {
    @Environment(AppModel.self) private var model

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
    @State private var editor: EditorRequest?
    @State private var voiding: Segment?

    var body: some View {
        List {
            if let error = store.error {
                ErrorBanner(error: error) { Task { await store.load() } }
                    .listRowSeparator(.hidden)
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
                            .onTapGesture { editor = EditorRequest(segment: segment, day: day.date) }
                            .swipeActions(edge: .trailing) {
                                Button("time.void", role: .destructive) { voiding = segment }
                                Button("time.edit") { editor = EditorRequest(segment: segment, day: day.date) }.tint(.accentColor)
                            }
                            .accessibilityAction(named: Text("time.edit")) { editor = EditorRequest(segment: segment, day: day.date) }
                            .accessibilityAction(named: Text("time.void")) { voiding = segment }
                    }
                } header: {
                    DayHeader(day: day, calendar: store.calendar) { editor = EditorRequest(segment: nil, day: day.date) }
                }
            }
        }
        .overlay { if store.days.isEmpty && store.isLoading { ProgressView() } }
        .task { await store.load() }
        .refreshable { await store.load() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { editor = EditorRequest(segment: nil, day: store.calendar.day(for: .now)) } label: { Label("command.new_entry", systemImage: "plus") }
                    .accessibilityIdentifier("time.new")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { Task { await store.shiftWeeks(-1) } } label: { Label("time.previous_week", systemImage: "chevron.left") }
                Spacer()
                VStack(spacing: 0) {
                    Text("time.week_range \(dayTitle(store.weekStart, calendar: store.calendar)) \(dayTitle(store.weekEnd, calendar: store.calendar))").font(.footnote)
                    Text("time.week_total \(DurationFormat.hoursMinutes(store.weekEvaluatedSeconds)) \(DurationFormat.hoursMinutes(store.weekTargetSeconds))")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Button("time.this_week") { Task { await store.goToCurrentWeek() } }
                Button { Task { await store.shiftWeeks(1) } } label: { Label("time.next_week", systemImage: "chevron.right") }
            }
            .labelStyle(.iconOnly)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .glassEffect(in: .capsule)
            .padding(.horizontal, 16)
        }
        .sheet(item: $editor) { request in
            SegmentEditor(store: store, segment: request.segment, day: request.day)
        }
        .sheet(item: $voiding) { segment in
            VoidSheet(store: store, segment: segment)
        }
    }
}

private struct DayHeader: View {
    let day: DayEvaluation
    let calendar: DayCalendar
    let add: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(dayTitle(day.date, calendar: calendar)).font(.headline)
                if day.provisional { Text("common.provisional").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("time.day_total \(DurationFormat.hoursMinutes(day.evaluatedWorkSeconds + day.creditSeconds)) \(DurationFormat.hoursMinutes(day.targetSeconds))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(DurationFormat.signed(day.deltaSeconds)).font(.caption.weight(.semibold))
                    .foregroundStyle(day.deltaSeconds < 0 ? Color.orange : Color.green)
            }
            .monospacedDigit()
            Button(action: add) { Image(systemName: "plus.circle").imageScale(.large) }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("time.add_to_day \(dayTitle(day.date, calendar: calendar))"))
        }
        .textCase(nil)
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
        NavigationStack {
            Form {
                Picker("editor.kind", selection: $kind) {
                    ForEach(SegmentKind.selectable, id: \.self) { Text($0.titleKey).tag($0) }
                }
                DatePicker("editor.start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                Toggle("editor.has_end", isOn: $hasEnd).disabled(segment?.endedAt != nil)
                if hasEnd { DatePicker("editor.end", selection: $end, displayedComponents: [.date, .hourAndMinute]) }
                TextField("editor.note", text: $note, axis: .vertical).lineLimit(1...3)
                if isEditing {
                    Section {
                        TextField("editor.reason", text: $reason).accessibilityIdentifier("editor.reason")
                    } footer: {
                        Text("editor.reason.hint")
                    }
                }
                if let error = store.error { error.messageText.foregroundStyle(.red) }
            }
            .navigationTitle(isEditing ? "time.edit.title" : "command.new_entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { Task { await save() } }.disabled(!valid || saving)
                }
            }
        }
        // DatePickers show wall-clock time in the work model's zone, like the rest of the app.
        .environment(\.timeZone, store.calendar.timeZone)
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
        NavigationStack {
            Form {
                TextField("editor.reason", text: $reason).accessibilityIdentifier("void.reason")
                if let error = store.error { error.messageText.foregroundStyle(.red) }
            }
            .navigationTitle("void.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("time.void", role: .destructive) {
                        Task { if await store.void(segment, reason: reason.trimmingCharacters(in: .whitespaces)) { dismiss() } }
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { store.error = nil }
    }
}
