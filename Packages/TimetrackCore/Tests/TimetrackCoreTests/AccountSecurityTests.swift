import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// AUD3-A: passkeys, recovery, identities and sessions (contract 0.36.0). Synthetic data only.

private let pk1 = "99999999-9999-4999-8999-999999999991"
private let pk2 = "99999999-9999-4999-8999-999999999992"
private let ident1 = "99999999-9999-4999-8999-9999999999a1"
private let reauthBody = #"{"error":{"code":"reauth_required","message":"x"}}"#

private func passkeyJSON(_ id: String, name: String = "iPhone", created: String = "2026-10-20T08:00:00Z", used: String? = nil) -> String {
    #"{"id":"\#(id)","name":"\#(name)","createdAt":"\#(created)","lastUsedAt":\#(used.map { "\"\($0)\"" } ?? "null")}"#
}

private func recoveryJSON(codes: Bool = false, remaining: Int? = nil, password: Bool = false, available: Bool = true, active: Bool = false,
                          verified: Bool? = true, account: String? = "a@b.example") -> String {
    let rem = remaining.map { ",\"remaining\":\($0)" } ?? ""
    let ver = verified.map { ",\"verified\":\($0)" } ?? ""
    let acc = account.map { ",\"accountEmail\":\"\($0)\",\"usesAccountEmail\":true" } ?? #","accountEmail":null"#
    return #"{"recoveryCodes":{"active":\#(codes)\#(rem)},"fallbackPassword":{"active":\#(password)},"email":{"available":\#(available),"active":\#(active)\#(ver)\#(acc)}}"#
}

