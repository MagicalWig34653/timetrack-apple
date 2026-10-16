import Foundation
import TimetrackCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Writes the complication's display state (App Group defaults) and asks WidgetKit to redraw.
/// Only non-secret values are written; see `WidgetSnapshot`.
enum WidgetBridge {
    static func publish(running: Segment?, todaySeconds: Int, day: String, timeZone: String, accentHex: String?, colorScheme: String?) {
        let snapshot = WidgetSnapshot(
            isRunning: running != nil, kind: running?.kind ?? .work, startedAt: running?.startedAt,
            todaySeconds: todaySeconds, day: day, timeZone: timeZone, updatedAt: .now,
            accentHex: accentHex, colorScheme: colorScheme
        )
        let store = WidgetSnapshotStore()
        guard store.read() != snapshot.withUpdatedAt(store.read()?.updatedAt) else { return }
        store.write(snapshot)
        reload()
    }

    /// Signed out: the complication shows "Aus" without any leftover totals.
    static func clear() {
        WidgetSnapshotStore().clear()
        reload()
    }

    private static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

private extension WidgetSnapshot {
    func withUpdatedAt(_ date: Date?) -> WidgetSnapshot {
        var copy = self
        if let date { copy.updatedAt = date }
        return copy
    }
}
