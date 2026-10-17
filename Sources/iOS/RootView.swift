import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        Group {
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
        .onChange(of: model.phase, initial: true) { runPendingQuickAction() }
        .onChange(of: ui.pendingQuickAction) { runPendingQuickAction() }
    }

    private func runPendingQuickAction() {
        guard model.phase == .signedIn, let action = ui.pendingQuickAction, let today = model.today else { return }
        ui.pendingQuickAction = nil
        ui.selection = .today
        Task {
            switch action {
            case .start: if today.running == nil { await today.start() }
            case .stop: if today.running != nil { await today.stop() }
            }
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var sections: [AppSection] {
        AppSection.allCases.filter { section in section.requiredModule.map(model.isEnabled) ?? true }
    }

    var body: some View {
        @Bindable var ui = ui
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List(selection: Binding<AppSection?>(get: { ui.selection }, set: { if let value = $0 { ui.selection = value } })) {
                        ForEach(sections) { section in
                            Label(section.titleKey, systemImage: section.symbol)
                                .tag(section)
                                .accessibilityIdentifier("sidebar.\(section.rawValue)")
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background { TTBackdrop() }
                    .navigationTitle("Timetrack")
                    .safeAreaInset(edge: .bottom) {
                        if let account = model.account {
                            HStack(spacing: TT.Space.s) {
                                Image(systemName: "person.crop.circle.fill").foregroundStyle(TT.textSecondary)
                                Text(verbatim: account.displayName).font(TTFont.meta).foregroundStyle(TT.textSecondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(TT.Space.l)
                        }
                    }
                } detail: {
                    NavigationStack { SectionView(section: ui.selection) }
                }
            } else {
                TabView(selection: $ui.selection) {
                    ForEach(sections) { section in
                        Tab(section.titleKey, systemImage: section.symbol, value: section) {
                            NavigationStack { SectionView(section: section) }
                        }
                    }
                }
            }
        }
        // A module switched off while its screen is open falls back to "Heute".
        .onChange(of: sections) { if !sections.contains(ui.selection) { ui.selection = .today } }
    }
}

struct SectionView: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .today: TodayView()
        case .time: TimeView()
        case .calendar: CalendarScreen()
        case .vacation: VacationView()
        case .settings: SettingsView()
        }
    }
}

struct RecoveryRestrictedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: TT.Space.l) {
            EmptyState(symbol: "key.horizontal.fill", title: "recovery.title", message: "recovery.explanation")
            if let error = model.lastError { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { model.lastError = nil } }
            Button("recovery.add_passkey") { Task { await model.addPasskey(name: UIDevice.current.name) } }
                .buttonStyle(.ttPrimary).controlSize(.large)
                .disabled(model.isBusy)
            Button("account.sign_out") { Task { await model.signOut() } }.buttonStyle(.ttSecondary)
        }
        .padding(TT.Space.xl)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ttScreenBackground()
    }
}
