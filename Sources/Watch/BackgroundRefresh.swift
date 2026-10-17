import Foundation
import WatchKit

/// Budget-friendly background refresh (A12): about every 20 minutes the system may wake the app to refresh today's snapshot for the
/// complication and the Smart Stack. watchOS decides the real moment; a failed or skipped refresh just waits for the next one.
/// No extended runtime or workout session is used (not allowed for a time tracker).
@MainActor enum BackgroundRefresh {
    static let interval: TimeInterval = 20 * 60

    static func schedule(after interval: TimeInterval = BackgroundRefresh.interval) {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date(timeIntervalSinceNow: interval), userInfo: "refresh" as NSString) { error in
            if let error { LaunchTrace.event("refresh.schedule.failed \(error.localizedDescription)") }
        }
    }
}
