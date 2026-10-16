import SwiftUI
import TimetrackCore
import WidgetKit

struct ComplicationProvider: TimelineProvider {
    private let store = WidgetSnapshotStore()

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: .init(isRunning: true, kind: .work, startedAt: .now.addingTimeInterval(-3_723),
                                                       todaySeconds: 0, day: "", timeZone: TimeZone.current.identifier, updatedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        // The watch app reloads this timeline on every start/stop; the periodic refresh only corrects a stale "Heute" total after midnight.
        completion(Timeline(entries: [currentEntry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func currentEntry() -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: store.read() ?? .empty)
    }
}

struct TimetrackComplication: Widget {
    static let kind = "de.linolaske.timetrack.complication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ComplicationProvider()) { entry in
            ComplicationFamilyView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(LocalizedStringResource("complication.title", table: "Complication"))
        .description(LocalizedStringResource("complication.description", table: "Complication"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

private struct ComplicationFamilyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View { ComplicationView(entry: entry, family: family) }
}

@main
struct TimetrackWidgetBundle: WidgetBundle {
    var body: some Widget { TimetrackComplication() }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    TimetrackComplication()
} timeline: {
    ComplicationEntry(date: .now, snapshot: .init(isRunning: true, kind: .travel, startedAt: .now.addingTimeInterval(-1_800), todaySeconds: 7_200, day: "", timeZone: "Europe/Berlin", updatedAt: .now))
    ComplicationEntry(date: .now, snapshot: .empty)
}
