import CoreLocation
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// M2: Settings > Automatik. Places (CoreLocation), "Beim Verlassen stoppen" (L4) and the Mac's own presence signals.
struct MacAutomationSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var store: AutomationStore?
    @State private var companion = MacCompanion.shared
    @State private var showingNewPlace = false

    var body: some View {
        Form {
            if let store {
                locationSections(store)
            } else {
                Section { Text("Bitte zuerst anmelden.").foregroundStyle(TT.textSecondary) }
            }
            presenceSection
        }
        .formStyle(.grouped)
        .task {
            guard store == nil, let client = model.apiClient else { return }
            let created = MacAutomationRuntime.shared.store(for: client)
            store = created
            created.status = MacAutomationRuntime.shared.service.status
            await created.load()
        }
        .sheet(isPresented: $showingNewPlace) { if let store { MacNewPlaceSheet(store: store) } }
    }

    // MARK: Location

    @ViewBuilder private func locationSections(_ store: AutomationStore) -> some View {
        Section {
            Toggle("Standortautomatik", isOn: Binding(get: { store.config.enabled }, set: { value in Task { await store.setEnabled(value) } }))
                .accessibilityIdentifier("macautomation.master")
            LabeledContent("Standortzugriff") {
                HStack {
                    StatusChip(verbatim: permissionTitle(store.status), tone: store.status.permission == .always ? .success : .warning)
                    if store.status.permission == .notDetermined {
                        Button("Erlauben") { MacAutomationRuntime.shared.service.requestAlways() }
                    } else if store.status.permission != .always {
                        Button("Systemeinstellungen") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                        }
                    }
                }
            }
        } header: { Text("Orte") } footer: {
            Text("Der Mac erkennt, wenn er einen deiner Orte betritt oder verlässt, und meldet das wie die iPhone-App (nur Ort und Uhrzeit, keine Koordinaten). Orts-WLAN (SSID) wird bewusst nicht ausgewertet. Mehr dazu in der Anleitung „Mac-Automatik“.")
        }
        Section("Meine Orte") {
            if store.places.isEmpty { Text("Noch keine Orte.").foregroundStyle(TT.textSecondary) }
            ForEach(store.places.filter { !$0.archived }) { place in
                VStack(alignment: .leading, spacing: TT.Space.xs) {
                    HStack {
                        Text(verbatim: place.name)
                        Spacer()
                        Picker("Automatik", selection: Binding(get: { store.mode(of: place) }, set: { mode in Task { await store.setMode(mode, for: place) } })) {
                            Text("Aus").tag(AutomationMode.off)
                            Text("Vorschlag").tag(AutomationMode.suggest)
                            Text("Direkt").tag(AutomationMode.direct)
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width: 120)
                        .disabled(!store.canAutomate(place))
                    }
                    if store.mode(of: place) != .off {
                        Toggle("Beim Verlassen stoppen", isOn: Binding(get: { store.stopsOnLeave(place) }, set: { value in Task { await store.setStopOnLeave(value, for: place) } }))
                            .font(TTFont.meta)
                    }
                    if !store.canAutomate(place) { Text("Ohne Koordinaten: in der Web-App ergänzen.").font(TTFont.meta).foregroundStyle(TT.textSecondary) }
                }
            }
            Button { showingNewPlace = true } label: { Label("Ort am aktuellen Standort anlegen…", systemImage: "plus.circle") }
        }
        Section {
            Stepper("Wartezeit nach Ankunft: \(store.config.dwellMinutes) Min", value: Binding(get: { store.config.dwellMinutes }, set: { v in Task { await store.setDwellMinutes(v) } }), in: AutomationConfig.dwellRange)
            Stepper("Wartezeit nach Verlassen: \(store.config.leaveWaitMinutes) Min", value: Binding(get: { store.config.leaveWaitMinutes }, set: { v in Task { await store.setLeaveWaitMinutes(v) } }), in: AutomationConfig.leaveWaitRange)
        } header: { Text("Zeiten") } footer: {
            Text("Wie auf dem iPhone: Vorbeifahrt wird nicht gebucht, und beim Verlassen wird erst nach der Wartezeit gestoppt – im Modus „Vorschlag“ fragt eine Mitteilung.")
        }
        if let error = store.error { Text(verbatim: error.germanDescription).foregroundStyle(TT.danger) }
    }

    private func permissionTitle(_ status: LocationStatus) -> String {
        switch status.permission {
        case .notDetermined: "Nicht gefragt"
        case .denied: "Verweigert"
        case .restricted: "Eingeschränkt"
        case .whenInUse: "Nur beim Verwenden"
        case .always: "Erlaubt"
        }
    }

    // MARK: Presence

    private var presenceSection: some View {
        Section {
            Toggle("Vorschläge bei Sperre, Ruhezustand und Inaktivität", isOn: Binding(get: { companion.presence.enabled }, set: { value in companion.updatePresence { $0.enabled = value } }))
                .accessibilityIdentifier("macautomation.presence")
            if companion.presence.enabled {
                Toggle("Nach Abwesenheit fragen, ob der Timer enden soll", isOn: Binding(get: { companion.presence.askAfterAbsence }, set: { v in companion.updatePresence { $0.askAfterAbsence = v } }))
                if companion.presence.askAfterAbsence {
                    Picker("Abwesenheit ab", selection: Binding(get: { companion.presence.minAwayMinutes }, set: { v in companion.updatePresence { $0.minAwayMinutes = v } })) {
                        ForEach(PresenceSettings.awayOptions, id: \.self) { Text("\($0) Minuten").tag($0) }
                    }
                }
                Toggle("Bei langer Inaktivität fragen", isOn: Binding(get: { companion.presence.askWhenIdle }, set: { v in companion.updatePresence { $0.askWhenIdle = v } }))
                if companion.presence.askWhenIdle {
                    Picker("Keine Eingabe seit", selection: Binding(get: { companion.presence.idleMinutes }, set: { v in companion.updatePresence { $0.idleMinutes = v } })) {
                        ForEach(PresenceSettings.idleOptions, id: \.self) { Text("\($0) Minuten").tag($0) }
                    }
                }
                Toggle("Beim Entsperren an einem Arbeitsort Start vorschlagen", isOn: Binding(get: { companion.presence.suggestStartAtUnlock }, set: { v in companion.updatePresence { $0.suggestStartAtUnlock = v } }))
            }
        } header: { Text("Mac-Signale") } footer: {
            Text("Der Mac beendet oder startet nie von selbst: Eine Sperre kann eine Kaffeepause sein. Stattdessen fragt eine Mitteilung „Timer beenden um hh:mm?“ mit dem Zeitpunkt, an dem du gegangen bist. Der Start-Vorschlag braucht eingeschaltete Standortautomatik und erscheint höchstens einmal pro Stunde.")
        }
    }
}

