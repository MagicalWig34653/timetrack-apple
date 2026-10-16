import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

struct TimeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let store = model.timeList {
                TimeContent(store: store)
            } else {
                ScrollView { SkeletonList(rows: 3).padding(TT.Space.xl) }.ttScreenBackground()
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
    @Environment(UIState.self) private var ui
    @State private var editor: EditorRequest?
    @State private var voiding: Segment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                WeekHeader(store: store)
                if let error = store.error { ErrorBannerView(error: error) { Task { await store.load() } } }
                if store.days.isEmpty && store.isLoading { SkeletonList(rows: 3) }
                ForEach(store.days) { day in
                    VStack(alignment: .leading, spacing: TT.Space.s) {
                        DayHeader(day: day, calendar: store.calendar, isToday: day.date == store.calendar.day(for: .now)) {
                            editor = EditorRequest(segment: nil, day: day.date)
                        }
                        let segments = (day.segments ?? []).filter { !$0.voided }.sorted { $0.startedAt < $1.startedAt }
                        if segments.isEmpty {
                            Card(padding: 0) { EmptyDayRow(day: day) }
                        } else {
                            ListCard {
                                ForEach(segments) { segment in
                                    SegmentRow(segment: segment, zone: store.calendar.timeZone)
                                        .onTapGesture(count: 2) { editor = EditorRequest(segment: segment, day: day.date) }
                                        .contextMenu {
                                            Button("time.edit") { editor = EditorRequest(segment: segment, day: day.date) }
                                            Button("time.void", role: .destructive) { voiding = segment }
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .padding(TT.Space.xl)
            .frame(maxWidth: TT.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
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
        .sheet(item: $editor) { request in
            SegmentEditor(store: store, segment: request.segment, day: request.day)
        }
        .sheet(item: $voiding) { segment in
            VoidSheet(store: store, segment: segment)
        }
    }
}

private struct WeekHeader: View {
    let store: TimeListStore

    var body: some View {
        let done = store.weekEvaluatedSeconds
        let target = store.weekTargetSeconds
        Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                Text(verbatim: weekRangeText(start: store.weekStart, end: store.weekEnd, calendar: store.calendar))
                    .font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                ProgressBar(progress: target > 0 ? Double(done) / Double(target) : 0)
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: DurationFormat.hoursMinutes(done)).font(TTFont.stat).foregroundStyle(TT.textPrimary)
                    Text("time.of_target \(DurationFormat.hoursMinutes(target))").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    Spacer()
                    if target > 0 { StatusChip(verbatim: DurationFormat.signed(done - target), tone: deltaTone(done - target)) }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct EmptyDayRow: View {
    let day: DayEvaluation

    var body: some View {
        HStack(spacing: TT.Space.m) {
            if let mark = day.mark, mark != .unmarked, mark != .unknown {
                KindGlyph(symbol: markSymbol(mark), tint: markTint(mark))
                Text(markKey(mark)).foregroundStyle(TT.textPrimary)
            } else {
                Text("time.no_entries").foregroundStyle(TT.textTertiary)
            }
            Spacer()
        }
        .padding(TT.Space.l)
        .accessibilityElement(children: .combine)
    }
}

private struct DayHeader: View {
    let day: DayEvaluation
    let calendar: DayCalendar
    let isToday: Bool
    let add: () -> Void

    var body: some View {
        let done = day.evaluatedWorkSeconds + day.creditSeconds
        HStack(spacing: TT.Space.s) {
            Text(verbatim: dayTitle(day.date, calendar: calendar)).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
            if isToday { StatusChip("time.today", tone: .accent) }
            if day.provisional { StatusChip("common.provisional", tone: .neutral) }
            Spacer()
            if day.targetSeconds > 0 || done > 0 {
                Text("time.day_total \(DurationFormat.hoursMinutes(done)) \(DurationFormat.hoursMinutes(day.targetSeconds))")
                    .font(TTFont.numeralSmall).foregroundStyle(TT.textSecondary)
                if day.deltaSeconds != 0 {
                    Text(verbatim: DurationFormat.signed(day.deltaSeconds)).font(TTFont.numeralSmall.weight(.semibold))
                        .foregroundStyle(day.deltaSeconds < 0 ? TT.warning : TT.success)
                }
            }
            Button(action: add) { Image(systemName: "plus.circle.fill").symbolRenderingMode(.hierarchical) }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("time.add_to_day \(dayTitle(day.date, calendar: calendar))"))
        }
        .padding(.horizontal, TT.Space.xs)
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    Text(isEditing ? "time.edit.title" : "command.new_entry").font(TTFont.sectionTitle).foregroundStyle(TT.textPrimary)
                    FormSection("editor.kind") { KindSelector(selection: $kind).padding(TT.Space.m) }
                    FormSection("editor.time") {
                        DatePicker("editor.start", selection: $start, displayedComponents: [.date, .hourAndMinute]).padding(TT.Space.m)
                        Toggle("editor.has_end", isOn: $hasEnd).disabled(segment?.endedAt != nil).padding(TT.Space.m)
                        if hasEnd { DatePicker("editor.end", selection: $end, displayedComponents: [.date, .hourAndMinute]).padding(TT.Space.m) }
                    }
                    FormSection("editor.note") {
                        TextField("editor.note", text: $note, axis: .vertical).textFieldStyle(.plain).lineLimit(1...4).padding(TT.Space.m)
                    }
                    if isEditing {
                        FormSection("editor.reason", footer: "editor.reason.hint") {
                            TextField("editor.reason", text: $reason).textFieldStyle(.plain).accessibilityIdentifier("editor.reason").padding(TT.Space.m)
                        }
                    }
                    if let error = store.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { store.error = nil } }
                }
                .padding(TT.Space.xl)
            }
            HStack {
                Spacer()
                Button("common.cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("common.save") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid || saving)
            }
            .padding(TT.Space.l)
            .background(.bar)
        }
        .ttScreenBackground()
        .environment(\.timeZone, store.calendar.timeZone)
        .frame(width: 480, height: 600)
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
        VStack(alignment: .leading, spacing: TT.Space.l) {
            Text("void.title").font(TTFont.sectionTitle).foregroundStyle(TT.textPrimary)
            FormSection("editor.reason", footer: "void.hint") {
                TextField("editor.reason", text: $reason).textFieldStyle(.plain).accessibilityIdentifier("void.reason").padding(TT.Space.m)
            }
            if let error = store.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { store.error = nil } }
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
        .padding(TT.Space.xl)
        .frame(width: 420)
        .ttScreenBackground()
        .onAppear { store.error = nil }
    }
}
