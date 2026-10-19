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
        let clock = state.clock
        Text(timerInterval: clock.range, pauseTime: clock.pauseTime, countsDown: false, showsHours: true)
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

/// Left label under the bar: "Beginn 8:15" for the day bar, "Soll 8:00 Std" for the worked-time fallback, else nothing.
struct LiveStartLabel: View {
    let state: LiveActivityTarget

    var body: some View {
        if state.hasDayStart, let start = state.dayStart {
            wtext("w.live.start \(start.formatted(.dateTime.hour().minute()))")
        } else if state.dayInterval == nil, let planned = state.plannedSeconds {
            wtext("w.live.target \(DurationFormat.hoursMinutes(planned))")
        }
    }
}

/// Labels under the bar: where the bar begins on the left, Feierabend (or the estimate) on the right.
struct LiveDayLabels: View {
    let state: LiveActivityTarget

    var body: some View {
        HStack(spacing: 8) {
            LiveStartLabel(state: state)
            Spacer(minLength: 8)
            LiveEndLabel(state: state)
        }
        .font(.system(.footnote, design: .rounded, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
    }
}

/// Bar plus its labels; nothing without a planned day.
struct LiveDayProgress: View {
    let state: LiveActivityTarget

    var body: some View {
        if state.plannedSeconds != nil {
            VStack(spacing: 6) {
                LiveProgress(state: state)
                LiveDayLabels(state: state)
            }
        }
    }
}

/// "Arbeit - Läuft" caption (kind and state in one quiet line).
private struct LiveCaption: View {
    let state: LiveActivityTarget

    var body: some View {
        HStack(spacing: 5) {
            state.kind.widgetTitle
            Circle().fill(state.isPaused ? Color.orange : state.theme.accent).frame(width: 6, height: 6)
            state.stateTitle
        }
        .font(.system(.subheadline, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
    }
}

/// Kind glyph, caption and the big clock.
private struct LiveHeadline: View {
    let state: LiveActivityTarget
    var scales = false

    var body: some View {
        HStack(spacing: 12) {
            KindGlyph(symbol: state.isPaused ? "pause.fill" : state.kind.ttSymbol, tint: state.kind.ttTint, size: 44)
            VStack(alignment: .leading, spacing: 0) {
                LiveCaption(state: state)
                LiveWorkedClock(state: state)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold)).lineLimit(1).minimumScaleFactor(scales ? 0.5 : 1)
            }
        }
    }
}

/// Solid (not glass) fills: `glassEffect` made the whole button vanish on the Lock Screen (LA2 analysis), so the fills are opaque
/// and the label colour comes from the theme (`onAccent`), which keeps the contrast in every appearance.
private struct LiveWideLabel: View {
    let symbol: String
    let title: Text
    let fill: Color
    let ink: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).imageScale(.small)
            title.lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.system(.body, design: .rounded, weight: .semibold)).foregroundStyle(ink)
        .frame(maxWidth: .infinity, minHeight: 44).background(fill, in: .capsule)
    }
}

private struct LiveRoundLabel: View {
    let symbol: String
    let fill: Color
    let ink: Color

    var body: some View {
        Image(systemName: symbol).font(.system(size: 19, weight: .bold)).foregroundStyle(ink)
            .frame(width: 50, height: 50).background(fill, in: .circle)
    }
}

/// Pause / Weiter and Stopp. Both are `LiveActivityIntent`s that go through the shared offline queue.
/// `.round`: two icon buttons (Lock Screen headline row); `.wide`: two labelled capsules sharing the width.
struct LiveControls: View {
    enum Style { case round, wide }
    let state: LiveActivityTarget
    var style: Style = .wide

    var body: some View {
        let theme = state.theme
        HStack(spacing: style == .round ? 10 : 8) {
            if state.isPaused {
                Button(intent: WidgetResumeTimerIntent()) { label("play.fill", "w.resume", theme.accent, theme.onAccent) }
                    .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringResource("w.resume", table: "Widget")))
            } else {
                Button(intent: WidgetPauseTimerIntent()) { label("pause.fill", "w.pause", theme.accent, theme.onAccent) }
                    .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringResource("w.pause", table: "Widget")))
            }
            Button(intent: WidgetStopTimerIntent()) { label("stop.fill", "w.stop", TT.dangerFill, .white) }
                .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringResource("w.stop", table: "Widget")))
        }
    }

    @ViewBuilder private func label(_ symbol: String, _ key: String.LocalizationValue, _ fill: Color, _ ink: Color) -> some View {
        switch style {
        case .round: LiveRoundLabel(symbol: symbol, fill: fill, ink: ink)
        case .wide: LiveWideLabel(symbol: symbol, title: wtext(key), fill: fill, ink: ink)
        }
    }
}

