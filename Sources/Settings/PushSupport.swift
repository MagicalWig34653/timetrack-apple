import Foundation
import TimetrackCore
import TimetrackStores
import UserNotifications
import TimetrackDesign
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// P14c: the platform side of APNs push (iOS/iPadOS and macOS share this file). Asking for permission, asking the system for a
/// device token, and the identity this build registers under. What happens with the token is `PushRegistrationStore`'s job.
@MainActor
enum PushSupport {
    /// Platform, environment (from the signing profile's `aps-environment`), bundle ID and a label without personal names.
    static func identity() -> PushIdentity {
        #if os(iOS)
        let platform = PushPlatform.ios
        let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
        let label = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        let platform = PushPlatform.macos
        let profileURL: URL? = Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile")
        let label = "Mac"
        #endif
        #if DEBUG || targetEnvironment(simulator)
        let sandboxFallback = true
        #else
        let sandboxFallback = false
        #endif
        let profile = profileURL.flatMap { try? Data(contentsOf: $0) }
        return PushIdentity(platform: platform, environment: PushEnvironmentResolver.resolve(profile: profile, fallbackIsSandbox: sandboxFallback),
                            appBundleId: Bundle.main.bundleIdentifier ?? "de.linolaske.timetrack", label: label)
    }

    static func authorization() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    nonisolated static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional: true
        #if os(iOS)
        case .ephemeral: true
        #endif
        default: false
        }
    }

    /// App start / foreground / sign-in: when the user already allowed notifications, ask the system for the token again (Apple
    /// recommends doing this on every launch; the token can change). Never shows a permission dialog.
    static func registerIfAuthorized() async {
        guard isAllowed(await authorization()) else { return }
        registerWithSystem()
    }

    /// The settings row's "Aktivieren": the one place that asks. Returns the resulting status.
    @discardableResult
    static func enable() async -> UNAuthorizationStatus {
        #if os(iOS)
        _ = await FocusNotifications.requestPermission()
        #else
        _ = await MacNotifications.requestIfNeeded()
        #endif
        let status = await authorization()
        if isAllowed(status) { registerWithSystem() }
        return status
    }

    static func registerWithSystem() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #else
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    static func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        #endif
    }
}

/// Connects the app delegate (token, failure, silent push) to the `AppModel`, which the delegate cannot reach directly.
@MainActor
final class PushBridge {
    static let shared = PushBridge()

    private weak var model: AppModel?
    private var pendingToken: String?
    /// Silent pushes must finish within this budget; the system suspends or throttles apps that overrun.
    static let silentPushBudget: Duration = .seconds(20)

    /// Called once from the app's `init`, before the system can deliver a token.
    func attach(_ model: AppModel) {
        self.model = model
        model.pushIdentity = PushSupport.identity()
        if let pendingToken { model.setPushToken(pendingToken) }
    }

    func tokenArrived(_ data: Data) {
        let hex = PushTokenFormat.hex(data)
        if let model { model.setPushToken(hex) } else { pendingToken = hex }
    }

    func tokenFailed(_ error: Error) {
        model?.pushTokenRequestFailed(error.localizedDescription)
    }

    /// Silent `content-available` push: restores the session if the app was started in the background, then reloads today/time/review/planning
    /// within the budget. True when something was refreshed.
    func handleSilentPush() async -> Bool {
        guard let model else { return false }
        let work = Task { @MainActor () -> Bool in
            await model.restoreIfNeeded()
            return await model.refreshAfterPush()
        }
        let timer = Task { try? await Task.sleep(for: Self.silentPushBudget); work.cancel() } // overrunning loads are cancelled
        let refreshed = await work.value
        timer.cancel()
        return refreshed
    }
}

extension View {
    /// Width and padding of the P14c settings pages (iOS "Mehr" and the Mac settings tabs).
    func p14cPageLayout() -> some View {
        padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s).frame(maxWidth: 680).frame(maxWidth: .infinity)
    }
}