/// New place at the current location (no map on the Mac sheet: the fix is taken once, the radius is chosen by number).
private struct MacNewPlaceSheet: View {
    let store: AutomationStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var fix: LocationFix?
    @State private var radius = 150.0
    @State private var mode = AutomationMode.suggest
    @State private var locating = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name, z. B. Büro", text: $name)
                Section {
                    Button { Task { await locate() } } label: { Label(locating ? "Standort wird ermittelt…" : "Aktuellen Standort verwenden", systemImage: "location.fill") }.disabled(locating)
                    if let fix { Text("Standort gefunden (Genauigkeit etwa \(Int(fix.horizontalAccuracy)) m).").foregroundStyle(TT.textSecondary) }
                    if failed { Text("Der Standort konnte nicht ermittelt werden. Ist der Standortzugriff erlaubt?").foregroundStyle(TT.warning) }
                }
                Slider(value: $radius, in: 100...500, step: 25) { Text("Radius \(Int(radius)) m") }
                Picker("Automatik", selection: $mode) {
                    Text("Aus").tag(AutomationMode.off); Text("Vorschlag").tag(AutomationMode.suggest); Text("Direkt").tag(AutomationMode.direct)
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    guard let fix else { return }
                    Task {
                        await store.createPlace(name: name.trimmingCharacters(in: .whitespaces), coordinate: GeoPoint(latitude: fix.latitude, longitude: fix.longitude), radius: Int(radius), mode: mode)
                        if store.error == nil { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(fix == nil || name.trimmingCharacters(in: .whitespaces).isEmpty || store.isBusy)
            }
            .padding(TT.Space.l).background(.bar)
        }
        .frame(width: 440, height: 400)
    }

    private func locate() async {
        locating = true; failed = false
        defer { locating = false }
        let service = MacAutomationRuntime.shared.service
        if service.status.permission == .notDetermined {
            service.requestAlways()
            for _ in 0..<60 where service.status.permission == .notDetermined { try? await Task.sleep(for: .milliseconds(500)) }
        }
        fix = await service.currentFix()
        failed = fix == nil
    }
}
