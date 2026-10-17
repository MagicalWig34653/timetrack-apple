import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        switch model.phase {
        case .restoring:
            ZStack {
                TTBackdrop()
                VStack(spacing: TT.Space.l) { BrandMark(size: 72); ProgressView() }
                    .accessibilityElement(children: .ignore).accessibilityLabel(Text("root.loading"))
            }
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
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .top) {
                HStack(spacing: TT.Space.s) {
                    BrandMark(size: 28)
                    Text("signin.brand").font(.system(.headline, design: .rounded, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, TT.Space.l).padding(.top, TT.Space.s)
            }
            .safeAreaInset(edge: .bottom) {
                if let account = model.account {
                    HStack(spacing: TT.Space.s) {
                        Image(systemName: "person.crop.circle.fill").foregroundStyle(TT.textSecondary)
                        Text(verbatim: account.displayName).font(TTFont.meta).foregroundStyle(TT.textSecondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TT.Space.m)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("account.signed_in_as \(account.displayName)"))
                }
            }
        } detail: {
            switch ui.selection {
            case .today: TodayView()
            case .time: TimeView()
            case .calendar: CalendarScreen()
            case .vacation: VacationScreen()
            }
        }
    }
}

struct RecoveryRestrictedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: TT.Space.l) {
            EmptyState(symbol: "key.horizontal.fill", title: "recovery.title", message: "recovery.explanation")
            if let error = model.lastError { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { model.lastError = nil } }
            Button("recovery.add_passkey") { Task { await model.addPasskey(name: Host.current().localizedName) } }
                .buttonStyle(.ttPrimary).controlSize(.large)
                .disabled(model.isBusy)
            Button("account.sign_out") { Task { await model.signOut() } }.buttonStyle(.ttSecondary)
        }
        .padding(TT.Space.xl)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ttScreenBackground()
    }
}
