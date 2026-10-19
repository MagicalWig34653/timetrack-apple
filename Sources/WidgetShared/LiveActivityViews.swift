#if os(iOS)
import AppIntents
import SwiftUI
import TimetrackCore
import TimetrackDesign
import WidgetKit

// LA1: Lock Screen banner, Dynamic Island (compact / minimal / expanded) and the small layout for the watch Smart Stack.
// Time and progress are drawn from dates (`Text(timerInterval:)`, `ProgressView(timerInterval:)`), so they tick without updates.

private extension LiveActivityTarget {
    var theme: TTTheme { TTTheme(accentHex: accentHex) }
    var stateTitle: Text { isPaused ? wtext("w.paused") : wtext("w.running") }
}

/// Today's work as a clock: ticking while running, frozen while paused.
struct LiveWorkedClock: View {
    let state: LiveActivityTarget

    var body: some View {
        Group {
            if state.isPaused {
                let origin = state.workedOrigin
                Text(timerInterval: origin...origin.addingTimeInterval(TimeInterval(state.workedSeconds + 1)),
                     pauseTime: origin.addingTimeInterval(TimeInterval(state.workedSeconds)), countsDown: false, showsHours: true)
            } else {
                Text(timerInterval: state.workedOrigin...Date.distantFuture, pauseTime: nil, countsDown: false, showsHours: true)
            }
        }
        .monospacedDigit()
        .contentTransition(.identity)
    }
}

/// Elapsed against the planned day: a bar or a ring that fills by itself while running.
struct LiveProgress: View {
    let state: LiveActivityTarget

    var body: some View {
        Group {
            if let interval = state.progressInterval {
                ProgressView(timerInterval: interval, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else if let fraction = state.fraction(at: .now) {
                ProgressView(value: fraction) { EmptyView() } currentValueLabel: { EmptyView() }
            }
        }
        .progressViewStyle(.linear)
        .tint(state.theme.accent)
    }
}

/// "Feierabend 16:30" (planned), "Soll erreicht ca. 17:05" (estimate) or "Soll erreicht".
struct LiveEndLabel: View {
    let state: LiveActivityTarget

    var body: some View {
        switch state.end(at: .now) {
        case .planned(let date): wtext("w.live.planned_end \(date.formatted(.dateTime.hour().minute()))")
        case .estimated(let date): wtext("w.live.est_end \(date.formatted(.dateTime.hour().minute()))")
        case .reached: wtext("w.live.reached")
        case nil: state.stateTitle
        }
    }
}

/// "von 8:00 Std geplant" or nothing without a plan.
struct LivePlannedLength: View {
    let state: LiveActivityTarget

    var body: some View {
        if let planned = state.plannedSeconds { wtext("w.live.of_planned \(DurationFormat.hoursMinutes(planned))") }
    }
}

private struct LiveButtonLabel: View {
    let symbol: String
    let title: Text
    let fill: Color
    let ink: Color
    var expand = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).imageScale(.small)
            title.lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.system(.footnote, design: .rounded, weight: .semibold)).foregroundStyle(ink)
        .padding(.horizontal, 14).padding(.vertical, 9).frame(maxWidth: expand ? .infinity : nil).frame(minHeight: 36)
        .modifier(LiveGlassFill(fill: fill))
    }
}

/// E2: Liquid Glass for the Live Activity buttons. `glassEffect` is the glass API usable in widget content on iOS
/// (`WidgetTexture.glass` is visionOS only; the Lock Screen background is the system's own material, `activityBackgroundTint(nil)`).
/// The glass is tinted with the button colour; with Reduce Transparency the solid fill stays so the label keeps its contrast.
private struct LiveGlassFill: ViewModifier {
    let fill: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(fill, in: .capsule)
        } else {
            content.glassEffect(.regular.tint(fill), in: .capsule)
        }
    }
}

/// Pause / Weiter and Stopp. Both are `LiveActivityIntent`s that go through the shared offline queue.
struct LiveControls: View {
    let state: LiveActivityTarget
    var expand = true

