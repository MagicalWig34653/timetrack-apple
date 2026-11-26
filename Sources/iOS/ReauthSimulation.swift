#if DEBUG
import AuthenticationServices
import Foundation
import TimetrackCore

/// Test hook for `ReauthNoticeTests` (not compiled into release builds). The simulator has no passkey, so
/// `TT_DEV_REAUTH=other,cancel,success` scripts what each system prompt of the fresh sign-in does. Everything else is real:
/// `AuthService.reauthenticate`, the views, and all other requests to the (throwaway) server.
enum ReauthSimulation {
    static func authService(passkeys: PasskeyAuthenticator) -> AuthService {
        guard let value = ProcessInfo.processInfo.environment["TT_DEV_REAUTH"] else {
            return AuthService(secrets: KeychainSecretStore(), transport: URLSessionTransport(), passkeys: passkeys)
        }
        let script = Script(value.split(separator: ",").map(String.init))
        return AuthService(secrets: KeychainSecretStore(), transport: Transport(script: script), passkeys: Passkeys(script: script))
    }

    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var steps: [String]
        private var step = ""
        init(_ steps: [String]) { self.steps = steps }
        func next() -> String { lock.withLock { step = steps.isEmpty ? "cancel" : steps.removeFirst(); return step } }
        var current: String { lock.withLock { step } }
    }

    private struct Passkeys: PasskeyAuthenticator {
        let script: Script
        func register(options: WebAuthnOptions) async throws -> JSONValue { throw TimetrackError.passkey("unavailable") }
        func authenticate(options: WebAuthnOptions) async throws -> JSONValue {
            let step = script.next()
            try await Task.sleep(for: .milliseconds(600)) // the system sheet takes a moment
            // The same mapping the real authenticator applies when the user closes the sheet.
            if step == "cancel" { throw PlatformPasskeyAuthenticator.failure(for: ASAuthorizationError(.canceled)) }
            return .object([:])
        }
    }

    /// Answers only the passkey sign-in itself; "success" returns the real current session, "other" the same under another account id.
    private final class Transport: HTTPTransport, SessionCookieJar, @unchecked Sendable {
        private let inner = URLSessionTransport()
        private let script: Script
        init(script: Script) { self.script = script }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            guard let url = request.url else { return try await inner.send(request) }
            switch (request.httpMethod ?? "GET", url.path) {
            case ("POST", "/api/v1/auth/login/options"):
                return reply(url, 200, Data(#"{"challengeId":"simulated","publicKey":{}}"#.utf8))
            case ("POST", "/api/v1/auth/login/verify"):
                var current = URLRequest(url: url.deletingLastPathComponent().deletingLastPathComponent().appending(path: "session"))
                current.allHTTPHeaderFields = ["Accept": "application/json"]
                let (data, response) = try await inner.send(current)
                guard script.current == "other", response.statusCode == 200,
                      var session = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      var account = session["account"] as? [String: Any] else { return (data, response) }
                account["id"] = UUID().uuidString
                session["account"] = account
                return reply(url, 200, try JSONSerialization.data(withJSONObject: session))
            case ("DELETE", "/api/v1/auth/session") where script.current == "other":
                return reply(url, 204, Data()) // ends the "other" session, which never existed; the real one stays
            default:
                return try await inner.send(request)
            }
        }

        private func reply(_ url: URL, _ status: Int, _ data: Data) -> (Data, HTTPURLResponse) {
            (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }

        func sessionCookieValue(for baseURL: URL) -> String? { inner.sessionCookieValue(for: baseURL) }
        func setSessionCookie(_ value: String, for baseURL: URL) { inner.setSessionCookie(value, for: baseURL) }
        func clearSessionCookie(for baseURL: URL) { inner.clearSessionCookie(for: baseURL) }
    }
}
#endif
