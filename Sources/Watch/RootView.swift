import SwiftUI
import TimetrackCore
import TimetrackStores

struct RootView: View {
    @Environment(AppModel.self) private var model
    let receiver: WatchHandoffReceiver

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TT_DEV_GALLERY"] != nil { return AnyView(ComplicationGallery()) }
        #endif
        return AnyView(content)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .restoring:
            ProgressView()
        case .signedIn:
            MainView(receiver: receiver)
        case .offline:
            NoticeView(symbol: "wifi.slash", title: "watch.offline", detail: "watch.offline.detail") {
                Button("common.retry") { Task { await model.restore() } }
            }
        case .signedOut, .recoveryRestricted:
            SignedOutView(receiver: receiver)
                .task { WidgetBridge.clear() }
        }
    }
}

/// Shown without a session, and after the server rejected the handed-over session (expired or ended on the iPhone).
struct SignedOutView: View {
    let receiver: WatchHandoffReceiver

    var body: some View {
        NoticeView(symbol: "iphone", title: "watch.signin_on_iphone", detail: "watch.signin_on_iphone.detail") {
            Button("watch.adopt_session") { Task { await receiver.pullNow() } }
                .accessibilityIdentifier("watch.adopt")
        }
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
