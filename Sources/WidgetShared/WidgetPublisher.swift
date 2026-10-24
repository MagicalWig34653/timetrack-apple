import Foundation
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
import WidgetKit
#if os(iOS)
import ActivityKit
#endif

/// Writes the non-secret widget snapshot and asks the system to redraw widgets, controls and the Live Activity.
/// Called by the apps after every refresh and by the user-triggered intents; the widget extensions only read.
enum WidgetPublisher {
    /// Writes `snapshot` and reloads. Unchanged content still gets a fresh `updatedAt` so the "Aktualisiert um" note stays truthful.
    static func publish(_ snapshot: WidgetSnapshot, source: String = "model", store: WidgetSnapshotStore = WidgetSnapshotStore()) async {
        var snapshot = snapshot
        // Intents refresh without the app's appearance state: keep the accent the app wrote last.
        if snapshot.accentHex == nil, let previous = store.read() {
            snapshot.accentHex = previous.accentHex
            snapshot.colorScheme = previous.colorScheme
        }
        store.write(snapshot)
        reloadAll()
        #if os(macOS)
        await OverworkScheduler.sync(snapshot: snapshot) // M2: same overwork notifications as iOS, planned from the timer state
        #endif
        #if os(iOS)
        // A running timer ends any pause (resumed in the app or elsewhere); otherwise a pause marker keeps a paused activity.
        let markers = PauseMarkerStore()
        if snapshot.isRunning { markers.clear() }
        await TimerLiveActivity.sync(target: .desired(snapshot: snapshot, pause: markers.read(), iconStyle: LiveActivityIconStore().read(), tintStyle: LiveActivityTintStore().read()), source: source)
        #endif
    }

    /// Signed out: no totals, no Live Activity.
    static func clear(store: WidgetSnapshotStore = WidgetSnapshotStore()) async {
        store.clear()
        reloadAll()
        #if os(macOS)
        await OverworkScheduler.sync(snapshot: nil)
        #endif
        #if os(iOS)
        PauseMarkerStore().clear()
        await TimerLiveActivity.sync(target: nil, source: "signedOut")
        #endif
    }

    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        ControlCenter.shared.reloadAllControls()
        #endif
    }

    /// `.failure` (not "no timer") when the request fails.
    private static func readTimer(_ client: APIClient) async -> Result<Segment?, Error> {
        do { return .success(try await client.currentTimer()) } catch { return .failure(error) }
    }

    /// Fetches the current state from the API and publishes it. Used by intents, which run without the app's stores.
    static func refresh(client: APIClient, source: String = "refresh") async {
        let zone = (try? await client.listWorkModels())?.current()?.timeZone ?? TimeZone(identifier: "Europe/Berlin") ?? .current
        let today = DayCalendar(timeZone: zone).day(for: .now)
        // A failed read must never look like "no timer" (that would end the Live Activity).
        async let timer = Self.readTimer(client)
        async let evaluation = try? await client.getDay(today)
        async let balance = try? await client.getTimeAccount(asOf: today)
        let (answer, day, account) = await (timer, evaluation, balance)
        guard case .success(let running) = answer else { return }
        // Presses still waiting in the queue are newer than the server's answer: keep the optimistic snapshot until they arrive.
        #if os(iOS)
        guard await TimerControlRunner.queue.count == 0 else { return }
        #endif
        let segments = (day?.segments ?? []).filter { !$0.voided }
        var snapshot = WidgetSnapshot.make(running: running, day: day, account: account, segments: segments, zone: zone)
        await attachPlan(to: &snapshot, client: client, day: today, zone: zone)
        await publish(snapshot, source: source)
    }

    /// LA1: today's planned end and length (plan day, contract 0.17.0). A failed or empty read keeps what the previous snapshot of the
    /// same day had, so a flaky network does not make the planned end disappear.
    static func attachPlan(to snapshot: inout WidgetSnapshot, client: APIClient, day: LocalDay, zone: TimeZone,
                           store: WidgetSnapshotStore = WidgetSnapshotStore()) async {
        if let days = try? await client.listPlanDays(from: day, to: day) {
            let planned = PlannedDay(plan: days.first { $0.date == day }, zone: zone)
            snapshot.plannedEnd = planned.end
            snapshot.plannedSeconds = planned.seconds
        } else if let previous = store.read(), previous.day == snapshot.day {
            snapshot.plannedEnd = previous.plannedEnd
            snapshot.plannedSeconds = previous.plannedSeconds
        }
    }
}

// MARK: - App side

/// What the snapshot depends on; `onChange` publishes when it changes (including every successful reload).
private struct SyncSignature: Equatable {
    let phase: AppModel.Phase
    let loaded: Date?
    let runningID: UUID?
    let segmentCount: Int
    let appearance: LocalAppearance

    @MainActor init(model: AppModel) {
        appearance = model.appearance.local
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
            let appearance = model.appearance.local
            var snapshot = WidgetSnapshot.make(running: today.running, day: today.day, account: today.account, segments: today.segments, zone: zone,
                                               accentHex: AppearanceKeys.effectiveHex(appearance), colorScheme: appearance.scheme,
                                               evaluatedAt: today.lastLoaded)
            if let client = model.apiClient { await WidgetPublisher.attachPlan(to: &snapshot, client: client, day: snapshot.day, zone: zone) }
            await WidgetPublisher.publish(snapshot)
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
