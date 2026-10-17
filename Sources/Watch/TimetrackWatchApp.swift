import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

@main
struct TimetrackWatchApp: App {
    @State private var model: AppModel
    private let receiver: WatchHandoffReceiver

    init() {
        let secrets = KeychainSecretStore()
        let model = AppModel(auth: AuthService(secrets: secrets, transport: URLSessionTransport()))
        model.onOutcome = { TTHaptics.handle($0) }
        _model = State(initialValue: model)
        // The session arrives from the iPhone over WatchConnectivity and is stored in this watch's own Keychain.
        receiver = WatchHandoffReceiver(
            channel: WCSessionChannel(),
            secrets: secrets,
            onSession: { server, cookie in await model.adoptHandedOverSession(server: server, cookie: cookie) },
            onSignedOut: { await model.discardSessionLocally() }
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(receiver: receiver)
                .environment(model)
                .ttTheme()
                .task {
                    await model.restore()
                    await receiver.start()
                    #if DEBUG
                    // Simulator convenience: TT_DEV_SERVER + TT_DEV_COOKIE (a throwaway server's tt_session) sign in without an iPhone.
                    let env = ProcessInfo.processInfo.environment
                    if model.phase != .signedIn, let server = env["TT_DEV_SERVER"], let cookie = env["TT_DEV_COOKIE"],
                       let url = try? AuthService.normalizeServerURL(server) {
                        await model.adoptHandedOverSession(server: url, cookie: cookie)
                    }
                    #endif
                }
        }
    }
}
