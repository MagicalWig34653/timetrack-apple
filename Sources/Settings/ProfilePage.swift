import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// AUD3-A: "Profil": display name, account name (read only) and the e-mail address with its confirmation code.
/// Mirrors the web app's `/settings/profile`. Time zone and language are not profile fields in the contract: the time zone
/// belongs to the work model ("Server und Module" shows it) and the apps are German only.
struct ProfilePage: View {
    @Environment(AppModel.self) private var model
    @State private var store: ProfileStore?
    @State private var name = ""
    @State private var nameLoaded = false
    @State private var emailInput = ""
    @State private var editingEmail = false
    @State private var code = ""
    @State private var confirmingRemoval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                if let store, store.hasLoaded, let profile = store.profile {
                    nameSection(store, profile)
                    emailSection(store, profile)
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
        .navigationTitle("Profil")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if store == nil, let client = model.apiClient {
                let made = ProfileStore(client: client)
                made.onDisplayNameChanged = { [weak model] in model?.applyDisplayName($0) }
                store = made
            }
            await store?.load()
            if let profile = store?.profile, !nameLoaded { name = profile.displayName; nameLoaded = true }
        }
    }

    // MARK: - Name

    private func nameSection(_ store: ProfileStore, _ profile: Profile) -> some View {
        let dirty = ProfileValidation.displayName(name).map { $0 != profile.displayName } ?? false
        return FormSection("Anzeigename", footer: "So erscheinst du in der App und bei Freigaben. Der Kontoname dient zur Anmeldung und Wiederherstellung und lässt sich nicht ändern.") {
            TextField("Anzeigename", text: $name)
                .textFieldStyle(.plain)
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .onSubmit { Task { await store.saveDisplayName(name) } }
                .accessibilityIdentifier("profile.name")
            HStack {
                Text("Kontoname").font(TTFont.body).foregroundStyle(TT.textPrimary)
                Spacer()
                Text(verbatim: "@\(profile.handle)").font(TTFont.body).foregroundStyle(TT.textSecondary).textSelection(.enabled)
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            .accessibilityElement(children: .combine)
            if name.count > ProfileValidation.displayNameLimit || (nameLoaded && ProfileValidation.displayName(name) == nil) {
                StatusLine(text: "Der Anzeigename muss 1 bis 80 Zeichen lang sein.", tone: .error, id: "profile.name_error")
            }
            if store.notice == .nameSaved { StatusLine(text: "Anzeigename gespeichert.", tone: .success, id: "profile.name_saved") }
            Button("Speichern") { Task { await store.saveDisplayName(name) } }
                .buttonStyle(.ttSecondary)
                .disabled(!dirty || store.isWorking)
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityIdentifier("profile.name_save")
        }
    }

    // MARK: - E-mail

    private func emailSection(_ store: ProfileStore, _ profile: Profile) -> some View {
        FormSection("E-Mail-Adresse", footer: "Diese Kontomail ist auch die Adresse für die Wiederherstellung per E-Mail. Einschalten kannst du sie unter „Wiederherstellung“; ändern oder entfernen wirkt sich dort sofort aus.") {
            if !profile.mailAvailable {
                Label("Dieser Server kann keine E-Mails versenden. Eine Adresse lässt sich deshalb nicht bestätigen; sie bleibt freiwillig und du brauchst sie für nichts in der App.", systemImage: "info.circle")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    .accessibilityIdentifier("profile.no_mail")
            }
            if let email = profile.email {
                HStack(spacing: TT.Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aktuelle Adresse").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        Text(verbatim: email).font(TTFont.body).foregroundStyle(TT.textPrimary).textSelection(.enabled)
                    }
                    Spacer(minLength: TT.Space.s)
                    StatusChip(profile.emailVerified ? "Bestätigt" : "Nicht bestätigt", tone: profile.emailVerified ? .success : .neutral)
                }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("profile.email_current")
            } else {
                Text("Keine E-Mail-Adresse hinterlegt. Das ist in Ordnung, sie ist freiwillig.")
                    .font(TTFont.body).foregroundStyle(TT.textSecondary)
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    .accessibilityIdentifier("profile.email_none")
            }
            if let pending = profile.pendingEmail {
                pendingBlock(store, pending: pending)
            } else if editingEmail {
                editBlock(store)
            }
            if let error = store.error { StatusLine(text: error.germanDescription, tone: .error, id: "profile.email_error") }
            if let notice = Self.emailNotice(store.notice) { StatusLine(text: notice, tone: .success, id: "profile.email_notice") }
            emailActions(store, profile)
        }
    }

    private func pendingBlock(_ store: ProfileStore, pending: String) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.m) {
            Text("Code gesendet an \(pending). Gib ihn hier ein, um die Adresse zu übernehmen.").font(TTFont.body).foregroundStyle(TT.textPrimary)
            TextField("Bestätigungscode", text: $code)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textContentType(.oneTimeCode)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit { confirm(store) }
                .accessibilityIdentifier("profile.code")
            Button("Bestätigen") { confirm(store) }
                .buttonStyle(.ttPrimary)
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || store.isWorking)
                .accessibilityIdentifier("profile.code_confirm")
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
    }

    private func confirm(_ store: ProfileStore) {
        Task { if await store.confirmEmail(code: code) { code = "" } }
    }

    private func editBlock(_ store: ProfileStore) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.m) {
            TextField("Neue E-Mail-Adresse", text: $emailInput)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit { sendCode(store) }
                .accessibilityIdentifier("profile.email_input")
            Text("Wir senden einen Code an diese Adresse. Sie wird erst übernommen, wenn du ihn eingibst.").font(TTFont.meta).foregroundStyle(TT.textSecondary)
            HStack(spacing: TT.Space.m) {
                Button("Code senden") { sendCode(store) }
                    .buttonStyle(.ttPrimary)
                    .disabled(ProfileValidation.email(emailInput) == nil || store.isWorking)
                    .accessibilityIdentifier("profile.email_send")
                Button("Abbrechen") { editingEmail = false }
                    .buttonStyle(.ttSecondary)
            }
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
    }

    private func sendCode(_ store: ProfileStore) {
        Task {
            if await store.requestEmailChange(emailInput) { editingEmail = false; code = "" }
        }
    }

    @ViewBuilder private func emailActions(_ store: ProfileStore, _ profile: Profile) -> some View {
        if profile.mailAvailable, !editingEmail {
            Button(profile.email == nil ? "Adresse hinzufügen" : "Adresse ändern") {
                emailInput = ""
                store.error = nil
                editingEmail = true
            }
            .buttonStyle(.ttSecondary)
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            .accessibilityIdentifier("profile.email_edit")
        }
        if profile.email != nil || profile.pendingEmail != nil {
            Button(role: .destructive) { confirmingRemoval = true } label: { Text("Adresse entfernen") }
                .font(TTFont.label).foregroundStyle(TT.danger)
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .disabled(store.isWorking)
                .accessibilityIdentifier("profile.email_remove")
                .confirmationDialog("E-Mail-Adresse wirklich entfernen?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                    Button("Entfernen", role: .destructive) { Task { await store.removeEmail() } }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Die Wiederherstellung per E-Mail wird dabei abgeschaltet.")
                }
        }
    }

    static func emailNotice(_ notice: ProfileStore.Notice?) -> String? {
        switch notice {
        case .codeSent: "Code gesendet."
        case .emailConfirmed: "E-Mail-Adresse bestätigt und übernommen."
        case .emailRemoved: "E-Mail-Adresse entfernt."
        case .nameSaved, nil: nil
        }
    }
}
