import Network
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
import WatchKit

@main
struct TimetrackWatchApp: App {
    @State private var model: AppModel
    private let receiver: WatchHandoffReceiver
    /// Read synchronously (one small UserDefaults value) so the very first frame already shows the last known state.
    private let launchDisplay: TodayDisplay
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LaunchTrace.mark("app.init")
        let secrets = KeychainSecretStore()
        let queue = TimerActionQueue(fileURL: Self.queueURL)
        let model = AppModel(auth: AuthService(secrets: secrets, transport: TracingTransport(base: URLSessionTransport(timeout: 15))))
        model.onOutcome = { TTHaptics.handle($0) }
        model.fastLaunch = .init(snapshot: { WidgetSnapshotStore().read() }, queue: queue)
        launchDisplay = .cached(WidgetSnapshotStore().read())
        model.onTodayChanged = { [weak model] in if let model { Self.publish(model) } }
        _model = State(initialValue: model)
        // The session arrives from the iPhone over WatchConnectivity and is stored in this watch's own Keychain.
        receiver = WatchHandoffReceiver(
            channel: WCSessionChannel(),
            secrets: secrets,
            onSession: { server, cookie in await model.adoptHandedOverSession(server: server, cookie: cookie) },
            onSignedOut: { await model.discardSessionLocally() }
        )
    }

    private static var queueURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("timer-queue.json")
    }

    @MainActor static func publish(_ model: AppModel) {
        guard let store = model.today else { return }
        WidgetBridge.publish(display: store.display, zone: model.dayCalendar.timeZone,
                             accentHex: AppearanceKeys.effectiveHex(model.appearance.local), colorScheme: model.appearance.local.scheme)
    }

    var body: some Scene {
        WindowGroup {
            RootView(receiver: receiver, launchDisplay: launchDisplay)
                .environment(model)
                .ttTheme()
                .onAppear { LaunchTrace.mark("rootview.appear") }
                .task {
                    LaunchTrace.mark("task.start")
                    // Session check and first load run in parallel inside; the screen is already showing cached content.
                    await model.restore()
                    LaunchTrace.mark("restore.done")
                    // Not needed for the first frame: WatchConnectivity and the refresh schedule.
                    await receiver.start()
                    BackgroundRefresh.schedule()
                    #if DEBUG
                    // Simulator convenience: TT_DEV_SERVER + TT_DEV_COOKIE (a throwaway server's tt_session) sign in without an iPhone.
                    let env = ProcessInfo.processInfo.environment
                    if model.phase != .signedIn, let server = env["TT_DEV_SERVER"], let cookie = env["TT_DEV_COOKIE"],
                       let url = try? AuthService.normalizeServerURL(server) {
                        await model.adoptHandedOverSession(server: url, cookie: cookie)
                    }
                    // Simulator convenience: TT_DEV_ACTION=start|stop presses the button once (no touch input via simctl).
                    if let action = env["TT_DEV_ACTION"] {
                        try? await Task.sleep(for: .seconds(2.5))
                        if action == "start" { await model.today?.start(kind: .travel) } else if action == "stop" { await model.today?.stop() }
                    }
                    #endif
                }
                .task { await watchConnectivityBack() }
                .task { await retryWhileWaiting() }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await model.revalidate() } }
        }
        // Runs even when the app is not in the foreground; refreshes the snapshot (complication, Smart Stack) and sends queued actions.
        .backgroundTask(.appRefresh("refresh")) {
            LaunchTrace.event("refresh.begin")
            await model.restore()
            await MainActor.run { Self.publish(model); BackgroundRefresh.schedule() }
            LaunchTrace.event("refresh.end")
        }
    }

    /// While actions wait or the server was unreachable, try again every 30 seconds in the foreground (the connection monitor
    /// only reports changes; a server that was down while the radio was up produces none).
    private func retryWhileWaiting() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            let offline = model.lifecycle.state == .active(.offline)
            if offline || !(model.today?.pending.isEmpty ?? true) { await model.revalidate() }
        }
    }

    /// When the connection returns while queued actions or an offline state wait, retry at once instead of waiting for the next launch.
    private func watchConnectivityBack() async {
        var wasSatisfied: Bool?
        for await path in NWPathMonitor() {
            let satisfied = path.status == .satisfied
            defer { wasSatisfied = satisfied }
            guard satisfied, wasSatisfied == false else { continue }
            await model.revalidate()
        }
    }
}
