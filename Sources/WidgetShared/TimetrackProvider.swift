import SwiftUI
import TimetrackCore
import WidgetKit

/// Reads the snapshot the apps write. The widget never calls the API; only the user-triggered intents do.
struct TimetrackProvider: TimelineProvider {
    private let store = WidgetSnapshotStore()

    func placeholder(in context: Context) -> TimetrackEntry { .sample(running: true) }

    func getSnapshot(in context: Context, completion: @escaping (TimetrackEntry) -> Void) {
        completion(context.isPreview ? .sample(running: true) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimetrackEntry>) -> Void) {
        // The apps reload this timeline after every change; the periodic refresh only drops yesterday's totals after midnight
        // and lets the "Aktualisiert um" note appear when the apps have not written for a while.
        completion(Timeline(entries: [current()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func current() -> TimetrackEntry { TimetrackEntry(date: .now, snapshot: store.read()) }
}
