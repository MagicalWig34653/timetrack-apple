import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
import UIKit
import UserNotifications

/// Settings > "Fokus-Filter": explains the feature, shows the live state and the last actions, and lets the user try it.
struct FocusFilterView: View {
    private let store = FocusStateStore()
    private let log = FocusActionLog()
    @State private var state = FocusStateStore().load()
    @State private var entries: [FocusLogEntry] = []
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var testMode: FocusMode = .suggest
    @State private var testKind: SegmentKind = .work
    @State private var executeForReal = false
    @State private var testResult: String?
    @State private var busy = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                introCard
                stepsSection
                statusSection
                modesSection
                rulesSection
                testSection
                logSection
                Text("focus.privacy").font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.s)
            }
            .padding(.horizontal, TT.Space.l)
            .padding(.vertical, TT.Space.s)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("focus.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await reload() } } }
    }

    // MARK: Sections

    private var introCard: some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Label("focus.intro.title", systemImage: "moon.circle").font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                Text("focus.intro.body").font(TTFont.body).foregroundStyle(TT.textSecondary)
            }
        }
    }

    private var stepsSection: some View {
        FormSection("focus.steps.title", footer: "focus.steps.footer") {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                step(1, "focus.step1")
                step(2, "focus.step2")
                step(3, "focus.step3")
                Text("focus.path")
                    .font(.system(.footnote, design: .monospaced, weight: .medium))
                    .foregroundStyle(TT.textPrimary)
                    .padding(TT.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TT.surfaceRaised, in: .rect(cornerRadius: TT.Radius.chip))
                    .accessibilityIdentifier("focus.path")
            }
            .padding(TT.Space.l)
        }
    }

    private func step(_ number: Int, _ key: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TT.Space.m) {
            Text(verbatim: "\(number)").font(TTFont.numeral).foregroundStyle(TT.textPrimary)
                .frame(width: 26, height: 26).background(TT.surfaceRaised, in: .circle)
                .accessibilityHidden(true)
            Text(key).font(TTFont.body).foregroundStyle(TT.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusSection: some View {
        FormSection("focus.status.title", footer: "focus.status.footer") {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                if let active = state.active {
                    StatusChip(verbatim: FocusText.activeSummary(active), tone: active.mode == .off ? .neutral : .success, symbol: "moon.fill")
                        .accessibilityIdentifier("focus.status.active")
                } else {
                    StatusChip("focus.status.none", tone: .neutral, symbol: "moon")
                        .accessibilityIdentifier("focus.status.none")
                }
                HStack {
                    StatusChip(notificationStatus.isAllowed ? "focus.notify.on" : "focus.notify.off",
                               tone: notificationStatus.isAllowed ? .success : .warning, symbol: notificationStatus.isAllowed ? "bell" : "bell.slash")
                    Spacer()
                }
                if notificationStatus == .notDetermined {
                    Button("focus.notify.ask") { Task { _ = await FocusNotifications.requestPermission(); await reload() } }
                        .buttonStyle(.ttSecondary).accessibilityIdentifier("focus.notify.ask")
                } else if !notificationStatus.isAllowed {
                    Button("focus.notify.settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.ttSecondary).accessibilityIdentifier("focus.notify.settings")
                }
            }
            .padding(TT.Space.l)
        }
    }

    private var modesSection: some View {
        FormSection("focus.modes.title", footer: "focus.modes.footer") {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                mode("bell.badge", "focus.mode.suggest.title", "focus.mode.suggest.body")
                Divider()
                mode("bolt.fill", "focus.mode.direct.title", "focus.mode.direct.body")
                Divider()
                mode("circle.slash", "focus.mode.off.title", "focus.mode.off.body")
            }
            .padding(TT.Space.l)
        }
    }

    private func mode(_ symbol: String, _ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: TT.Space.m) {
            Image(systemName: symbol).font(.body).foregroundStyle(TT.textSecondary).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                Text(body).font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var rulesSection: some View {
        FormSection("focus.rules.title", footer: "focus.rules.footer") {
            Toggle("focus.rules.manual", isOn: Binding(
                get: { state.settings.stopManuallyStarted },
                set: { value in
                    store.update { $0.settings.stopManuallyStarted = value }
                    state = store.load()
                }))
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityIdentifier("focus.rules.manual")
        }
    }

    private var testSection: some View {
        FormSection("focus.test.title", footer: executeForReal ? "focus.test.footer.real" : "focus.test.footer.dry") {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                Picker("focus.test.mode", selection: $testMode) {
                    Text("focus.mode.suggest.short").tag(FocusMode.suggest)
                    Text("focus.mode.direct.short").tag(FocusMode.direct)
                    Text("focus.mode.off.short").tag(FocusMode.off)
                }
                .pickerStyle(.segmented).accessibilityIdentifier("focus.test.mode")
                Picker("focus.test.kind", selection: $testKind) {
                    Text("kind.work").tag(SegmentKind.work)
                    Text("kind.travel").tag(SegmentKind.travel)
                    Text("kind.school").tag(SegmentKind.school)
                }
                .pickerStyle(.segmented).accessibilityIdentifier("focus.test.kind")
                Toggle("focus.test.real", isOn: $executeForReal).accessibilityIdentifier("focus.test.real")
                HStack(spacing: TT.Space.m) {
                    Button { Task { await runTest(activate: true) } } label: { Label("focus.test.on", systemImage: "moon.fill") }
                        .buttonStyle(.ttSecondary).accessibilityIdentifier("focus.test.on")
                    Button { Task { await runTest(activate: false) } } label: { Label("focus.test.off", systemImage: "moon") }
                        .buttonStyle(.ttSecondary).accessibilityIdentifier("focus.test.off")
                }
                .disabled(busy)
                if let testResult {
                    Text(verbatim: testResult).font(TTFont.body).foregroundStyle(TT.textPrimary)
                        .padding(TT.Space.m).frame(maxWidth: .infinity, alignment: .leading)
                        .background(TT.surfaceRaised, in: .rect(cornerRadius: TT.Radius.chip))
                        .accessibilityIdentifier("focus.test.result")
                }
            }
            .padding(TT.Space.l)
        }
    }

    private var logSection: some View {
        FormSection("focus.log.title", footer: "focus.log.footer") {
            if entries.isEmpty {
                Text("focus.log.empty").font(TTFont.body).foregroundStyle(TT.textSecondary).padding(TT.Space.l)
                    .accessibilityIdentifier("focus.log.empty")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider() }
                        logRow(entry)
                    }
                }
                .accessibilityIdentifier("focus.log.list")
            }
        }
    }

    private func logRow(_ entry: FocusLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(Self.triggerTitle(entry.trigger)).font(TTFont.eyebrow).foregroundStyle(TT.textSecondary)
                Spacer()
                Text(entry.date, format: .dateTime.hour().minute().second()).font(TTFont.numeralSmall).foregroundStyle(TT.textTertiary)
            }
            Text(verbatim: entry.summary).font(TTFont.body).foregroundStyle(entry.isFailure ? TT.danger : TT.textPrimary)
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        .accessibilityElement(children: .combine)
    }

    private static func triggerTitle(_ trigger: FocusTrigger) -> LocalizedStringKey {
        switch trigger {
        case .focusOn: "focus.trigger.on"
        case .focusOff: "focus.trigger.off"
        case .test: "focus.trigger.test"
        case .notificationAction: "focus.trigger.notification"
        }
    }

    // MARK: Actions

    private func reload() async {
        state = store.load()
        entries = log.entries()
        notificationStatus = await FocusNotifications.authorizationStatus()
    }

    private func runTest(activate: Bool) async {
        busy = true
        defer { busy = false }
        let configuration = FocusConfiguration(mode: testMode, kind: testKind, focusName: String(localized: "focus.test.name"))
        let runner = FocusEnvironment.makeRunner()
        let reports: [FocusRunReport]
        if activate {
            reports = await runner.handle(incoming: configuration, trigger: .test, dryRun: !executeForReal)
        } else {
            reports = await runner.handle(incoming: nil, trigger: .test, dryRun: !executeForReal, assumingActive: executeForReal ? nil : configuration)
        }
        if executeForReal { await FocusEnvironment.publishIfChanged(reports) }
        let prefix = executeForReal ? "" : String(localized: "focus.test.prefix.dry")
        testResult = prefix + (reports.first?.entry.summary ?? String(localized: "focus.test.nothing"))
        await reload()
    }
}

private extension UNAuthorizationStatus {
    var isAllowed: Bool { self == .authorized || self == .provisional || self == .ephemeral }
}

private extension FocusLogEntry {
    var isFailure: Bool {
        if case .failed = result { return true }
        return false
    }
}

/// Keeps the Focus filter's copy of "is the automation module on" current (the filter runs without the app's stores).
struct FocusSyncModifier: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        content.onChange(of: model.modules, initial: true) {
            guard !model.modules.isEmpty else { return }
            let enabled = model.isEnabled(.automation)
            FocusStateStore().update { $0.automationEnabled = enabled }
        }
    }
}

extension View {
    func focusSync(_ model: AppModel) -> some View { modifier(FocusSyncModifier(model: model)) }
}
