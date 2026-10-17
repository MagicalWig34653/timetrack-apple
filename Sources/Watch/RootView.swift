import SwiftUI
import TimetrackCore
import TimetrackStores

struct RootView: View {
    @Environment(AppModel.self) private var model
    let receiver: WatchHandoffReceiver
    /// Last known state read at launch; drawn in the very first frame while the session is checked.
    let launchDisplay: TodayDisplay

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TT_DEV_GALLERY"] != nil { return AnyView(ComplicationGallery()) }
        #endif
        return AnyView(content)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .restoring:
            // First frame: cached content, no spinner. Read only until the stores exist (a few milliseconds).
            if launchDisplay.source == .cached {
                NavigationStack { TodayContent(display: launchDisplay, status: .refreshing, actions: nil) }
            } else {
                ProgressView()
            }
        case .signedIn:
            MainView(receiver: receiver)
        case .offline:
            NoticeView(symbol: "wifi.slash", title: "watch.offline", detail: "watch.offline.detail") {
                Button("common.retry") { Task { await model.restore() } }
            }
        case .signedOut, .recoveryRestricted:
            SignedOutView(receiver: receiver, reason: model.lifecycle.state)
                .task { WidgetBridge.clear() }
        }
    }
}

/// Shown without a session, and after the server rejected it (expired) or the iPhone signed out.
/// Sign-in on the watch alone is not possible yet: passkey APIs do not exist on watchOS and the backend has no device pairing,
/// so the session comes from the iPhone (WatchConnectivity). The hand-over is delivered by the system even when the watch was
/// away, as soon as both devices can talk again.
struct SignedOutView: View {
    let receiver: WatchHandoffReceiver
    let reason: SessionLifecycle.State

    private var title: LocalizedStringKey {
        switch reason {
        case .signedOut(.expired): "watch.signin.expired"
        case .signedOut(.endedOnPhone): "watch.signin.ended"
        default: "watch.signin_on_iphone"
        }
    }

    var body: some View {
        NoticeView(symbol: "iphone", title: title, detail: "watch.signin_on_iphone.detail") {
            Button("watch.adopt_session") { Task { await receiver.pullNow() } }
                .accessibilityIdentifier("watch.adopt")
        }
        .accessibilityIdentifier("watch.signedout")
    }
}

struct NoticeView<Actions: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(title).font(.headline).multilineTextAlignment(.center)
                Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                actions
            }
        }
    }
}
