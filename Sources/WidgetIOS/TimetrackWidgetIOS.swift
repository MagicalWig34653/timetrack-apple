import ActivityKit
import AppIntents
import SwiftUI
import TimetrackCore
import TimetrackDesign
import WidgetKit

struct TimetrackHomeWidget: Widget {
    static let kind = "de.linolaske.timetrack.widget.today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TimetrackProvider()) { entry in
            FamilyView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringResource("w.title", table: "Widget"))
        .description(LocalizedStringResource("w.description", table: "Widget"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private struct FamilyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimetrackEntry

    var body: some View {
        TimetrackWidgetView(entry: entry, family: family)
            // System families get the standard 16 pt margins back (they were disabled so the lock screen families stay edge to edge).
            .padding(family.isAccessory ? 0 : 16)
    }
}

private extension WidgetFamily {
    var isAccessory: Bool { self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline }
}

// MARK: - Live Activity

struct TimetrackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LiveActivityContent(state: context.state)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) { IslandExpanded(state: context.state) }
            } compactLeading: {
                IslandCompactLeading(state: context.state)
            } compactTrailing: {
                IslandCompactTrailing(state: context.state)
            } minimal: {
                IslandMinimal(state: context.state)
            }
            .keylineTint(TTTheme(accentHex: context.state.accentHex).accent)
            .widgetURL(WidgetLinks.today)
        }
        // LA1: the paired watch mirrors the activity in its Smart Stack with this layout (buttons run on the iPhone).
        .supplementalActivityFamilies([.small])
    }
}

/// Lock Screen on the iPhone or the compact layout of the watch, depending on where the system draws the activity.
private struct LiveActivityContent: View {
    @Environment(\.activityFamily) private var family
    let state: LiveActivityTarget

    var body: some View {
        switch family {
        case .small: LiveActivitySmall(state: state)
        default: LiveActivityBanner(state: state)
        }
    }
}

#if DEBUG
#Preview("Lock Screen running", as: .content, using: TimerActivityAttributes()) {
    TimetrackLiveActivity()
} contentStates: {
    LiveActivityTarget.sample()
    LiveActivityTarget.sample(paused: true)
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: TimerActivityAttributes()) {
    TimetrackLiveActivity()
} contentStates: {
    LiveActivityTarget.sample()
    LiveActivityTarget.sample(paused: true)
}
#endif

// MARK: - Control Center

struct TimerControl: ControlWidget {
    static let kind = "de.linolaske.timetrack.control.timer"

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { WidgetSnapshotStore().read()?.isRunning ?? false }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { running in
            ControlWidgetToggle(isOn: running, action: ToggleTimerControlIntent()) {
                Label { running ? wtext("w.running") : wtext("w.idle") } icon: { Image(systemName: running ? "stop.fill" : "play.fill") }
            } valueLabel: { isOn in
                Label { isOn ? wtext("w.control.stop_hint") : wtext("w.control.start_hint") } icon: { Image(systemName: isOn ? "timer" : "clock") }
            }
        }
        .displayName(LocalizedStringResource("w.control.title", table: "Widget"))
        .description(LocalizedStringResource("w.control.description", table: "Widget"))
    }
}

@main
struct TimetrackWidgetIOSBundle: WidgetBundle {
    var body: some Widget {
        TimetrackHomeWidget()
        TimetrackLiveActivity()
        TimerControl()
    }
}

#Preview("Small running", as: .systemSmall) {
    TimetrackHomeWidget()
} timeline: {
    TimetrackEntry.sample(running: true)
    TimetrackEntry.sample(running: false)
}

#Preview("Medium", as: .systemMedium) {
    TimetrackHomeWidget()
} timeline: {
    TimetrackEntry.sample(running: true)
}

#Preview("Large", as: .systemLarge) {
    TimetrackHomeWidget()
} timeline: {
    TimetrackEntry.sample(running: false)
}
