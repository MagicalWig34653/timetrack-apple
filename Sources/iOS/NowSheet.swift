import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// H2: the "Jetzt" sheet that opens from the bar (like the Apple Music mini player opens the full player).
/// Large clock, start/stop, kind, and for a running segment the start time (correction) and a note.
/// Detents medium/large; the system draws the Liquid Glass sheet. Start/stop also stays in the bar itself.
struct NowSheet: View {
    let store: TodayStore
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 52
    @AppStorage("ios.lastKind") private var lastKindRaw = SegmentKind.work.rawValue
    @State private var draftKind: SegmentKind = .work
    @State private var draftStart: Date = .now
    @State private var draftNote = ""
    @State private var loadedId: UUID?
    @State private var saving = false
    @SwiftUI.FocusState private var noteFocused: Bool

    private var idleKind: Binding<SegmentKind> {
        Binding(get: { SegmentKind(rawValue: lastKindRaw).flatMap { SegmentKind.selectable.contains($0) ? $0 : nil } ?? .work },
                set: { lastKindRaw = $0.rawValue })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TT.Space.l) {
                    if let running = store.running { runningContent(running) } else { idleContent }
                    if let error = store.error { ErrorBannerView(error: error) { store.error = nil } }
                }
                .padding(.horizontal, TT.Space.l)
                .padding(.bottom, TT.Space.l)
                .frame(maxWidth: TT.contentWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(ux3("ux3.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { ux3("ux3.sheet.done") }.accessibilityIdentifier("nowsheet.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: store.running?.id) { loadDraft() }
    }

    private func loadDraft() {
        guard let running = store.running, running.id != loadedId else { return }
        loadedId = running.id
        draftKind = running.kind
        draftStart = running.startedAt
        draftNote = running.note ?? ""
    }

    // MARK: Idle

    private var idleContent: some View {
        VStack(spacing: TT.Space.l) {
            Text(verbatim: DurationFormat.clock(0))
                .font(.system(size: clockSize, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(TT.textTertiary).lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityHidden(true)
            KindSelector(selection: idleKind)
            Button {
                let kind = idleKind.wrappedValue
                Task { await store.start(kind: kind) }
            } label: {
                Label { ux3("ux3.now.start") } icon: { Image(systemName: "play.fill") }
            }
            .buttonStyle(.ttPrimary).controlSize(.large)
            .accessibilityIdentifier("nowsheet.start")
        }
    }

    // MARK: Running

    private func runningContent(_ running: Segment) -> some View {
        VStack(spacing: TT.Space.l) {
            VStack(spacing: TT.Space.xs) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = RunningTimerDisplay(startedAt: running.startedAt).elapsedSeconds(at: context.date)
                    Text(verbatim: DurationFormat.clock(seconds))
                        .font(.system(size: clockSize, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(TT.textPrimary).lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .accessibilityHidden(true)
                }
                Label(running.kind.ttTitle, systemImage: running.kind.ttSymbol)
                    .font(TTFont.label).foregroundStyle(running.kind.ttTint)
                Text(running.startedAt, format: .dateTime.hour().minute())
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(running))

            Button { Task { await store.stop(); dismiss() } } label: {
                Label { ux3("ux3.now.stop") } icon: { Image(systemName: "stop.fill") }
            }
            .buttonStyle(.ttDanger).controlSize(.large)
            .accessibilityIdentifier("nowsheet.stop")

            VStack(alignment: .leading, spacing: TT.Space.m) {
                ux3("ux3.sheet.details").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                KindSelector(selection: $draftKind)
                DatePicker(selection: $draftStart, in: ...Date.now, displayedComponents: [.hourAndMinute]) { ux3("ux3.sheet.start_time") }
                    .accessibilityIdentifier("nowsheet.start_time")
                TextField(text: $draftNote, axis: .vertical) { ux3("ux3.sheet.note") }
                    .lineLimit(1...4).focused($noteFocused)
                    .padding(TT.Space.m).background(TT.glassFallback.opacity(0.5), in: .rect(cornerRadius: TT.Radius.control))
                    .accessibilityIdentifier("nowsheet.note")
                if dirty(running) {
                    Button { Task { await save(running) } } label: { ux3("ux3.sheet.save") }
                        .buttonStyle(.ttPrimary).controlSize(.large).disabled(saving)
                        .accessibilityIdentifier("nowsheet.save")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func startChanged(_ running: Segment) -> Bool { abs(draftStart.timeIntervalSince(running.startedAt)) >= 60 }

    private func dirty(_ running: Segment) -> Bool {
        startChanged(running) || draftKind != running.kind
            || draftNote.trimmingCharacters(in: .whitespacesAndNewlines) != (running.note ?? "")
    }

    private func save(_ running: Segment) async {
        saving = true
        defer { saving = false }
        let note = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let correction = SegmentCorrection(
            startedAt: startChanged(running) ? draftStart : nil,
            kind: draftKind != running.kind ? draftKind : nil,
            note: note != (running.note ?? "") ? note : nil,
            reason: String(localized: "ux3.sheet.reason", table: "UX3"))
        noteFocused = false
        if await store.correctRunning(correction) { loadedId = nil; loadDraft() }
    }

    private func spoken(_ running: Segment) -> String {
        let elapsed = DurationFormat.spoken(RunningTimerDisplay(startedAt: running.startedAt).elapsedSeconds(at: .now))
        return String(localized: "ux3.now.running \(running.kind.ttTitle) \(elapsed.isEmpty ? "0" : elapsed)", table: "UX3")
    }
}
