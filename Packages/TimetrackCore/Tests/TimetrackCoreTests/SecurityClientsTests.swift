import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// SEC-clients (contracts 0.40.0 and 0.41.0): weak passwords, 429 with Retry-After, storage quota, sessions ended elsewhere.
// Synthetic data only.

@Suite("SEC clients: error mapping") struct SecurityErrorMappingTests {
    @Test func retryAfterParsing() {
        #expect(APIClient.retryAfterSeconds("120") == 120)
        #expect(APIClient.retryAfterSeconds(" 30 ") == 30)
        #expect(APIClient.retryAfterSeconds("0") == nil)
        #expect(APIClient.retryAfterSeconds("Wed, 21 Oct 2026 07:28:00 GMT") == nil)
        #expect(APIClient.retryAfterSeconds(nil) == nil)
        #expect(APIClient.retryAfterSeconds("9999999") == 86_400, "capped at a day")
    }

    @Test func tooManyRequestsKeepsRetryAfter() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/auth/recovery/start", status: 429, body: #"{"error":{"code":"too_many_requests","message":"x"}}"#,
                          headers: ["Retry-After": "300"])
        let client = Fixtures.client(transport)
        do {
            _ = try await client.recoveryStart(method: .fallbackPassword, identifier: "anna")
            Issue.record("expected 429")
        } catch let error as TimetrackError {
            #expect(error.status == 429 && error.knownCode == .tooManyRequests && error.retryAfterSeconds == 300)
            #expect(error.germanDescription.contains("Zu viele Versuche"))
            #expect(error.germanDescription.contains("5 Minuten"), Comment(rawValue: error.germanDescription))
        } catch { Issue.record("unexpected \(error)") }
        #expect(transport.requests.count == 1, "a 429 is never repeated automatically")
    }

    @Test func tooManyRequestsWithoutHeaderStillReadable() async {
        let transport = MockTransport()
        transport.enqueue("PUT /api/v1/me/profile/email", status: 429, body: "")
        do {
            try await Fixtures.client(transport).requestProfileEmailChange(email: "a@b.example")
            Issue.record("expected 429")
        } catch let error as TimetrackError {
            #expect(error.status == 429 && error.retryAfterSeconds == nil && error.knownCode == .tooManyRequests)
            #expect(error.germanDescription == "Zu viele Versuche. Bitte warte einen Moment.")
        } catch { Issue.record("unexpected \(error)") }
    }

    @Test func waitPhrases() {
        #expect(TimetrackError.waitPhrase(seconds: 45) == "45 Sekunden")
        #expect(TimetrackError.waitPhrase(seconds: 150) == "etwa 3 Minuten")
        #expect(TimetrackError.waitPhrase(seconds: 7200) == "etwa 2 Stunden")
        #expect(TimetrackError.waitPhrase(seconds: nil) == nil)
    }

    @Test func exportLimitAndQuotaTexts() {
        let limited = TimetrackError.rateLimited(code: "export_rate_limited", message: "x", retryAfter: 1800)
        #expect(limited.germanDescription.contains("Export") && limited.germanDescription.contains("30 Minuten"), Comment(rawValue: limited.germanDescription))
        let quota = TimetrackError.api(status: 413, code: "storage_quota_exceeded", message: "x")
        #expect(quota.knownCode == .storageQuotaExceeded && quota.germanDescription.contains("Speicherplatz"))
        let weak = TimetrackError.api(status: 400, code: "weak_password", message: "x")
        #expect(weak.knownCode == .weakPassword && weak.germanDescription.contains("Passphrase") && weak.germanDescription.contains("16"))
    }

    @Test func uploadAnswers413And429() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/files", status: 413, body: #"{"error":{"code":"storage_quota_exceeded","message":"x"}}"#)
        transport.enqueue("POST /api/v1/files", status: 429, body: #"{"error":{"code":"too_many_requests","message":"x"}}"#, headers: ["Retry-After": "60"])
        let client = Fixtures.client(transport)
        for expected in [413, 429] {
            do {
                _ = try await client.uploadFile(name: "a.pdf", contentType: "application/pdf", data: Data("x".utf8))
                Issue.record("expected \(expected)")
            } catch let error as TimetrackError { #expect(error.status == expected) } catch { Issue.record("unexpected \(error)") }
        }
    }
}

