#if DEBUG
import AppKit
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Debug-only visual check without screen-recording permission: signs in with a throwaway server (TT_DEV_SERVER/TT_DEV_COOKIE)
/// and writes the window's own view hierarchy to PNG files (TT_DEV_SNAPSHOT_DIR). Not compiled into release builds.
@MainActor
enum DebugSnapshots {
    static func run(model: AppModel, ui: UIState) async {
        let env = ProcessInfo.processInfo.environment
        if env["TT_DEV_M2"] == "1", let directory = env["TT_DEV_SNAPSHOT_DIR"] { await m2Pictures(model: model, directory: directory); NSApp.terminate(nil); return }
        guard let directory = env["TT_DEV_SNAPSHOT_DIR"], let server = env["TT_DEV_SERVER"], let cookie = env["TT_DEV_COOKIE"] else { return }
        if model.phase != .signedIn { await model.signInWithSessionCookie(serverInput: server, cookie: cookie) }
        if env["TT_DEV_CONTINUE"] == "1" { await continuePictures(model: model, ui: ui, directory: directory); NSApp.terminate(nil); return }
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

    /// H5: with the seeded entries of today, pictures of "Heute" with the continue offer, the menu bar panel, and after continuing.
    private static func continuePictures(model: AppModel, ui: UIState, directory: String) async {
        ui.selection = .today
        guard let today = model.today else { return }
        if today.running != nil { await today.stop() }
        try? await Task.sleep(for: .seconds(2))
        picture(NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView, name: "mac-h5-continue-idle", directory: directory)
        let panel = NSHostingView(rootView: MenuBarContent().environment(model).ttAppearance())
        panel.frame = NSRect(x: 0, y: 0, width: 280, height: 260)
        panel.layoutSubtreeIfNeeded()
        picture(panel, name: "mac-h5-continue-menubar", directory: directory)
    }

    /// M2: no server needed. Seeds synthetic activity data, then pictures of the "Aktivität" view, the menu bar panel and the new settings tabs.
    private static func m2Pictures(model: AppModel, directory: String) async {
        let companion = MacCompanion.shared
        let store = companion.activity
        store.update { $0.enabled = true }
        store.deleteAllData()
        let zone = model.dayCalendar.timeZone
        let calendar = DayCalendar(timeZone: zone)
        let day = calendar.day(for: .now)
        func at(_ h: Int, _ m: Int) -> Date { calendar.instant(day: day, hour: h, minute: m) ?? .now }
        let apps = [("com.apple.dt.Xcode", "Xcode", 8, 30, 10, 40), ("com.apple.Safari", "Safari", 10, 40, 11, 20), ("com.apple.Terminal", "Terminal", 11, 20, 12, 0),
                    ("com.apple.mail", "Mail", 13, 0, 13, 30), ("com.apple.dt.Xcode", "Xcode", 13, 30, 15, 45)]
        store.record(apps.map { ActivityInterval(bundleID: $0.0, appName: $0.1, start: at($0.2, $0.3), end: at($0.4, $0.5)) })
        store.saveRule(ActivityRule(bundleID: "com.apple.dt.Xcode", appName: "Xcode", labelType: .project, label: "Timetrack"))
        store.saveRule(ActivityRule(bundleID: "com.apple.Terminal", appName: "Terminal", labelType: .project, label: "Timetrack"))
        NSApp.activate()
        let size = NSSize(width: 1000, height: 640)
        let host = NSHostingView(rootView: NavigationStack { ActivityView() }.environment(model).ttAppearance())
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        try? await Task.sleep(for: .seconds(2))
        picture(host, name: "mac-m2-activity", directory: directory)
        window.close()
        let panel = NSHostingView(rootView: MenuBarContent().environment(model).ttAppearance())
        panel.frame = NSRect(x: 0, y: 0, width: 300, height: 320)
        panel.layoutSubtreeIfNeeded()
        picture(panel, name: "mac-m2-menubar", directory: directory)
        // The new settings tabs, hosted directly (the toolbar-driven tab switching of `settingsPictures` is not used here).
        let tabs: [(String, AnyView)] = [("menubar", AnyView(MenuBarSettingsView())), ("automation", AnyView(MacAutomationSettingsView())), ("activity", AnyView(ActivitySettingsView()))]
        for (name, view) in tabs {
            let host = NSHostingView(rootView: view.environment(model).ttAppearance().frame(width: 640, height: 600))
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 600)
            let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            win.contentView = host
            win.isReleasedWhenClosed = false
            win.orderFront(nil)
            try? await Task.sleep(for: .seconds(1.5))
            picture(host, name: "mac-m2-settings-\(name)", directory: directory)
            win.close()
        }
        store.deleteAllData() // leave no synthetic data behind
        store.update { $0.enabled = false }
        for rule in store.rules { store.deleteRule(rule.id) }
    }

    private static func picture(_ view: NSView?, name: String, directory: String) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")) }
    }

    /// One picture per tab of the settings window (light and dark); tabs are switched through the window toolbar items.
    private static func settingsPictures(directory: String) async {
        NotificationCenter.default.post(name: .ttDebugOpenSettings, object: nil)
        try? await Task.sleep(for: .seconds(2))
        try? "\(NSApp.windows.map { "\($0.title)|\($0.isVisible)|\($0.frame.width)|\($0.toolbar != nil)|\($0.toolbar?.items.count ?? -1)" })".write(toFile: directory + "/windows.txt", atomically: true, encoding: .utf8)
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
