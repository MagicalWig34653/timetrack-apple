import AppKit
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// M2: Settings > Aktivität. Opt-in, local-only app tracking with the privacy controls in one place.
struct ActivitySettingsView: View {
    @State private var companion = MacCompanion.shared
    @State private var confirmDelete = false
    @State private var addExcluded: String = ""
    @Environment(\.scenePhase) private var scenePhase

    private var store: ActivityStore { companion.activity }
    private var settings: ActivitySettings { store.settings }

    var body: some View {
        Form {
            Section {
                Toggle("Aktivitätserfassung", isOn: Binding(get: { settings.enabled }, set: { value in store.update { $0.enabled = value } }))
                    .accessibilityIdentifier("activity.enabled")
                Text("Timetrack merkt sich lokal, welche App im Vordergrund ist, solange ein Timer läuft. Daraus entstehen nur Vorschläge für Notizen, die du prüfst. Standardmäßig ist alles aus.")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }

            if settings.enabled {
                Section("Was erfasst wird") {
                    Toggle("Nur erfassen, solange ein Timer läuft", isOn: Binding(get: { settings.onlyWhileTimerRuns }, set: { v in store.update { $0.onlyWhileTimerRuns = v } }))
                    Toggle("Erfassung pausieren", isOn: Binding(get: { settings.paused }, set: { v in store.update { $0.paused = v } }))
                    Toggle("Fenstertitel mit erfassen", isOn: Binding(get: { settings.recordWindowTitles }, set: { v in titles(v) }))
                        .disabled(!companion.accessibilityTrusted && !settings.recordWindowTitles)
                    if !companion.accessibilityTrusted {
                        HStack {
                            Text("Fenstertitel brauchen die Bedienungshilfen-Berechtigung (Datenschutz & Sicherheit). Ohne sie bleibt es bei App-Namen.")
                                .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                            Spacer()
                            Button("Berechtigung anfragen") { companion.requestAccessibility() }
                        }
                    }
                    LabeledContent("Aktuell im Vordergrund") { Text(verbatim: companion.currentApp ?? "–").foregroundStyle(TT.textSecondary) }
                }

                Section {
                    Picker("Daten behalten", selection: Binding(get: { settings.retentionDays }, set: { v in store.update { $0.retentionDays = v } })) {
                        ForEach(ActivitySettings.retentionOptions, id: \.self) { Text($0 == 1 ? "1 Tag" : "\($0) Tage").tag($0) }
                    }
                    LabeledContent("Gespeichert") { Text("\(store.log.intervals.count) Abschnitte").foregroundStyle(TT.textSecondary) }
                    Button("Alle Aktivitätsdaten löschen…", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("activity.deleteAll")
                } header: { Text("Speicherung") } footer: {
                    Text("Ältere Daten werden automatisch gelöscht. Die Daten liegen im Programmordner dieser App auf diesem Mac, sind nicht in iCloud oder im Backup-Konto und werden nie an den Server gesendet. Eine Übernahme als Notiz ist immer deine bewusste Korrektur.")
                }

                Section {
                    ForEach(settings.excludedBundleIDs, id: \.self) { id in
                        HStack {
                            Text(verbatim: name(for: id))
                            Spacer()
                            Button { store.include(bundleID: id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("\(name(for: id)) wieder erfassen")
                        }
                    }
                    Menu("App ausschließen…") {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "?") { if let id = app.bundleIdentifier { store.exclude(bundleID: id) } }
                        }
                    }
                } header: { Text("Ausgeschlossene Apps") } footer: {
                    Text("Diese Apps werden nie erfasst. Beim Ausschließen werden schon gespeicherte Daten der App gelöscht.")
                }
            }

            Section("Datenschutz") {
                Label("Keine Tastatureingaben, keine Bildschirmfotos, keine Inhalte.", systemImage: "hand.raised")
                Label("Nichts verlässt diesen Mac, außer du übernimmst einen Vorschlag.", systemImage: "lock")
                Label("Bei gesperrtem Bildschirm, Ruhezustand und nach 5 Minuten ohne Eingabe wird nicht erfasst.", systemImage: "moon.zzz")
            }
            .font(TTFont.meta).foregroundStyle(TT.textSecondary)
        }
        .formStyle(.grouped)
        .onChange(of: scenePhase) { companion.refreshAccessibility() }
        .onAppear { companion.refreshAccessibility() }
        .confirmationDialog("Alle Aktivitätsdaten löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Alle löschen", role: .destructive) { store.deleteAllData() }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Das Protokoll wird von diesem Mac entfernt. Einstellungen und Regeln bleiben.") }
    }

    private func titles(_ on: Bool) {
        if on && !companion.accessibilityTrusted { companion.requestAccessibility(); return }
        store.update { $0.recordWindowTitles = on }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !settings.isExcluded($0.bundleIdentifier ?? "") }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func name(for bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }
}
