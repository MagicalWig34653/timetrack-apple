#if os(iOS)
import Foundation
import TimetrackCore
import UserNotifications

/// Shared notification permission logic (R3 vacation reminders and OT1 overwork notifications).
enum NotificationPermission {
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func isGranted(_ status: UNAuthorizationStatus) -> Bool { [.authorized, .provisional, .ephemeral].contains(status) }

    /// Asks the system only while the decision is open (first activation); returns the resulting status.
    static func requestIfNeeded() async -> UNAuthorizationStatus {
        var current = await status()
        if current == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            current = await status()
        }
        return current
    }
}

/// OT1: keeps the pending overwork notifications in step with the timer. The plan is the pure `OverworkPlanner` (TimetrackCore);
/// this applies it to `UNUserNotificationCenter`. It is called from `WidgetPublisher.publish`, which every start, pause, resume, stop and refresh
/// (app, intents, Live Activity buttons) passes through, and when the settings change.
@MainActor
enum OverworkScheduler {
    private static var tail: Task<Void, Never>?

    /// Runs after the previous call, so removing and adding never interleave.
    static func sync(snapshot: WidgetSnapshot?, settings: OverworkSettings = OverworkSettingsStore().read(),
                     now: Date = .now) async {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await apply(snapshot: snapshot, settings: settings, now: now)
        }
        tail = task
        await task.value
    }

    /// Re-plans from the snapshot last written (after a settings change).
    static func syncFromStoredSnapshot() async {
        await sync(snapshot: WidgetSnapshotStore().read())
    }

    static func pendingCount() async -> Int {
        let center = UNUserNotificationCenter.current()
        return await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(OverworkItem.idPrefix) }.count
    }

    private static func apply(snapshot: WidgetSnapshot?, settings: OverworkSettings, now: Date) async {
        let center = UNUserNotificationCenter.current()
        let granted = NotificationPermission.isGranted(await NotificationPermission.status())
        let planned = granted && settings.isAnyEnabled && snapshot != nil
            ? OverworkPlanner.plan(snapshot: snapshot!, settings: settings, now: now) : []
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let result = OverworkPlanner.reconcile(pendingIDs: pending, planned: planned)
        center.removePendingNotificationRequests(withIdentifiers: result.remove)
        if planned.isEmpty { // timer stopped or paused, switched off: delivered ones would only confuse
            let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(OverworkItem.idPrefix) }
            center.removeDeliveredNotifications(withIdentifiers: delivered)
        }
        for item in result.add {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = "de.linolaske.timetrack.overwork"
            content.interruptionLevel = .active
            let interval = max(1, item.fireDate.timeIntervalSince(now))
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
        }
    }
}
#endif
