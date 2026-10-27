import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
import UserNotifications

/// P14c: "Push-Benachrichtigungen": state of this device (system permission, server registration), enabling, and a test notification.
/// Shared by the iOS "Mehr" page and the Mac settings tab.
struct PushSettingsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization: UNAuthorizationStatus?
    @State private var asking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                if let push = model.push {
                    statusSection(push)
                    if push.isRegistered { deviceSection(push) }
                } else {
                    FormSection("Dieses Gerät") {
                        FormRow("Status") { StatusChip("Nicht angemeldet", tone: .neutral, symbol: "person.crop.circle.badge.questionmark") }
                    }
                }
                Text("Mitteilungen zu laufendem Timer, offenen Vorschlägen, Lücken im Berichtsheft und Hinweisen des Servers. Sie enthalten keine Zeiten, Orte oder Notizen; die Details lädt die App. Welche Arten und Ruhezeiten gelten, stellst du in der Web-App ein. Ein stiller Hinweis kann die App im Hintergrund aktualisieren.")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.s)
            }
            .p14cPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("Push-Benachrichtigungen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await refreshAuthorization() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await refreshAuthorization() } } }
    }

    private func refreshAuthorization() async {
        authorization = await PushSupport.authorization()
        if let authorization, PushSupport.isAllowed(authorization) { await PushSupport.registerIfAuthorized() }
    }

    // MARK: - Sections

    @ViewBuilder private func statusSection(_ push: PushRegistrationStore) -> some View {
        FormSection("Dieses Gerät") {
            FormRow("Status") { statusChip(push) }
                .accessibilityIdentifier("push.status")
            if let detail = detailText(push) {
                Text(verbatim: detail).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("push.detail")
            }
            if let action = action(push) {
                Button { Task { await run(action, push) } } label: {
                    Text(verbatim: action.title).frame(maxWidth: .infinity)
                }
                .buttonStyle(.ttSecondary)
                .disabled(asking)
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityIdentifier(action.id)
            }
        }
    }

    @ViewBuilder private func deviceSection(_ push: PushRegistrationStore) -> some View {
        if let device = push.device {
            FormSection("Angemeldetes Gerät", footer: "Mit „Test senden“ schickt der Server eine allgemeine Mitteilung an dieses Gerät (höchstens fünf pro Stunde).") {
                FormRow("Name") { Text(verbatim: device.label ?? "–") }
                FormRow("Umgebung") { Text(verbatim: device.environment == "sandbox" ? "Entwicklung (Sandbox)" : "Produktiv") }
                FormRow("Letzte Zustellung") {
                    if let date = device.lastSuccessAt { Text(date, format: .dateTime.day().month().hour().minute()) } else { Text(verbatim: "noch keine") }
                }
                Button { Task { await push.sendTest() } } label: {
                    HStack {
                        Label("Test senden", systemImage: "paperplane")
                        if push.testState == .sending { ProgressView().controlSize(.small) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.ttSecondary)
                .disabled(push.testState == .sending)
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityIdentifier("push.test")
                if let text = testText(push.testState) {
                    Text(verbatim: text.message).font(TTFont.meta).foregroundStyle(text.isError ? TT.danger : TT.textSecondary)
                        .padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("push.test.result")
                }
            }
        }
    }

    // MARK: - Texts and actions (pure, tested through `PushSettingsText`)

    private func statusChip(_ push: PushRegistrationStore) -> some View {
        let status = PushSettingsText.status(authorization: authorization, state: push.state)
        return StatusChip(verbatim: status.title, tone: status.tone, symbol: status.symbol)
    }

    private func detailText(_ push: PushRegistrationStore) -> String? {
        PushSettingsText.detail(authorization: authorization, state: push.state)
    }

    private func action(_ push: PushRegistrationStore) -> PushSettingsText.Action? {
        PushSettingsText.action(authorization: authorization, state: push.state)
    }

    private func testText(_ state: PushTestState) -> (message: String, isError: Bool)? {
        switch state {
        case .idle, .sending: nil
        case .sent: ("Test gesendet. Die Mitteilung sollte gleich erscheinen.", false)
        case .failed(let error): (error.germanDescription, true)
        }
    }

    private func run(_ action: PushSettingsText.Action, _ push: PushRegistrationStore) async {
        switch action.kind {
        case .enable:
            asking = true
            authorization = await PushSupport.enable()
            asking = false
        case .openSystemSettings:
            PushSupport.openSystemSettings()
        case .retry:
            PushSupport.registerWithSystem()
            await push.register(force: true)
        }
    }
}

/// The wording of the push row for every combination of system permission and server state.
enum PushSettingsText {
    struct Status { let title: String; let tone: TTTone; let symbol: String }
    struct Action: Equatable {
        enum Kind { case enable, openSystemSettings, retry }
        let kind: Kind
        let title: String
        var id: String {
            switch kind {
            case .enable: "push.enable"
            case .openSystemSettings: "push.system_settings"
            case .retry: "push.retry"
            }
        }
    }

    static func status(authorization: UNAuthorizationStatus?, state: PushRegistrationState) -> Status {
        guard let authorization else { return Status(title: "Wird geprüft …", tone: .neutral, symbol: "ellipsis.circle") }
        if authorization == .notDetermined { return Status(title: "Aus", tone: .neutral, symbol: "bell.slash") }
        if !PushSupport.isAllowed(authorization) { return Status(title: "In den Systemeinstellungen aus", tone: .warning, symbol: "bell.slash") }
        switch state {
        case .idle: return Status(title: "Wartet auf Gerätekennung", tone: .neutral, symbol: "ellipsis.circle")
        case .registering: return Status(title: "Wird angemeldet …", tone: .neutral, symbol: "ellipsis.circle")
        case .registered: return Status(title: "Aktiv", tone: .success, symbol: "checkmark.circle")
        case .unavailable: return Status(title: "Vom Server nicht angeboten", tone: .neutral, symbol: "minus.circle")
        case .limitReached: return Status(title: "Zu viele Geräte", tone: .warning, symbol: "exclamationmark.triangle")
        case .systemFailure: return Status(title: "Nicht möglich", tone: .danger, symbol: "exclamationmark.circle")
        case .failed: return Status(title: "Anmeldung fehlgeschlagen", tone: .danger, symbol: "exclamationmark.circle")
        }
    }

    static func detail(authorization: UNAuthorizationStatus?, state: PushRegistrationState) -> String? {
        guard let authorization else { return nil }
        if authorization == .notDetermined { return "Timetrack fragt erst, wenn du es hier einschaltest." }
        if !PushSupport.isAllowed(authorization) { return "Erlaube Mitteilungen für Timetrack in den Systemeinstellungen, damit dieses Gerät Push erhält." }
        switch state {
        case .unavailable: return "Dein Server ist nicht für Apple-Push eingerichtet. Lokale Erinnerungen der App funktionieren trotzdem."
        case .limitReached: return TimetrackError.api(status: 409, code: APIErrorCode.tooManyPushDevices.rawValue, message: "").germanDescription
        case .systemFailure(let message):
            return "Das System hat keine Gerätekennung geliefert (\(message)). Bei Entwicklungs-Builds mit persönlichem Team ist Push nicht verfügbar."
        case .failed(let error): return error.germanDescription
        case .idle, .registering, .registered: return nil
        }
    }

    static func action(authorization: UNAuthorizationStatus?, state: PushRegistrationState) -> Action? {
        guard let authorization else { return nil }
        if authorization == .notDetermined { return Action(kind: .enable, title: "Push einschalten") }
        if !PushSupport.isAllowed(authorization) { return Action(kind: .openSystemSettings, title: "Systemeinstellungen öffnen") }
        switch state {
        case .failed, .systemFailure, .limitReached: return Action(kind: .retry, title: "Erneut versuchen")
        case .idle, .registering, .registered, .unavailable: return nil
        }
    }
}