@Suite("AUD3-A account security models") struct AccountSecurityModelTests {
    @Test func passkeyAndIdentityDecode() throws {
        let decoder = JSONCoding.makeDecoder()
        let key = try decoder.decode(Passkey.self, from: Data(passkeyJSON(pk1, used: "2026-10-21T08:00:00Z").utf8))
        #expect(key.name == "iPhone" && key.lastUsedAt != nil)
        let identity = try decoder.decode(ExternalIdentity.self, from: Data(#"{"id":"\#(ident1)","providerName":"Example IdP","emailHint":null,"linkedAt":"2026-10-20T08:00:00Z"}"#.utf8))
        #expect(identity.providerName == "Example IdP" && identity.emailHint == nil && identity.lastUsedAt == nil)
    }

    @Test func recoveryStatusDecodesOldAndNewServers() throws {
        let decoder = JSONCoding.makeDecoder()
        let status = try decoder.decode(RecoveryStatus.self, from: Data(recoveryJSON(codes: true, remaining: 7, password: true, active: true).utf8))
        #expect(status.recoveryCodes.remaining == 7 && status.hasAnyMethod)
        let old = try decoder.decode(RecoveryStatus.self, from: Data(#"{"recoveryCodes":{"active":false},"fallbackPassword":{"active":false},"email":{"available":true,"active":false}}"#.utf8))
        #expect(old.email.verified == nil && old.email.accountEmail == nil && old.hasAnyMethod == false)
    }

    @Test func emailStateFollowsTheWebAppsOrder() {
        func state(available: Bool = true, active: Bool = false, verified: Bool? = true, account: String? = "a@b.example") -> EmailRecoveryState {
            EmailRecoveryState(.init(available: available, active: active, verified: verified, accountEmail: account))
        }
        #expect(state(available: false, active: true) == .unavailable)
        #expect(state(account: nil) == .noAccountEmail)
        #expect(state(account: "") == .noAccountEmail)
        #expect(state(active: true) == .active(email: "a@b.example"))
        #expect(state(verified: false) == .unconfirmed(email: "a@b.example"))
        #expect(state(verified: nil) == .canEnable(email: "a@b.example"), "older servers do not report it")
        #expect(state() == .canEnable(email: "a@b.example"))
    }

    @Test func passwordRules() {
        let long = String(repeating: "a", count: 12)
        #expect(RecoveryValidation.passwordProblem("short", repeated: "short") == .tooShort)
        #expect(RecoveryValidation.passwordProblem(long, repeated: long + "x") == .mismatch)
        #expect(RecoveryValidation.passwordProblem(long, repeated: long) == nil)
        #expect(RecoveryValidation.passwordProblem(String(repeating: "a", count: 257), repeated: String(repeating: "a", count: 257)) == .tooLong)
    }
}

@Suite("AUD3-A passkeys store") @MainActor struct PasskeysStoreTests {
    private func store(_ transport: MockTransport, register: @escaping @MainActor (String?) async -> TimetrackError? = { _ in nil }) -> PasskeysStore {
        PasskeysStore(client: Fixtures.client(transport), register: register)
    }

    @Test func loadsOldestFirst() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/passkeys", body: "[\(passkeyJSON(pk2, name: "Mac", created: "2026-10-22T08:00:00Z")),\(passkeyJSON(pk1))]")
        let store = store(transport)
        await store.load()
        #expect(store.passkeys.map(\.name) == ["iPhone", "Mac"])
        #expect(store.isLast == false)
    }

    @Test func addRunsTheCeremonyWithATrimmedNameAndReloads() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/passkeys", body: "[\(passkeyJSON(pk1)),\(passkeyJSON(pk2, name: "Mac"))]")
        var names: [String?] = []
        let store = store(transport) { names.append($0); return nil }
        #expect(await store.add(name: "  Mac  "))
        #expect(names == ["Mac"])
        #expect(store.notice == .added && store.passkeys.count == 2)
        _ = await store.add(name: "   ")
        #expect(names.last! == nil, "a blank name is not sent")
    }

    @Test func addFailureAndStaleSessionAreSeparated() async {
        let transport = MockTransport()
        var failures: [TimetrackError] = [.api(status: 403, code: "reauth_required", message: "x"), .passkey("cancelled")]
        let store = store(transport) { _ in failures.removeFirst() }
        #expect(await store.add(name: nil) == false)
        #expect(store.needsFreshLogin && store.error == nil)
        #expect(await store.add(name: nil) == false)
        #expect(store.needsFreshLogin == false && store.error == .passkey("cancelled"))
    }

    @Test func renameSendsTheTrimmedNameAndReplacesTheRow() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/passkeys", body: "[\(passkeyJSON(pk1))]")
        transport.enqueue("PATCH /api/v1/me/passkeys/\(pk1)", body: passkeyJSON(pk1, name: "Work phone"))
        let store = store(transport)
        await store.load()
        #expect(await store.rename(store.passkeys[0], to: "  Work phone "))
        #expect(store.passkeys[0].name == "Work phone" && store.notice == .renamed)
        let sent = try #require(transport.requests(matching: "PATCH /api/v1/me/passkeys/\(pk1)").first)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any])
        #expect(body["name"] as? String == "Work phone")
        #expect(await store.rename(store.passkeys[0], to: "   ") == false)
        #expect(await store.rename(store.passkeys[0], to: String(repeating: "x", count: 81)) == false)
    }

    @Test func revokeRemovesAndTheLastPasskeyConflictIsShown() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/passkeys", body: "[\(passkeyJSON(pk1)),\(passkeyJSON(pk2, created: "2026-10-22T08:00:00Z"))]")
        transport.enqueue("DELETE /api/v1/me/passkeys/\(pk2)", status: 204)
        transport.enqueue("DELETE /api/v1/me/passkeys/\(pk1)", status: 409, body: #"{"error":{"code":"last_passkey","message":"x"}}"#)
        let store = store(transport)
        await store.load()
        #expect(await store.revoke(store.passkeys[1]))
        #expect(store.isLast)
        #expect(await store.revoke(store.passkeys[0]) == false)
        #expect(store.error?.knownCode == .lastPasskey && store.passkeys.count == 1)
    }
}

@Suite("AUD3-A recovery store") @MainActor struct RecoveryStoreTests {
    private func store(_ transport: MockTransport) -> RecoveryStore { RecoveryStore(client: Fixtures.client(transport)) }

