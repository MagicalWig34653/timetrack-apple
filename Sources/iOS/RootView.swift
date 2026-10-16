import SwiftUI
import TimetrackCore
import TimetrackStores

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        Group {
            switch model.phase {
            case .restoring:
                ProgressView("root.loading").frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .navigationTitle("Timetrack")
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
        case .vacation: VacationView()
        case .settings: SettingsView()
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
            Button("recovery.add_passkey") { Task { await model.addPasskey(name: UIDevice.current.name) } }
                .buttonStyle(.glassProminent)
                .disabled(model.isBusy)
            Button("account.sign_out") { Task { await model.signOut() } }
        }
    }
}
