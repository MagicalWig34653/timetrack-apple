import Carbon.HIToolbox
import Foundation

/// M2: UserDefaults keys of the Mac-only preferences (menu bar companion, Dock, hotkey). All per device; nothing is synced.
enum MacPrefs {
    /// Show the menu bar item at all (forced on in menu-bar-only mode, otherwise the app could not be reached).
    static let menuBarInserted = "mac.menubar.inserted"
    /// Show the running time next to the icon in the menu bar.
    static let menuBarShowsTimer = "mac.menubar.showsTimer"
    /// No Dock icon and no window at launch (`NSApplication.ActivationPolicy.accessory`).
    static let menuBarOnly = "mac.menubarOnly"
    static let hotkeyEnabled = "mac.hotkey.enabled"
    static let hotkeyPreset = "mac.hotkey.preset"
    /// Most recently started kinds, comma separated (`RecentKinds`).
    static let recentKinds = "mac.recentKinds"
    static let presenceSettings = "mac.presence.settings"
    static let reminderPromptShown = "mac.notifications.asked"
}

/// Choosable global shortcuts for "Timer starten/stoppen". Fixed presets instead of a key recorder: they avoid clashes with
/// common system shortcuts and need no Accessibility permission (`RegisterEventHotKey` is a public Carbon API).
enum HotkeyPreset: Int, CaseIterable, Identifiable {
    case controlOptionT, controlOptionCommandT, controlOptionSpace, controlOptionReturn

    var id: Int { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .controlOptionT, .controlOptionCommandT: UInt32(kVK_ANSI_T)
        case .controlOptionSpace: UInt32(kVK_Space)
        case .controlOptionReturn: UInt32(kVK_Return)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .controlOptionCommandT: UInt32(controlKey | optionKey | cmdKey)
        default: UInt32(controlKey | optionKey)
        }
    }

    var title: String {
        switch self {
        case .controlOptionT: "⌃⌥T"
        case .controlOptionCommandT: "⌃⌥⌘T"
        case .controlOptionSpace: "⌃⌥Leertaste"
        case .controlOptionReturn: "⌃⌥Return"
        }
    }
}
