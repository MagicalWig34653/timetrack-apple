import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// AUD3-A: profile (contract 0.13.0). Synthetic data only.

private func profileJSON(name: String = "Test User", email: String? = nil, verified: Bool = false, pending: String? = nil, mail: Bool = true, onboarding: String = "completed") -> String {
    let emailJSON = email.map { "\"\($0)\"" } ?? "null"
    let pendingJSON = pending.map { "\"\($0)\"" } ?? "null"
    return #"{"handle":"test","displayName":"\#(name)","email":\#(emailJSON),"emailVerified":\#(verified),"pendingEmail":\#(pendingJSON),"mailAvailable":\#(mail),"onboarding":{"state":"\#(onboarding)"}}"#
}

@Suite("AUD3-A profile models") struct ProfileModelTests {
    @Test func decodesAllFieldsAndToleratesUnknownOnboarding() throws {
        let decoder = JSONCoding.makeDecoder()
        let profile = try decoder.decode(Profile.self, from: Data(profileJSON(email: "a@b.example", verified: true, pending: "c@d.example", onboarding: "later").utf8))
        #expect(profile.handle == "test")
        #expect(profile.email == "a@b.example" && profile.emailVerified)
        #expect(profile.pendingEmail == "c@d.example")
        #expect(profile.onboarding == .unknown)
        let plain = try decoder.decode(Profile.self, from: Data(profileJSON(mail: false).utf8))
        #expect(plain.email == nil && plain.pendingEmail == nil && plain.mailAvailable == false)
        #expect(plain.onboarding == .completed)
    }

    @Test func displayNameRules() {
        #expect(ProfileValidation.displayName("  Lena  ") == "Lena")
        #expect(ProfileValidation.displayName("   ") == nil)
        #expect(ProfileValidation.displayName(String(repeating: "x", count: 80)) != nil)
        #expect(ProfileValidation.displayName(String(repeating: "x", count: 81)) == nil)
    }

    @Test func emailRules() {
        #expect(ProfileValidation.email(" a@b.example ") == "a@b.example")
        for bad in ["", "a", "a@b", "@b.example", "a@.example", "a@b.", "a b@c.example", "a@b@c.example"] {
            #expect(ProfileValidation.email(bad) == nil, "\(bad) must be rejected")
        }
    }

    @Test func newErrorCodesHaveGermanText() {
        for code in [APIErrorCode.emailTaken, .accountEmailMissing, .recoveryEmailMustBeAccountEmail, .lastLoginMethod] {
            let error = TimetrackError.api(status: 409, code: code.rawValue, message: "x")
            #expect(error.knownCode == code)
            #expect(error.germanDescription != "error.\(code.rawValue)")
            #expect(error.germanDescription != TimetrackError.api(status: 400, code: "zzz", message: "").germanDescription)
        }
    }
}

@Suite("AUD3-A profile store") @MainActor struct ProfileStoreTests {
    private let reauth = #"{"error":{"code":"reauth_required","message":"x"}}"#

