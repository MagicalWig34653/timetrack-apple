import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// UX3: the "Jetzt" bar above the tab bar on every tab (iPhone). Running: kind, ticking clock, stop. Idle: kind menu and start.
/// The system draws the Liquid Glass capsule (`tabViewBottomAccessory`); with Reduce Transparency it gets a solid fill here.
struct NowBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let store = model.today { NowBarContent(store: store) }
    }
}

private struct NowBarContent: View {
    let store: TodayStore
        @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.ttTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("ios.lastKind") private var lastKindRaw = SegmentKind.work.rawValue
    /// H3: height the system gives the capsule (measured), so the buttons nest concentrically inside its rounded ends.
    @State private var barHeight: CGFloat = 48
    /// Visual height of the start capsule and the stop circle; the touch target stays 44 pt (frame), the drawn shape is smaller.
    @ScaledMetric(relativeTo: .body) private var controlHeight: CGFloat = 34
    /// H2: tapping the bar opens the "Jetzt" sheet (like the Apple Music mini player opens the full player).
    @State private var showSheet = false

    private var kind: SegmentKind {
        SegmentKind(rawValue: lastKindRaw).flatMap { SegmentKind.selectable.contains($0) ? $0 : nil } ?? .work
    }

    /// The capsule has a fixed system height: at accessibility sizes the bar shows icons only (full text stays in the accessibility labels).
    private var inline: Bool { placement == .inline || typeSize.isAccessibilitySize }
    private var visual: CGFloat { min(controlHeight, max(24, barHeight - 12)) }
    /// Gap between the drawn control and the capsule edge: equal above, below and at the trailing end (concentric nesting).
    private var inset: CGFloat { max(5, (barHeight - visual) / 2) }

    var body: some View {
        Group {
            if let running = store.running { runningBar(running) } else { idleBar }
        }
        // H3: the system capsule has fully rounded ends (radius = height / 2). Text starts further in than the controls, which sit
        // `inset` from the top, bottom and trailing edge, so inner and outer curvature are concentric.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.leading, barHeight / 2 - 4)
        .padding(.trailing, inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 > 20 { barHeight = $0 } }
        .background { if reduceTransparency { Capsule().fill(TT.glassFallback) } }
        .overlay { if reduceTransparency { Capsule().strokeBorder(TT.cardBorder, lineWidth: 1) } }
        .animation(.smooth(duration: 0.25), value: store.running?.id)
        .sheet(isPresented: $showSheet) { NowSheet(store: store) }
    }

    // MARK: Running

