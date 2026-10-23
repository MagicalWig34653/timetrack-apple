import Charts
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// M2: "Aktivität" – the local app-usage log of one day. Everything shown here stays on this Mac; the only way something reaches the
/// account is a suggestion that the user edits and applies as a normal, reasoned correction of an entry.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var companion = MacCompanion.shared
    @State private var day: LocalDay = ""
    @State private var segments: [Segment] = []
    @State private var showRules = false
    @State private var ruleDraft: ActivityRule?
    @State private var applying: ActivitySuggestion?
    @State private var selectedApp: String?
    @State private var confirmDelete = false

    private var store: ActivityStore { companion.activity }
    private var calendar: DayCalendar { model.dayCalendar }
    private var range: (from: Date, to: Date) {
        let interval = calendar.interval(of: day) ?? (Date.now, Date.now)
        return (interval.start, interval.end)
    }
    private var intervals: [ActivityInterval] { store.intervals(from: range.from, to: range.to) }
    private var totals: [ActivityAppTotal] { ActivitySummary.totals(intervals) }
    private var suggestions: [ActivitySuggestion] { store.suggestions(segments: segments, from: range.from, to: range.to) }

    var body: some View {
        Group {
            if !store.settings.enabled && store.log.isEmpty {
                disabledState
            } else {
                content
            }
        }
        .navigationTitle("Aktivität")
        .toolbar { toolbar }
        .task {
            if day.isEmpty { day = calendar.day(for: .now) }
            await loadSegments()
        }
        .onChange(of: day) { Task { await loadSegments() } }
        .inspector(isPresented: $showRules) { RulesInspector(draft: $ruleDraft).inspectorColumnWidth(min: 260, ideal: 300, max: 380) }
        .sheet(item: $ruleDraft) { draft in RuleEditor(rule: draft) }
        .sheet(item: $applying) { suggestion in
            ApplySuggestionSheet(suggestion: suggestion, segment: segments.first { $0.id == suggestion.segmentID }, client: model.apiClient) {
                store.dismiss(suggestion.id) // applied: it must not reappear
                Task { await loadSegments(); await model.today?.load() }
            }
        }
        .confirmationDialog("Alle Aktivitätsdaten löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Alle löschen", role: .destructive) { store.deleteAllData() }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Das Protokoll und verworfene Vorschläge werden von diesem Mac entfernt. Einstellungen und Regeln bleiben.") }
    }

    // MARK: Parts

    private var disabledState: some View {
        VStack(spacing: TT.Space.l) {
            EmptyState(symbol: "square.stack.3d.up", title: "Aktivitätserfassung ist aus",
                       message: "Wenn du sie einschaltest, merkt sich Timetrack lokal auf diesem Mac, welche App läuft, solange ein Timer läuft. Nichts davon wird gesendet.")
            Button("Einstellungen öffnen") { openSettings() }.buttonStyle(.ttPrimary)
        }
        .frame(maxWidth: 460).frame(maxWidth: .infinity, maxHeight: .infinity)
        .ttScreenBackground()
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                statusLine
                timeline
                if !suggestions.isEmpty { suggestionList }
                totalsTable
                Text("Die Daten liegen nur auf diesem Mac und werden nach \(store.settings.retentionDays) Tagen gelöscht. Vorschläge ändern nichts, bis du sie bestätigst.")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
            .padding(TT.Space.xl)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
    }

    @ViewBuilder private var statusLine: some View {
        let s = store.settings
        HStack(spacing: TT.Space.s) {
            if !s.enabled {
                StatusChip(verbatim: "Aus", tone: .neutral, symbol: "circle.slash")
            } else if s.paused {
                StatusChip(verbatim: "Pausiert", tone: .warning, symbol: "pause.circle")
            } else {
                StatusChip(verbatim: s.onlyWhileTimerRuns ? "Aktiv, solange ein Timer läuft" : "Aktiv", tone: .success, symbol: "record.circle")
            }
            if s.recordWindowTitles { StatusChip(verbatim: "mit Fenstertiteln", tone: .neutral, symbol: "macwindow") }
            Spacer()
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            SectionHeader("Zeitleiste") { EmptyView() }
            if intervals.isEmpty {
                Card { EmptyState(symbol: "tray", title: "Nichts erfasst", message: "Für diesen Tag gibt es keine Aktivitätsdaten.") }
            } else {
                Card {
                    Chart {
                        ForEach(segments.filter { !$0.voided }) { segment in
                            BarMark(xStart: .value("Von", segment.startedAt), xEnd: .value("Bis", segment.endedAt ?? .now), y: .value("App", "Timer"), height: .fixed(14))
                                .foregroundStyle(segment.kind.ttTint.opacity(0.55))
                        }
                        ForEach(intervals) { interval in
                            BarMark(xStart: .value("Von", interval.start), xEnd: .value("Bis", interval.end), y: .value("App", interval.appName), height: .fixed(14))
                                .foregroundStyle(by: .value("App", interval.appName))
                        }
                    }
                    .chartXScale(domain: chartDomain)
                    .chartLegend(.hidden)
                    .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 2)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.hour()) } }
                    .environment(\.timeZone, calendar.timeZone)
                    .frame(height: CGFloat(min(max(totals.count + 1, 3), 10)) * 30 + 30)
                    .padding(TT.Space.m)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(spokenTimeline))
                }
            }
        }
    }

    /// From shortly before the first interval to shortly after the last one (the whole day would squash a short session).
    private var chartDomain: ClosedRange<Date> {
        let all = intervals.map(\.start) + intervals.map(\.end) + segments.filter { !$0.voided }.flatMap { [$0.startedAt, $0.endedAt ?? .now] }
        let from = (all.min() ?? range.from).addingTimeInterval(-900), to = (all.max() ?? range.to).addingTimeInterval(900)
        return max(from, range.from)...min(to, range.to)
    }

    private var spokenTimeline: String {
        let top = totals.prefix(3).map { "\($0.appName) \(DurationFormat.hoursMinutes(Int($0.seconds)))" }.joined(separator: ", ")
        return "Aktivität am \(day): \(top)"
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            SectionHeader("Vorschläge") { Text(verbatim: "\(suggestions.count)") }
            Card {
                VStack(spacing: 0) {
                    ForEach(suggestions) { suggestion in
                        HStack(alignment: .firstTextBaseline, spacing: TT.Space.m) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: suggestion.proposedNote.isEmpty ? (suggestion.proposedKind?.plainName ?? "") : suggestion.proposedNote).font(TTFont.body)
                                Text("\(suggestion.appNames.joined(separator: ", ")) · \(DurationFormat.hoursMinutes(Int(suggestion.seconds))) · \(suggestion.start.clockText(in: calendar.timeZone))–\(suggestion.end.clockText(in: calendar.timeZone))")
                                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                            }
                            Spacer()
                            Button("Prüfen…") { applying = suggestion }.accessibilityIdentifier("activity.suggestion.review")
                            Button { store.dismiss(suggestion.id) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.borderless).help("Vorschlag verwerfen").accessibilityLabel("Vorschlag verwerfen")
                        }
                        .padding(TT.Space.m)
                        if suggestion.id != suggestions.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var totalsTable: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            SectionHeader("Apps") { EmptyView() }
            Table(totals, selection: $selectedApp) {
                TableColumn("App") { total in
                    Text(verbatim: total.appName).opacity(store.settings.isExcluded(total.bundleID) ? 0.5 : 1)
                }
                TableColumn("Dauer") { total in Text(verbatim: DurationFormat.hoursMinutes(Int(total.seconds))).monospacedDigit() }.width(80)
                TableColumn("Anteil") { total in
                    let sum = totals.reduce(0) { $0 + $1.seconds }
                    Text(sum > 0 ? (total.seconds / sum).formatted(.percent.precision(.fractionLength(0))) : "–").monospacedDigit().foregroundStyle(TT.textSecondary)
                }.width(70)
                TableColumn("Regel") { total in
                    if let rule = store.rules.first(where: { $0.bundleID == total.bundleID }), rule.isUseful {
                        Text(verbatim: [rule.kind?.plainName, rule.formattedLabel].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(TT.textSecondary)
                    } else { Text("–").foregroundStyle(TT.textTertiary) }
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let total = totals.first(where: { $0.bundleID == id }) {
                    Button("Regel für diese App…") { ruleDraft = store.rules.first { $0.bundleID == id } ?? ActivityRule(bundleID: id, appName: total.appName) }
                    Button("Aus der Erfassung ausschließen", role: .destructive) { store.exclude(bundleID: id) }
                }
            }
            .frame(minHeight: CGFloat(min(totals.count, 8) + 1) * 28 + 12)
            .accessibilityIdentifier("activity.table")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { shift(-1) } label: { Label("Vorheriger Tag", systemImage: "chevron.left") }.help("Vorheriger Tag")
            Text(verbatim: dayTitle).monospacedDigit().frame(minWidth: 120)
            Button { shift(1) } label: { Label("Nächster Tag", systemImage: "chevron.right") }.help("Nächster Tag").disabled(day >= calendar.day(for: .now))
            Button("Heute") { day = calendar.day(for: .now) }
        }
        ToolbarItemGroup {
            Button { showRules.toggle() } label: { Label("Regeln", systemImage: "sidebar.right") }
                .keyboardShortcut("r", modifiers: [.command, .option]).help("Regeln ein-/ausblenden (⌥⌘R)")
            Menu {
                Button(store.settings.paused ? "Erfassung fortsetzen" : "Erfassung pausieren") { store.update { $0.paused.toggle() } }
                    .disabled(!store.settings.enabled)
                Button("Einstellungen…") { openSettings() }
                Divider()
                Button("Alle Aktivitätsdaten löschen…", role: .destructive) { confirmDelete = true }
            } label: { Label("Mehr", systemImage: "ellipsis.circle") }
        }
    }

    private var dayTitle: String {
        guard let start = calendar.interval(of: day)?.start else { return day }
        return start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated))
    }

    private func shift(_ days: Int) { if let next = LocalDays.adding(days, to: day) { day = next } }

    private func loadSegments() async {
        guard let client = model.apiClient, !day.isEmpty else { return }
        segments = (try? await client.listSegments(from: range.from, to: range.to)) ?? []
    }
}

