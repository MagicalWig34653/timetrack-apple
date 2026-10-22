import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// The "Zeit" tab (Z2): one screen for time. Month and week are zoom levels of the same view (`TimeHub`), the week planner is its editing
/// mode; the sheets to create, correct and void entries (below) are shared by all of them.
struct TimeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let store = model.timeList {
                TimeHub(timeList: store, calendar: model.calendar)
            } else {
                ScrollView { SkeletonList(rows: 3).padding(TT.Space.l) }.ttScreenBackground()
            }
        }
        .ttScreenBackground()
        .navigationTitle("sidebar.time")
    }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    let segment: Segment?
    let day: LocalDay
}

struct SegmentEditor: View {
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
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    FormSection("editor.kind") {
                        KindSelector(selection: $kind).padding(TT.Space.m)
                    }
                    FormSection("editor.time") {
                        DatePicker("editor.start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                        Toggle("editor.has_end", isOn: $hasEnd).disabled(segment?.endedAt != nil)
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                        if hasEnd {
                            DatePicker("editor.end", selection: $end, displayedComponents: [.date, .hourAndMinute])
                                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                        }
                    }
                    FormSection("editor.note") {
                        TextField("editor.note", text: $note, axis: .vertical).lineLimit(1...4)
                            .padding(TT.Space.l)
                    }
                    if isEditing {
                        FormSection("editor.reason", footer: "editor.reason.hint") {
                            TextField("editor.reason", text: $reason).accessibilityIdentifier("editor.reason").padding(TT.Space.l)
                        }
                    }
                    if let error = store.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { store.error = nil } }
                }
                .padding(TT.Space.l)
            }
            .ttScreenBackground()
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

struct VoidSheet: View {
    let store: TimeListStore
    let segment: Segment
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    FormSection("editor.reason", footer: "void.hint") {
                        TextField("editor.reason", text: $reason).accessibilityIdentifier("void.reason").padding(TT.Space.l)
                    }
                    if let error = store.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { store.error = nil } }
                }
                .padding(TT.Space.l)
            }
            .ttScreenBackground()
            .navigationTitle("void.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("time.void", role: .destructive) {
                        guard !busy else { return }
                        busy = true
                        Task {
                            // The store removes the segment in one state change before returning; the sheet closes right after.
                            if await store.void(segment, reason: reason.trimmingCharacters(in: .whitespaces)) { dismiss() }
                            busy = false
                        }
                    }
                    .disabled(busy || reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { store.error = nil; TTHaptics.play(.confirmDestructive) } // the confirmation appeared; success follows from the store
    }
}
