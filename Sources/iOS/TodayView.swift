import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let store = model.today {
                TodayContent(store: store)
            } else {
                ScrollView { SkeletonList(rows: 3).padding(TT.Space.l) }.ttScreenBackground()
            }
        }
        .navigationTitle("sidebar.today")
    }
}

private struct TodayContent: View {
    let store: TodayStore
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Width of the content area; the two-column layout needs room beyond the size class (iPad portrait with an open sidebar is narrow).
    @State private var contentWidth: CGFloat = 0
    /// H3: on iPhone the clock card opens the "Jetzt" sheet (the same sheet as the bar).
    @State private var showSheet = false
    private var twoColumns: Bool { sizeClass == .regular && contentWidth >= 760 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                Eyebrow(verbatim: dateLine).padding(.horizontal, TT.Space.xs)
                if let error = store.error { ErrorBannerView(error: error) { Task { await store.load() } } }
                if twoColumns {
                    HStack(alignment: .top, spacing: TT.Space.xl) {
                        VStack(spacing: TT.Space.l) {
                            TimerCard(store: store, onOpen: { showSheet = true })
                            DayStandingCard(store: store, showsOutlook: true)
                            QuickAbsenceRow()
                        }
                        .frame(maxWidth: 440)
                        VStack(alignment: .leading, spacing: TT.Space.l) {
                            hints
                            TodaySegments(store: store, zone: model.dayCalendar.timeZone)
                        }
                    }
                } else {
                    TimerCard(store: store, onOpen: { showSheet = true })
                    DayStandingCard(store: store, showsOutlook: true)
                    QuickAbsenceRow()
                    hints
                    TodaySegments(store: store, zone: model.dayCalendar.timeZone)
                }
            }
            .padding(.horizontal, TT.Space.l)
            .padding(.vertical, TT.Space.s)
            .frame(maxWidth: twoColumns ? 1100 : TT.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .ttScreenBackground()
        .task { await store.load() }
        .refreshable { await store.load(); TTHaptics.play(.softTap) }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await store.load() } } }
        .animation(.smooth(duration: 0.35), value: store.running?.id)
        .sheet(isPresented: $showSheet) { NowSheet(store: store) }
    }

    @ViewBuilder private var hints: some View {
        if let hints = store.day?.breakHints, !hints.isEmpty {
            VStack(spacing: TT.Space.s) {
                ForEach(hints, id: \.code) { HintBanner(breakHintKey($0.code), symbol: "cup.and.saucer.fill") }
            }
        }
    }

    private var dateLine: String {
        Date.now.formatted(Date.FormatStyle(timeZone: model.dayCalendar.timeZone).weekday(.wide).day().month(.wide))
    }
}

private struct TimerCard: View {
    let store: TodayStore
    let onOpen: () -> Void
    /// H3: on iPhone (compact) the "Jetzt" bar and its sheet own start/stop and the kind choice; the card is only the time (clock and
    /// one status line) and opens the sheet. Where the bar is absent (iPad sidebar layout, regular width) the card keeps the kind
    /// choice and its own button.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("ios.lastKind") private var lastKindRaw = SegmentKind.work.rawValue

    private var cardHasButton: Bool { sizeClass == .regular }

    private var kind: Binding<SegmentKind> {
        Binding(get: { SegmentKind(rawValue: lastKindRaw).flatMap { SegmentKind.selectable.contains($0) ? $0 : nil } ?? .work },
                set: { lastKindRaw = $0.rawValue })
    }

    var body: some View {
        if cardHasButton { regularCard } else { ClockCard(store: store, onOpen: onOpen) }
    }

    private var regularCard: some View {
        TimerHero(startedAt: store.running?.startedAt, kind: store.running?.kind ?? kind.wrappedValue,
                  idleTitle: "today.not_running", idleSubtitle: "today.idle_hint", runningCaption: "today.running") {
            if store.running != nil {
                Button { Task { await store.stop() } } label: {
                    Label("today.stop", systemImage: "stop.fill")
                }
                .buttonStyle(.ttDanger)
                .controlSize(.large)
                .accessibilityIdentifier("today.stop")
            } else {
                KindSelector(selection: kind)
                Button { Task { await store.start(kind: kind.wrappedValue) } } label: {
                    Label("today.start", systemImage: "play.fill")
                }
                .buttonStyle(.ttPrimary)
                .controlSize(.large)
                .accessibilityIdentifier("today.start")
            }
        }
    }
}

/// H3: the first section of "Heute" on iPhone: just the time. Running: live clock, kind and start (and place). Idle: how long the
/// pause lasts, or that nothing runs. Tapping opens the "Jetzt" sheet.
private struct ClockCard: View {
    let store: TodayStore
    let onOpen: () -> Void
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 52

    var body: some View {
        Button(action: onOpen) {
            GlassCard(padding: TT.Space.l, tint: store.running.map { $0.kind.ttTint.opacity(0.22) }) {
                VStack(spacing: TT.Space.xs) {
                    if let running = store.running { runningContent(running) } else { idleContent }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(ux3("ux3.now.details"))
        .accessibilityIdentifier("today.clock")
    }

    private func runningContent(_ running: Segment) -> some View {
        VStack(spacing: TT.Space.xs) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = RunningTimerDisplay(startedAt: running.startedAt).elapsedSeconds(at: context.date)
                Text(verbatim: DurationFormat.clock(seconds))
                    .font(.system(size: numeralSize, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(TT.textPrimary).lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text(verbatim: DurationFormat.spoken(seconds)))
            }
            HStack(spacing: TT.Space.s) {
                LiveDot(color: running.kind.ttTint)
                Label(running.kind.ttTitle, systemImage: running.kind.ttSymbol).font(TTFont.label).foregroundStyle(running.kind.ttTint)
                Text(verbatim: "·").foregroundStyle(TT.textTertiary)
                ux3("h3.since \(running.startedAt.formatted(Date.FormatStyle(timeZone: model.dayCalendar.timeZone).hour().minute()))")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                if let place = store.runningPlace {
                    Image(systemName: "mappin.and.ellipse").imageScale(.small).foregroundStyle(TT.textSecondary)
                    Text(verbatim: place.name).font(TTFont.meta).foregroundStyle(TT.textSecondary).lineLimit(1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var idleContent: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: TT.Space.xs) {
                if let gap = PauseGap(running: nil, segments: store.segments) {
                    Image(systemName: "pause.circle").font(.title2).foregroundStyle(TT.textTertiary).accessibilityHidden(true)
                    Text("today.not_running").font(TTFont.sectionTitle).foregroundStyle(TT.textPrimary)
                    ux3("h3.pause_since_for \(gap.since.formatted(Date.FormatStyle(timeZone: model.dayCalendar.timeZone).hour().minute())) \(DurationFormat.hoursMinutes(gap.seconds(at: context.date)))")
                        .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                } else {
                    Image(systemName: "timer").font(.title2).foregroundStyle(TT.textTertiary).accessibilityHidden(true)
                    Text("today.not_running").font(TTFont.sectionTitle).foregroundStyle(TT.textPrimary)
                    ux3("h3.idle_hint").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
            }
        }
    }
}

private struct TodaySegments: View {
    let store: TodayStore
    let zone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            SectionHeader("today.segments") { if !store.segments.isEmpty { Text(verbatim: "\(store.segments.count)") } }
            if store.segments.isEmpty {
                Card { EmptyState(symbol: "tray", title: "today.no_segments", message: "today.no_segments.hint") }
            } else {
                ListCard {
                    ForEach(store.segments) { SegmentRow(segment: $0, zone: zone) }
                }
            }
        }
    }
}
