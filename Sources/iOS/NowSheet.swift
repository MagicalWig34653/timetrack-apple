import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// H3: the "Jetzt" sheet that opens from the bar (like the Apple Music mini player opens the full player).
///
/// Running: big live clock with kind and start, the two things you do most (Pause, Stoppen), the day against its target
/// (ring, remaining time, expected end, break status), correcting the start with quick steps, the kind, a note and today's strip.
/// Idle: where the day stands, one-tap "Weiter"/"Starten" with the last used kind, other kinds, start with a head start
/// ("5 Min früher") or at a chosen time, today's strip.
/// "Pause" is honest: there is no pause command, a pause is a gap, so it stops the timer and the sheet then offers "Weiter".
/// Detents medium/large; the system draws the Liquid Glass sheet. Start/stop also stays in the bar itself.
struct NowSheet: View {
    let store: TodayStore
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 56
    @AppStorage("ios.lastKind") private var lastKindRaw = SegmentKind.work.rawValue
    @State private var draftStart: Date = .now
    @State private var draftNote = ""
    @State private var loadedId: UUID?
    @State private var busy = false
    @State private var customStart: Date = Calendar.current.date(byAdding: .minute, value: -30, to: .now) ?? .now
    @SwiftUI.FocusState private var noteFocused: Bool

    private var lastKind: SegmentKind {
        SegmentKind(rawValue: lastKindRaw).flatMap { SegmentKind.selectable.contains($0) ? $0 : nil } ?? .work
    }

