import Foundation
import TimetrackCore
import TimetrackStores
import UserNotifications

/// Local questions ("Timer starten?") with action buttons. Posting never prompts for permission (callbacks run in the background);
/// the explainer page asks for it. Every question carries the stamp of the Focus transition that asked it (F3).
struct LocalFocusNotifier: FocusNotifier {
    func postStart(_ configuration: FocusConfiguration, eventId: UUID, sequence: Int64) async -> Bool {
        let text = FocusText.startNotification(configuration)
        return await post(id: FocusNotificationID.start, category: FocusNotificationID.startCategory, title: text.title, body: text.body,
                          configuration: configuration, eventId: eventId, sequence: sequence, clearing: FocusNotificationID.stop)
    }

    func postStop(_ configuration: FocusConfiguration, eventId: UUID, sequence: Int64) async -> Bool {
        let text = FocusText.stopNotification(configuration)
        return await post(id: FocusNotificationID.stop, category: FocusNotificationID.stopCategory, title: text.title, body: text.body,
                          configuration: configuration, eventId: eventId, sequence: sequence, clearing: FocusNotificationID.start)
    }

    func postSignIn() async -> Bool {
        await post(id: FocusNotificationID.signIn, category: nil, title: FocusText.signInNotification.title, body: FocusText.signInNotification.body,
                   configuration: nil, eventId: nil, sequence: nil, clearing: nil)
    }

    private func post(id: String, category: String?, title: String, body: String, configuration: FocusConfiguration?, eventId: UUID?, sequence: Int64?, clearing: String?) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return false }
        FocusNotifications.registerCategories()
        if let clearing { center.removeDeliveredNotifications(withIdentifiers: [clearing]) }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "de.linolaske.timetrack.focus"
        // The question is posted while the Focus is already on, so it is silenced unless Timetrack is an allowed app.
        // `.timeSensitive` could break through but needs the "Time Sensitive Notifications" entitlement; setting it without
        // one stalled the simulator's notification center in F3 testing, so it stays `.active` (see docs/handoffs/F3.md).
        content.interruptionLevel = .active
        if let category { content.categoryIdentifier = category }
        if let configuration, let data = try? JSONEncoder().encode(configuration) {
            var info: [String: Any] = ["configuration": data.base64EncodedString(), "eventId": eventId?.uuidString ?? ""]
            if let sequence { info["sequence"] = NSNumber(value: sequence) }
            content.userInfo = info
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
        let leave = UNNotificationCategory( // L4: "Du hast {Ort} verlassen – Timer stoppen?"
            identifier: LeaveStopNotification.category,
            actions: [UNNotificationAction(identifier: LeaveStopNotification.stopAction, title: "Stoppen", options: [.destructive]),
                      UNNotificationAction(identifier: LeaveStopNotification.keepAction, title: "Weiterlaufen lassen", options: [])],
            intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([start, stop, leave])
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
        if let vacationID = info[VacationReminderCenter.absenceKey] as? String { // R3: vacation reminder tap opens the Urlaub tab
            let start = (info[VacationReminderCenter.startKey] as? String) ?? ""
            await MainActor.run { VacationReminderCenter.shared.handleTap(absenceID: vacationID, startDate: start) }
            return
        }
        if info[LeaveStopNotification.eventKey] != nil { // L4: answer to the leave question
            await LeaveStopNotification.answer(action: response.actionIdentifier, info: info)
            return
        }
        guard let text = info["configuration"] as? String, let data = Data(base64Encoded: text),
              let configuration = try? JSONDecoder().decode(FocusConfiguration.self, from: data) else { return }
        // The stamp of the question makes repeated taps and answers to a superseded question harmless (see `FocusRunner.confirm*`).
        let sequence = (info["sequence"] as? NSNumber)?.int64Value
        let eventId = (info["eventId"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let action = response.actionIdentifier
        guard action == FocusNotificationID.startAction || action == FocusNotificationID.stopAction else {
            return // "Nicht jetzt" / "Weiterlaufen lassen" / tapping the banner: nothing to do
        }
        let report = await FocusEnvironment.withBackgroundTime("focus.answer") { () -> FocusRunReport in
            let runner = FocusEnvironment.makeRunner()
            return action == FocusNotificationID.startAction
                ? await runner.confirmStart(configuration, eventId: eventId, sequence: sequence)
                : await runner.confirmStop(configuration, eventId: eventId, sequence: sequence)
        }
        await FocusEnvironment.publishIfChanged([report])
        NotificationCenter.default.post(name: FocusEnvironment.changed, object: nil)
    }
}
