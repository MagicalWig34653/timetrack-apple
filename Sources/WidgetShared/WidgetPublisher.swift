import Foundation
import SwiftUI
import TimetrackCore
import TimetrackStores
import WidgetKit
#if os(iOS)
import ActivityKit
#endif

/// Writes the non-secret widget snapshot and asks the system to redraw widgets, controls and the Live Activity.
/// Called by the apps after every refresh and by the user-triggered intents; the widget extensions only read.
enum WidgetPublisher {
    /// Writes `snapshot` and reloads. Unchanged content still gets a fresh `updatedAt` so the "Aktualisiert um" note stays truthful.
    static func publish(_ snapshot: WidgetSnapshot, store: WidgetSnapshotStore = WidgetSnapshotStore()) async {
        store.write(snapshot)
        reloadAll()
        #if os(iOS)
        await TimerLiveActivity.sync(running: snapshot.isRunning ? snapshot.startedAt.map { ($0, snapshot.kind) } : nil)
        #endif
    }

    /// Signed out: no totals, no Live Activity.
    static func clear(store: WidgetSnapshotStore = WidgetSnapshotStore()) async {
        store.clear()
        reloadAll()
        #if os(iOS)
        await TimerLiveActivity.sync(running: nil)
        #endif
    }

    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        ControlCenter.shared.reloadAllControls()
        #endif
    }

    /// Fetches the current state from the API and publishes it. Used by intents, which run without the app's stores.
    static func refresh(client: APIClient) async {
        let zone = (try? await client.listWorkModels())?.current()?.timeZone ?? TimeZone(identifier: "Europe/Berlin") ?? .current
        let today = DayCalendar(timeZone: zone).day(for: .now)
        async let timer = try? await client.currentTimer()
        async let evaluation = try? await client.getDay(today)
        async let balance = try? await client.getTimeAccount(asOf: today)
        let (running, day, account) = await (timer ?? nil, evaluation, balance)
        let segments = (day?.segments ?? []).filter { !$0.voided }
        await publish(.make(running: running, day: day, account: account, segments: segments, zone: zone))
    }
}

// MARK: - App side

/// What the snapshot depends on; `onChange` publishes when it changes (including every successful reload).
private struct SyncSignature: Equatable {
    let phase: AppModel.Phase
    let loaded: Date?
    let runningID: UUID?
    let segmentCount: Int

    @MainActor init(model: AppModel) {
        phase = model.phase
        loaded = model.today?.lastLoaded
        runningID = model.today?.running?.id
        segmentCount = model.today?.segments.count ?? 0
    }
}

private struct WidgetSyncModifier: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .onChange(of: SyncSignature(model: model), initial: true) { Task { await sync() } }
            #if DEBUG && os(iOS)
            .overlay { if WidgetGallery.isRequested { WidgetGallery().ignoresSafeArea() } }
            #endif
    }

    @MainActor private func sync() async {
        #if os(iOS)
        KeychainSharing.migrateOnce()
        #endif
        switch model.phase {
        case .signedOut, .recoveryRestricted:
            await WidgetPublisher.clear()
        case .signedIn:
            guard let today = model.today, today.lastLoaded != nil else { return }
            let zone = model.dayCalendar.timeZone
            await WidgetPublisher.publish(.make(running: today.running, day: today.day, account: today.account, segments: today.segments, zone: zone))
        case .restoring, .offline:
            break // credentials stay; keep showing the last snapshot (marked stale after a while)
        }
    }
}

extension View {
    /// Keeps the Home Screen / Lock Screen widgets, Live Activity and control in step with what the app shows.
    func widgetSync(_ model: AppModel) -> some View { modifier(WidgetSyncModifier(model: model)) }
}

#if os(iOS)
enum KeychainSharing {
    private static let flag = "keychain.sharedGroup.migrated.v1"

    /// One-time move of the session into the keychain group shared with the widget extension.
    @MainActor static func migrateOnce() {
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        KeychainSecretStore().migrateToDefaultAccessGroup()
        UserDefaults.standard.set(true, forKey: flag)
    }
}
#endif