    private func runningBar(_ running: Segment) -> some View {
        HStack(spacing: TT.Space.s) {
            // Tapping the left part opens the sheet with the big clock, kind, start time and note.
            Button { showSheet = true } label: {
                HStack(spacing: TT.Space.s) {
                    LiveDot(color: running.kind.ttTint)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = RunningTimerDisplay(startedAt: running.startedAt).elapsedSeconds(at: context.date)
                        Text(verbatim: DurationFormat.clock(seconds))
                            .font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(TT.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                            // Spoken by the surrounding label (minute precision); the ticking digits would be re-read every second.
                            .accessibilityHidden(true)
                    }
                    if !inline {
                        Label(running.kind.ttTitle, systemImage: running.kind.ttSymbol)
                            .labelStyle(.titleAndIcon).font(TTFont.meta).foregroundStyle(running.kind.ttTint).lineLimit(1)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenRunning(running))
            .accessibilityHint(ux3("ux3.now.details"))
            .accessibilityIdentifier("nowbar.open")
            Button { Task { await store.stop() } } label: {
                Image(systemName: "stop.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: visual, height: visual).background(TT.dangerFill, in: .circle)
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
            .padding(.trailing, -(44 - visual) / 2)
            .buttonStyle(.plain)
            .accessibilityLabel(ux3("ux3.now.stop"))
            .accessibilityIdentifier("nowbar.stop")
        }
    }

    private func spokenRunning(_ running: Segment) -> String {
        let elapsed = DurationFormat.spoken(RunningTimerDisplay(startedAt: running.startedAt).elapsedSeconds(at: .now))
        return String(localized: "ux3.now.running \(kindName(running.kind)) \(elapsed.isEmpty ? "0" : elapsed)", table: "UX3")
    }

    // MARK: Idle

    private var idleBar: some View {
        HStack(spacing: TT.Space.s) {
            Menu {
                ForEach(SegmentKind.selectable, id: \.self) { option in
                    Button { if option != kind { TTHaptics.play(.selection) }; lastKindRaw = option.rawValue } label: {
                        Label(option.ttTitle, systemImage: kind == option ? "checkmark" : option.ttSymbol)
                    }
                }
            } label: {
                HStack(spacing: TT.Space.xs) {
                    Image(systemName: kind.ttSymbol).foregroundStyle(kind.ttTint)
                    if !inline { Text(kind.ttTitle).font(TTFont.label).foregroundStyle(TT.textPrimary).lineLimit(1) }
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(TT.textTertiary)
                }
                .frame(minHeight: 44).contentShape(.rect)
            }
            .accessibilityLabel(ux3("ux3.now.kind"))
            .accessibilityValue(Text(kind.ttTitle))
            .accessibilityIdentifier("nowbar.kind")
            Button { showSheet = true } label: { Color.clear.frame(minHeight: 44).contentShape(.rect) }
                .buttonStyle(.plain)
                .accessibilityLabel(ux3("ux3.now.details"))
                .accessibilityIdentifier("nowbar.open")
            Button { Task { await store.start(kind: kind) } } label: {
                HStack(spacing: TT.Space.xs) {
                    Image(systemName: "play.fill")
                    if !inline { ux3("ux3.now.start") }
                }
                .font(TTFont.label.weight(.semibold))
                .padding(.horizontal, TT.Space.l).frame(minWidth: 44, minHeight: visual)
                .foregroundStyle(theme.onAccent)
                .background(theme.accent, in: .capsule)
                .frame(minHeight: 44).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ux3("ux3.now.start_kind \(kindName(kind))"))
            .accessibilityIdentifier("nowbar.start")
        }
        // H4: long press on the idle bar offers to continue the last entry of today.
        .contextMenu {
            if let segment = store.continuableSegment, let ended = segment.endedAt {
                let at = ended.formatted(Date.FormatStyle(timeZone: store.timeZone).hour().minute())
                let long = Date.now.timeIntervalSince(ended) > TodayStore.longContinueGap
                Button { Task { await store.continueLast() } } label: {
                    Label(long ? ux3String("h4.continue.with_gap") : ux3String("h4.continue \(segment.kind.plainName) \(at)"), systemImage: "arrow.uturn.forward")
                }
                if long {
                    Button { Task { await store.continueLast(startNew: true) } } label: {
                        Label(ux3String("h4.continue.fresh"), systemImage: "play")
                    }
                }
            }
        }
    }

    private func kindName(_ kind: SegmentKind) -> String {
        switch kind {
        case .work, .unknown: String(localized: "kind.work")
        case .travel: String(localized: "kind.travel")
        case .school: String(localized: "kind.school")
        }
    }
}

/// H3: after a timer ended (bar, sheet, watch, Live Activity) a small banner offers "Weiter" for a few seconds. There is no "undo" of a stop
/// (the server has no reopen command); "Weiter" starts a new entry of the same kind, so the time in between stays an honest gap.
struct StopToast: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var previous: Segment?
    @State private var shown: Segment?
    @State private var shownSeconds = 0
    @State private var hideTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let shown, let store = model.today {
                    HStack(spacing: TT.Space.m) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(TT.success).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            ux3("h3.toast.stopped").font(TTFont.label).foregroundStyle(TT.textPrimary)
                            Text(verbatim: "\(shown.kind.plainName) · \(DurationFormat.hoursMinutes(shownSeconds))")
                                .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        }
                        Spacer(minLength: TT.Space.s)
                        Button { dismissToast(); Task { await store.start(kind: shown.kind) } } label: {
                            ux3("h3.toast.continue").font(TTFont.label.weight(.semibold)).frame(minHeight: 44).padding(.horizontal, TT.Space.s)
                        }
                        .accessibilityIdentifier("toast.continue")
                    }
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.xs)
                    .background(.regularMaterial, in: .capsule)
                    .overlay { Capsule().strokeBorder(TT.cardBorder, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(.horizontal, TT.Space.l).padding(.top, TT.Space.xs)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("toast.stopped")
                }
            }
            .animation(.smooth(duration: 0.3), value: shown?.id)
            .onChange(of: model.today?.running) { old, new in
                if let new { previous = new; if shown != nil { dismissToast() }; return }
                guard let ended = old ?? previous else { return }
                previous = nil
                shownSeconds = max(0, Int(Date.now.timeIntervalSince(ended.startedAt)))
                shown = ended
                hideTask?.cancel()
                hideTask = Task {
                    try? await Task.sleep(for: .seconds(7))
                    if !Task.isCancelled { shown = nil }
                }
            }
    }

    private func dismissToast() { hideTask?.cancel(); shown = nil }
}
