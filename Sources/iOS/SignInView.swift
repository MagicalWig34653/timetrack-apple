import SwiftUI
import TimetrackCore
import TimetrackStores

struct SignInView: View {
    @Environment(AppModel.self) private var model

    enum Mode: String, CaseIterable, Identifiable {
        case passkey, recovery
        #if DEBUG
        case developer
        #endif
        var id: String { rawValue }
        var titleKey: LocalizedStringKey {
            switch self {
            case .passkey: "signin.mode.passkey"
            case .recovery: "signin.mode.recovery"
            #if DEBUG
            case .developer: "signin.mode.developer"
            #endif
            }
        }
    }

    @State private var server = ""
    @State private var mode: Mode = .passkey
    @State private var handle = ""
    @State private var method: RecoveryMethod = .recoveryCode
    @State private var proof = ""
    @State private var cookie = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("signin.title").font(.largeTitle.bold()).multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    TextField("signin.server", text: $server, prompt: Text("signin.server.prompt"))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Text("signin.server"))
                        .accessibilityIdentifier("signin.server")

                    Picker("signin.mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.titleKey).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(Text("signin.mode"))

                    switch mode {
                    case .passkey:
                        Text("signin.passkey.hint").font(.callout).foregroundStyle(.secondary)
                        Button("signin.passkey.button") { Task { await model.signInWithPasskey(serverInput: server) } }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .disabled(server.isEmpty)
                            .accessibilityIdentifier("signin.passkey")
                    case .recovery:
                        TextField("signin.handle", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("signin.handle")
                        Picker("signin.method", selection: $method) {
                            Text("signin.method.code").tag(RecoveryMethod.recoveryCode)
                            Text("signin.method.password").tag(RecoveryMethod.fallbackPassword)
                        }
                        SecureField(method == .recoveryCode ? "signin.proof.code" : "signin.proof.password", text: $proof)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("signin.proof")
                        Text("signin.recovery.hint").font(.callout).foregroundStyle(.secondary)
                        Button("signin.recovery.button") {
                            Task { await model.signInWithRecovery(serverInput: server, method: method, handle: handle, proof: proof) }
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(handle.isEmpty || proof.isEmpty || server.isEmpty)
                    #if DEBUG
                    case .developer:
                        SecureField("signin.cookie", text: $cookie)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("signin.cookie")
                        Text("signin.developer.hint").font(.callout).foregroundStyle(.secondary)
                        Button("signin.developer.button") { Task { await model.signInWithSessionCookie(serverInput: server, cookie: cookie) } }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .disabled(cookie.isEmpty || server.isEmpty)
                            .accessibilityIdentifier("signin.developer")
                    #endif
                    }

                    if model.phase == .offline {
                        Label("signin.offline", systemImage: "wifi.slash").foregroundStyle(.orange)
                        Button("signin.retry") { Task { await model.restore() } }
                    }
                    if let error = model.lastError {
                        error.messageText.foregroundStyle(.red).accessibilityIdentifier("signin.error")
                    }
                }
                .disabled(model.isBusy)
                .padding(20)
                .glassEffect(in: .rect(cornerRadius: 24))
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if server.isEmpty { server = model.serverURL?.absoluteString ?? "" } }
    }
}
