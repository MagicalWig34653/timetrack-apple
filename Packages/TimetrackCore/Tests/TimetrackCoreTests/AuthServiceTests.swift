#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
import Foundation
import Testing
@testable import TimetrackCore

struct FakePasskeys: PasskeyAuthenticator {
    func register(options: WebAuthnOptions) async throws -> JSONValue { .object(["id": .string("new"), "challenge": options.publicKey["challenge"] ?? .null]) }
    func authenticate(options: WebAuthnOptions) async throws -> JSONValue { .object(["id": .string("cred"), "challenge": options.publicKey["challenge"] ?? .null]) }
}

@Suite struct AuthServiceTests {
    func makeService(_ transport: MockTransport, secrets: SecretStore = InMemorySecretStore()) -> AuthService {
        AuthService(secrets: secrets, transport: transport, passkeys: FakePasskeys())
    }

    @Test func normalizesServerURLs() throws {
        #expect(try AuthService.normalizeServerURL("zeit.example.org").absoluteString == "https://zeit.example.org")
        #expect(try AuthService.normalizeServerURL(" http://localhost:18090/ ").absoluteString == "http://localhost:18090")
        #expect(try AuthService.normalizeServerURL("https://x.org/base/?q=1#f").absoluteString == "https://x.org/base/")
        #expect(throws: TimetrackError.invalidServerURL) { try AuthService.normalizeServerURL("") }
        #expect(throws: TimetrackError.invalidServerURL) { try AuthService.normalizeServerURL("ftp://x.org") }
        #expect(throws: TimetrackError.invalidServerURL) { try AuthService.normalizeServerURL("https://user:pw@x.org") }
    }

    @Test func recoveryFlowCallsStartThenCompleteAndPersistsCookie() async throws {
        let transport = MockTransport()
        let secrets = InMemorySecretStore()
        transport.enqueue("POST /api/v1/auth/recovery/start", status: 202, body: #"{"recoveryId":"rec-1"}"#)
        transport.enqueue("POST /api/v1/auth/recovery/complete", body: Fixtures.sessionJSON(csrf: "c", recovery: true))
        let service = makeService(transport, secrets: secrets)
        transport.setSessionCookie("cookie-value", for: Fixtures.baseURL) // what the URLSession would have stored
        let context = try await service.signInWithRecovery(server: Fixtures.baseURL, method: .recoveryCode, handle: "  Anna ", proof: " abcd-efgh \n")
        #expect(context.session.recovery)
        let start = try JSONSerialization.jsonObject(with: transport.requests(matching: "POST /api/v1/auth/recovery/start")[0].httpBody ?? Data()) as? [String: String]
        #expect(start == ["method": "recovery-code", "identifier": "anna"])
        let complete = try JSONSerialization.jsonObject(with: transport.requests(matching: "POST /api/v1/auth/recovery/complete")[0].httpBody ?? Data()) as? [String: String]
        #expect(complete == ["recoveryId": "rec-1", "proof": "abcd-efgh"])
        #expect(secrets.read(SecretKey.sessionCookie) == "cookie-value")
        #expect(secrets.read(SecretKey.serverURL) == "http://localhost:18090")
    }

    @Test func passkeyFlowForwardsOptionsAndCredential() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/auth/login/options", body: #"{"challengeId":"ch-1","publicKey":{"challenge":"YWJj","rpId":"localhost"}}"#)
        transport.enqueue("POST /api/v1/auth/login/verify", body: Fixtures.sessionJSON())
        let context = try await makeService(transport).signInWithPasskey(server: Fixtures.baseURL)
        #expect(!context.session.recovery)
        let verify = try JSONSerialization.jsonObject(with: transport.requests(matching: "POST /api/v1/auth/login/verify")[0].httpBody ?? Data()) as? [String: Any]
        #expect(verify?["challengeId"] as? String == "ch-1")
        #expect((verify?["credential"] as? [String: Any])?["challenge"] as? String == "YWJj")
    }