/// Lock Screen banner (also used by the debug gallery). One row with glyph, clock and the two round buttons, then the day bar;
/// large text sizes stack the buttons below the clock instead. Kept below the 160 pt the system allows.
struct LiveActivityBanner: View {
    let state: LiveActivityTarget

    var body: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    LiveHeadline(state: state).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    LiveControls(state: state, style: .round)
                }
                VStack(alignment: .leading, spacing: 10) {
                    LiveHeadline(state: state, scales: true)
                    LiveControls(state: state, style: .wide)
                }
            }
            LiveDayProgress(state: state)
        }
        .padding(16)
    }
}

/// Dynamic Island expanded, leading: glyph and kind.
struct IslandExpandedLeading: View {
    let state: LiveActivityTarget

    var body: some View {
        HStack(spacing: 8) {
            KindGlyph(symbol: state.isPaused ? "pause.fill" : state.kind.ttSymbol, tint: state.kind.ttTint, size: 36)
            LiveCaption(state: state)
        }
    }
}

/// Dynamic Island expanded, trailing: the clock.
struct IslandExpandedTrailing: View {
    let state: LiveActivityTarget

    var body: some View {
        LiveWorkedClock(state: state).font(.system(.title, design: .rounded, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
    }
}

/// Dynamic Island expanded, bottom: the day bar with labels and the two buttons.
struct IslandExpandedBottom: View {
    let state: LiveActivityTarget

    var body: some View {
        VStack(spacing: 10) {
            LiveDayProgress(state: state)
            LiveControls(state: state, style: .wide)
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

/// Minimal (another app's activity is also running): the kind symbol only.
struct IslandMinimal: View {
    let state: LiveActivityTarget
    var body: some View { IslandCompactLeading(state: state) }
}

/// Smart Stack on the paired watch (`supplementalActivityFamilies([.small])`): the system mirrors the activity and runs the
/// intents on the iPhone. Clock, a thin progress bar and the two buttons as symbols.
struct LiveActivitySmall: View {
    let state: LiveActivityTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: state.isPaused ? "pause.fill" : state.kind.ttSymbol).foregroundStyle(state.kind.ttTint)
                LiveWorkedClock(state: state).font(.system(.title3, design: .rounded, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            }
            if state.plannedSeconds != nil {
                LiveProgress(state: state)
                LiveEndLabel(state: state).font(.system(.caption, design: .rounded, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(spacing: 6) {
                if state.isPaused {
                    Button(intent: WidgetResumeTimerIntent()) { Image(systemName: "play.fill").frame(maxWidth: .infinity, minHeight: 30) }
                        .tint(state.theme.accent).accessibilityLabel(Text(LocalizedStringResource("w.resume", table: "Widget")))
                } else {
                    Button(intent: WidgetPauseTimerIntent()) { Image(systemName: "pause.fill").frame(maxWidth: .infinity, minHeight: 30) }
                        .tint(state.theme.accent).accessibilityLabel(Text(LocalizedStringResource("w.pause", table: "Widget")))
                }
                Button(intent: WidgetStopTimerIntent()) { Image(systemName: "stop.fill").frame(maxWidth: .infinity, minHeight: 30) }
                    .tint(TT.dangerFill).accessibilityLabel(Text(LocalizedStringResource("w.stop", table: "Widget")))
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

#if DEBUG
extension LiveActivityTarget {
    /// Sample states for the gallery and previews: 2 h finished + 31 min running, day started 5 h ago, planned end 5 h from now.
    static func sample(paused: Bool = false, kind: SegmentKind = .work, planned: Bool = true, accentHex: String? = nil, now: Date = .now) -> LiveActivityTarget {
        let start = paused ? now.addingTimeInterval(-300) : now.addingTimeInterval(-1_860)
        return LiveActivityTarget(kind: kind, startedAt: start, pausedAt: paused ? start : nil, workedSeconds: 7_200 + (paused ? 1_860 : 0),
                                  plannedSeconds: planned ? 28_800 : nil, plannedEnd: planned ? now.addingTimeInterval(5 * 3600) : nil,
                                  dayStart: planned ? now.addingTimeInterval(-3 * 3600 - 1_860 - 1_800) : nil, accentHex: accentHex)
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
            VStack(spacing: 8) {
                HStack { IslandExpandedLeading(state: state); Spacer(); IslandExpandedTrailing(state: state) }
                IslandExpandedBottom(state: state)
            }
            .padding(18).frame(width: 358).background(.black, in: .rect(cornerRadius: 44)).environment(\.colorScheme, .dark)
            HStack(spacing: 12) {
                IslandMinimal(state: state)
                    .padding(8).background(.black, in: .circle).environment(\.colorScheme, .dark)
                LiveActivitySmall(state: state)
                    .frame(width: 176).background(.black, in: .rect(cornerRadius: 20)).environment(\.colorScheme, .dark)
            }
        }
    }
}
#endif
#endif
