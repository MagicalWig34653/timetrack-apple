#if DEBUG
import AppKit
import SwiftUI
import TimetrackStores

/// Debug-only visual check without screen-recording permission: signs in with a throwaway server (TT_DEV_SERVER/TT_DEV_COOKIE)
/// and writes the window's own view hierarchy to PNG files (TT_DEV_SNAPSHOT_DIR). Not compiled into release builds.
@MainActor
enum DebugSnapshots {
    static func run(model: AppModel, ui: UIState) async {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["TT_DEV_SNAPSHOT_DIR"], let server = env["TT_DEV_SERVER"], let cookie = env["TT_DEV_COOKIE"] else { return }
        if model.phase != .signedIn { await model.signInWithSessionCookie(serverInput: server, cookie: cookie) }
        if let size = env["TT_DEV_WINDOW"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2,
           let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
            window.setContentSize(NSSize(width: size[0], height: size[1]))
        }
        for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            NSApp.appearance = NSAppearance(named: appearance)
            for item in SidebarItem.allCases {
                ui.selection = item
                try? await Task.sleep(for: .seconds(3))
                guard let view = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("mac-\(name)-\(item.rawValue).png"))
                }
            }
        }
        await settingsPictures(directory: directory)
        NSApp.terminate(nil)
    }

    /// One picture per tab of the settings window (light and dark); tabs are switched through the window toolbar items.
    private static func settingsPictures(directory: String) async {
        NotificationCenter.default.post(name: .ttDebugOpenSettings, object: nil)
        try? await Task.sleep(for: .seconds(2))
        try? "\(NSApp.windows.map { "\($0.title)|\($0.isVisible)|\($0.frame.width)|\($0.toolbar != nil)" })".write(toFile: directory + "/windows.txt", atomically: true, encoding: .utf8)
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.toolbar != nil && $0.styleMask.contains(.titled) && $0.frame.width < 700 }) else { return }
        for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            NSApp.appearance = NSAppearance(named: appearance)
            window.appearance = NSAppearance(named: appearance)
            for (index, item) in (window.toolbar?.items ?? []).enumerated() {
                window.toolbar?.selectedItemIdentifier = item.itemIdentifier
                if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
                try? await Task.sleep(for: .seconds(2))
                guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("mac-\(name)-settings-\(index).png"))
                }
            }
        }
    }
}

extension Notification.Name { static let ttDebugOpenSettings = Notification.Name("tt.debug.openSettings") }

/// Debug only: lets `DebugSnapshots` open the Settings scene (only possible through the environment action).
private struct DebugSettingsOpener: ViewModifier {
    @Environment(\.openSettings) private var openSettings
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .ttDebugOpenSettings)) { _ in openSettings() }
    }
}

extension View { func debugSettingsOpener() -> some View { modifier(DebugSettingsOpener()) } }
#else
import SwiftUI
extension View { func debugSettingsOpener() -> some View { self } }
#endif