    private var idleKind: Binding<SegmentKind> { Binding(get: { lastKind }, set: { lastKindRaw = $0.rawValue }) }
    private var zone: TimeZone { model.dayCalendar.timeZone }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TT.Space.l) {
                    if let running = store.running { runningContent(running) } else { idleContent }
                    if store.running != nil { ContinueNotice(store: store) }
                    if let error = store.error { ErrorBannerView(error: error) { store.error = nil } }
                    dayBlock
                    timelineBlock
                }
                .padding(.horizontal, TT.Space.l)
                .padding(.bottom, TT.Space.xl)
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
        // A correction made elsewhere (head start, quick step, another device) moves the start: the picker follows it.
        .onChange(of: store.running?.startedAt) { _, new in if let new { draftStart = new } }
    }

    private func loadDraft() {
        guard let running = store.running, running.id != loadedId else { return }
        loadedId = running.id
        draftStart = running.startedAt
        draftNote = running.note ?? ""
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
                HStack(spacing: TT.Space.s) {
                    LiveDot(color: running.kind.ttTint)
                    Label(running.kind.ttTitle, systemImage: running.kind.ttSymbol)
                        .font(TTFont.label).foregroundStyle(running.kind.ttTint)
                }
                contextLine(running)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(running))

            HStack(spacing: TT.Space.m) {
                if running.kind == .work {
                    Button { Task { await store.stop() } } label: {
                        Label { ux3("h3.pause") } icon: { Image(systemName: "pause.fill") }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.ttSecondary).controlSize(.large)
                    .accessibilityHint(ux3("h3.pause.hint"))
                    .accessibilityIdentifier("nowsheet.pause")
                }
                Button { Task { await store.stop(); dismiss() } } label: {
                    Label { ux3("ux3.now.stop") } icon: { Image(systemName: "stop.fill") }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.ttDanger).controlSize(.large)
                .accessibilityIdentifier("nowsheet.stop")
            }

            // Correct the start: the quick steps apply at once, the picker and the note are saved with one button.
            VStack(alignment: .leading, spacing: TT.Space.m) {
                ux3("h3.start.title").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                HStack(spacing: TT.Space.s) {
                    stepChip("h3.start.earlier \(15)", id: "nowsheet.earlier15") { await shift(running, by: 15) }
                    stepChip("h3.start.earlier \(5)", id: "nowsheet.earlier5") { await shift(running, by: 5) }
                    stepChip("h3.start.now", id: "nowsheet.now", enabled: Date.now.timeIntervalSince(running.startedAt) > 60) {
                        await shift(running, by: -Int(Date.now.timeIntervalSince(running.startedAt) / 60))
                    }
                }
                DatePicker(selection: $draftStart, in: ...Date.now, displayedComponents: [.hourAndMinute]) { ux3("ux3.sheet.start_time") }
                    .accessibilityIdentifier("nowsheet.start_time")
                Divider()
                ux3("h3.kind.title").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                KindSelector(selection: Binding(get: { running.kind }, set: { newKind in Task { await changeKind(running, to: newKind) } }))
                    .disabled(busy)
                TextField(text: $draftNote, axis: .vertical) { ux3("ux3.sheet.note") }
                    .lineLimit(1...4).focused($noteFocused)
                    .padding(TT.Space.m).background(TT.glassFallback.opacity(0.5), in: .rect(cornerRadius: TT.Radius.control))
                    .accessibilityIdentifier("nowsheet.note")
                if dirty(running) {
                    Button { Task { await save(running) } } label: { ux3("ux3.sheet.save") }
                        .buttonStyle(.ttPrimary).controlSize(.large).disabled(busy)
                        .accessibilityIdentifier("nowsheet.save")
                }
            }
            .padding(TT.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TT.glassFallback.opacity(0.35), in: .rect(cornerRadius: TT.Radius.card, style: .continuous))
        }
    }

    /// "seit 06:12 · Büro Mitte": the place only when the entry has one and the account's places are known.
    private func contextLine(_ running: Segment) -> some View {
        let since = running.startedAt.formatted(Date.FormatStyle(timeZone: zone).hour().minute())
        return HStack(spacing: TT.Space.xs) {
            ux3("h3.since \(since)")
            if let place = store.runningPlace {
                Text(verbatim: "·")
                Image(systemName: "mappin.and.ellipse").imageScale(.small)
                Text(verbatim: place.name).lineLimit(1)
            }
        }
        .font(TTFont.meta).foregroundStyle(TT.textSecondary)
        .accessibilityIdentifier("nowsheet.context")
    }

    private func stepChip(_ key: String.LocalizationValue, id: String, enabled: Bool = true, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            ux3(key).font(TTFont.label).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay { Capsule().strokeBorder(TT.separator, lineWidth: 1) }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain).foregroundStyle(enabled ? TT.textPrimary : TT.textTertiary)
        .disabled(busy || !enabled)
        .accessibilityIdentifier(id)
    }

    // MARK: Idle

    private var idleContent: some View {
        VStack(spacing: TT.Space.l) {
            idleHeader
            Button { Task { await store.start(kind: lastKind) } } label: {
                Label { Text(verbatim: primaryTitle) } icon: { Image(systemName: "play.fill") }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.ttPrimary).controlSize(.large)
            .accessibilityIdentifier("nowsheet.start")
            ContinueButton(store: store)
            ContinueNotice(store: store)

            VStack(alignment: .leading, spacing: TT.Space.m) {
                ux3("h3.kind.title").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                KindSelector(selection: idleKind)
                Divider()
                ux3("h3.start.later_title").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                HStack(spacing: TT.Space.s) {
                    headStart(minutes: 5)
                    headStart(minutes: 15)
                    headStart(minutes: 30)
                }
                HStack(spacing: TT.Space.m) {
                    DatePicker(selection: $customStart, in: dayStart...Date.now, displayedComponents: [.hourAndMinute]) { ux3("h3.start.at") }
                        .accessibilityIdentifier("nowsheet.custom_start")
                    Button { Task { await store.start(kind: lastKind, since: customStart) } } label: { ux3("h3.start.go") }
                        .buttonStyle(.ttSecondary).fixedSize()
                        .accessibilityIdentifier("nowsheet.start_at")
                }
                recentKinds
            }
            .padding(TT.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TT.glassFallback.opacity(0.35), in: .rect(cornerRadius: TT.Radius.card, style: .continuous))
        }
    }

    private var dayStart: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.startOfDay(for: .now)
    }

    /// "Weiter" once something was recorded today (a gap, not an invented break); otherwise "Starten".
    private var primaryTitle: String {
        let kind = lastKind.plainName
        return store.segments.isEmpty ? String(localized: "ux3.now.start_kind \(kind)", table: "UX3") : String(localized: "h3.continue_kind \(kind)", table: "UX3")
    }

    @ViewBuilder private var idleHeader: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: TT.Space.xs) {
                if let gap = PauseGap(running: nil, segments: store.segments) {
                    Text(verbatim: DurationFormat.clock(gap.seconds(at: context.date)))
                        .font(.system(size: clockSize, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(TT.textSecondary).lineLimit(1).minimumScaleFactor(0.5)
                    ux3("h3.pause_since \(gap.since.formatted(Date.FormatStyle(timeZone: zone).hour().minute()))")
                        .font(TTFont.label).foregroundStyle(TT.textSecondary)
                        .accessibilityIdentifier("nowsheet.pause_since")
                } else {
                    Text(verbatim: DurationFormat.clock(0))
                        .font(.system(size: clockSize, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(TT.textTertiary).lineLimit(1).minimumScaleFactor(0.5)
                    ux3("h3.not_running").font(TTFont.label).foregroundStyle(TT.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private func headStart(minutes: Int) -> some View {
        Button { Task { await store.start(kind: lastKind, since: Date.now.addingTimeInterval(TimeInterval(-minutes * 60))) } } label: {
            ux3("h3.start.earlier \(minutes)").font(TTFont.label).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay { Capsule().strokeBorder(TT.separator, lineWidth: 1) }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain).foregroundStyle(TT.textPrimary)
        .accessibilityIdentifier("nowsheet.head\(minutes)")
    }

    /// Other kinds used today, most recent first: one tap starts them.
    @ViewBuilder private var recentKinds: some View {
        let others = recentOtherKinds
        if !others.isEmpty {
            Divider()
            ux3("h3.recent").font(TTFont.meta).foregroundStyle(TT.textSecondary)
            HStack(spacing: TT.Space.s) {
                ForEach(others, id: \.self) { kind in
                    Button { Task { await store.start(kind: kind) } } label: {
                        Label(kind.ttTitle, systemImage: kind.ttSymbol).font(TTFont.label).foregroundStyle(kind.ttTint)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay { Capsule().strokeBorder(kind.ttTint.opacity(0.5), lineWidth: 1) }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ux3String("ux3.now.start_kind \(kind.plainName)"))
                }
            }
        }
    }

    private var recentOtherKinds: [SegmentKind] {
        var seen: [SegmentKind] = []
        for segment in store.segments.reversed() where SegmentKind.selectable.contains(segment.kind) && segment.kind != lastKind && !seen.contains(segment.kind) {
            seen.append(segment.kind)
        }
        return Array(seen.prefix(2))
    }

    // MARK: Day

    private var dayBlock: some View { DayStandingCard(store: store, showsOutlook: true, showsBalance: false) }

    @ViewBuilder private var timelineBlock: some View {
        if !store.segments.isEmpty {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                ux3("h3.timeline.title").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    DayTimeline(segments: store.segments, running: store.running, now: context.date, zone: zone)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TT.Space.xs)
        }
    }

    // MARK: Actions

    private func shift(_ running: Segment, by minutes: Int) async {
        busy = true
        defer { busy = false }
        if await store.shiftRunningStart(byMinutes: minutes) { loadedId = nil; loadDraft() }
    }

    private func changeKind(_ running: Segment, to kind: SegmentKind) async {
        guard kind != running.kind else { return }
        busy = true
        defer { busy = false }
        if SegmentKind.selectable.contains(kind) { lastKindRaw = kind.rawValue }
        _ = await store.correctRunning(SegmentCorrection(kind: kind, reason: String(localized: "ux3.sheet.reason", table: "UX3")))
    }

    private func startChanged(_ running: Segment) -> Bool { abs(draftStart.timeIntervalSince(running.startedAt)) >= 60 }

    private func dirty(_ running: Segment) -> Bool {
        startChanged(running) || draftNote.trimmingCharacters(in: .whitespacesAndNewlines) != (running.note ?? "")
    }

    private func save(_ running: Segment) async {
        busy = true
        defer { busy = false }
        let note = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let correction = SegmentCorrection(
            startedAt: startChanged(running) ? draftStart : nil,
            note: note != (running.note ?? "") ? note : nil,
            reason: String(localized: "ux3.sheet.reason", table: "UX3"))
        noteFocused = false
        if await store.correctRunning(correction) { loadedId = nil; loadDraft() }
    }

    private func spoken(_ running: Segment) -> String {
        let elapsed = DurationFormat.spoken(RunningTimerDisplay(startedAt: running.startedAt).elapsedSeconds(at: .now))
        return String(localized: "ux3.now.running \(running.kind.plainName) \(elapsed.isEmpty ? "0" : elapsed)", table: "UX3")
    }
}
