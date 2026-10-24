import Foundation
import TimetrackCore
import TimetrackStores
import UserNotifications

/// M2: timer actions that run without the stores (notification buttons, leave-stop). Same idempotent queue as iOS: a stable event id,
/// the end corrected back to the real time when the delivery is late, offline actions wait in the file queue.
enum MacTimerActions {
    static let queue: TimerActionQueue = {
        let directory = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return TimerActionQueue(fileURL: directory.appendingPathComponent("mac-timer-queue.json"), limit: 8)
    }()

    static func client() async -> APIClient? {
        await AuthService(secrets: KeychainSecretStore(), transport: URLSessionTransport(timeout: 8)).optimisticClient()
    }

    static func stop(eventId: UUID, at: Date, reason: String) async -> LeaveStopResult {
        await queue.enqueue(QueuedTimerAction(id: eventId, command: .stop, queuedAt: at, correctionReason: reason))
        guard let client = await client() else { return .queued }
        let result = await queue.drain(client: client)
        defer { Task { @MainActor in NotificationCenter.default.post(name: .ttTimerChangedExternally, object: nil) } }
        if result.delivered > 0 { return .stopped }
        if result.remaining == 0 { return result.dropped > 0 ? .alreadyGone : .stopped }
        return .queued
    }

    static func start(kind: SegmentKind) async {
        await queue.enqueue(QueuedTimerAction(command: .start(kind), queuedAt: .now))
        if let client = await client() { _ = await queue.drain(client: client) }
        await MainActor.run { NotificationCenter.default.post(name: .ttTimerChangedExternally, object: nil) }
    }
}

/// Local notifications of the Mac app: the question "Timer beenden um hh:mm?" (presence or leaving a place) and "Timer starten?".
/// Nothing is stopped or started before the user presses a button.
final class MacNotifications: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = MacNotifications()

    static func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        center.setNotificationCategories([
            UNNotificationCategory(identifier: MacNotificationID.stopCategory, actions: [
                UNNotificationAction(identifier: MacNotificationID.stopAction, title: "Beenden", options: []),
                UNNotificationAction(identifier: MacNotificationID.keepAction, title: "Weiterlaufen lassen", options: []),
            ], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: MacNotificationID.startCategory, actions: [
                UNNotificationAction(identifier: MacNotificationID.startAction, title: "Timer starten", options: []),
            ], intentIdentifiers: [], options: []),
        ])
    }

    static func isAllowed() async -> Bool {
        [.authorized, .provisional].contains(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    /// Asks once, when the user switches on a feature that needs notifications.
    @discardableResult
    static func requestIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        return await isAllowed()
    }

    static func postStopQuestion(title: String, body: String, endAt: Date, eventId: UUID, source: String, place: String? = nil) async -> Bool {
        guard await isAllowed() else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = MacNotificationID.stopCategory
        content.threadIdentifier = MacNotificationID.reminderPrefix + "stop"
        content.interruptionLevel = .active
        var info: [String: Any] = [MacNotificationID.endKey: endAt.timeIntervalSince1970, MacNotificationID.eventKey: eventId.uuidString,
                                   MacNotificationID.sourceKey: source]
        if let place { info[MacNotificationID.placeKey] = place }
        content.userInfo = info
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: MacNotificationID.reminderPrefix + "stop." + eventId.uuidString, content: content, trigger: nil))
            return true
        } catch { return false }
    }

    static func postStartQuestion(awayMinutes: Int) async -> Bool {
        guard await isAllowed() else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Timer starten?"
        content.body = "Du bist seit \(awayMinutes) Minuten wieder am Mac und an einem Arbeitsort. Soll ein Arbeits-Timer laufen?"
        content.categoryIdentifier = MacNotificationID.startCategory
        content.threadIdentifier = MacNotificationID.reminderPrefix + "start"
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: MacNotificationID.reminderPrefix + "start", content: content, trigger: nil))
            return true
        } catch { return false }
    }

    // MARK: Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case MacNotificationID.stopAction:
            guard let seconds = info[MacNotificationID.endKey] as? Double, let text = info[MacNotificationID.eventKey] as? String,
                  let eventId = UUID(uuidString: text) else { return }
            let endAt = Date(timeIntervalSince1970: seconds)
            // A timer that was started after the question was asked is not the one the question was about.
            if let client = await MacTimerActions.client(), let running = try? await client.currentTimer(), running.endedAt == nil, running.startedAt > endAt { return }
            let reason = (info[MacNotificationID.sourceKey] as? String) == "leave" ? "Beim Verlassen des Orts gestoppt" : "Auf Nachfrage beim Verlassen des Macs gestoppt"
            let result = await MacTimerActions.stop(eventId: eventId, at: endAt, reason: reason)
            if (info[MacNotificationID.sourceKey] as? String) == "leave", let place = info[MacNotificationID.placeKey] as? String {
                let clock = LeaveStopFilter.clockText(endAt)
                let engine = await MainActor.run { MacAutomationRuntime.shared.engine }
                switch result {
                case .stopped: await engine.recordLeaveAnswer(placeName: place, decision: .leaveStopped, detail: "Timer gestoppt um \(clock)")
                case .queued, .failed: await engine.recordLeaveAnswer(placeName: place, decision: .leaveStopQueued, detail: "Stopp um \(clock) wartet auf Verbindung")
                case .alreadyGone: await engine.recordLeaveAnswer(placeName: place, decision: .leaveNoTimer, detail: "Kein Timer läuft")
                }
            }
        case MacNotificationID.startAction:
            let raw = UserDefaults.standard.string(forKey: "mac.lastKind") ?? SegmentKind.work.rawValue
            await MacTimerActions.start(kind: SegmentKind(rawValue: raw) ?? .work)
        default: break
        }
    }
}
