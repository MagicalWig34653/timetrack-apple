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

private struct VoidRequest: Identifiable {
    let id = UUID()
    let segments: [Segment]
}

/// AD1: Mac list with multi-selection, search, context menu, keyboard commands and an inspector for the selection.
private struct TimeContent: View {
    let store: TimeListStore
    @Environment(UIState.self) private var ui
    @Environment(AppModel.self) private var model
    @State private var editor: EditorRequest?
    @State private var voiding: VoidRequest?
    @State private var selection = Set<UUID>()
    @State private var query = ""
    @SwiftUI.FocusState private var searchFocused: Bool

    private var needle: String { query.trimmingCharacters(in: .whitespaces) }

    private func matches(_ segment: Segment) -> Bool {
        guard !needle.isEmpty else { return true }
        let kindName: String
        switch segment.kind {
        case .work, .unknown: kindName = String(localized: "kind.work")
        case .travel: kindName = String(localized: "kind.travel")
        case .school: kindName = String(localized: "kind.school")
        }
        return kindName.localizedCaseInsensitiveContains(needle) || (segment.note ?? "").localizedCaseInsensitiveContains(needle)
    }

    /// Rows of a day; with a search term only matching segments (days without a match disappear).
    private func rows(_ day: DayEvaluation) -> [TimeRow] {
        let all = day.timeRows
        guard !needle.isEmpty else { return all }
        return all.filter { if case .segment(let segment, _) = $0 { matches(segment) } else { false } }
    }

    private var visibleDays: [DayEvaluation] { needle.isEmpty ? store.days : store.days.filter { !rows($0).isEmpty } }

