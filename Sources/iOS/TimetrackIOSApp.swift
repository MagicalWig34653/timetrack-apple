import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
import UIKit

@main
struct TimetrackIOSApp: App {
    @UIApplicationDelegateAdaptor(QuickActionDelegate.self) private var delegate
    @State private var model: AppModel
    @State private var ui = UIState.shared
    /// Hands the session to the Apple Watch app (WatchConnectivity); the watch stores it in its own Keychain.
    private let watchSender = WatchHandoffSender(channel: WCSessionChannel(), secrets: KeychainSecretStore())

    init() {
        let passkeys = PlatformPasskeyAuthenticator { Self.keyWindow() }
        let auth = AuthService(secrets: KeychainSecretStore(), transport: URLSessionTransport(), passkeys: passkeys)
        _model = State(initialValue: AppModel(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(ui)
                .environment(\.watchSender, watchSender)
                .ttTheme()
                .task { await watchSender.start() }
                .onChange(of: model.phase) {
                    // restoring/offline keep the watch's session untouched (credentials are still stored on this phone).
                    switch model.phase {
                    case .signedIn: Task { await watchSender.update(isSignedIn: true) }
                    case .signedOut, .recoveryRestricted: Task { await watchSender.update(isSignedIn: false) }
                    case .restoring, .offline: break
                    }
                }
                .task {
                    await model.restore()
                    #if DEBUG
                    // Simulator/UI-test convenience: TT_DEV_SERVER + TT_DEV_COOKIE (a throwaway server's tt_session) sign in without typing.
                    let env = ProcessInfo.processInfo.environment
                    if model.phase != .signedIn, let server = env["TT_DEV_SERVER"], let cookie = env["TT_DEV_COOKIE"] {
                        await model.signInWithSessionCookie(serverInput: server, cookie: cookie)
                    }
                    #endif
                }
        }
    }

    @MainActor
    private static func keyWindow() -> UIWindow {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
        guard let scene = scenes.first else { preconditionFailure("passkey prompt without a window scene") }
        return UIWindow(windowScene: scene)
    }
}

/// Cross-screen UI state. A shared instance lets the UIKit quick-action callbacks reach SwiftUI.
@MainActor
@Observable
final class UIState {
    static let shared = UIState()

    var selection: AppSection = .today
    var newEntryRequest = 0
    /// Set by a Home-screen quick action; consumed by `RootView` once the user is signed in.
    var pendingQuickAction: QuickAction?
}

enum QuickAction: String {
    case start = "de.linolaske.timetrack.quick.start"
    case stop = "de.linolaske.timetrack.quick.stop"
}

enum AppSection: String, CaseIterable, Identifiable {
    case today, time, vacation, settings
    var id: String { rawValue }

    /// Module that must be on for this entry; `nil` = core feature that is always available.
    var requiredModule: ModuleKey? { self == .vacation ? .planning : nil }

    var titleKey: LocalizedStringKey {
        switch self {
        case .today: "sidebar.today"
        case .time: "sidebar.time"
        case .vacation: "sidebar.vacation"
        case .settings: "sidebar.settings"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .time: "calendar.day.timeline.left"
        case .vacation: "beach.umbrella"
        case .settings: "gearshape"
        }
    }
}

final class QuickActionDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { Self.handle(item) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }

    static func handle(_ item: UIApplicationShortcutItem) {
        guard let action = QuickAction(rawValue: item.type) else { return }
        Task { @MainActor in UIState.shared.pendingQuickAction = action }
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        guard QuickAction(rawValue: shortcutItem.type) != nil else { return false }
        QuickActionDelegate.handle(shortcutItem)
        return true
    }
}
