import SwiftUI
import TimetrackCore
import TimetrackDesign
import WidgetKit

/// macOS desktop / Notification Center widgets. Display only: the Mac widget does not run intents (the session lives in the app's
/// Keychain, which the extension does not share on macOS); tapping opens the app.
struct TimetrackMacWidget: Widget {
    static let kind = "de.linolaske.timetrack.widget.today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TimetrackProvider()) { entry in
            MacFamilyView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringResource("w.title", table: "Widget"))
        .description(LocalizedStringResource("w.description", table: "Widget"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private struct MacFamilyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimetrackEntry

    var body: some View { TimetrackWidgetView(entry: entry, family: family).padding(16) }
}

@main
struct TimetrackWidgetMacBundle: WidgetBundle {
    var body: some Widget { TimetrackMacWidget() }
}

#Preview("Medium", as: .systemMedium) {
    TimetrackMacWidget()
} timeline: {
    TimetrackEntry.sample(running: true)
}
