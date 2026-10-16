#if os(iOS)
import AppIntents
import SwiftUI
import TimetrackCore
import TimetrackDesign

/// Lock Screen banner of the running-timer Live Activity (also used by the debug gallery).
struct LiveActivityBanner: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            KindGlyph(symbol: state.kind.ttSymbol, tint: state.kind.ttTint, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    state.kind.widgetTitle
                    Circle().fill(state.kind.ttTint).frame(width: 6, height: 6)
                    wtext("w.running")
                }
                .font(.system(.footnote, weight: .semibold)).foregroundStyle(state.kind.ttTint)
                LiveTimerText(since: state.startedAt)
                    .font(.system(size: 34, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(intent: WidgetStopTimerIntent()) {
                HStack(spacing: 5) { Image(systemName: "stop.fill").imageScale(.small); wtext("w.stop") }
                    .font(.system(.footnote, design: .rounded, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9).background(TT.dangerFill, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }
}

/// Dynamic Island parts, shared between the real presentation and the gallery mock-up.
struct IslandExpanded: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label { state.kind.widgetTitle } icon: { Image(systemName: state.kind.ttSymbol) }
                    .font(.system(.subheadline, weight: .semibold)).foregroundStyle(state.kind.ttTint)
                Spacer()
                LiveTimerText(since: state.startedAt).font(.system(.title2, design: .rounded, weight: .bold)).frame(maxWidth: 120, alignment: .trailing)
            }
            Button(intent: WidgetStopTimerIntent()) {
                HStack(spacing: 5) { Image(systemName: "stop.fill").imageScale(.small); wtext("w.stop") }
                    .font(.system(.footnote, design: .rounded, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 8).background(TT.dangerFill, in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
}

struct IslandCompactLeading: View {
    let state: TimerActivityAttributes.ContentState
    var body: some View { Image(systemName: state.kind.ttSymbol).foregroundStyle(state.kind.ttTint) }
}

struct IslandCompactTrailing: View {
    let state: TimerActivityAttributes.ContentState
    var body: some View {
        LiveTimerText(since: state.startedAt).font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(state.kind.ttTint).frame(maxWidth: 52)
    }
}

#if DEBUG
/// Approximation of the Lock Screen banner and the Dynamic Island states for screenshots.
struct LiveActivityPreview: View {
    let state: TimerActivityAttributes.ContentState

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
            Image(systemName: state.kind.ttSymbol).foregroundStyle(state.kind.ttTint)
                .padding(10).background(.black, in: .circle).environment(\.colorScheme, .dark)
        }
    }
}
#endif
#endif
