import Foundation
import TimetrackCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Writes the display state (App Group defaults) that the complication and the next launch read, and asks WidgetKit to redraw.
/// Only non-secret values are written; see `WidgetSnapshot`. A reload is requested only when the content really changed
/// (the update time alone does not count), so a refresh that finds nothing new costs no timeline reload.
enum WidgetBridge {
    @discardableResult
    static func publish(display: TodayDisplay, zone: TimeZone, accentHex: String?, colorScheme: String?) -> Bool {
        let snapshot = WidgetSnapshot.make(display: display, zone: zone, accentHex: accentHex, colorScheme: colorScheme)
        let store = WidgetSnapshotStore()
        if let current = store.read(), current.sameContent(as: snapshot), !current.isStale(at: .now, maxAge: 5 * 60) { return false }
        let changed = store.read().map { !$0.sameContent(as: snapshot) } ?? true
        store.write(snapshot)
        if changed { reload() }
        return changed
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