    @Test func generatingCodesKeepsThemInMemoryUntilDismissed() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/recovery/recovery-codes", status: 201, body: #"{"codes":["aaaa-1111","bbbb-2222"]}"#)
        transport.enqueue("GET /api/v1/me/recovery", body: recoveryJSON(codes: true, remaining: 2))
        let store = store(transport)
        #expect(await store.generateCodes())
        #expect(store.freshCodes == ["aaaa-1111", "bbbb-2222"])
        #expect(store.codesText == "aaaa-1111\nbbbb-2222")
        #expect(store.status?.recoveryCodes.remaining == 2)
        store.dismissCodes()
        #expect(store.freshCodes == nil && store.codesText.isEmpty)
    }

    @Test func disablingCodesDropsFreshCodes() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/recovery/recovery-codes", status: 201, body: #"{"codes":["x"]}"#)
        transport.enqueue("GET /api/v1/me/recovery", body: recoveryJSON(codes: true, remaining: 1))
        transport.enqueue("DELETE /api/v1/me/recovery/recovery-codes", status: 204)
        transport.enqueue("GET /api/v1/me/recovery", body: recoveryJSON())
        let store = store(transport)
        _ = await store.generateCodes()
        #expect(await store.disableCodes())
        #expect(store.freshCodes == nil && store.status?.recoveryCodes.active == false && store.notice == .codesDisabled)
    }

    @Test func passwordIsValidatedLocallyThenSent() async throws {
        let transport = MockTransport()
        transport.enqueue("PUT /api/v1/me/recovery/fallback-password", status: 204)
        transport.enqueue("GET /api/v1/me/recovery", body: recoveryJSON(password: true))
        let store = store(transport)
        #expect(await store.setPassword("short", repeated: "short") == false)
        #expect(await store.setPassword("long enough pw!", repeated: "other") == false)
        #expect(transport.requests.isEmpty)
        #expect(await store.setPassword("long enough pw!", repeated: "long enough pw!"))
        #expect(store.status?.fallbackPassword.active == true && store.notice == .passwordSaved)
        let sent = try #require(transport.requests(matching: "PUT /api/v1/me/recovery/fallback-password").first)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any])
        #expect(body["password"] as? String == "long enough pw!" && body.count == 1)
    }

    @Test func removingThePassword() async {
        let transport = MockTransport()
        transport.enqueue("DELETE /api/v1/me/recovery/fallback-password", status: 204)
        transport.enqueue("GET /api/v1/me/recovery", body: recoveryJSON())
        let store = store(transport)
        #expect(await store.removePassword())
        #expect(store.notice == .passwordRemoved)
    }

    @Test func emailRecoveryActiveAtOnceOn204AndSendsNoBody() async throws {
        let transport = MockTransport()
        transport.enqueue("PUT /api/v1/me/recovery/email", status: 204)
        transport.enqueue("GET /api/v1/me/recovery", body: recoveryJSON(active: true))
        let store = store(transport)
        #expect(await store.enableEmail())
        #expect(store.emailCodePending == false && store.notice == .emailActive)
        #expect(store.emailState == .active(email: "a@b.example"))
        let sent = try #require(transport.requests(matching: "PUT /api/v1/me/recovery/email").first)
        #expect((sent.httpBody ?? Data()).isEmpty, "contract 0.36.0: the account e-mail is the address, no body")
    }

    @Test func emailRecoveryWaitsForTheCodeOn202ThenVerifies() async throws {
        let transport = MockTransport()
        transport.enqueue("PUT /api/v1/me/recovery/email", status: 202)
        transport.enqueue("POST /api/v1/me/recovery/email/verify", status: 204)
        transport.enqueue("GET /api/v1/me/recovery", body: recoveryJSON(active: true))
        let store = store(transport)
        #expect(await store.enableEmail())
        #expect(store.emailCodePending && store.notice == .emailCodeSent)
        #expect(await store.verifyEmail(code: "  ") == false)
        #expect(await store.verifyEmail(code: " 123456 "))
        #expect(store.emailCodePending == false && store.status?.email.active == true)
        let sent = try #require(transport.requests(matching: "POST /api/v1/me/recovery/email/verify").first)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any])
        #expect(body["code"] as? String == "123456")
    }

    @Test func emailRecoveryErrors() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/recovery", body: recoveryJSON())
        transport.enqueue("PUT /api/v1/me/recovery/email", status: 403, body: reauthBody)
        transport.enqueue("PUT /api/v1/me/recovery/email", status: 409, body: #"{"error":{"code":"account_email_missing","message":"x"}}"#)
        transport.enqueue("PUT /api/v1/me/recovery/email", status: 501, body: #"{"error":{"code":"not_implemented","message":"x"}}"#)
        let store = store(transport)
        await store.load()
        #expect(await store.enableEmail() == false)
        #expect(store.needsFreshLogin && store.error == nil)
        #expect(await store.enableEmail() == false)
        #expect(store.needsFreshLogin == false && store.error?.knownCode == .accountEmailMissing)
        #expect(await store.enableEmail() == false)
        #expect(store.emailState == .unavailable, "501 marks the method unavailable")
    }

    @Test func disablingEmailRecovery() async {
        let transport = MockTransport()
        transport.enqueue("DELETE /api/v1/me/recovery/email", status: 204)
        transport.enqueue("GET /api/v1/me/recovery", body: recoveryJSON())
        let store = store(transport)
        #expect(await store.disableEmail())
        #expect(store.notice == .emailDisabled)
    }
}

