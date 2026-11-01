import SwiftUI
#if os(iOS)
import UIKit
#endif

/// SET-B: the notification settings pages (vacation reminders, overwork hints) run on iOS and on the Mac. Only the wording of the
/// system ("iOS" vs. "Systemeinstellungen") and the way to open the system settings differ.
enum NotificationSettingsText {
    #if os(iOS)
    static let system = "iOS"
    static let openSettingsTitle = "iOS-Einstellungen öffnen"
    static let settingsAreaName = "den iOS-Einstellungen"
    static var settingsURL: URL? { URL(string: UIApplication.openSettingsURLString) }
    #else
    static let system = "macOS"
    static let openSettingsTitle = "Systemeinstellungen öffnen"
    static let settingsAreaName = "den Systemeinstellungen"
    static var settingsURL: URL? { URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") }
    #endif

    /// "Beim Einschalten fragt <System> einmal nach der Erlaubnis für Mitteilungen."
    static func permissionFooter(_ lead: String) -> String { "\(lead) fragt \(system) einmal nach der Erlaubnis für Mitteilungen." }
    static func deniedText(_ what: String) -> String { "Du hast Mitteilungen für Timetrack abgelehnt. Erlaube sie in \(settingsAreaName), damit \(what) ankommen können." }
}

extension View {
    /// Inline title on iOS; the Mac detail pane has no navigation bar title style.
    @ViewBuilder func notificationPageTitle(_ title: String) -> some View {
        #if os(iOS)
        navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        #else
        navigationTitle(title)
        #endif
    }
}
