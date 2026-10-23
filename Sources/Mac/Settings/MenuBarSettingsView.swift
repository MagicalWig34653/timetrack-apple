import SwiftUI
import TimetrackCore
import TimetrackDesign

/// M2: Settings > Menüleiste. Menu bar item, Dock mode, login item, global hotkey and running-timer reminders.
struct MenuBarSettingsView: View {
    @AppStorage(MacPrefs.menuBarInserted) private var inserted = true
    @AppStorage(MacPrefs.menuBarShowsTimer) private var showsTimer = true
    @AppStorage(MacPrefs.menuBarOnly) private var menuBarOnly = false
    @AppStorage(MacPrefs.hotkeyEnabled) private var hotkeyOn = false
    @AppStorage(MacPrefs.hotkeyPreset) private var presetRaw = HotkeyPreset.controlOptionT.rawValue
    @State private var companion = MacCompanion.shared
    @State private var overwork = OverworkSettingsStore().read()
    @State private var notificationsAllowed = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                Toggle("Symbol in der Menüleiste anzeigen", isOn: $inserted).disabled(menuBarOnly)
                Toggle("Laufende Zeit in der Menüleiste anzeigen", isOn: $showsTimer)
                    .disabled(!inserted && !menuBarOnly)
            } header: { Text("Menüleiste") } footer: {
                Text("Das Menü zeigt Timer, Tagesstand (Soll, Ist, Feierabend), Schnellstart mit den zuletzt genutzten Arten und „Fortführen“.")
            }

            Section {
                Toggle("Nur Menüleiste (kein Dock-Symbol)", isOn: $menuBarOnly)
                    .onChange(of: menuBarOnly) {
                        if menuBarOnly { inserted = true }
                        companion.applyActivationPolicy()
                    }
                    .accessibilityIdentifier("settings.menubarOnly")
                Toggle("Beim Anmelden starten", isOn: Binding(get: { companion.loginItem.isOn || companion.loginItem.needsApproval },
                                                              set: { companion.loginItem.set($0) }))
                    .accessibilityIdentifier("settings.loginItem")
                if companion.loginItem.needsApproval {
                    HStack {
                        Label("Bitte in den Systemeinstellungen bestätigen.", systemImage: "exclamationmark.triangle").foregroundStyle(TT.warning)
                        Spacer()
                        Button("Öffnen") { companion.loginItem.openSystemSettings() }
                    }
                }
                if let error = companion.loginItem.lastError { Text(verbatim: error).font(TTFont.meta).foregroundStyle(TT.danger) }
            } header: { Text("App") } footer: {
                Text("Im Modus „Nur Menüleiste“ öffnet das Menüleisten-Symbol das Fenster bei Bedarf; das Dock-Symbol erscheint, solange ein Fenster offen ist.")
            }

            Section {
                Toggle("Tastenkürzel für Start/Stopp", isOn: $hotkeyOn)
                    .onChange(of: hotkeyOn) { companion.applyHotkey() }
                if hotkeyOn {
                    Picker("Kürzel", selection: $presetRaw) {
                        ForEach(HotkeyPreset.allCases) { Text(verbatim: $0.title).tag($0.rawValue) }
                    }
                    .onChange(of: presetRaw) { companion.applyHotkey() }
                    if companion.hotkeyFailed {
                        Label("Dieses Kürzel ist bereits belegt. Bitte ein anderes wählen.", systemImage: "exclamationmark.triangle").foregroundStyle(TT.warning)
                    }
                }
            } header: { Text("Globales Tastenkürzel") } footer: {
                Text("Funktioniert in jeder App und braucht keine Berechtigung. Es schaltet den Timer um (mit der zuletzt gewählten Art).")
            }

            Section {
                Toggle("Geplantes Ende erreicht", isOn: binding(\.plannedEnd))
                Toggle("Vor und bei 8 und 10 Stunden", isOn: binding(\.dailyLimits))
                Toggle("Pause fehlt nach 6 und 9 Stunden", isOn: binding(\.missingBreak))
                if overwork.isAnyEnabled && !notificationsAllowed {
                    Label("Mitteilungen sind für Timetrack ausgeschaltet.", systemImage: "bell.slash").foregroundStyle(TT.warning)
                }
            } header: { Text("Hinweise bei laufendem Timer") } footer: {
                Text("Dieselben Hinweise wie auf dem iPhone, nur für diesen Mac. Sie werden im Voraus geplant, solange ein Arbeits-Timer läuft. Pausen werden nach tatsächlichen Zeiten beurteilt, nichts wird erfunden.")
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
        .onChange(of: scenePhase) { Task { await refresh() } }
    }

    private func binding(_ key: WritableKeyPath<OverworkSettings, Bool>) -> Binding<Bool> {
        Binding(get: { overwork[keyPath: key] }, set: { value in
            overwork[keyPath: key] = value
            OverworkSettingsStore().write(overwork)
            Task {
                if value { notificationsAllowed = await MacNotifications.requestIfNeeded() }
                await OverworkScheduler.syncFromStoredSnapshot()
            }
        })
    }

    private func refresh() async {
        companion.loginItem.refresh()
        notificationsAllowed = await MacNotifications.isAllowed()
    }
}
