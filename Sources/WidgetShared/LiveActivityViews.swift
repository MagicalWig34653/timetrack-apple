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

/// LA4: the kind icon. While work runs and an animation style is chosen it is a poses font driven by a ticking timer text (the only
/// content a Live Activity changes by itself); otherwise the plain SF Symbol. Reduce Motion and the Always-On display show one
/// resting pose instead, and a pause or another kind keeps the symbol.
struct LiveKindIcon: View {
    let state: LiveActivityTarget
    var size: CGFloat = 36
    /// Tinted rounded badge (Lock Screen, expanded) or the bare glyph (compact, minimal, Smart Stack).
    var badge = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        let symbol = state.isPaused ? "pause.fill" : state.kind.ttSymbol
        let style = state.activeIconStyle
        if let font = style.fontName {
            let tint = state.kind.ttTint
            let box = badge ? size * 0.74 : size
            Group {
                if reduceMotion || dimmed {
                    Text(verbatim: "\(style.restingFrame)").font(.custom(font, fixedSize: box)).lineLimit(1).fixedSize().frame(width: box, height: box)
                } else {
                    let clock = state.clock
                    // Only the last character (the seconds digit) stays inside the frame; the rest of the timer text is clipped away.
                    Text(timerInterval: clock.range, pauseTime: clock.pauseTime, countsDown: false, showsHours: true)
                        .font(.custom(font, fixedSize: box)).lineLimit(1).fixedSize().frame(width: box, height: box, alignment: .trailing).clipped()
                }
            }
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(badge ? tint.opacity(0.16) : Color.clear, in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
        } else if badge {
            KindGlyph(symbol: symbol, tint: state.isPaused ? Color.orange : state.kind.ttTint, size: size)
        } else {
            Image(systemName: symbol).foregroundStyle(state.isPaused ? Color.orange : state.kind.ttTint)
        }
    }
}

/// LA4: in-app preview of the chosen icon (settings). Unlike the Live Activity this runs real SwiftUI time, so it plays at 5 poses per
/// second; the Live Activity itself shows one pose per second. Static with Reduce Motion or no style.
struct LiveIconPreview: View {
    let style: LiveActivityIconStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            Spacer()
            Group {
                if let font = style.fontName {
                    TimelineView(.periodic(from: .now, by: 0.2)) { context in
                        let frame = reduceMotion ? style.restingFrame : LiveActivityIconStyle.frame(atElapsed: Int(context.date.timeIntervalSinceReferenceDate * 5))
                        Text(verbatim: "\(frame)").font(.custom(font, fixedSize: 64)).foregroundStyle(Color.accentColor)
                    }
                } else {
                    Image(systemName: SegmentKind.work.ttSymbol).font(.system(size: 40)).foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 80, height: 80)
            Spacer()
        }
        .accessibilityHidden(true)
    }
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
            LiveKindIcon(state: state, size: 44)
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
            LiveKindIcon(state: state, size: 36)
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
        LiveKindIcon(state: state, size: 22, badge: false)
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

/// LA7: round icon button for the Smart Stack. The drawn circle is `diameter`; the tap frame is `hit` (as large as the card allows).
/// Pause/Weiter is a translucent white fill, Stopp the solid danger fill; both carry a hairline. Always-On: outline only.
private struct SmartStackButtonLabel: View {
    let symbol: String
    let fill: Color
    let dimmed: Bool
    var diameter: CGFloat = 32
    var hit: CGFloat = 36

    var body: some View {
        Image(systemName: symbol).font(.system(size: diameter * 0.42, weight: .bold)).foregroundStyle(.white.opacity(dimmed ? 0.75 : 1))
            .frame(width: diameter, height: diameter)
            .background(dimmed ? Color.clear : fill, in: .circle)
            .overlay { Circle().strokeBorder(.white.opacity(dimmed ? 0.4 : 0.25), lineWidth: 0.75) }
            .frame(width: hit, height: hit)
            .contentShape(.rect)
    }
}