    @Test func loadsTheProfile() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/profile", body: profileJSON(email: "a@b.example"))
        let store = ProfileStore(client: Fixtures.client(transport))
        await store.load()
        #expect(store.hasLoaded)
        #expect(store.profile?.email == "a@b.example")
    }

    @Test func savingTheNameSendsTrimmedTextAndNotifiesTheApp() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/profile", body: profileJSON())
        transport.enqueue("PATCH /api/v1/me/profile", body: profileJSON(name: "Lena"))
        let store = ProfileStore(client: Fixtures.client(transport))
        var heard: [String] = []
        store.onDisplayNameChanged = { heard.append($0) }
        await store.load()
        #expect(await store.saveDisplayName("  Lena "))
        #expect(store.notice == .nameSaved)
        #expect(store.profile?.displayName == "Lena")
        #expect(heard == ["Test User", "Lena"], "the first load and the save both report the shown name")
        let sent = try #require(transport.requests(matching: "PATCH /api/v1/me/profile").first)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any])
        #expect(body["displayName"] as? String == "Lena")
        #expect(body.count == 1)
    }

    @Test func invalidNameIsRejectedWithoutARequest() async {
        let transport = MockTransport()
        let store = ProfileStore(client: Fixtures.client(transport))
        #expect(await store.saveDisplayName("   ") == false)
        #expect(store.error?.knownCode == .badRequest)
        #expect(transport.requests.isEmpty)
    }

    @Test func emailChangeSendsTheCodeThenShowsThePendingAddress() async throws {
        let transport = MockTransport()
        transport.enqueue("PUT /api/v1/me/profile/email", status: 202)
        transport.enqueue("GET /api/v1/me/profile", body: profileJSON(pending: "new@b.example"))
        let store = ProfileStore(client: Fixtures.client(transport))
        #expect(await store.requestEmailChange(" New@b.example "))
        #expect(store.notice == .codeSent)
        #expect(store.profile?.pendingEmail == "new@b.example")
        let sent = try #require(transport.requests(matching: "PUT /api/v1/me/profile/email").first)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any])
        #expect(body["email"] as? String == "New@b.example", "the client trims only; the server lowercases")
    }

    @Test func invalidEmailIsRejectedWithoutARequest() async {
        let transport = MockTransport()
        let store = ProfileStore(client: Fixtures.client(transport))
        #expect(await store.requestEmailChange("nope") == false)
        #expect(transport.requests.isEmpty)
    }

    @Test func staleSessionAsksForAFreshLoginInsteadOfAnError() async {
        let transport = MockTransport()
        transport.enqueue("PUT /api/v1/me/profile/email", status: 403, body: reauth)
        let store = ProfileStore(client: Fixtures.client(transport))
        #expect(await store.requestEmailChange("a@b.example") == false)
        #expect(store.needsFreshLogin)
        #expect(store.error == nil)
    }

    @Test func freshLoginFlagClearsOnTheNextAction() async {
        let transport = MockTransport()
        transport.enqueue("DELETE /api/v1/me/profile/email", status: 403, body: reauth)
        transport.enqueue("DELETE /api/v1/me/profile/email", status: 204)
        transport.enqueue("GET /api/v1/me/profile", body: profileJSON())
        let store = ProfileStore(client: Fixtures.client(transport))
        #expect(await store.removeEmail() == false)
        #expect(store.needsFreshLogin)
        #expect(await store.removeEmail())
        #expect(store.needsFreshLogin == false)
        #expect(store.notice == .emailRemoved)
    }

    @Test func confirmingTheCodeAdoptsTheVerifiedAddress() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/profile/email/verify", body: profileJSON(email: "new@b.example", verified: true))
        let store = ProfileStore(client: Fixtures.client(transport))
        #expect(await store.confirmEmail(code: " 123456 "))
        #expect(store.profile?.emailVerified == true)
        #expect(store.notice == .emailConfirmed)
        let sent = try #require(transport.requests(matching: "POST /api/v1/me/profile/email/verify").first)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any])
        #expect(body["code"] as? String == "123456")
        #expect(await store.confirmEmail(code: "  ") == false)
    }

    @Test func wrongCodeShowsTheErrorAndATakenAddressReloads() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/profile/email/verify", status: 400, body: #"{"error":{"code":"invalid_code","message":"x"}}"#)
        transport.enqueue("POST /api/v1/me/profile/email/verify", status: 409, body: #"{"error":{"code":"email_taken","message":"x"}}"#)
        transport.enqueue("GET /api/v1/me/profile", body: profileJSON())
        let store = ProfileStore(client: Fixtures.client(transport))
        #expect(await store.confirmEmail(code: "1") == false)
        #expect(store.error?.knownCode == .invalidCode)
        #expect(await store.confirmEmail(code: "2") == false)
        #expect(store.error?.knownCode == .emailTaken)
        #expect(store.profile?.pendingEmail == nil, "the consumed request no longer waits for a code")
    }
}
