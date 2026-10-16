import SwiftUI
import TimetrackCore
import TimetrackDesign
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
            VStack(spacing: TT.Space.xl) {
                VStack(spacing: TT.Space.m) {
                    BrandMark(size: 84)
                    Text("signin.brand").font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(TT.textPrimary)
                    Text("signin.tagline").font(TTFont.body).foregroundStyle(TT.textSecondary).multilineTextAlignment(.center)
                }
                .padding(.top, TT.Space.xxl)
                .accessibilityElement(children: .combine)

                Card(padding: TT.Space.xl) {
                    VStack(alignment: .leading, spacing: TT.Space.l) {
                        VStack(alignment: .leading, spacing: TT.Space.s) {
                            Text("signin.server").font(TTFont.label).foregroundStyle(TT.textSecondary)
                            TextField("signin.server", text: $server, prompt: Text("signin.server.prompt"))
                                .textContentType(.URL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .ttField()
                                .accessibilityLabel(Text("signin.server"))
                                .accessibilityIdentifier("signin.server")
                        }

                        switch mode {
                        case .passkey:
                            Button { Task { await model.signInWithPasskey(serverInput: server) } } label: {
                                Label("signin.passkey.button", systemImage: "person.badge.key.fill")
                            }
                            .buttonStyle(.ttPrimary)
                            .controlSize(.large)
                            .disabled(server.isEmpty)
                            .accessibilityIdentifier("signin.passkey")
                            Text("signin.passkey.hint").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        case .recovery:
                            VStack(alignment: .leading, spacing: TT.Space.s) {
                                Text("signin.handle").font(TTFont.label).foregroundStyle(TT.textSecondary)
                                TextField("signin.handle", text: $handle)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .ttField()
                                    .accessibilityIdentifier("signin.handle")
                            }
                            Picker("signin.method", selection: $method) {
                                Text("signin.method.code").tag(RecoveryMethod.recoveryCode)
                                Text("signin.method.password").tag(RecoveryMethod.fallbackPassword)
                            }
                            .pickerStyle(.segmented)
                            SecureField(method == .recoveryCode ? "signin.proof.code" : "signin.proof.password", text: $proof)
                                .ttField()
                                .accessibilityIdentifier("signin.proof")
                            Button("signin.recovery.button") {
                                Task { await model.signInWithRecovery(serverInput: server, method: method, handle: handle, proof: proof) }
                            }
                            .buttonStyle(.ttPrimary)
                            .controlSize(.large)
                            .disabled(handle.isEmpty || proof.isEmpty || server.isEmpty)
                            Text("signin.recovery.hint").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        #if DEBUG
                        case .developer:
                            SecureField("signin.cookie", text: $cookie)
                                .ttField()
                                .accessibilityIdentifier("signin.cookie")
                            Button("signin.developer.button") { Task { await model.signInWithSessionCookie(serverInput: server, cookie: cookie) } }
                                .buttonStyle(.ttPrimary)
                                .controlSize(.large)
                                .disabled(cookie.isEmpty || server.isEmpty)
                                .accessibilityIdentifier("signin.developer")
                            Text("signin.developer.hint").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        #endif
                        }

                        if model.phase == .offline {
                            HintBanner("signin.offline", symbol: "wifi.slash")
                            Button("signin.retry") { Task { await model.restore() } }.buttonStyle(.ttSecondary)
                        }
                        if let error = model.lastError {
                            ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { model.lastError = nil }
                                .accessibilityIdentifier("signin.error")
                        }
                    }
                    .disabled(model.isBusy)
                }

                // Secondary ways to sign in stay quiet below the main action.
                HStack(spacing: TT.Space.l) {
                    ForEach(Mode.allCases.filter { $0 != mode }) { other in
                        Button(other.titleKey) { withAnimation(.smooth) { mode = other } }
                            .font(TTFont.label)
                            .accessibilityIdentifier("signin.mode.\(other.rawValue)")
                    }
                }
                .padding(.bottom, TT.Space.xl)
            }
            .padding(.horizontal, TT.Space.xl)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .ttScreenBackground()
        .onAppear { if server.isEmpty { server = model.serverURL?.absoluteString ?? "" } }
    }
}