// MARK: - Rules inspector

private struct RulesInspector: View {
    @Binding var draft: ActivityRule?
    @State private var companion = MacCompanion.shared

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.m) {
            Text("Regeln").font(TTFont.sectionTitle)
            Text("Eine Regel sagt: Wenn diese App läuft, gehört die Zeit wahrscheinlich zu dieser Art, diesem Projekt oder Lernfeld. Daraus entstehen nur Vorschläge, die du prüfst.")
                .font(TTFont.meta).foregroundStyle(TT.textSecondary)
            List {
                ForEach(companion.activity.rules) { rule in
                    Button { draft = rule } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: rule.appName).font(TTFont.body)
                            Text(verbatim: [rule.kind?.plainName, rule.formattedLabel].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "Keine Wirkung")
                                .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Löschen", role: .destructive) { companion.activity.deleteRule(rule.id) } }
                }
                .onDelete { offsets in
                    for index in offsets { companion.activity.deleteRule(companion.activity.rules[index].id) }
                }
            }
            .overlay { if companion.activity.rules.isEmpty { Text("Noch keine Regeln").foregroundStyle(TT.textSecondary) } }
            Button { draft = ActivityRule(bundleID: "", appName: "") } label: { Label("Regel hinzufügen", systemImage: "plus") }
                .accessibilityIdentifier("activity.rule.add")
        }
        .padding(TT.Space.m)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// Editor for one rule: the app (from the apps seen so far or running now), the proposed kind and the label.