/// Smart Stack on the paired watch (`supplementalActivityFamilies([.small, .medium])`): the system mirrors the activity and runs the
/// intents on the iPhone.
///
/// LA7 card. Root cause of the bright card (LA6/N2 still showed grey-green): the tint was a dynamic `UIColor` that resolved to its light
/// variant on the watch and was translucent. Now the family `.small` gets `LiveActivityTint.watchCard` (static, opaque, dark; see
/// `LiveActivityContent`) and the view paints the same colour itself (forum workaround for `activityBackgroundTint` not applying).
/// Layout for the usual 175 x 73 pt card (hierarchy top to bottom): caption row (state icon and label left, planned end right, 11 pt),
/// clock (rounded, semibold, white, monospaced digits, 22 pt) with two round buttons (32 pt drawn, 36 pt tap frame; 44 pt does not fit
/// a 73 pt card next to the clock), a 5 pt accent capsule. A card at least 92 pt tall (larger watches, taller layouts) switches to the
/// roomy layout: 34 pt clock and two full-width 44 pt capsule buttons. Fixed point sizes (a card has a fixed height).
struct LiveActivitySmall: View {
    let state: LiveActivityTarget
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        // `Text(timerInterval:)` truncates instead of shrinking, so the clock size is picked from the card size (tiers), not scaled.
        GeometryReader { proxy in
            let width = proxy.size.width
            Group {
                if proxy.size.height >= 92 { roomy(width: width) } else { compact(width: width) }
            }
            .frame(width: width, height: proxy.size.height, alignment: .center)
        }
        .background(state.watchCardColor.ignoresSafeArea())
    }

    // MARK: compact

    private func compact(width: CGFloat) -> some View {
        let tier: (clock: CGFloat, button: CGFloat, hit: CGFloat) = width >= 170 ? (22, 32, 36) : (width >= 150 ? (20, 30, 33) : (18, 28, 30))
        return VStack(alignment: .leading, spacing: 2) {
            caption(showsState: width >= 165)
            HStack(spacing: 4) {
                clock(size: tier.clock)
                Spacer(minLength: 0)
                buttons(diameter: tier.button, hit: tier.hit)
            }
            .frame(height: tier.hit)
            capsule(height: 5)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
    }

    // MARK: roomy

    private func roomy(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            caption(showsState: true)
            clock(size: width >= 170 ? 34 : 30)
            capsule(height: 6)
            wideButtons
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: parts

    private var ink: Color { .white.opacity(dimmed ? 0.9 : 1) }

    private func clock(size: CGFloat) -> some View {
        LiveWorkedClock(state: state)
            .font(.system(size: size, weight: .semibold, design: .rounded)).foregroundStyle(ink)
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    /// State icon and label on the left, planned end (or estimate) on the right; both truncate tidily.
    private func caption(showsState: Bool) -> some View {
        HStack(spacing: 4) {
            LiveKindIcon(state: state, size: 12, badge: false).font(.system(size: 11, weight: .semibold))
            if showsState { state.stateTitle.layoutPriority(1) }
            Spacer(minLength: 6)
            if state.plannedSeconds != nil { LiveEndLabel(state: state).foregroundStyle(.white.opacity(dimmed ? 0.7 : 0.82)) }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(dimmed ? 0.9 : 0.92))
        .lineLimit(1).truncationMode(.tail).minimumScaleFactor(0.8)
    }

    /// Accent capsule: the system bar clipped to a capsule (hides its end knob) on a faint track.
    @ViewBuilder private func capsule(height: CGFloat) -> some View {
        if state.plannedSeconds != nil {
            LiveProgress(state: state)
                .frame(height: height).clipShape(.capsule)
                .background(.white.opacity(0.16), in: .capsule)
                .opacity(dimmed ? 0.7 : 1)
        }
    }

    private func buttons(diameter: CGFloat, hit: CGFloat) -> some View {
        HStack(spacing: 2) {
            if state.isPaused {
                Button(intent: WidgetResumeTimerIntent()) { SmartStackButtonLabel(symbol: "play.fill", fill: .white.opacity(0.24), dimmed: dimmed, diameter: diameter, hit: hit) }
                    .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringResource("w.resume", table: "Widget")))
            } else {
                Button(intent: WidgetPauseTimerIntent()) { SmartStackButtonLabel(symbol: "pause.fill", fill: .white.opacity(0.24), dimmed: dimmed, diameter: diameter, hit: hit) }
                    .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringResource("w.pause", table: "Widget")))
            }
            Button(intent: WidgetStopTimerIntent()) { SmartStackButtonLabel(symbol: "stop.fill", fill: TT.dangerFill.opacity(0.92), dimmed: dimmed, diameter: diameter, hit: hit) }
                .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringResource("w.stop", table: "Widget")))
        }
    }

    /// Roomy layout: two capsules of 44 pt height sharing the width.
    private var wideButtons: some View {
        HStack(spacing: 6) {
            if state.isPaused {
                Button(intent: WidgetResumeTimerIntent()) { wideLabel("play.fill", .white.opacity(0.24)) }
                    .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringResource("w.resume", table: "Widget")))
            } else {
                Button(intent: WidgetPauseTimerIntent()) { wideLabel("pause.fill", .white.opacity(0.24)) }
                    .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringResource("w.pause", table: "Widget")))
            }
            Button(intent: WidgetStopTimerIntent()) { wideLabel("stop.fill", TT.dangerFill.opacity(0.92)) }
                .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringResource("w.stop", table: "Widget")))
        }
    }

    private func wideLabel(_ symbol: String, _ fill: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(.white.opacity(dimmed ? 0.75 : 1))
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .background(dimmed ? Color.clear : fill, in: .capsule)
            .overlay { Capsule().strokeBorder(.white.opacity(dimmed ? 0.4 : 0.25), lineWidth: 0.75) }
            .contentShape(.capsule)
    }
}