@Suite("AUD3-A identities and sessions") @MainActor struct IdentitiesAndSessionsTests {
    private let identityJSON = #"{"id":"\#(ident1)","providerName":"Example IdP","linkedAt":"2026-10-20T08:00:00Z"}"#

    @Test func serverWithoutOidcShowsAnEmptyList() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/identities", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let store = IdentitiesStore(client: Fixtures.client(transport))
        await store.load()
        #expect(store.hasLoaded && store.identities.isEmpty && store.error == nil)
    }

    @Test func unlinkRemovesTheRowAndMapsTheLastMethodConflict() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/identities", body: "[\(identityJSON)]")
        transport.enqueue("DELETE /api/v1/me/identities/\(ident1)", status: 409, body: #"{"error":{"code":"last_login_method","message":"x"}}"#)
        transport.enqueue("DELETE /api/v1/me/identities/\(ident1)", status: 403, body: reauthBody)
        transport.enqueue("DELETE /api/v1/me/identities/\(ident1)", status: 204)
        let store = IdentitiesStore(client: Fixtures.client(transport))
        await store.load()
        #expect(await store.unlink(store.identities[0]) == false)
        #expect(store.error?.knownCode == .lastLoginMethod)
        #expect(await store.unlink(store.identities[0]) == false)
        #expect(store.needsFreshLogin && store.error == nil)
        #expect(await store.unlink(store.identities[0]))
        #expect(store.identities.isEmpty && store.unlinkedNotice && store.needsFreshLogin == false)
    }

    @Test func revokingOtherSessions() async {
        let transport = MockTransport()
        transport.enqueue("DELETE /api/v1/me/sessions", status: 204)
        transport.enqueue("DELETE /api/v1/me/sessions", status: 403, body: reauthBody)
        let store = SessionsStore(client: Fixtures.client(transport))
        #expect(await store.revokeOthers())
        #expect(store.revokedNotice)
        #expect(await store.revokeOthers() == false)
        #expect(store.revokedNotice == false && store.needsFreshLogin)
    }
}