    private var selectedSegments: [Segment] {
        store.days.flatMap { $0.segments ?? [] }.filter { selection.contains($0.id) && !$0.voided }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private func edit(_ ids: Set<UUID>) {
        guard let segment = selectedSegments.first(where: { ids.contains($0.id) }),
              let day = store.days.first(where: { ($0.segments ?? []).contains { $0.id == segment.id } })?.date else { return }
        editor = EditorRequest(segment: segment, day: day)
    }

    private func requestVoid(_ ids: Set<UUID>) {
        let segments = selectedSegments.filter { ids.contains($0.id) }
        if !segments.isEmpty { voiding = VoidRequest(segments: segments) }
    }

    private func newEntry() { editor = EditorRequest(segment: nil, day: store.calendar.day(for: .now)) }

    /// BH1: opens the Berichtsheft on the week that is shown here.
    private func openReports() {
        guard model.isEnabled(.reports) else { return }
        ui.reportsWeek = ReportWeekRef(containing: store.weekStart)
        ui.selection = .reports
    }

    private func handleCommand() {
        guard let command = ui.timeCommand else { return }
        ui.timeCommand = nil
        switch command {
        case .previousWeek: Task { await store.shiftWeeks(-1) }
        case .nextWeek: Task { await store.shiftWeeks(1) }
        case .thisWeek: Task { await store.goToCurrentWeek() }
        case .newEntry: newEntry()
        case .search: searchFocused = true
        case .toggleInspector: ui.inspectorVisible.toggle()
        case .openReports: openReports()
        }
    }

    var body: some View {
        @Bindable var ui = ui
        List(selection: $selection) {
            WeekHeader(store: store)
                .listRowSeparator(.hidden).listRowBackground(Color.clear).selectionDisabled()
            if let error = store.error {
                ErrorBannerView(error: error) { Task { await store.load() } }
                    .listRowSeparator(.hidden).listRowBackground(Color.clear).selectionDisabled()
            }
            if store.days.isEmpty && store.isLoading {
                SkeletonList(rows: 3).listRowSeparator(.hidden).listRowBackground(Color.clear).selectionDisabled()
            }
            ForEach(visibleDays) { day in
                Section {
                    ForEach(rows(day)) { row in
                        switch row {
                        case .segment(let segment, _):
                            SegmentRow(segment: segment, zone: store.calendar.timeZone).tag(segment.id)
                        case .empty:
                            EmptyDayRow(day: day).selectionDisabled()
                        }
                    }
                } header: {
                    DayHeader(day: day, calendar: store.calendar, isToday: day.date == store.calendar.day(for: .now)) {
                        editor = EditorRequest(segment: nil, day: day.date)
                    }
                }
            }
            if !needle.isEmpty && visibleDays.isEmpty && !store.isLoading {
                EmptyState(symbol: "magnifyingglass", title: LocalizedStringKey(AD.s("time.search.empty")), message: LocalizedStringKey(AD.s("time.search.empty.hint")))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear).selectionDisabled()
            }
        }
        .listStyle(.inset)
        .environment(\.defaultMinListRowHeight, 40)
        .scrollContentBackground(.hidden)
        .ttScreenBackground()
        .contextMenu(forSelectionType: UUID.self) { ids in
            if ids.isEmpty {
                Button("command.new_entry") { newEntry() }
            } else {
                if ids.count == 1 { Button("time.edit") { edit(ids) } }
                Button("time.void", role: .destructive) { requestVoid(ids) }
            }
        } primaryAction: { ids in edit(ids) }
        .onDeleteCommand { requestVoid(selection) }
        .searchable(text: $query, placement: .toolbar, prompt: Text(AD.s("time.search.prompt")))
        .searchFocused($searchFocused)
        .inspector(isPresented: $ui.inspectorVisible) {
            SegmentInspector(segments: selectedSegments, zone: store.calendar.timeZone,
                             edit: { edit(selection) }, void: { requestVoid(selection) })
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .task { await store.load() }
        .onAppear(perform: handleCommand)
        .onChange(of: ui.timeCommandSerial) { handleCommand() }
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await store.shiftWeeks(-1) } } label: { Label("time.previous_week", systemImage: "chevron.left") }
                    .help(Text("time.previous_week"))
                Button("time.this_week") { Task { await store.goToCurrentWeek() } }
                Button { Task { await store.shiftWeeks(1) } } label: { Label("time.next_week", systemImage: "chevron.right") }
                    .help(Text("time.next_week"))
                Button { newEntry() } label: { Label("command.new_entry", systemImage: "plus") }
                    .help(Text("command.new_entry"))
                if model.isEnabled(.reports) {
                    Button { openReports() } label: { Label(BH.s("entry.link"), systemImage: "book.closed") }
                        .help(Text(verbatim: BH.s("entry.link")))
                        .accessibilityIdentifier("time.reports")
                }
                Button { ui.inspectorVisible.toggle() } label: { Label(AD.s("command.inspector"), systemImage: "sidebar.trailing") }
                    .help(Text(AD.s("command.inspector")))
            }
        }
        .sheet(item: $editor) { request in
            SegmentEditor(store: store, segment: request.segment, day: request.day)
        }
        .sheet(item: $voiding) { request in
            VoidSheet(store: store, segments: request.segments) { selection.subtract(request.segments.map(\.id)) }
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
        .padding(.vertical, TT.Space.xs)
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
    let segments: [Segment]
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.l) {
            Text("void.title").font(TTFont.sectionTitle).foregroundStyle(TT.textPrimary)
            if segments.count > 1 {
                Text(AD.s("void.many \(segments.count)")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
            FormSection("editor.reason", footer: "void.hint") {
                TextField("editor.reason", text: $reason).textFieldStyle(.plain).accessibilityIdentifier("void.reason").padding(TT.Space.m)
            }
            if let error = store.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { store.error = nil } }
            HStack {
                Spacer()
                Button("common.cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("time.void", role: .destructive) { Task { await voidAll() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
        }
        .padding(TT.Space.xl)
        .frame(width: 420)
        .ttScreenBackground()
        .onAppear { store.error = nil }
    }

    /// One reason for all selected segments; stops at the first failure so the error stays visible.
    private func voidAll() async {
        working = true
        defer { working = false }
        let trimmed = reason.trimmingCharacters(in: .whitespaces)
        for segment in segments {
            guard await store.void(segment, reason: trimmed) else { return }
        }
        done()
        dismiss()
    }
}
