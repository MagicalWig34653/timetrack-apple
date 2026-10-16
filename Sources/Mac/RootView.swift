import SwiftUI
import TimetrackCore
import TimetrackStores

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        switch model.phase {
        case .restoring:
            ProgressView("root.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedOut, .offline:
            SignInView()
        case .recoveryRestricted:
            RecoveryRestrictedView()
        case .signedIn:
            MainView()
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    private var items: [SidebarItem] {
        SidebarItem.allCases.filter { item in item.requiredModule.map(model.isEnabled) ?? true }
    }

    var body: some View {
        @Bindable var ui = ui
        NavigationSplitView {
            List(items, selection: $ui.selection) { item in
                Label(item.titleKey, systemImage: item.symbol)
                    .tag(item)
                    .accessibilityIdentifier("sidebar.\(item.rawValue)")
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                if let account = model.account {
                    Label(account.displayName, systemImage: "person.crop.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .accessibilityLabel(Text("account.signed_in_as \(account.displayName)"))
                }
            }
        } detail: {
            switch ui.selection {
            case .today: TodayView()
            case .time: TimeView()
            }
        }
    }
}

struct RecoveryRestrictedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("recovery.title", systemImage: "key.horizontal")
        } description: {
            VStack(spacing: 8) {
                Text("recovery.explanation")
                if let error = model.lastError { error.messageText.foregroundStyle(.red) }
            }
        } actions: {
            Button("recovery.add_passkey") { Task { await model.addPasskey(name: Host.current().localizedName) } }
                .buttonStyle(.glassProminent)
                .disabled(model.isBusy)
            Button("account.sign_out") { Task { await model.signOut() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