    @Test func unavailablePasskeyAuthenticatorFailsTyped() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/auth/login/options", body: #"{"challengeId":"ch","publicKey":{}}"#)
        let service = AuthService(secrets: InMemorySecretStore(), transport: transport)
        await #expect(throws: TimetrackError.passkey("unavailable")) { try await service.signInWithPasskey(server: Fixtures.baseURL) }
    }

    @Test func addPasskeyUpgradesRecoverySession() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/auth/recovery/start", status: 202, body: #"{"recoveryId":"r"}"#)
        transport.enqueue("POST /api/v1/auth/recovery/complete", body: Fixtures.sessionJSON(recovery: true))
        transport.enqueue("POST /api/v1/me/passkeys/options", body: #"{"challengeId":"ch","publicKey":{"challenge":"YWJj"}}"#)
        transport.enqueue("POST /api/v1/me/passkeys/verify", status: 201, body: #"{"id":"p"}"#)
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "up", recovery: false))
        let service = makeService(transport)
        let restricted = try await service.signInWithRecovery(server: Fixtures.baseURL, method: .fallbackPassword, handle: "anna", proof: "pw")
        let upgraded = try await service.addPasskey(context: restricted, name: "Mac")
        #expect(!upgraded.session.recovery)
    }

    @Test func restoreWithoutCredentialsIsSignedOut() async {
        let result = await makeService(MockTransport()).restore()
        guard case .signedOut = result else { Issue.record("expected signedOut"); return }
    }

    @Test func restoreUsesStoredCookieAndHandlesRejection() async throws {
        let secrets = InMemorySecretStore()
        secrets.write("http://localhost:18090", for: SecretKey.serverURL)
        secrets.write("stored-cookie", for: SecretKey.sessionCookie)
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        let result = await makeService(transport, secrets: secrets).restore()
        guard case .signedIn(let context) = result else { Issue.record("expected signedIn"); return }
        #expect(context.session.account.handle == "anna")
        #expect(transport.sessionCookieValue(for: Fixtures.baseURL) == "stored-cookie")

        let rejecting = MockTransport()
        rejecting.enqueue("GET /api/v1/auth/session", status: 401, body: #"{"error":{"code":"unauthorized","message":"x"}}"#)
        let again = makeService(rejecting, secrets: secrets)
        guard case .signedOut = await again.restore() else { Issue.record("expected signedOut"); return }
        #expect(secrets.read(SecretKey.sessionCookie) == nil, "a rejected session is dropped")
        #expect(secrets.read(SecretKey.serverURL) != nil, "the server URL is kept")
    }

    @Test func restoreKeepsCredentialsWhenOffline() async {
        let secrets = InMemorySecretStore()
        secrets.write("http://localhost:18090", for: SecretKey.serverURL)
        secrets.write("stored-cookie", for: SecretKey.sessionCookie)
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", error: .cannotConnectToHost)
        guard case .offline = await makeService(transport, secrets: secrets).restore() else { Issue.record("expected offline"); return }
        #expect(secrets.read(SecretKey.sessionCookie) == "stored-cookie")
    }

    /// Review finding 1: a failed sign-in on server B must not rebind the stored cookie of server A to B.
    @Test func failedSignInOnOtherServerKeepsCookieBoundToStoredServer() async throws {
        let secrets = InMemorySecretStore()
        secrets.write("http://localhost:18090", for: SecretKey.serverURL)
        secrets.write("cookie-of-a", for: SecretKey.sessionCookie)
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", error: .cannotConnectToHost)
        transport.enqueue("POST /api/v1/auth/login/options", status: 500, body: #"{"error":{"code":"internal","message":"x"}}"#)
        let service = makeService(transport, secrets: secrets)
        guard case .offline = await service.restore() else { Issue.record("expected offline"); return }
        let other = URL(string: "https://b.example.org")!
        await #expect(throws: TimetrackError.self) { try await service.signInWithPasskey(server: other) }
        #expect(secrets.read(SecretKey.serverURL) == "http://localhost:18090")
        #expect(await service.serverURL == Fixtures.baseURL)
        _ = await service.restore()
        _ = await makeService(transport, secrets: secrets).restore()
        let sessionChecks = transport.requests(matching: "GET /api/v1/auth/session")
        #expect(sessionChecks.count == 3)
        #expect(sessionChecks.allSatisfy { $0.url?.host == "localhost" }, "the cookie of A is never sent to B")
    }

    @Test func successfulSignInOnOtherServerStoresIt() async throws {
        let secrets = InMemorySecretStore()
        secrets.write("http://localhost:18090", for: SecretKey.serverURL)
        secrets.write("cookie-of-a", for: SecretKey.sessionCookie)
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        let other = URL(string: "https://b.example.org")!
        _ = try await makeService(transport, secrets: secrets).signInWithSessionCookie(server: other, cookieValue: "cookie-of-b")
        #expect(secrets.read(SecretKey.serverURL) == "https://b.example.org")
        #expect(secrets.read(SecretKey.sessionCookie) == "cookie-of-b")
    }

    /// Review finding 3: a fresh sign-in for `reauth_required` must stay on the same account. Choosing another account's passkey
    /// is refused, that session is ended and the previous cookie is put back.
    @Test func reauthenticationWithAnotherAccountIsRefusedAndRestoresTheSession() async throws {
        struct SwitchingPasskeys: PasskeyAuthenticator {
            let transport: MockTransport
            func register(options: WebAuthnOptions) async throws -> JSONValue { .null }
            func authenticate(options: WebAuthnOptions) async throws -> JSONValue {
                transport.setSessionCookie("cookie-of-b", for: Fixtures.baseURL) // what the server's Set-Cookie would do
                return .object(["id": .string("cred-b")])
            }
        }
        let secrets = InMemorySecretStore()
        let transport = MockTransport()
        let service = AuthService(secrets: secrets, transport: transport, passkeys: SwitchingPasskeys(transport: transport))
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "csrf-a"))
        let first = try await service.signInWithSessionCookie(server: Fixtures.baseURL, cookieValue: "cookie-of-a")
        let other = #"{"account":{"id":"99999999-9999-4999-8999-999999999999","handle":"bert","displayName":"Bert","role":"member"},"csrfToken":"csrf-b","recovery":false,"expiresAt":"2026-11-01T08:00:00Z"}"#
        transport.enqueue("POST /api/v1/auth/login/options", body: #"{"challengeId":"ch","publicKey":{}}"#)
        transport.enqueue("POST /api/v1/auth/login/verify", body: other)
        transport.enqueue("DELETE /api/v1/auth/session", status: 204)
        await #expect(throws: TimetrackError.passkey("other_account")) {
            try await service.reauthenticate(server: Fixtures.baseURL, accountId: first.session.account.id)
        }
        #expect(transport.requests(matching: "DELETE /api/v1/auth/session").count == 1, "the session of the other account is ended")
        #expect(transport.sessionCookieValue(for: Fixtures.baseURL) == "cookie-of-a")
        #expect(secrets.read(SecretKey.sessionCookie) == "cookie-of-a")
        #expect(TimetrackError.passkey("other_account").germanDescription.contains("anderen Kontos"))
    }

    @Test func reauthenticationWithTheSameAccountReplacesTheSession() async throws {
        let transport = MockTransport()
        let service = makeService(transport)
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        let first = try await service.signInWithSessionCookie(server: Fixtures.baseURL, cookieValue: "cookie-of-a")
        transport.enqueue("POST /api/v1/auth/login/options", body: #"{"challengeId":"ch","publicKey":{}}"#)
        transport.enqueue("POST /api/v1/auth/login/verify", body: Fixtures.sessionJSON(csrf: "fresh"))
        let fresh = try await service.reauthenticate(server: Fixtures.baseURL, accountId: first.session.account.id)
        #expect(fresh.session.account.id == first.session.account.id)
        #expect(transport.requests(matching: "DELETE /api/v1/auth/session").isEmpty)
    }

    #if canImport(AuthenticationServices) && (os(macOS) || os(iOS))
    /// B33A8F6A: cancelling the system prompt must not leave an error on screen (`FreshLoginNotice` hides `.cancelled` only).
    @Test func cancellingTheSystemPromptDuringReauthenticationIsReportedAsCancelled() async throws {
        struct CancellingPasskeys: PasskeyAuthenticator {
            func register(options: WebAuthnOptions) async throws -> JSONValue { .null }
            func authenticate(options: WebAuthnOptions) async throws -> JSONValue {
                throw PlatformPasskeyAuthenticator.failure(for: ASAuthorizationError(.canceled))
            }
        }
        let secrets = InMemorySecretStore()
        let transport = MockTransport()
        let service = AuthService(secrets: secrets, transport: transport, passkeys: CancellingPasskeys())
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        let first = try await service.signInWithSessionCookie(server: Fixtures.baseURL, cookieValue: "cookie-of-a")
        transport.enqueue("POST /api/v1/auth/login/options", body: #"{"challengeId":"ch","publicKey":{}}"#)
        await #expect(throws: TimetrackError.cancelled) {
            try await service.reauthenticate(server: Fixtures.baseURL, accountId: first.session.account.id)
        }
        #expect(secrets.read(SecretKey.sessionCookie) == "cookie-of-a")
    }
    #endif

    @Test func devCookieSignInAndFailureCleanup() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        let service = makeService(transport)
        let context = try await service.signInWithSessionCookie(server: Fixtures.baseURL, cookieValue: " abc \n")
        #expect(context.session.account.handle == "anna")
        #expect(transport.sessionCookieValue(for: Fixtures.baseURL) == "abc")

        let bad = MockTransport()
        bad.enqueue("GET /api/v1/auth/session", status: 401, body: #"{"error":{"code":"unauthorized","message":"x"}}"#)
        await #expect(throws: TimetrackError.self) { try await self.makeService(bad).signInWithSessionCookie(server: Fixtures.baseURL, cookieValue: "nope") }
        #expect(bad.sessionCookieValue(for: Fixtures.baseURL) == nil)
    }

    @Test func signOutClearsStoredSession() async throws {
        let secrets = InMemorySecretStore()
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("DELETE /api/v1/auth/session", status: 204)
        let service = makeService(transport, secrets: secrets)
        _ = try await service.signInWithSessionCookie(server: Fixtures.baseURL, cookieValue: "abc")
        await service.signOut()
        #expect(secrets.read(SecretKey.sessionCookie) == nil)
        #expect(transport.sessionCookieValue(for: Fixtures.baseURL) == nil)
        let delete = transport.requests(matching: "DELETE /api/v1/auth/session")[0]
        #expect(delete.value(forHTTPHeaderField: "X-CSRF-Token") == "csrf-1")
    }
}
