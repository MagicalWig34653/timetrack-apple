import Foundation
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
import UserNotifications

/// M2: the Mac counterpart of the iOS `AutomationRuntime`. Same engine, same filter and L4 rules (shared `TimetrackStores` code); only the
/// platform parts differ: no BackgroundTasks (a Mac app that is running is simply running, pending arrivals are checked by a timer), no
/// significant-change/visit wake-ups (CoreLocation offers them on iOS only), notifications instead of Focus plumbing.
@MainActor
final class MacAutomationRuntime {
    static let shared = MacAutomationRuntime()
    private static let moduleKey = "automation.moduleEnabled"

    let engine: AutomationEngine
    let service: LocationService
    let secrets: SecretStore
    private(set) var store: AutomationStore?
    private var storeClient: APIClient?
    private var checkTask: Task<Void, Never>?
    private var started = false
    private var lastPlanKey = ""

    private init() {
        let secrets: SecretStore = KeychainSecretStore()
        self.secrets = secrets
        let service = LocationService()
        self.service = service
        let directory = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let folder = directory.appendingPathComponent("Automation", isDirectory: true)
        let queue = AutomationEventQueue(storage: FileBlobStorage(url: folder.appendingPathComponent("queue.json")))
        let deviceId = Self.deviceId(secrets)
        engine = AutomationEngine(
            storage: FileBlobStorage(url: folder.appendingPathComponent("state.json")), queue: queue, location: service, deviceId: deviceId,
            senderFactory: {
                guard let server = secrets.read(SecretKey.serverURL), let url = URL(string: server),
                      let token = secrets.read(AutomationSecretKey.deviceToken) else { return nil }
                return DeviceTokenEventSender(baseURL: url, token: token, transport: URLSessionTransport())
            },
            leaveStop: MacLeaveStopActions())
    }

    private static func deviceId(_ secrets: SecretStore) -> String {
        if let existing = secrets.read(AutomationSecretKey.deviceId) { return existing }
        let id = "mac-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
        secrets.write(id, for: AutomationSecretKey.deviceId)
        return id
    }