extension LiveActivityTarget {
    /// Card background (Lock Screen and Smart Stack). Q1: the default is a dark, low-saturation graphite with a hint of the account
    /// colour (`LiveActivityTint`); LA3's stronger tint is the "Farbig" choice. The colour maths lives in the core and is tested there.
    var backgroundTint: Color {
        let accent = UIColor(theme.accent)
        let style = activeTintStyle
        return Color(uiColor: UIColor { traits in
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
            accent.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            let tint = LiveActivityTint.color(style: style, hue: hue, saturation: sat, brightness: bri, dark: traits.userInterfaceStyle == .dark)
            return UIColor(hue: tint.hue, saturation: tint.saturation, brightness: tint.brightness, alpha: tint.alpha)
        })
    }
}

extension LiveActivityTarget {
    /// LA7: the watch card colour: static, opaque and dark (see `LiveActivityTint.watchCard`), same hue logic as `backgroundTint`.
    var watchCardColor: Color {
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        UIColor(theme.accent).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        let tint = LiveActivityTint.watchCard(style: activeTintStyle, hue: hue, saturation: sat, brightness: bri)
        return Color(uiColor: UIColor(hue: tint.hue, saturation: tint.saturation, brightness: tint.brightness, alpha: tint.alpha))
    }
}

#if DEBUG
extension LiveActivityTarget {
    /// Sample states for the gallery and previews: 2 h finished + 31 min running, day started 5 h ago, planned end 5 h from now.
    static func sample(paused: Bool = false, kind: SegmentKind = .work, planned: Bool = true, accentHex: String? = nil, iconStyle: LiveActivityIconStyle? = nil, tintStyle: LiveActivityTintStyle? = nil, now: Date = .now) -> LiveActivityTarget {
        let start = paused ? now.addingTimeInterval(-300) : now.addingTimeInterval(-1_860)
        return LiveActivityTarget(kind: kind, startedAt: start, pausedAt: paused ? start : nil, workedSeconds: 7_200 + (paused ? 1_860 : 0),
                                  plannedSeconds: planned ? 28_800 : nil, plannedEnd: planned ? now.addingTimeInterval(5 * 3600) : nil,
                                  dayStart: planned ? now.addingTimeInterval(-3 * 3600 - 1_860 - 1_800) : nil, accentHex: accentHex, iconStyle: iconStyle, tintStyle: tintStyle)
    }
}

/// Approximation of the Lock Screen banner and the Dynamic Island states for screenshots.
struct LiveActivityPreview: View {
    let state: LiveActivityTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiveActivityBanner(state: state)
                .background(state.backgroundTint, in: .rect(cornerRadius: 24))
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

/// Smart Stack card gallery (LA7). Cards are 175 x 73 pt (49 mm, measured), 160 x 73 and 148 x 68 (estimates), 175 x 100 (roomy),
/// shown for running, paused, travel, no plan, estimate, Accessibility 3 and Always-On. The card paints its own opaque dark colour
/// (`watchCardColor`), so the black backdrop here is the real situation, not an approximation.
struct LiveActivityWatchPreview: View {
    let state: LiveActivityTarget

    private func card(_ title: String, _ target: LiveActivityTarget, _ width: CGFloat, _ height: CGFloat = 73, size: DynamicTypeSize = .large, dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: "\(title) (\(Int(width)) x \(Int(height)))").font(.caption2).foregroundStyle(.secondary)
            LiveActivitySmall(state: target)
                .environment(\.dynamicTypeSize, size)
                .environment(\.isLuminanceReduced, dimmed)
                .frame(width: width, height: height, alignment: .top)
                .background(dimmed ? Color.black : Color.clear)
                .clipShape(.rect(cornerRadius: 22))
        }
    }

    var body: some View {
        let running = LiveActivityTarget.sample(paused: false, kind: state.kind, planned: true, accentHex: state.accentHex, iconStyle: state.iconStyle, tintStyle: state.tintStyle)
        let paused = LiveActivityTarget.sample(paused: true, kind: state.kind, planned: true, accentHex: state.accentHex, iconStyle: state.iconStyle, tintStyle: state.tintStyle)
        let noPlan = LiveActivityTarget.sample(paused: false, kind: state.kind, planned: false, accentHex: state.accentHex, iconStyle: state.iconStyle, tintStyle: state.tintStyle)
        let travel = LiveActivityTarget.sample(paused: false, kind: .travel, planned: true, accentHex: state.accentHex, tintStyle: state.tintStyle)
        VStack(alignment: .leading, spacing: 8) {
            card("49 mm running", running, 175); card("49 mm paused", paused, 175)
            card("49 mm travel", travel, 175); card("49 mm no plan", noPlan, 175)
            card("45 mm", running, 160); card("41 mm", running, 148, 68)
            card("49 mm roomy", running, 175, 100)
            card("49 mm, Accessibility 3", paused, 175, size: .accessibility3)
            card("49 mm, Always-On", running, 175, dimmed: true)
            card("49 mm, Always-On paused", paused, 175, dimmed: true)
        }
        .environment(\.colorScheme, .dark)
        .padding(8).background(Color.black)
    }
}
#endif
#endif
