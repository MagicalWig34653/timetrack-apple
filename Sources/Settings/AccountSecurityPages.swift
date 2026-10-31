import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// AUD3-A: "Konto und Sicherheit". Mirrors the web app's /settings/passkeys, /recovery, /identities and /sessions.

/// Hub page: profile, passkeys, recovery, linked sign-ins and sessions.
struct AccountSecurityPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                FormSection {
                    SettingsLinkRow(title: "Profil", symbol: "person.crop.circle", id: "security.profile") { ProfilePage() }
                }
                FormSection("Anmeldung", footer: "Passkeys sind deine Anmeldung. Die Wiederherstellung ist der Weg zurück ins Konto, wenn alle Passkeys verloren sind.") {
                    SettingsLinkRow(title: "Passkeys", symbol: "person.badge.key", id: "security.passkeys") { PasskeysPage() }
                    SettingsLinkRow(title: "Wiederherstellung", symbol: "lifepreserver", id: "security.recovery") { RecoveryPage() }
                    SettingsLinkRow(title: "Verknüpfte Anmeldungen", symbol: "link", id: "security.identities") { IdentitiesPage() }
                }
                FormSection("Geräte") {
                    SettingsLinkRow(title: "Sitzungen", symbol: "iphone.and.arrow.forward", id: "security.sessions") { SessionsPage() }
                }
            }
            .p14cPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("Konto und Sicherheit")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Passkeys

struct PasskeysPage: View {
    @Environment(AppModel.self) private var model
    @State private var store: PasskeysStore?
    @State private var newName = Self.deviceName
    @State private var renaming: Passkey?
    @State private var renameText = ""
    @State private var revoking: Passkey?