    var body: some View {
        HStack(spacing: 8) {
            if state.isPaused {
                Button(intent: WidgetResumeTimerIntent()) {
                    LiveButtonLabel(symbol: "play.fill", title: wtext("w.resume"), fill: state.theme.accent, ink: state.theme.onAccent, expand: expand)
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: WidgetPauseTimerIntent()) {
                    LiveButtonLabel(symbol: "pause.fill", title: wtext("w.pause"), fill: state.theme.accent, ink: state.theme.onAccent, expand: expand)
                }
                .buttonStyle(.plain)
            }
            Button(intent: WidgetStopTimerIntent()) {
                LiveButtonLabel(symbol: "stop.fill", title: wtext("w.stop"), fill: TT.dangerFill, ink: .white, expand: expand)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Lock Screen banner (also used by the debug gallery).
struct LiveActivityBanner: View {
    let state: LiveActivityTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                KindGlyph(symbol: state.isPaused ? "pause.fill" : state.kind.ttSymbol, tint: state.kind.ttTint, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        state.kind.widgetTitle
                        Circle().fill(state.isPaused ? Color.orange : state.kind.ttTint).frame(width: 6, height: 6)
                        state.stateTitle
                    }
                    .font(.system(.footnote, weight: .semibold)).foregroundStyle(state.kind.ttTint).lineLimit(1)
                    LiveWorkedClock(state: state)
                        .font(.system(size: 34, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if state.plannedSeconds != nil {
                VStack(spacing: 4) {
                    LiveProgress(state: state)
                    HStack {
                        LiveEndLabel(state: state)
                        Spacer(minLength: 8)
                        LivePlannedLength(state: state)
                    }
                    .font(.system(.caption, design: .rounded, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            LiveControls(state: state)
        }
        .padding(16)
    }
}

/// Dynamic Island, expanded: heading row, progress and the two buttons.
struct IslandExpanded: View {
    let state: LiveActivityTarget

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label { state.kind.widgetTitle } icon: { Image(systemName: state.isPaused ? "pause.fill" : state.kind.ttSymbol) }
                    .font(.system(.subheadline, weight: .semibold)).foregroundStyle(state.kind.ttTint).lineLimit(1)
                Spacer()
                LiveWorkedClock(state: state).font(.system(.title2, design: .rounded, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            if state.plannedSeconds != nil {
                LiveProgress(state: state)
                HStack {
                    LiveEndLabel(state: state)
                    Spacer(minLength: 8)
                    LivePlannedLength(state: state)
                }
                .font(.system(.caption, design: .rounded, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            LiveControls(state: state)
        }
    }
}

/// Compact leading: the kind symbol (a pause symbol while paused). Progress is shown by the bar in the expanded layout;
/// a ticking circular timer gauge does not render in the compact slot.
struct IslandCompactLeading: View {
    let state: LiveActivityTarget

    var body: some View {
        Image(systemName: state.isPaused ? "pause.fill" : state.kind.ttSymbol).foregroundStyle(state.isPaused ? Color.orange : state.kind.ttTint)
    }
}

struct IslandCompactTrailing: View {
    let state: LiveActivityTarget
    var body: some View {
        LiveWorkedClock(state: state).font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(state.isPaused ? Color.orange : state.kind.ttTint).lineLimit(1).minimumScaleFactor(0.6).frame(width: 58, alignment: .trailing)
    }
}

/// Minimal (another app's activity is also running): ring or symbol only.
struct IslandMinimal: View {
    let state: LiveActivityTarget
    var body: some View { IslandCompactLeading(state: state) }
}

/// Smart Stack on the paired watch (`supplementalActivityFamilies([.small])`): the system mirrors the activity and runs the
/// intents on the iPhone. Clock, a thin progress bar and the two buttons as symbols.
struct LiveActivitySmall: View {
    let state: LiveActivityTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: state.isPaused ? "pause.fill" : state.kind.ttSymbol).foregroundStyle(state.kind.ttTint)
                LiveWorkedClock(state: state).font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            }
            if state.plannedSeconds != nil {
                LiveProgress(state: state)
                LiveEndLabel(state: state).font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(spacing: 6) {
                if state.isPaused {
                    Button(intent: WidgetResumeTimerIntent()) { Image(systemName: "play.fill").frame(maxWidth: .infinity) }
                        .tint(state.theme.accent).accessibilityLabel(Text(LocalizedStringResource("w.resume", table: "Widget")))
                } else {
                    Button(intent: WidgetPauseTimerIntent()) { Image(systemName: "pause.fill").frame(maxWidth: .infinity) }
                        .tint(state.theme.accent).accessibilityLabel(Text(LocalizedStringResource("w.pause", table: "Widget")))
                }
                Button(intent: WidgetStopTimerIntent()) { Image(systemName: "stop.fill").frame(maxWidth: .infinity) }
                    .tint(TT.dangerFill).accessibilityLabel(Text(LocalizedStringResource("w.stop", table: "Widget")))
            }
            .buttonStyle(.bordered)
        }
    }
}

#if DEBUG
extension LiveActivityTarget {
    /// Sample states for the gallery and previews: 2 h finished + 31 min running of an 8 h day, planned end 5 h from now.
    static func sample(paused: Bool = false, kind: SegmentKind = .work, planned: Bool = true, accentHex: String? = nil, now: Date = .now) -> LiveActivityTarget {
        let start = paused ? now.addingTimeInterval(-300) : now.addingTimeInterval(-1_860)
        return LiveActivityTarget(kind: kind, startedAt: start, pausedAt: paused ? start : nil, workedSeconds: 7_200 + (paused ? 1_860 : 0),
                                  plannedSeconds: planned ? 28_800 : nil, plannedEnd: planned ? now.addingTimeInterval(5 * 3600) : nil,
                                  accentHex: accentHex)
    }
}

/// Approximation of the Lock Screen banner and the Dynamic Island states for screenshots.
struct LiveActivityPreview: View {
    let state: LiveActivityTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiveActivityBanner(state: state)
                .background(TT.surface, in: .rect(cornerRadius: 24))
                .frame(width: 358)
            HStack(spacing: 8) {
                IslandCompactLeading(state: state)
                Spacer(minLength: 110)
                IslandCompactTrailing(state: state)
            }
            .padding(.horizontal, 14).frame(width: 240, height: 37).background(.black, in: .capsule).environment(\.colorScheme, .dark)
            IslandExpanded(state: state)
                .padding(18).frame(width: 358).background(.black, in: .rect(cornerRadius: 44)).environment(\.colorScheme, .dark)
            HStack(spacing: 12) {
                IslandMinimal(state: state)
                    .padding(8).background(.black, in: .circle).environment(\.colorScheme, .dark)
                LiveActivitySmall(state: state)
                    .padding(10).frame(width: 170).background(.black, in: .rect(cornerRadius: 20)).environment(\.colorScheme, .dark)
            }
        }
    }
}
#endif
#endif