private struct RuleEditor: View {
    @State var rule: ActivityRule
    @Environment(\.dismiss) private var dismiss
    @State private var companion = MacCompanion.shared

    private var candidates: [(id: String, name: String)] {
        var map: [String: String] = [:]
        for interval in companion.activity.log.intervals { map[interval.bundleID] = interval.appName }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier { map[id] = app.localizedName ?? id }
        }
        if !rule.bundleID.isEmpty { map[rule.bundleID] = map[rule.bundleID] ?? rule.appName }
        return map.map { ($0.key, $0.value) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("App", selection: Binding(get: { rule.bundleID }, set: { id in
                    rule.bundleID = id
                    rule.appName = candidates.first { $0.id == id }?.name ?? id
                })) {
                    Text("Bitte wählen").tag("")
                    ForEach(candidates, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                }
                Picker("Art vorschlagen", selection: $rule.kind) {
                    Text("Art nicht ändern").tag(SegmentKind?.none)
                    ForEach(SegmentKind.selectable, id: \.self) { Text(verbatim: $0.plainName).tag(SegmentKind?.some($0)) }
                }
                Picker("Zuordnen zu", selection: $rule.labelType) {
                    Text("Nichts").tag(ActivityLabelType.none)
                    Text("Projekt").tag(ActivityLabelType.project)
                    Text("Lernfeld").tag(ActivityLabelType.learningField)
                }
                if rule.labelType != .none {
                    TextField(rule.labelType == .project ? "Projektname" : "Lernfeld, z. B. LF 5", text: $rule.label)
                }
                Section { Text("Die Zuordnung landet nur als Vorschlag in der Notiz eines Eintrags. Du bearbeitest und bestätigst sie, bevor etwas gespeichert wird.").font(TTFont.meta).foregroundStyle(TT.textSecondary) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Sichern") { companion.activity.saveRule(rule); dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(rule.bundleID.isEmpty)
            }
            .padding(TT.Space.l).background(.bar)
        }
        .frame(width: 440, height: 380)
    }
}

