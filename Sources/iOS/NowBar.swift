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
    @AppStorage("ios.lastKind") private var lastKindRaw = SegmentKind.work.rawValue
    /// H2: tapping the bar opens the "Jetzt" sheet (like the Apple Music mini player opens the full player).
    @State private var showSheet = false

    private var kind: SegmentKind {
        SegmentKind(rawValue: lastKindRaw).flatMap { SegmentKind.selectable.contains($0) ? $0 : nil } ?? .work
    }

    private var inline: Bool { placement == .inline }

    var body: some View {
        Group {
            if let running = store.running { runningBar(running) } else { idleBar }
        }
        // H1: breathing room around the capsule/stop button (it used to touch the bar's edge).
        .padding(.horizontal, TT.Space.l)
        .padding(.vertical, TT.Space.xs)
        .frame(maxWidth: .infinity, minHeight: 44)
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
                Image(systemName: "stop.fill").font(.body.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(TT.dangerFill, in: .circle)
            }
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
                .padding(.horizontal, TT.Space.l).frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(theme.onAccent)
                .background(theme.accent, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ux3("ux3.now.start_kind \(kindName(kind))"))
            .accessibilityIdentifier("nowbar.start")
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