    private static var deviceName: String {
        #if os(iOS)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                if let store, store.hasLoaded {
                    listSection(store)
                    addSection(store)
                    if store.needsFreshLogin { FreshLoginNotice() }
                } else if let error = store?.error {
                    StatusLine(text: error.germanDescription, tone: .error)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, TT.Space.xl)
                }
            }
            .p14cPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("Passkeys")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if store == nil, let client = model.apiClient {
                store = PasskeysStore(client: client) { [weak model] name in await model?.registerAdditionalPasskey(name: name) }
            }
            await store?.load()
        }
        .alert("Passkey umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Speichern") { if let renaming { Task { await store?.rename(renaming, to: renameText) } } }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog(revoking.map { "Passkey „\($0.name)“ widerrufen?" } ?? "", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible, presenting: revoking) { key in
            Button("Endgültig widerrufen", role: .destructive) { Task { await store?.revoke(key) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text((store?.isLast ?? false) ? "Das ist dein letzter Passkey. Danach kommst du nur noch über eine Wiederherstellungsmethode ins Konto. Der Server verweigert den Widerruf, wenn keine Methode aktiv ist." : "Mit diesem Passkey ist danach keine Anmeldung mehr möglich.")
        }
    }

    private func listSection(_ store: PasskeysStore) -> some View {
        FormSection("Deine Passkeys", footer: "Mit diesen Passkeys kannst du dich anmelden. Du kannst mehrere pro Konto haben.") {
            if store.passkeys.isEmpty {
                Text("Keine Passkeys vorhanden.").font(TTFont.body).foregroundStyle(TT.textSecondary)
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    .accessibilityIdentifier("passkeys.empty")
            }
            ForEach(store.passkeys) { key in
                HStack(alignment: .center, spacing: TT.Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: key.name).font(TTFont.body).foregroundStyle(TT.textPrimary)
                        Text(verbatim: Self.usage(key)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    }
                    Spacer(minLength: TT.Space.s)
                    Menu {
                        Button("Umbenennen", systemImage: "pencil") { renameText = key.name; renaming = key }
                        Button("Widerrufen", systemImage: "trash", role: .destructive) { revoking = key }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel(Text("Aktionen für Passkey „\(key.name)“"))
                        .accessibilityIdentifier("passkeys.menu.\(key.name)")
                }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("passkeys.row.\(key.name)")
            }
            if let error = store.error { StatusLine(text: error.germanDescription, tone: .error, id: "passkeys.error") }
            if let notice = Self.noticeText(store.notice) { StatusLine(text: notice, tone: .success, id: "passkeys.notice") }
        }
    }

    private func addSection(_ store: PasskeysStore) -> some View {
        FormSection("Passkey hinzufügen", footer: "Das System fragt danach nach Face ID, Touch ID oder deinem Code. Für das Hinzufügen kann eine frische Anmeldung nötig sein.") {
            TextField("Name des neuen Passkeys (optional)", text: $newName)
                .textFieldStyle(.plain)
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityIdentifier("passkeys.new_name")
            Button { Task { await store.add(name: newName) } } label: { Label("Passkey hinzufügen", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.ttSecondary)
                .disabled(store.isWorking)
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityIdentifier("passkeys.add")
        }
    }

    static func usage(_ key: Passkey) -> String {
        func stamp(_ date: Date) -> String { date.formatted(.dateTime.day().month().year().hour().minute()) }
        return "Erstellt \(stamp(key.createdAt)), " + (key.lastUsedAt.map { "zuletzt genutzt \(stamp($0))" } ?? "noch nicht genutzt")
    }

    static func noticeText(_ notice: PasskeysStore.Notice?) -> String? {
        switch notice {
        case .added: "Passkey hinzugefügt."
        case .renamed: "Passkey umbenannt."
        case .revoked: "Passkey widerrufen."
        case nil: nil
        }
    }
}

// MARK: - Recovery

struct RecoveryPage: View {
    @Environment(AppModel.self) private var model
    @State private var store: RecoveryStore?
    @State private var confirmedSaved = false
    @State private var confirmingRegenerate = false
    @State private var password = ""
    @State private var passwordRepeat = ""
    @State private var emailCode = ""
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                if let store, store.status != nil {
                    codesSection(store)
                    passwordSection(store)
                    emailSection(store)
                    if let error = store.error { StatusLine(text: error.germanDescription, tone: .error, id: "recovery.error") }
                    if let notice = Self.noticeText(store.notice) { StatusLine(text: notice, tone: .success, id: "recovery.notice") }
                    if store.needsFreshLogin { FreshLoginNotice() }
                } else if let error = store?.error {
                    StatusLine(text: error.germanDescription, tone: .error)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, TT.Space.xl)
                }
            }
            .p14cPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("Wiederherstellung")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if store == nil, let client = model.apiClient { store = RecoveryStore(client: client) }
            await store?.load()
        }
    }

    private func chip(_ active: Bool) -> some View { StatusChip(active ? "Aktiv" : "Inaktiv", tone: active ? .success : .neutral) }

    // Codes

    @ViewBuilder private func codesSection(_ store: RecoveryStore) -> some View {
        let active = store.status?.recoveryCodes.active ?? false
        FormSection("Recovery-Codes", footer: "Einmalcodes zum Ausdrucken oder sicheren Speichern. Jeder Code gilt nur einmal.") {
            HStack { Text("Status").font(TTFont.body); Spacer(); chip(active) }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            if let codes = store.freshCodes {
                VStack(alignment: .leading, spacing: TT.Space.m) {
                    Label("Diese Codes werden nur jetzt angezeigt. Speichere sie an einem sicheren Ort.", systemImage: "exclamationmark.triangle")
                        .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(codes, id: \.self) { code in
                            Text(verbatim: code).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                    .accessibilityIdentifier("recovery.codes")
                    HStack(spacing: TT.Space.m) {
                        Button { Clipboard.copy(store.codesText); copied = true } label: { Label(copied ? "Kopiert" : "Alle kopieren", systemImage: copied ? "checkmark" : "doc.on.doc") }
                            .buttonStyle(.ttSecondary)
                            .accessibilityIdentifier("recovery.codes_copy")
                        ShareLink(item: store.codesText) { Label("Teilen", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.ttSecondary)
                    }
                    Toggle("Ich habe die Codes sicher gespeichert.", isOn: $confirmedSaved).accessibilityIdentifier("recovery.codes_saved")
                    Button("Fertig") { store.dismissCodes(); confirmedSaved = false; copied = false }
                        .buttonStyle(.ttPrimary)
                        .disabled(!confirmedSaved)
                        .accessibilityIdentifier("recovery.codes_done")
                }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            } else {
                if active {
                    Text("Übrige Codes: \(store.status?.recoveryCodes.remaining ?? 0)").font(TTFont.body).foregroundStyle(TT.textSecondary)
                        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                }
                VStack(spacing: TT.Space.m) {
                    Button { if active { confirmingRegenerate = true } else { Task { await store.generateCodes() } } } label: {
                        Label(active ? "Neue Codes erzeugen" : "Codes erzeugen", systemImage: "key.viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.ttSecondary).disabled(store.isWorking)
                    .accessibilityIdentifier("recovery.codes_generate")
                    if active {
                        Button("Ausschalten", role: .destructive) { Task { await store.disableCodes() } }
                            .font(TTFont.label).foregroundStyle(TT.danger).disabled(store.isWorking)
                            .accessibilityIdentifier("recovery.codes_disable")
                    }
                }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .confirmationDialog("Neue Codes erzeugen?", isPresented: $confirmingRegenerate, titleVisibility: .visible) {
                    Button("Ja, neue Codes erzeugen", role: .destructive) { Task { await store.generateCodes() } }
                    Button("Abbrechen", role: .cancel) {}
                } message: { Text("Die bisherigen Codes werden dadurch ungültig.") }
            }
        }
    }

    // Fallback password

    @ViewBuilder private func passwordSection(_ store: RecoveryStore) -> some View {
        let active = store.status?.fallbackPassword.active ?? false
        let problem = password.isEmpty ? nil : RecoveryValidation.passwordProblem(password, repeated: passwordRepeat)
        FormSection("Rückfallpasswort", footer: "Ein Passwort ausschließlich für die Wiederherstellung. Es dient nie zur normalen Anmeldung. Mindestens 12 Zeichen.") {
            HStack { Text("Status").font(TTFont.body); Spacer(); chip(active) }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            SecureField(active ? "Neues Rückfallpasswort" : "Rückfallpasswort", text: $password)
                .textFieldStyle(.plain)
                #if os(iOS)
                .textContentType(.newPassword)
                #endif
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityIdentifier("recovery.password")
            SecureField("Passwort wiederholen", text: $passwordRepeat)
                .textFieldStyle(.plain)
                #if os(iOS)
                .textContentType(.newPassword)
                #endif
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityIdentifier("recovery.password_repeat")
            if let problem, problem != .mismatch || !passwordRepeat.isEmpty {
                StatusLine(text: Self.problemText(problem), tone: .error, id: "recovery.password_problem")
            }
            HStack(spacing: TT.Space.m) {
                Button("Speichern") {
                    Task { if await store.setPassword(password, repeated: passwordRepeat) { password = ""; passwordRepeat = "" } }
                }
                .buttonStyle(.ttSecondary)
                .disabled(password.isEmpty || RecoveryValidation.passwordProblem(password, repeated: passwordRepeat) != nil || store.isWorking)
                .accessibilityIdentifier("recovery.password_save")
                if active {
                    Button("Entfernen", role: .destructive) { Task { await store.removePassword() } }
                        .font(TTFont.label).foregroundStyle(TT.danger).disabled(store.isWorking)
                        .accessibilityIdentifier("recovery.password_remove")
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        }
    }

    // E-mail

    @ViewBuilder private func emailSection(_ store: RecoveryStore) -> some View {
        let active = store.status?.email.active ?? false
        FormSection("E-Mail-Code", footer: "Wir senden einen Code an deine Kontomail. Eine eigene Wiederherstellungsadresse gibt es nicht.") {
            HStack { Text("Status").font(TTFont.body); Spacer(); chip(active) }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            switch store.emailState {
            case .unavailable, nil:
                note("Auf diesem Server ist der E-Mail-Versand nicht eingerichtet. Diese Methode ist nicht verfügbar.", id: "recovery.email_unavailable")
            case .noAccountEmail:
                note("Du hast noch keine Kontomail. Hinterlege sie zuerst im Profil, dann kannst du die Wiederherstellung per E-Mail einschalten.", id: "recovery.email_none")
                profileLink("Kontomail im Profil hinterlegen")
            case .active(let email):
                note("Wiederherstellungs-Codes werden an deine Kontomail gesendet (\(email)).", id: "recovery.email_active")
                Button("Ausschalten", role: .destructive) { Task { await store.disableEmail() } }
                    .font(TTFont.label).foregroundStyle(TT.danger).disabled(store.isWorking)
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    .accessibilityIdentifier("recovery.email_disable")
            case .unconfirmed(let email):
                note("Wiederherstellungs-Codes würden an \(email) gehen. Deine Kontomail ist noch nicht bestätigt. Bestätige sie zuerst im Profil.", id: "recovery.email_unconfirmed")
                profileLink("Zum Profil")
            case .canEnable(let email):
                if store.emailCodePending {
                    VStack(alignment: .leading, spacing: TT.Space.m) {
                        Text("Wir haben einen Bestätigungscode an deine Kontomail gesendet.").font(TTFont.body)
                        TextField("Bestätigungscode", text: $emailCode)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("recovery.email_code")
                        HStack(spacing: TT.Space.m) {
                            Button("Bestätigen") { Task { if await store.verifyEmail(code: emailCode) { emailCode = "" } } }
                                .buttonStyle(.ttPrimary)
                                .disabled(emailCode.trimmingCharacters(in: .whitespaces).isEmpty || store.isWorking)
                                .accessibilityIdentifier("recovery.email_verify")
                            Button("Abbrechen") { store.cancelEmailCode() }.buttonStyle(.ttSecondary)
                        }
                    }
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                } else {
                    note("Wiederherstellungs-Codes werden an deine Kontomail gesendet (\(email)).", id: "recovery.email_account")
                    Button("Per E-Mail wiederherstellen") { Task { await store.enableEmail() } }
                        .buttonStyle(.ttSecondary).disabled(store.isWorking)
                        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                        .accessibilityIdentifier("recovery.email_enable")
                }
            }
        }
    }

    private func note(_ text: String, id: String) -> some View {
        Text(verbatim: text).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(id)
    }

    private func profileLink(_ title: String) -> some View {
        NavigationLink { ProfilePage() } label: { Text(verbatim: title).font(TTFont.label) }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            .accessibilityIdentifier("recovery.profile_link")
    }

    static func problemText(_ problem: RecoveryValidation.PasswordProblem) -> String {
        switch problem {
        case .tooShort: "Das Passwort muss mindestens 12 Zeichen lang sein."
        case .tooLong: "Das Passwort darf höchstens 256 Zeichen lang sein."
        case .mismatch: "Die Passwörter stimmen nicht überein."
        }
    }

    static func noticeText(_ notice: RecoveryStore.Notice?) -> String? {
        switch notice {
        case .codesDisabled: "Recovery-Codes deaktiviert."
        case .passwordSaved: "Rückfallpasswort gespeichert."
        case .passwordRemoved: "Rückfallpasswort entfernt."
        case .emailCodeSent: "Wir haben einen Bestätigungscode an deine Kontomail gesendet."
        case .emailActive: "E-Mail-Wiederherstellung ist aktiv."
        case .emailDisabled: "E-Mail-Wiederherstellung deaktiviert."
        case nil: nil
        }
    }
}

// MARK: - Identities

struct IdentitiesPage: View {
    @Environment(AppModel.self) private var model
    @State private var store: IdentitiesStore?
    @State private var unlinking: ExternalIdentity?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                if let store, store.hasLoaded {
                    FormSection("Verknüpfte Anmeldungen", footer: "Externe Konten, mit denen du dich anmelden kannst. Neue Verknüpfungen legst du in der Web-App an (Einstellungen, Verknüpfte Anmeldungen), weil die Anmeldung beim Anbieter im Browser läuft. Entfernen kannst du sie hier.") {
                        if store.identities.isEmpty {
                            Text("Noch kein externes Konto verknüpft.").font(TTFont.body).foregroundStyle(TT.textSecondary)
                                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                                .accessibilityIdentifier("identities.empty")
                        }
                        ForEach(store.identities) { identity in row(identity) }
                        if let error = store.error { StatusLine(text: error.germanDescription, tone: .error, id: "identities.error") }
                        if store.unlinkedNotice { StatusLine(text: "Die Verknüpfung wurde entfernt.", tone: .success, id: "identities.notice") }
                    }
                    if store.needsFreshLogin { FreshLoginNotice() }
                } else if let error = store?.error {
                    StatusLine(text: error.germanDescription, tone: .error)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, TT.Space.xl)
                }
            }
            .p14cPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("Verknüpfte Anmeldungen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if store == nil, let client = model.apiClient { store = IdentitiesStore(client: client) }
            await store?.load()
        }
        .confirmationDialog(unlinking.map { "Verknüpfung mit „\($0.providerName)“ entfernen?" } ?? "", isPresented: Binding(get: { unlinking != nil }, set: { if !$0 { unlinking = nil } }), titleVisibility: .visible, presenting: unlinking) { identity in
            Button("Verknüpfung endgültig entfernen", role: .destructive) { Task { await store?.unlink(identity) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { identity in
            Text("Danach kannst du dich nicht mehr über \(identity.providerName) anmelden.")
        }
    }

    private func row(_ identity: ExternalIdentity) -> some View {
        func stamp(_ date: Date) -> String { date.formatted(.dateTime.day().month().year()) }
        return HStack(alignment: .top, spacing: TT.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: identity.providerName).font(TTFont.body).foregroundStyle(TT.textPrimary)
                if let hint = identity.emailHint {
                    Text("E-Mail laut Anbieter: \(hint) (nur Hinweis, wird nie zum Verknüpfen genutzt)").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
                Text(verbatim: "Verknüpft am \(stamp(identity.linkedAt)), " + (identity.lastUsedAt.map { "zuletzt genutzt am \(stamp($0))" } ?? "noch nicht genutzt"))
                    .font(TTFont.meta).foregroundStyle(TT.textTertiary)
            }
            Spacer(minLength: TT.Space.s)
            Button { unlinking = identity } label: { Image(systemName: "xmark.circle").font(.title3).frame(minWidth: 44, minHeight: 44) }
                .buttonStyle(.plain).foregroundStyle(TT.danger)
                .accessibilityLabel(Text("Verknüpfung mit „\(identity.providerName)“ entfernen"))
                .accessibilityIdentifier("identities.unlink.\(identity.providerName)")
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Sessions

struct SessionsPage: View {
    @Environment(AppModel.self) private var model
    @State private var store: SessionsStore?
    @State private var confirming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                FormSection("Andere Sitzungen beenden", footer: "Meldet alle anderen Geräte ab. Diese Sitzung bleibt bestehen. Eine Liste der Sitzungen gibt es nicht; sie wird vom Server nicht angeboten.") {
                    VStack(alignment: .leading, spacing: TT.Space.m) {
                        Button("Andere Sitzungen abmelden", role: .destructive) { confirming = true }
                            .buttonStyle(.ttSecondary)
                            .disabled(store?.isWorking ?? true)
                            .accessibilityIdentifier("sessions.revoke")
                        if let error = store?.error { StatusLine(text: error.germanDescription, tone: .error, id: "sessions.error") }
                        if store?.revokedNotice == true { StatusLine(text: "Alle anderen Sitzungen wurden beendet.", tone: .success, id: "sessions.notice") }
                    }
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                }
                if store?.needsFreshLogin == true { FreshLoginNotice() }
            }
            .p14cPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("Sitzungen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { if store == nil, let client = model.apiClient { store = SessionsStore(client: client) } }
        .confirmationDialog("Alle anderen Sitzungen abmelden?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await store?.revokeOthers() } }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Andere Geräte müssen sich danach neu anmelden.") }
    }
}
