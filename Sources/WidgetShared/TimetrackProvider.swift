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
        // The apps reload this timeline after every change. While a timer runs, one entry per minute moves the "Gearbeitet" figure on
        // (h:mm, no ticking seconds); the final refresh drops yesterday's totals after midnight and lets the "Aktualisiert um" note appear.
        let first = current()
        var entries = [first]
        if first.runningSince != nil {
            let now = first.date
            let nextMinute = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
            entries += (0..<15).map { TimetrackEntry(date: nextMinute.addingTimeInterval(Double($0) * 60), snapshot: first.snapshot) }
        }
        completion(Timeline(entries: entries, policy: .after(max(entries.last?.date ?? .now, .now.addingTimeInterval(15 * 60)))))
    }

    private func current() -> TimetrackEntry { TimetrackEntry(date: .now, snapshot: store.read()) }
}
