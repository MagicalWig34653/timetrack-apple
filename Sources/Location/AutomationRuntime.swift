import BackgroundTasks
import Foundation
import SwiftUI
import TimetrackCore
import TimetrackStores
import UIKit

/// Process-wide wiring of the location automation: the engine, the CoreLocation layer and background wake-ups.
/// One shared instance so that region callbacks (also on a background launch) and App Intents use the same state and queue.
@MainActor
final class AutomationRuntime {
    static let shared = AutomationRuntime()
    static let refreshTaskIdentifier = "de.linolaske.timetrack.automation.refresh"
    private static let moduleKey = "automation.moduleEnabled"

    let engine: AutomationEngine
    let service: LocationService
    let secrets: SecretStore
    private(set) var store: AutomationStore?
    private var checkTask: Task<Void, Never>?
    private var started = false
    private var lastPlanKey = ""
    private var storeChangedHandler: (() -> Void)?

    private init() {
        let secrets = KeychainSecretStore()
        let service = LocationService()
        self.secrets = secrets
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
            })
    }

    /// Stable, non-personal name of this installation for the server (`ios-` plus six hex characters).
    private static func deviceId(_ secrets: SecretStore) -> String {
        if let existing = secrets.read(AutomationSecretKey.deviceId) { return existing }
        let id = "ios-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
        secrets.write(id, for: AutomationSecretKey.deviceId)
        return id
    }

    var deviceId: String { secrets.read(AutomationSecretKey.deviceId) ?? "ios" }

    /// Whether the server-side `automation` module is on. Persisted so that a background launch before sign-in respects it.
    var moduleEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.moduleKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.moduleKey) }
    }

    // MARK: - Lifecycle

    /// Call once at launch (also for background launches caused by a region event). Registers the refresh task, restores
    /// monitoring from the cached places and checks pending arrivals. No network is needed for any of this.
    func start() {
        guard !started else { return }
        started = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            Self.shared.runRefresh(task)
        }
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

    func attach(_ store: AutomationStore) {
        self.store = store
        store.status = service.status
        store.onConfigurationChanged = { [weak self] in
            TimetrackShortcuts.updateAppShortcutParameters() // one App Shortcut per place
            Task { await self?.replan(force: true); await self?.scheduleChecks() }
        }
    }

    /// The account is gone (sign-out): stop watching, forget cached places and queued events, delete the local token.
    func signedOut() async {
        await engine.clearAll()
        secrets.delete(AutomationSecretKey.deviceToken)
        secrets.delete(AutomationSecretKey.deviceTokenId)
        await replan(force: true)
    }

    func foregrounded() {
        Task {
            await engine.evaluate()
            await replan(force: false)
            await scheduleChecks()
            await store?.refreshFromEngine()
        }
    }

    // MARK: - Wake-ups

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
    }

    /// Applies the monitored-region plan. Skipped when nothing relevant changed (a significant change is frequent).
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

    /// Pending arrivals are checked (a) in this process after the dwell time if the app stays alive, and (b) by the system's
    /// background refresh, whose timing iOS decides (the earliest begin date is only a lower bound).
    func scheduleChecks() async {
        checkTask?.cancel()
        guard let due = await engine.nextDueDate() else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskIdentifier)
            return
        }
        // An arrival that is overdue but still unresolved (fast device, no fix) is retried with a back-off, never in a tight loop.
        let target = max(due, Date().addingTimeInterval(5 * 60))
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = target
        try? BGTaskScheduler.shared.submit(request)
        checkTask = Task { [engine, weak self] in
            let wait = max(target.timeIntervalSinceNow, 1)
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await engine.evaluate()
            await self?.scheduleChecks()
            await self?.store?.refreshFromEngine()
        }
    }

    private func runRefresh(_ task: BGAppRefreshTask) {
        let work = Task {
            await engine.evaluate()
            await scheduleChecks()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
