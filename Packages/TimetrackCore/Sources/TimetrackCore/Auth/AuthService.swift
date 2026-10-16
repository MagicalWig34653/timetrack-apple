import Foundation

/// A signed-in (or recovery-restricted) connection to one server.
public struct AuthContext: Sendable {
    public let client: APIClient
    public let session: Session
}

public enum RestoreResult: Sendable {
    case signedIn(AuthContext)
    /// No stored server or cookie, or the server rejected the stored session.
    case signedOut
    /// Credentials are kept but the server could not be reached.
    case offline(serverURL: URL)
}

/// Sign-in flows. REST accepts only the cookie session, so every flow ends with a `tt_session` cookie (kept in the
/// Keychain-backed secret store) and a CSRF token held by the `APIClient`.
public actor AuthService {
    private let secrets: SecretStore
    private let transport: HTTPTransport
    private let cookieJar: SessionCookieJar
    private let passkeys: PasskeyAuthenticator
    private var client: APIClient?
    private(set) public var serverURL: URL?

    public init(secrets: SecretStore, transport: some HTTPTransport & SessionCookieJar, passkeys: PasskeyAuthenticator = UnavailablePasskeyAuthenticator()) {
        self.secrets = secrets
        self.transport = transport
        self.cookieJar = transport
        self.passkeys = passkeys
        self.serverURL = secrets.read(SecretKey.serverURL).flatMap { URL(string: $0) }
    }

    /// Accepts "example.org", "https://example.org/" or "http://localhost:18090". Plain http is allowed for local development;
    /// the macOS/iOS targets only permit it for local networking (ATS).
    public static func normalizeServerURL(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TimetrackError.invalidServerURL }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text), let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil else { throw TimetrackError.invalidServerURL }
        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        if components.path == "/" { components.path = "" }
        guard let url = components.url else { throw TimetrackError.invalidServerURL }
        return url
    }

    private func useServer(_ url: URL) -> APIClient {
        if let client, client.baseURL == url { return client }
        let made = APIClient(baseURL: url, transport: transport)
        client = made
        serverURL = url
        secrets.write(url.absoluteString, for: SecretKey.serverURL)
        return made
    }

    private func persistCookie(for url: URL) {
        if let value = cookieJar.sessionCookieValue(for: url) { secrets.write(value, for: SecretKey.sessionCookie) }
    }

    // MARK: - Restore and sign out

    public func restore() async -> RestoreResult {
        guard let url = serverURL else { return .signedOut }
        guard let cookie = secrets.read(SecretKey.sessionCookie) else { return .signedOut }
        let client = useServer(url)
        cookieJar.setSessionCookie(cookie, for: url)
        do {
            let session = try await client.refreshSession()
            persistCookie(for: url)
            return .signedIn(AuthContext(client: client, session: session))
        } catch let error as TimetrackError where error.isNetworkError {
            return .offline(serverURL: url)
        } catch let error as TimetrackError where error.isUnauthorized {
            await clearSession(for: url)
            return .signedOut
        } catch {
            return .offline(serverURL: url)
        }
    }

    public func signOut() async {
        guard let url = serverURL else { return }
        if let client { try? await client.logout() }
        await clearSession(for: url)
    }

    /// Forgets the session but keeps the server URL for the next sign-in.
    public func clearSession(for url: URL) async {
        cookieJar.clearSessionCookie(for: url)
        secrets.delete(SecretKey.sessionCookie)
        await client?.setCSRFToken(nil)
    }

    /// Also forgets the server (settings: "Server wechseln").
    public func forgetServer() async {
        await signOut()
        secrets.delete(SecretKey.serverURL)
        serverURL = nil
        client = nil
    }

    // MARK: - Sign-in flows

    /// Passkey sign-in (primary path). Needs a real authenticator plus Associated Domains; see PasskeyAuthenticator.
    public func signInWithPasskey(server: URL) async throws -> AuthContext {
        let client = useServer(server)
        let options = try await client.loginOptions()
        let credential = try await passkeys.authenticate(options: options)
        let session = try await client.loginVerify(challengeId: options.challengeId, credential: credential)
        persistCookie(for: server)
        return AuthContext(client: client, session: session)
    }

    /// Recovery path (recovery code or fallback password). The result is a restricted session (`recovery == true`):
    /// the backend allows only passkey setup and session revocation until a passkey is added (ADR-0003).
    public func signInWithRecovery(server: URL, method: RecoveryMethod, handle: String, proof: String) async throws -> AuthContext {
        let client = useServer(server)
        let start = try await client.recoveryStart(method: method, identifier: handle.trimmingCharacters(in: .whitespaces).lowercased())
        let session = try await client.recoveryComplete(recoveryId: start.recoveryId, proof: proof.trimmingCharacters(in: .whitespacesAndNewlines))
        persistCookie(for: server)
        return AuthContext(client: client, session: session)
    }

    /// Adds a passkey to the current session; inside a recovery session this upgrades it to a normal one.
    public func addPasskey(context: AuthContext, name: String?) async throws -> AuthContext {
        let options = try await context.client.addPasskeyOptions()
        let credential = try await passkeys.register(options: options)
        try await context.client.addPasskeyVerify(challengeId: options.challengeId, credential: credential, name: name)
        let session = try await context.client.refreshSession()
        if let url = serverURL { persistCookie(for: url) }
        return AuthContext(client: context.client, session: session)
    }

    /// Development only: adopt a `tt_session` cookie value copied from a browser session on the same server.
    /// Recovery sessions cannot use time tracking, and registration/login need a passkey, so this is the only way to
    /// exercise the app against a test server before Associated Domains exist. Never offered in release UI.
    public func signInWithSessionCookie(server: URL, cookieValue: String) async throws -> AuthContext {
        let client = useServer(server)
        let value = cookieValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cookieJar.setSessionCookie(value, for: server)
        do {
            let session = try await client.refreshSession()
            persistCookie(for: server)
            return AuthContext(client: client, session: session)
        } catch {
            cookieJar.clearSessionCookie(for: server)
            throw error
        }
    }
}
