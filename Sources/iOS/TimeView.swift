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
                ScrollView { SkeletonList(rows: 3).padding(TT.Space.l) }.ttScreenBackground()
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
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: TT.Space.xl) {
                    dayList.frame(maxWidth: TT.contentWidth)
                    ScrollView {
                        VStack(spacing: TT.Space.l) {
                            WeekHeader(store: store)
                            WeekOverview(store: store)
                        }
                        .padding(.top, TT.Space.s)
                    }
                    .frame(maxWidth: 380)
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, TT.Space.l)
                .frame(maxWidth: .infinity)
            } else {
                dayList
            }
        }
        .ttScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { editor = EditorRequest(segment: nil, day: store.calendar.day(for: .now)) } label: { Label("command.new_entry", systemImage: "plus") }
                    .accessibilityIdentifier("time.new")
            }
        }
        .sheet(item: $editor) { request in
            SegmentEditor(store: store, segment: request.segment, day: request.day)
                .presentationDetents([.fraction(0.75), .large])
        }
        .sheet(item: $voiding) { segment in
            VoidSheet(store: store, segment: segment)
        }
    }

    private var dayList: some View {
        List {
            if sizeClass != .regular {
                WeekHeader(store: store)
                    .listRowBackground(Color.clear).listRowInsets(.init(top: 0, leading: 0, bottom: 4, trailing: 0)).listRowSeparator(.hidden)
            }
            if let error = store.error {
                ErrorBannerView(error: error) { Task { await store.load() } }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if store.days.isEmpty && store.isLoading {
                SkeletonList(rows: 3).listRowBackground(Color.clear).listRowInsets(.init()).listRowSeparator(.hidden)
            }
            ForEach(store.days) { day in
                Section {
                    let segments = (day.segments ?? []).filter { !$0.voided }.sorted { $0.startedAt < $1.startedAt }
                    if segments.isEmpty {
                        EmptyDayRow(day: day)
                            .listRowInsets(.init()).listRowBackground(TT.surface)
                    }
                    ForEach(segments) { segment in
                        SegmentRow(segment: segment, zone: store.calendar.timeZone)
                            .onTapGesture { editor = EditorRequest(segment: segment, day: day.date) }
                            .listRowInsets(.init()).listRowBackground(TT.surface)
                            .swipeActions(edge: .trailing) {
                                Button("time.void", role: .destructive) { voiding = segment }
                                Button("time.edit") { editor = EditorRequest(segment: segment, day: day.date) }.tint(.accentColor)
                            }
                            .accessibilityAction(named: Text("time.edit")) { editor = EditorRequest(segment: segment, day: day.date) }
                            .accessibilityAction(named: Text("time.void")) { voiding = segment }
                    }
                } header: {
                    DayHeader(day: day, calendar: store.calendar, isToday: day.date == store.calendar.day(for: .now)) {
                        editor = EditorRequest(segment: nil, day: day.date)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(TT.Space.s)
        .task { await store.load() }
        .refreshable { await store.load() }
    }
}

/// Week navigation + total with progress against the week's target.
private struct WeekHeader: View {
    let store: TimeListStore
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let done = store.weekEvaluatedSeconds
        let target = store.weekTargetSeconds
        Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                HStack(spacing: TT.Space.s) {
                    Button { Task { await store.shiftWeeks(-1) } } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                        .accessibilityLabel(Text("time.previous_week"))
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        Text(verbatim: weekRangeText(start: store.weekStart, end: store.weekEnd, calendar: store.calendar))
                            .font(TTFont.cardTitle).foregroundStyle(TT.textPrimary).multilineTextAlignment(.center)
                            .lineLimit(2).minimumScaleFactor(0.7)
                        Button("time.this_week") { Task { await store.goToCurrentWeek() } }.font(TTFont.meta)
                    }
                    Spacer(minLength: 0)
                    Button { Task { await store.shiftWeeks(1) } } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                        .accessibilityLabel(Text("time.next_week"))
                }
                .buttonStyle(.borderless)
                ProgressBar(progress: target > 0 ? Double(done) / Double(target) : 0)
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: TT.Space.xs)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                layout {
                    Text(verbatim: DurationFormat.hoursMinutes(done)).font(TTFont.stat).foregroundStyle(TT.textPrimary).lineLimit(1).minimumScaleFactor(0.5)
                    Text("time.of_target \(DurationFormat.hoursMinutes(target))").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    if !typeSize.isAccessibilitySize { Spacer() }
                    if target > 0 { StatusChip(verbatim: DurationFormat.signed(done - target), tone: deltaTone(done - target)) }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Per-day bars of the loaded week (iPad side column).
private struct WeekOverview: View {
    let store: TimeListStore

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            SectionHeader("time.overview")
            Card {
                VStack(spacing: TT.Space.m) {
                    ForEach(store.days) { day in
                        let done = day.evaluatedWorkSeconds + day.creditSeconds
                        HStack(spacing: TT.Space.m) {
                            Text(verbatim: dayTitle(day.date, calendar: store.calendar)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                                .frame(width: 84, alignment: .leading)
                            ProgressBar(progress: day.targetSeconds > 0 ? Double(done) / Double(day.targetSeconds) : (done > 0 ? 1 : 0), height: 8)
                            Text(verbatim: DurationFormat.hoursMinutes(done)).font(TTFont.numeralSmall).foregroundStyle(TT.textPrimary)
                                .frame(width: 44, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
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
                Text(markKey(mark)).font(TTFont.body).foregroundStyle(TT.textPrimary)
            } else {
                Text("time.no_entries").font(TTFont.body).foregroundStyle(TT.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        .accessibilityElement(children: .combine)
    }
}

private struct DayHeader: View {
    let day: DayEvaluation
    let calendar: DayCalendar
    let isToday: Bool
    let add: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let done = day.evaluatedWorkSeconds + day.creditSeconds
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: TT.Space.xs)) : AnyLayout(HStackLayout(alignment: .center, spacing: TT.Space.s))
        layout {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: dayTitle(day.date, calendar: calendar)).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                    if isToday { StatusChip("time.today", tone: .accent) }
                }
                if day.provisional { Text("common.provisional").font(.caption2).foregroundStyle(TT.textSecondary) }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: TT.Space.xs) }
            if day.targetSeconds > 0 || done > 0 {
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                    Text("time.day_total \(DurationFormat.hoursMinutes(done)) \(DurationFormat.hoursMinutes(day.targetSeconds))")
                        .font(TTFont.numeralSmall).foregroundStyle(TT.textSecondary)
                    if day.deltaSeconds != 0 {
                        Text(verbatim: DurationFormat.signed(day.deltaSeconds)).font(TTFont.numeralSmall.weight(.semibold))
                            .foregroundStyle(day.deltaSeconds < 0 ? TT.warning : TT.success)
                    }
                }
            }
            Button(action: add) { Image(systemName: "plus.circle.fill").imageScale(.large).symbolRenderingMode(.hierarchical) }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("time.add_to_day \(dayTitle(day.date, calendar: calendar))"))
        }
        .textCase(nil)
        .padding(.vertical, 2)
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

private struct VoidSheet: View {
    let store: TimeListStore
    let segment: Segment
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

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