// MARK: - Apply a suggestion

/// The suggestion as an editable correction: note and kind can be changed, a reason is required (like every correction).
private struct ApplySuggestionSheet: View {
    let suggestion: ActivitySuggestion
    let segment: Segment?
    let client: APIClient?
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var kind: SegmentKind = .work
    @State private var reason = "Aus App-Aktivität übernommen"
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("Betroffener Eintrag: \(segment.map { "\($0.kind.plainName), \($0.startedAt.formatted(date: .omitted, time: .shortened))" } ?? "nicht gefunden")")
                    Text("Erkannt: \(suggestion.appNames.joined(separator: ", ")) · \(DurationFormat.hoursMinutes(Int(suggestion.seconds)))").foregroundStyle(TT.textSecondary)
                }
                Picker("Art", selection: $kind) { ForEach(SegmentKind.selectable, id: \.self) { Text(verbatim: $0.plainName).tag($0) } }
                TextField("Notiz", text: $note, axis: .vertical).lineLimit(1...4)
                TextField("Grund der Korrektur", text: $reason)
                if let error { Text(verbatim: error).foregroundStyle(TT.danger) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Übernehmen") { Task { await save() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(saving || segment == nil || reason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(TT.Space.l).background(.bar)
        }
        .frame(width: 460, height: 420)
        .onAppear {
            note = suggestion.proposedNote
            kind = suggestion.proposedKind ?? segment?.kind ?? .work
        }
    }

    private func save() async {
        guard let segment, let client else { return }
        saving = true
        defer { saving = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let correction = SegmentCorrection(kind: kind != segment.kind ? kind : nil, note: trimmed != (segment.note ?? "") ? trimmed : nil,
                                           reason: reason.trimmingCharacters(in: .whitespaces))
        do {
            _ = try await client.correctSegment(id: segment.id, correction, ifMatchVersion: segment.version)
            done()
            dismiss()
        } catch let failure as TimetrackError {
            error = failure.germanDescription
        } catch {
            self.error = "Das Speichern ist fehlgeschlagen."
        }
    }
}