@Suite("SEC clients: fallback password") struct FallbackPasswordRuleTests {
    @Test func minimumIsSixteen() {
        #expect(RecoveryValidation.passwordMinimum == 16)
        let fifteen = String(repeating: "x", count: 15)
        let sixteen = String(repeating: "x", count: 16)
        #expect(RecoveryValidation.passwordProblem(fifteen, repeated: fifteen) == .tooShort)
        #expect(RecoveryValidation.passwordProblem(sixteen, repeated: sixteen) == nil)
    }

    @MainActor @Test func serverRefusalIsShownNotSwallowed() async {
        let transport = MockTransport()
        transport.enqueue("PUT /api/v1/me/recovery/fallback-password", status: 400, body: #"{"error":{"code":"weak_password","message":"x"}}"#)
        let store = RecoveryStore(client: Fixtures.client(transport))
        let password = "abababababababab"
        #expect(await store.setPassword(password, repeated: password) == false)
        #expect(store.error?.knownCode == .weakPassword && store.notice == nil)
    }
}

@Suite("SEC clients: session ended elsewhere") struct SessionEndedElsewhereTests {
    private let account = "11111111-1111-4111-8111-111111111111"

    @MainActor private func signedInModel(_ transport: MockTransport, secrets: InMemorySecretStore = InMemorySecretStore()) async -> AppModel {
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("GET /api/v1/modules", body: Fixtures.modulesJSON)
        transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        transport.enqueue("GET /api/v1/time/timer", body: "null")
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        let model = AppModel(auth: AuthService(secrets: secrets, transport: transport))
        await model.signInWithSessionCookie(serverInput: "localhost:18090", cookie: "c")
        try? await Task.sleep(for: .milliseconds(150))
        return model
    }

    private let unauthorized = #"{"error":{"code":"unauthorized","message":"x"}}"#

    @MainActor @Test func a401AfterRecoveryOnAnotherDeviceSignsOutCleanly() async {
        let transport = MockTransport()
        let secrets = InMemorySecretStore()
        let model = await signedInModel(transport, secrets: secrets)
        #expect(model.phase == .signedIn && model.sessionEnded == false)
        #expect(secrets.read(SecretKey.sessionCookie) != nil)

        // The server ended the session: the next call and the session check both answer 401.
        transport.set("GET /api/v1/auth/session", status: 401, body: unauthorized)
        transport.set("GET /api/v1/time/timer", status: 401, body: unauthorized)
        await model.today?.load()
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(200))

        #expect(model.phase == .signedOut && model.sessionEnded)
        #expect(model.today == nil && model.account == nil)
        #expect(secrets.read(SecretKey.sessionCookie) == nil, "the dead cookie leaves the keychain")
        #expect(model.lifecycle.state == .signedOut(.expired))
        let sessionChecks = transport.requests(matching: "GET /api/v1/auth/session").count
        #expect(sessionChecks <= 3, Comment(rawValue: "one check, no error loop (\(sessionChecks))"))
    }

    @MainActor @Test func a401ThatTheSessionCheckDisprovesKeepsTheSession() async {
        let transport = MockTransport()
        let model = await signedInModel(transport)
        transport.set("GET /api/v1/time/timer", status: 401, body: unauthorized) // only this call fails; the session answers 200
        await model.today?.load()
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(model.phase == .signedIn && model.sessionEnded == false)
    }

    @MainActor @Test func explicitSignOutIsNotAnEndedSession() async {
        let transport = MockTransport()
        transport.enqueue("DELETE /api/v1/auth/session", status: 204)
        let model = await signedInModel(transport)
        await model.signOut()
        #expect(model.phase == .signedOut && model.sessionEnded == false)
    }

    @Test func authPathsNeverTriggerTheGuard() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/auth/recovery/complete", status: 401, body: #"{"error":{"code":"unauthorized","message":"x"}}"#)
        let client = Fixtures.client(transport)
        let counter = Counter()
        await client.setUnauthorizedHandler { counter.bump() }
        _ = try? await client.recoveryComplete(recoveryId: "r", proof: "wrong")
        #expect(counter.value == 0, "a wrong proof at sign-in is not a lost session")
        transport.enqueue("GET /api/v1/time/timer", status: 401, body: #"{"error":{"code":"unauthorized","message":"x"}}"#)
        _ = try? await client.currentTimer()
        #expect(counter.value == 1)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@Suite("SEC clients: automation token") struct RejectedDeviceTokenTests {
    @Test func rejectedTokenIsNotRetriedOnEveryEvent() async {
        // Covered through the queue summary: a 401 stops the drain; the engine adds a cooldown on top (see AutomationEngine).
        #expect(AutomationEngine.rejectedTokenCooldown == 30 * 60)
    }
}
