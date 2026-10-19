import Foundation
import TimetrackCore
import TimetrackStores
import UserNotifications

/// L4: platform side of "stop when leaving". Observes the timer (server first, last widget snapshot when offline), stops it through
/// the normal idempotent stop path (`TimerActionQueue`, shared with Focus filter and Live Activity buttons; a late delivery is
/// corrected back to the time of leaving) and asks "Timer stoppen?" in suggestion mode.
struct AppLeaveStopActions: LeaveStopActing {
    func observeTimer() async -> TimerObservation {
        if let client = await FocusEnvironment.storedClient() {
            do {
                let segment = try await withFocusDeadline(8) { try await client.currentTimer() }
                guard let segment, segment.endedAt == nil, !segment.voided else { return .idle }
                return .running(startedAt: segment.startedAt, source: segment.source)
            } catch {
                // Offline or rejected: fall through to what the app knew last.
            }
        }
        guard let snapshot = WidgetSnapshotStore().read() else { return .unknown }
        guard snapshot.isRunning, let startedAt = snapshot.startedAt else { return .idle }
        return .running(startedAt: startedAt, source: .timer)
    }

    func stopTimer(eventId: UUID, at: Date) async -> LeaveStopResult {
        let queue = FocusEnvironment.queue
        await queue.enqueue(QueuedTimerAction(id: eventId, command: .stop, queuedAt: at, correctionReason: "Beim Verlassen des Orts gestoppt"))
        guard let client = await FocusEnvironment.storedClient() else {
            FocusEnvironment.scheduleRetry()
            return .queued
        }
        let result = await queue.drain(client: client)
        if result.delivered > 0 {
            _ = try? await withFocusDeadline(4) { await WidgetPublisher.refresh(client: client, source: "leave") }
            return .stopped
        }
        if result.remaining == 0 { return result.dropped > 0 ? .alreadyGone : .stopped }
        FocusEnvironment.scheduleRetry()
        return .queued
    }

    func offerStop(placeName: String, leftAt: Date, eventId: UUID) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return false }
        FocusNotifications.registerCategories()
        let content = UNMutableNotificationContent()
        content.title = "Timer stoppen?"
        content.body = "Du hast \(placeName) verlassen – Timer stoppen? Gestoppt wird um \(LeaveStopFilter.clockText(leftAt))."
        content.categoryIdentifier = LeaveStopNotification.category
        content.threadIdentifier = "de.linolaske.timetrack.leave"
        content.interruptionLevel = .active
        content.userInfo = [LeaveStopNotification.eventKey: eventId.uuidString, LeaveStopNotification.leftAtKey: leftAt.timeIntervalSince1970,
                            LeaveStopNotification.placeKey: placeName]
        do {
            try await center.add(UNNotificationRequest(identifier: LeaveStopNotification.identifier(eventId), content: content, trigger: nil))
            return true
        } catch { return false }
    }
}

enum LeaveStopNotification {
    static let category = "de.linolaske.timetrack.leave.category"
    static let stopAction = "leave.stop", keepAction = "leave.keep"
    static let eventKey = "leaveStopEventId", leftAtKey = "leaveStopLeftAt", placeKey = "leaveStopPlace"

    static func identifier(_ eventId: UUID) -> String { "de.linolaske.timetrack.leave." + eventId.uuidString }

    /// The user answered a "Timer stoppen?" question. Stopping uses the leave time as the end, but only if the timer is the one that
    /// was running when the user left (a timer started afterwards is never touched), and the event id keeps repeated taps harmless.
    static func answer(action: String, info: [AnyHashable: Any]) async {
        guard let text = info[eventKey] as? String, let eventId = UUID(uuidString: text),
              let seconds = info[leftAtKey] as? Double else { return }
        let leftAt = Date(timeIntervalSince1970: seconds)
        let place = (info[placeKey] as? String) ?? "Ort"
        guard action == stopAction else { return }
        await FocusEnvironment.withBackgroundTime("leave.answer") {
            let actions = AppLeaveStopActions()
            let engine = await MainActor.run { AutomationRuntime.shared.engine }
            let timer = await actions.observeTimer()
            if let blocked = LeaveStopFilter.timerDecision(timer, leftAt: leftAt) {
                let detail = blocked == .leaveNoTimer ? "Kein Timer läuft" : "Timer wurde nach dem Verlassen neu gestartet"
                await engine.recordLeaveAnswer(placeName: place, decision: blocked, detail: detail)
                return
            }
            guard timer != .unknown else {
                // No way to know: queue the stop with its stable id; the server answers "no running timer" if it is moot.
                _ = await actions.stopTimer(eventId: eventId, at: leftAt)
                await engine.recordLeaveAnswer(placeName: place, decision: .leaveStopQueued, detail: "Stopp um \(LeaveStopFilter.clockText(leftAt)) wartet auf Verbindung")
                return
            }
            let clock = LeaveStopFilter.clockText(leftAt)
            switch await actions.stopTimer(eventId: eventId, at: leftAt) {
            case .stopped: await engine.recordLeaveAnswer(placeName: place, decision: .leaveStopped, detail: "Timer gestoppt um \(clock)")
            case .queued, .failed: await engine.recordLeaveAnswer(placeName: place, decision: .leaveStopQueued, detail: "Stopp um \(clock) wartet auf Verbindung")
            case .alreadyGone: await engine.recordLeaveAnswer(placeName: place, decision: .leaveNoTimer, detail: "Kein Timer läuft")
            }
        }
        NotificationCenter.default.post(name: FocusEnvironment.changed, object: nil)
    }
}
