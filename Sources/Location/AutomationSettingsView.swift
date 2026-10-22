import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
import UIKit

/// Settings → "Standortautomatik". Everything on this page works on the device; places and their mode live on the server.
struct AutomationSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: AutomationStore?
    @State private var showingNewPlace = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                if let store {
                    content(store)
                } else {
                    SkeletonList(rows: 4)
                }
            }
            .padding(.horizontal, TT.Space.l)
            .padding(.vertical, TT.Space.s)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("Standortautomatik")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard store == nil, let client = model.apiClient else { return }
            let created = AutomationRuntime.shared.store(for: client)
            store = created
            await created.load()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active, let store {
                store.status = AutomationRuntime.shared.service.status
                Task { await store.refreshFromEngine() }
            }
        }
        .sheet(isPresented: $showingNewPlace) {
            if let store { NewPlaceSheet(store: store) }
        }
    }

    @ViewBuilder
    private func content(_ store: AutomationStore) -> some View {
        masterCard(store)
        if let error = store.error {
            ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await store.load() } }
        }
        permissionSection(store)
        placesSection(store)
        timingSection(store)
        shortcutsSection(store)
        tokenSection(store)
        energySection
        FormSection("Protokoll") {
            NavigationLink {
                AutomationLogView(store: store)
            } label: {
                navRow("Letzte Ereignisse", symbol: "list.bullet.rectangle", detail: store.log.isEmpty ? nil : "\(store.log.count)")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("automation.log.link")
        }
    }

    // MARK: Sections

    private func masterCard(_ store: AutomationStore) -> some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Toggle(isOn: Binding(get: { store.config.enabled }, set: { value in Task { await store.setEnabled(value) } })) {
                    Label("Standortautomatik", systemImage: "location.circle.fill").font(TTFont.cardTitle)
                }
                .accessibilityIdentifier("automation.master")
                Text(store.config.enabled
                     ? "Die App erkennt, wenn du einen Ort mit eingeschalteter Automatik betrittst oder verlässt, und meldet das als Ereignis. Gebucht wird erst nach einer Wartezeit."
                     : "Aus: Es wird nichts überwacht und kein Ereignis gesendet, auch nicht über Kurzbefehle.")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
        }
    }

    private func permissionSection(_ store: AutomationStore) -> some View {
        let status = store.status
        let (title, tone, symbol) = permissionPresentation(status)
        return FormSection("Standortzugriff", footer: "Für die Automatik im Hintergrund braucht Timetrack „Immer“ und den genauen Standort. Der Standort verlässt dein Gerät nicht; gemeldet werden nur Ort-ID und Uhrzeit.") {
            HStack {
                Text("Status").font(TTFont.body)
                Spacer()
                StatusChip(verbatim: title, tone: tone, symbol: symbol)
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("automation.permission.status")
            if let action = permissionAction(status) {
                Button { runPermissionAction(action) } label: {
                    HStack {
                        Label(action.title, systemImage: action.symbol)
                        Spacer()
                    }
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("automation.permission.fix")
            }
        }
    }

    private func placesSection(_ store: AutomationStore) -> some View {
        FormSection("Orte", footer: placesFooter(store)) {
            if store.places.isEmpty {
                Text("Noch keine Orte. Lege einen Ort am aktuellen Standort an oder erstelle ihn in der Web-App.")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(TT.Space.l)
            }
            ForEach(store.places) { place in
                PlaceAutomationRow(store: store, place: place)
            }
            Button { showingNewPlace = true } label: {
                HStack {
                    Label("Ort am aktuellen Standort anlegen", systemImage: "plus.circle")
                    Spacer()
                }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("automation.place.new")
        }
    }

    private func placesFooter(_ store: AutomationStore) -> LocalizedStringKey {
        var text = "Aus: nichts. Vorschlag: du entscheidest unter „Vorschläge“. Direkt: wird nach der Wartezeit gebucht."
        let omitted = store.plan.omitted.count
        if omitted > 0 {
            text += " iOS erlaubt höchstens 20 überwachte Orte: Es werden die \(store.plan.monitored.count) nächstgelegenen überwacht, \(omitted) weitere folgen, wenn du dich bewegst."
        }
        return LocalizedStringKey(text)
    }

    private func timingSection(_ store: AutomationStore) -> some View {
        FormSection("Wartezeit und Abkühlzeit", footer: "Wartezeit: So lange musst du bleiben, bevor ein Aufenthalt gemeldet wird (schützt vor Vorbeifahrten). Abkühlzeit: Eine erneute Ankunft kurz nach einer Abfahrt wird ignoriert.") {
            Stepper(value: Binding(get: { store.config.dwellMinutes }, set: { value in Task { await store.setDwellMinutes(value) } }), in: AutomationConfig.dwellRange) {
                HStack { Text("Wartezeit"); Spacer(); Text("\(store.config.dwellMinutes) min").foregroundStyle(TT.textSecondary).monospacedDigit() }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .accessibilityIdentifier("automation.dwell")
            Stepper(value: Binding(get: { store.config.cooldownMinutes }, set: { value in Task { await store.setCooldownMinutes(value) } }), in: AutomationConfig.cooldownRange, step: 5) {
                HStack { Text("Abkühlzeit"); Spacer(); Text("\(store.config.cooldownMinutes) min").foregroundStyle(TT.textSecondary).monospacedDigit() }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .accessibilityIdentifier("automation.cooldown")
            Stepper(value: Binding(get: { store.config.leaveWaitMinutes }, set: { value in Task { await store.setLeaveWaitMinutes(value) } }), in: AutomationConfig.leaveWaitRange) {
                HStack { Text("Wartezeit beim Verlassen"); Spacer(); Text("\(store.config.leaveWaitMinutes) min").foregroundStyle(TT.textSecondary).monospacedDigit() }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .accessibilityIdentifier("automation.leaveWait")
        }
    }

    private func shortcutsSection(_ store: AutomationStore) -> some View {
        FormSection("Kurzbefehle", footer: "Alternativ zur App-Überwachung kann die Kurzbefehle-App „Wenn ich ankomme“ auslösen. Beide Wege nutzen dieselben Regeln.") {
            NavigationLink {
                ShortcutGuideView(places: store.places)
            } label: {
                navRow("Kurzbefehl erstellen", symbol: "square.stack.3d.up", detail: nil)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("automation.shortcuts.link")
        }
    }

    private func tokenSection(_ store: AutomationStore) -> some View {
        FormSection("Gerätetoken", footer: "Das Token erlaubt dieser App nur, Ankunfts- und Abfahrtsereignisse zu melden. Es liegt im Schlüsselbund und wird nie angezeigt.") {
            HStack {
                Text("Status")
                Spacer()
                if store.hasLocalToken {
                    StatusChip("Aktiv", tone: .success, symbol: "checkmark.circle")
                } else {
                    StatusChip("Fehlt", tone: .warning, symbol: "exclamationmark.triangle")
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("automation.token.status")
            if let last = store.tokenInfo?.lastUsedAt {
                FormRow("Zuletzt benutzt") { Text(last.formatted(date: .abbreviated, time: .shortened)) }
            }
            if store.queuedCount > 0 {
                FormRow("Wartende Ereignisse") { Text("\(store.queuedCount)").monospacedDigit() }
            }
            HStack(spacing: TT.Space.m) {
                Button(store.hasLocalToken ? "Neu erzeugen" : "Erzeugen") { Task { await store.recreateDeviceToken() } }
                    .buttonStyle(.ttSecondary).accessibilityIdentifier("automation.token.create")
                if store.hasLocalToken {
                    Button("Widerrufen", role: .destructive) { Task { await store.revokeDeviceToken() } }
                        .buttonStyle(.ttSecondary).accessibilityIdentifier("automation.token.revoke")
                }
            }
            .padding(TT.Space.m)
            .disabled(store.isBusy)
        }
    }

    private var energySection: some View {
        FormSection("Energieverbrauch") {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Label("Die App fragt den Standort nicht laufend ab; iOS weckt sie nur beim Betreten oder Verlassen eines Ortes.", systemImage: "battery.100percent.bolt")
                    .font(TTFont.body).foregroundStyle(TT.textPrimary)
                Text("Dazu kommen gelegentliche Hinweise des Systems bei größeren Ortswechseln und Aufenthalten. Eine genaue Ortung läuft nur einmalig, wenn eine Ankunft nach der Wartezeit geprüft wird.")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
            .padding(TT.Space.l)
            .accessibilityIdentifier("automation.energy")
        }
    }

    // MARK: Helpers

    private func navRow(_ title: String, symbol: String, detail: String?) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(TT.textPrimary)
            Spacer()
            if let detail { Text(detail).foregroundStyle(TT.textSecondary).monospacedDigit() }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary)
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
    }

    private func permissionPresentation(_ status: LocationStatus) -> (String, TTTone, String) {
        switch status.permission {
        case .always where status.reducedAccuracy: ("Ungenau", .warning, "location.slash")
        case .always: ("Immer erlaubt", .success, "checkmark.circle")
        case .whenInUse: ("Nur beim Benutzen", .warning, "exclamationmark.triangle")
        case .notDetermined: ("Nicht gefragt", .neutral, "questionmark.circle")
        case .denied: ("Verweigert", .danger, "xmark.circle")
        case .restricted: ("Eingeschränkt", .danger, "lock")
        }
    }

    private struct PermissionAction { let title: String; let symbol: String; let kind: Kind; enum Kind { case ask, upgrade, settings, precise } }

    private func permissionAction(_ status: LocationStatus) -> PermissionAction? {
        switch status.permission {
        case .notDetermined: PermissionAction(title: "Standortzugriff erlauben", symbol: "location", kind: .ask)
        case .whenInUse: PermissionAction(title: "Auf „Immer“ erweitern", symbol: "location.fill", kind: .upgrade)
        case .denied, .restricted: PermissionAction(title: "Einstellungen öffnen", symbol: "gearshape", kind: .settings)
        case .always: status.reducedAccuracy ? PermissionAction(title: "Genauen Standort erlauben", symbol: "scope", kind: .precise) : nil
        }
    }

    private func runPermissionAction(_ action: PermissionAction) {
        let service = AutomationRuntime.shared.service
        switch action.kind {
        case .ask: service.requestWhenInUse()
        case .upgrade: service.requestAlways()
        case .settings: if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        case .precise: Task { await service.requestPreciseOnce(); store?.status = service.status }
        }
    }
}

/// One place: name, state hints and the Aus/Vorschlag/Direkt picker.
struct PlaceAutomationRow: View {
    let store: AutomationStore
    let place: Place

    private var mode: AutomationMode { store.mode(of: place) }
    private var automationAvailable: Bool { store.canAutomate(place) }

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            HStack(spacing: TT.Space.s) {
                Text(verbatim: place.name).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                Spacer()
                if let radius = place.radiusMeters, automationAvailable {
                    Text(verbatim: "\(radius) m").font(TTFont.numeralSmall).foregroundStyle(TT.textSecondary)
                }
            }
            Picker("Automatik für \(place.name)", selection: Binding(get: { mode }, set: { value in Task { await store.setMode(value, for: place) } })) {
                Text("Aus").tag(AutomationMode.off)
                Text("Vorschlag").tag(AutomationMode.suggest)
                Text("Direkt").tag(AutomationMode.direct)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(store.isBusy)
            .accessibilityIdentifier("automation.mode.\(place.name)")
            if mode != .off, automationAvailable {
                Toggle("Beim Verlassen stoppen", isOn: Binding(get: { store.stopsOnLeave(place) }, set: { value in Task { await store.setStopOnLeave(value, for: place) } }))
                    .font(TTFont.label)
                    .accessibilityIdentifier("automation.stopOnLeave.\(place.name)")
                hint(mode == .direct ? "Läuft beim Verlassen ein Timer (auch von Hand gestartet), wird er nach der Wartezeit zum Zeitpunkt des Verlassens gestoppt."
                                     : "Läuft beim Verlassen ein Timer, fragt eine Mitteilung, ob er gestoppt werden soll.", symbol: "stop.circle", tone: TT.textSecondary)
            }
            if !automationAvailable {
                hint("Ohne Koordinaten kann die App diesen Ort nicht überwachen. Kurzbefehle funktionieren trotzdem.", symbol: "mappin.slash", tone: TT.textSecondary)
            } else if let radius = place.radiusMeters, radius < PlaceMonitorPlanner.minimumRadius {
                hint("Der gespeicherte Radius (\(radius) m) ist zu klein für eine zuverlässige Erkennung. Überwacht wird mit \(PlaceMonitorPlanner.minimumRadius) m.", symbol: "exclamationmark.triangle", tone: TT.warning)
            }
            if mode != .off, automationAvailable, store.plan.omitted.contains(where: { $0.id == place.id }) {
                hint("Wird gerade nicht überwacht (Systemgrenze von 20 Orten); folgt, wenn du näher kommst.", symbol: "clock", tone: TT.textSecondary)
            }
            NavigationLink {
                ShortcutGuideView(places: [place])
            } label: {
                Label("Kurzbefehl erstellen", systemImage: "square.stack.3d.up").font(TTFont.label)
            }
            .accessibilityIdentifier("automation.place.shortcut.\(place.name)")
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
    }

    private func hint(_ text: String, symbol: String, tone: Color) -> some View {
        Label { Text(text) } icon: { Image(systemName: symbol) }
            .font(TTFont.meta).foregroundStyle(tone)
    }
}

/// The last 20 events with decision and result, for transparency and the manual test on the device.
struct AutomationLogView: View {
    let store: AutomationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                if store.log.isEmpty {
                    EmptyState(symbol: "list.bullet.rectangle", title: "Noch keine Ereignisse", message: "Sobald die App einen Ort betritt oder verlässt oder ein Kurzbefehl meldet, erscheint es hier.")
                } else {
                    ListCard {
                        ForEach(store.log) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(verbatim: AutomationLogText.trigger(entry.trigger)).font(TTFont.label).foregroundStyle(TT.textPrimary)
                                    if !entry.placeName.isEmpty { Text(verbatim: "· \(entry.placeName)").font(TTFont.label).foregroundStyle(TT.textSecondary) }
                                    Spacer()
                                    Text(entry.date.formatted(date: .omitted, time: .shortened)).font(TTFont.numeralSmall).foregroundStyle(TT.textSecondary)
                                }
                                Text(verbatim: AutomationLogText.decision(entry)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                            }
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .accessibilityIdentifier("automation.log.list")
                }
                if store.queuedCount > 0 {
                    HintBanner("Noch nicht gesendet: \(store.queuedCount) Ereignisse. Sie werden gesendet, sobald der Server erreichbar ist.")
                    Button("Jetzt senden") { Task { await store.syncNow() } }.buttonStyle(.ttSecondary)
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("Protokoll")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refreshFromEngine() }
    }
}

enum AutomationLogText {
    static func trigger(_ trigger: LogTrigger) -> String {
        switch trigger {
        case .regionEnter: "Ort betreten"
        case .regionExit: "Ort verlassen"
        case .check: "Prüfung"
        case .reconcile: "Abgleich"
        case .shortcutArrive: "Kurzbefehl: Ankunft"
        case .shortcutLeave: "Kurzbefehl: Abfahrt"
        case .sync: "Senden"
        case .leaveCheck: "Verlassen"
        }
    }

    static func decision(_ entry: AutomationLogEntry) -> String {
        var text: String
        switch entry.decision {
        case .pendingStarted: text = "Ankunft vorgemerkt, Aufenthalt wird nach der Wartezeit geprüft"
        case .alreadyInside: text = "Ignoriert: Ankunft war schon vorgemerkt"
        case .cooldown: text = "Ignoriert: zu kurz nach der letzten Abfahrt"
        case .modeOff: text = "Ignoriert: Automatik für diesen Ort ist aus"
        case .globalOff: text = "Ignoriert: Standortautomatik ist aus"
        case .unknownPlace: text = "Ignoriert: Ort unbekannt"
        case .stillWaiting: text = "Wartezeit läuft noch"
        case .speedTooHigh: text = "Zu schnell unterwegs (Vorbeifahrt?), nichts gebucht"
        case .passBy: text = "Vorbeifahrt: vor Ablauf der Wartezeit verlassen, nichts gebucht"
        case .outsideAtCheck: text = "Nach der Wartezeit nicht mehr am Ort, nichts gebucht"
        case .expired: text = "Verworfen: nicht bestätigt"
        case .confirmed: text = "Aufenthalt bestätigt (\(confidence(entry.confidence)))"
        case .confirmedOnExit: text = "Aufenthalt beim Verlassen bestätigt (\(confidence(entry.confidence)))"
        case .departureQueued: text = "Abfahrt vorgemerkt"
        case .noArrival: text = "Kein Besuch vorgemerkt, nichts an den Server gemeldet (ein laufender Timer wird trotzdem geprüft)"
        case .sent: text = "Gesendet: \(result(entry.detail))"
        case .sendFailed: text = "Server nicht erreichbar, wird später gesendet"
        case .dropped: text = "Vom Server abgelehnt: \(entry.detail ?? "")"
        case .unauthorized: text = "Gerätetoken ungültig: bitte unter „Gerätetoken“ neu erzeugen"
        case .leaveScheduled: text = "Verlassen vorgemerkt: \(entry.detail ?? "Timer wird nach der Wartezeit geprüft")"
        case .leaveStayTooShort: text = "Verlassen ignoriert: Aufenthalt zu kurz (Vorbeifahrt), Timer läuft weiter"
        case .leaveStopped: text = "Verlassen: \(entry.detail ?? "Timer gestoppt")"
        case .leaveStopQueued: text = "Verlassen: \(entry.detail ?? "Stopp wartet auf Verbindung")"
        case .leaveOffered: text = "Verlassen: \(entry.detail ?? "Nachfrage gesendet")"
        case .leaveReturned: text = "Verlassen abgebrochen: \(entry.detail ?? "wieder am Ort, Timer läuft weiter")"
        case .leaveNoTimer: text = "Verlassen: \(entry.detail ?? "kein Timer läuft"), nichts zu stoppen"
        case .leaveTimerRestarted: text = "Verlassen: \(entry.detail ?? "Timer wurde neu gestartet"), nicht gestoppt"
        case .leaveHandledByServer: text = "Verlassen: \(entry.detail ?? "Das Ende schlägt der Server vor")"
        case .leaveExpired: text = "Verlassen verworfen: zu lange nicht geprüft werden können, Timer läuft weiter"
        }
        return text
    }

    private static func confidence(_ value: PresenceConfidence?) -> String {
        switch value {
        case .verified: "Standort geprüft"
        case .regionOnly: "ohne Standortprüfung, Ort durchgehend belegt"
        case .trigger: "durch Kurzbefehl-Auslöser"
        case nil: "–"
        }
    }

    private static func result(_ detail: String?) -> String {
        guard let detail else { return "–" }
        let parts = detail.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return detail }
        let type = ["arrival": "Ankunft", "presence_confirmed": "Aufenthalt", "departure": "Abfahrt", "cancel": "Abbruch"][parts[0]] ?? parts[0]
        let outcome = ["booked": "gebucht", "suggested": "Vorschlag erstellt", "recorded": "festgehalten", "ignored": "ignoriert", "duplicate": "schon bekannt", "needs_review": "bitte prüfen"][parts[1]] ?? parts[1]
        return "\(type) – \(outcome)"
    }
}