    var moduleEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.moduleKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.moduleKey) }
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        service.onWake = { [weak self] wake in Task { await self?.handle(wake) } }
        service.onStatusChange = { [weak self] status in
            self?.store?.status = status
            Task { await self?.replan(force: true) }
        }
        Task {
            await replan(force: true)
            await engine.evaluate()
            await scheduleChecks()
        }
    }

    func store(for client: APIClient) -> AutomationStore {
        if let store, storeClient === client { return store }
        let created = AutomationStore(client: client, engine: engine, secrets: secrets, deviceName: secrets.read(AutomationSecretKey.deviceId) ?? "mac")
        created.onOutcome = { TTHaptics.handle($0) }
        created.status = service.status
        created.onConfigurationChanged = { [weak self] in Task { await self?.replan(force: true); await self?.scheduleChecks() } }
        store = created
        storeClient = client
        return created
    }

    /// Keeps the cached places current (sign-in, window activation) so a launch without network still knows them.
    func refreshPlaces(using client: APIClient?) async {
        guard moduleEnabled, let client else { return }
        await store(for: client).load()
        await replan(force: false)
    }

    func signedOut() async {
        await engine.clearAll()
        secrets.delete(AutomationSecretKey.deviceToken)
        secrets.delete(AutomationSecretKey.deviceTokenId)
        await replan(force: true)
    }

    func activated() {
        Task {
            await engine.evaluate()
            await replan(force: false)
            await scheduleChecks()
            await store?.refreshFromEngine()
        }
    }

    /// True while the Mac is inside a place with automation on (the arrival was seen), used by the presence advisor for "start at unlock".
    func isAtWorkPlace() async -> Bool {
        let state = await engine.snapshot
        guard state.config.enabled, moduleEnabled else { return false }
        return state.places.contains { place in
            place.mode != .off && (state.runtime[place.id.uuidString].map { $0.phase != .outside || $0.enteredAt != nil } ?? false)
        }
    }

    // MARK: Wake-ups

    private func handle(_ wake: LocationService.Wake) async {
        switch wake {
        case .enter(let id, let date): await engine.regionEntered(id, at: date)
        case .exit(let id, let date): await engine.regionExited(id, at: date)
        case .moved(let point):
            await engine.setLastKnown(point)
            await replan(force: false)
            await engine.evaluate()
        case .visit: await engine.evaluate()
        case .inside(let ids): await engine.reconcile(insidePlaceIds: ids)
        }
        await scheduleChecks()
        await store?.refreshFromEngine()
        NotificationCenter.default.post(name: .ttTimerChangedExternally, object: nil)
    }

    func replan(force: Bool) async {
        let snapshot = await engine.snapshot
        let plan = PlaceMonitorPlanner.plan(places: snapshot.places, near: snapshot.lastKnown)
        let enabled = snapshot.config.enabled && moduleEnabled
        let key = enabled.description + plan.monitored.map { "\($0.id)\($0.monitoringRadius)\($0.center?.latitude ?? 0)\($0.center?.longitude ?? 0)" }.joined()
        guard force || key != lastPlanKey else { return }
        lastPlanKey = key
        service.apply(plan: plan, enabled: enabled)
        store?.status = service.status
    }

    /// Pending arrivals and leaves are checked in this process after their wait time.
    func scheduleChecks() async {
        checkTask?.cancel()
        guard let due = await engine.nextDueDate() else { return }
        let target = due > Date() ? due : Date().addingTimeInterval(5 * 60)
        checkTask = Task { [engine, weak self] in
            try? await Task.sleep(for: .seconds(max(target.timeIntervalSinceNow, 1)))
            guard !Task.isCancelled else { return }
            await engine.evaluate()
            await self?.scheduleChecks()
            await self?.store?.refreshFromEngine()
            NotificationCenter.default.post(name: .ttTimerChangedExternally, object: nil)
        }
    }
}

extension Notification.Name {
    /// A timer was started or stopped outside the stores (notification action, leave-stop); the model reloads "Heute".
    static let ttTimerChangedExternally = Notification.Name("de.linolaske.timetrack.timerChangedExternally")
}

/// Identifiers shared by the Mac notifications (presence questions and the L4 leave question).
enum MacNotificationID {
    static let stopCategory = "de.linolaske.timetrack.mac.stop.category"
    static let startCategory = "de.linolaske.timetrack.mac.start.category"
    static let stopAction = "mac.stop", keepAction = "mac.keep", startAction = "mac.start"
    static let endKey = "endAt", eventKey = "eventId", sourceKey = "source", placeKey = "place"
    static let reminderPrefix = "de.linolaske.timetrack.mac."
}

/// L4 on the Mac: observes the timer, stops it through the same idempotent queue path as iOS, asks "Timer stoppen?" in suggestion mode.
struct MacLeaveStopActions: LeaveStopActing {
    func observeTimer() async -> TimerObservation {
        guard let client = await MacTimerActions.client() else { return .unknown }
        do {
            let segment = try await client.currentTimer()
            guard let segment, segment.endedAt == nil, !segment.voided else { return .idle }
            return .running(startedAt: segment.startedAt, source: segment.source)
        } catch { return .unknown }
    }

    func stopTimer(eventId: UUID, at: Date) async -> LeaveStopResult {
        await MacTimerActions.stop(eventId: eventId, at: at, reason: "Beim Verlassen des Orts gestoppt")
    }

    func offerStop(placeName: String, leftAt: Date, eventId: UUID) async -> Bool {
        await MacNotifications.postStopQuestion(
            title: "Timer stoppen?", body: "Du hast \(placeName) verlassen – Timer stoppen? Gestoppt wird um \(LeaveStopFilter.clockText(leftAt)).",
            endAt: leftAt, eventId: eventId, source: "leave", place: placeName)
    }
}
