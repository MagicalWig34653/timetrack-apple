import Foundation
import TimetrackCore
import TimetrackStores
import UserNotifications

/// Local questions ("Timer starten?") with action buttons. Posting never prompts for permission (callbacks run in the background);
/// the explainer page asks for it. Interruption level stays "active": a time-sensitive level needs an entitlement and is not used.
struct LocalFocusNotifier: FocusNotifier {
    func postStart(_ configuration: FocusConfiguration, eventId: UUID) async -> Bool {
        let text = FocusText.startNotification(configuration)
        return await post(id: FocusNotificationID.start, category: FocusNotificationID.startCategory, title: text.title, body: text.body,
                          configuration: configuration, eventId: eventId, clearing: FocusNotificationID.stop)
    }

    func postStop(_ configuration: FocusConfiguration) async -> Bool {
        let text = FocusText.stopNotification(configuration)
        return await post(id: FocusNotificationID.stop, category: FocusNotificationID.stopCategory, title: text.title, body: text.body,
                          configuration: configuration, eventId: UUID(), clearing: FocusNotificationID.start)
    }

    func postSignIn() async -> Bool {
        await post(id: FocusNotificationID.signIn, category: nil, title: FocusText.signInNotification.title, body: FocusText.signInNotification.body,
                   configuration: nil, eventId: nil, clearing: nil)
    }

    private func post(id: String, category: String?, title: String, body: String, configuration: FocusConfiguration?, eventId: UUID?, clearing: String?) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return false }
        FocusNotifications.registerCategories()
        if let clearing { center.removeDeliveredNotifications(withIdentifiers: [clearing]) }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "de.linolaske.timetrack.focus"
        content.interruptionLevel = .active
        if let category { content.categoryIdentifier = category }
        if let configuration, let data = try? JSONEncoder().encode(configuration) {
            content.userInfo = ["configuration": data.base64EncodedString(), "eventId": eventId?.uuidString ?? ""]
        }
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            return true
        } catch { return false }
    }
}

enum FocusNotificationID {
    static let start = "de.linolaske.timetrack.focus.start"
    static let stop = "de.linolaske.timetrack.focus.stop"
    static let signIn = "de.linolaske.timetrack.focus.signin"
    static let startCategory = "de.linolaske.timetrack.focus.category.start"
    static let stopCategory = "de.linolaske.timetrack.focus.category.stop"
    static let startAction = "start", stopAction = "stop"
}

/// Category registration, permission and the delegate that executes the action buttons (also when the app is launched in the background).
final class FocusNotifications: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = FocusNotifications()

    /// Call once while the app launches so action taps reach the delegate.
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
        registerCategories()
    }

    static func registerCategories() {
        let start = UNNotificationCategory(
            identifier: FocusNotificationID.startCategory,
            actions: [UNNotificationAction(identifier: FocusNotificationID.startAction, title: "Start", options: []),
                      UNNotificationAction(identifier: "dismiss", title: "Nicht jetzt", options: [])],
            intentIdentifiers: [], options: [])
        let stop = UNNotificationCategory(
            identifier: FocusNotificationID.stopCategory,
            actions: [UNNotificationAction(identifier: FocusNotificationID.stopAction, title: "Stopp", options: [.destructive]),
                      UNNotificationAction(identifier: "keep", title: "Weiterlaufen lassen", options: [])],
            intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([start, stop])
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let text = info["configuration"] as? String, let data = Data(base64Encoded: text),
              let configuration = try? JSONDecoder().decode(FocusConfiguration.self, from: data) else { return }
        let runner = FocusEnvironment.makeRunner()
        let report: FocusRunReport
        switch response.actionIdentifier {
        case FocusNotificationID.startAction:
            report = await runner.confirmStart(configuration, eventId: (info["eventId"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID())
        case FocusNotificationID.stopAction:
            report = await runner.confirmStop(configuration)
        default:
            return // "Nicht jetzt" / "Weiterlaufen lassen" / tapping the banner: nothing to do
        }
        await FocusEnvironment.publishIfChanged([report])
    }
}
