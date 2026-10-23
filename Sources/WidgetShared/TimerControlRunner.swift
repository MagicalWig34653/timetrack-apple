#if os(iOS)
import Foundation
import TimetrackCore
import TimetrackStores

/// Runs a Pause / Weiter / Stopp press from the Live Activity, the lock screen or the watch (LA1). The press is applied at once
/// (snapshot, pause marker, activity), then queued in the same `TimerActionQueue` as the Focus filter and delivered right away
/// when the server answers; offline it stays queued and the app's retries (launch, foreground, background task) deliver it,
/// corrected back to the press time.
enum TimerControlRunner {
    /// One queue per process, the file the Focus filter uses (an actor guarding one file; both paths drain it).
    static let queue: TimerActionQueue = {
        let directory = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return TimerActionQueue(fileURL: directory.appendingPathComponent("focus-queue.json"), limit: 8)
    }()

    static func perform(_ action: TimerControlAction) async {
        let snapshots = WidgetSnapshotStore()
        let markers = PauseMarkerStore()
        let plan = TimerPress.plan(action, snapshot: snapshots.read(), marker: markers.read())
        switch plan.marker {
        case .keep: break
        case .set(let marker): markers.write(marker)
        case .clear: markers.clear()
        }
        if let snapshot = plan.snapshot { snapshots.write(snapshot) }
        if let queued = plan.queued { await queue.enqueue(queued) }
        WidgetPublisher.reloadAll()
        await TimerLiveActivity.sync(target: LiveActivityTarget.desired(snapshot: snapshots.read(), pause: markers.read(), iconStyle: LiveActivityIconStore().read(), tintStyle: LiveActivityTintStore().read()), source: "intent")

        guard plan.queued != nil,
              let client = await AuthService(secrets: KeychainSecretStore(), transport: URLSessionTransport(timeout: 8)).optimisticClient() else { return }
        let result = await queue.drain(client: client)
        if result.delivered > 0 { await WidgetPublisher.refresh(client: client, source: "intent") }
    }
}
#endif
