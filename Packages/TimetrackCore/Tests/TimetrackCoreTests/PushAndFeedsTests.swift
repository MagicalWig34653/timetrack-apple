import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// P14c: APNs registration (contract 0.33.0) and ICS calendar feeds (contract 0.31.0). Synthetic data only.

private let deviceId = "55555555-5555-4555-8555-555555555555"
private let token64 = String(repeating: "ab", count: 32)

private func deviceJSON(id: String = deviceId, env: String = "sandbox", label: String? = "iPhone") -> String {
    let labelJSON = label.map { "\"\($0)\"" } ?? "null"
    return #"{"id":"\#(id)","platform":"ios","environment":"\#(env)","appBundleId":"com.example.timetrack","label":\#(labelJSON),"createdAt":"2026-10-26T08:00:00Z","lastSuccessAt":null}"#
}

private func feedJSON(id: String, label: String = "iPhone", include: String = #"["absences","holidays"]"#, withSecret: Bool = false) -> String {
    let secret = withSecret ? #","token":"tok123","path":"/ics/tok123.ics""# : ""
    return #"{"id":"\#(id)","label":"\#(label)","include":\#(include),"createdAt":"2026-10-26T08:00:00Z","expiresAt":null,"lastUsedAt":null\#(secret)}"#
}

private let identity = PushIdentity(platform: .ios, environment: .sandbox, appBundleId: "com.example.timetrack", label: "iPhone von Test")
private let accountId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

private func freshDefaults() -> UserDefaults {
    let name = "p14c-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("P14c push models") struct PushModelTests {
    @Test func registrationEncodesTheContractFields() throws {
        let body = PushDeviceRegistration(token: token64, platform: .macos, environment: .production, appBundleId: "com.example.timetrack", label: String(repeating: "x", count: 150))
        let json = try JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(body)) as? [String: Any]
        #expect(json?["token"] as? String == token64)
        #expect(json?["platform"] as? String == "macos")
        #expect(json?["environment"] as? String == "production")
        #expect(json?["appBundleId"] as? String == "com.example.timetrack")
        #expect((json?["label"] as? String)?.count == 100, "label is capped at the contract's 100 characters")
    }

    @Test func deviceInfoDecodesAndIgnoresUnknownFields() throws {
        let data = Data(#"{"id":"\#(deviceId)","platform":"watchos","environment":"production","appBundleId":"b","createdAt":"2026-10-26T08:00:00.500Z","future":1}"#.utf8)
        let info = try JSONCoding.makeDecoder().decode(PushDeviceInfo.self, from: data)
        #expect(info.platform == "watchos")
        #expect(info.label == nil)
        #expect(info.lastSuccessAt == nil)
    }

    @Test func tokenIsLowercaseHex() {
        #expect(PushTokenFormat.hex(Data([0x00, 0xAB, 0x0F, 0xff])) == "00ab0fff")
    }

    @Test func environmentFollowsTheProvisioningProfile() {
        func profile(_ value: String) -> Data {
            Data("garbage\u{0}<plist><dict><key>Entitlements</key><dict><key>aps-environment</key>\n\t<string>\(value)</string></dict></dict></plist>tail".utf8)
        }
        #expect(PushEnvironmentResolver.resolve(profile: profile("development"), fallbackIsSandbox: false) == .sandbox)
        #expect(PushEnvironmentResolver.resolve(profile: profile("production"), fallbackIsSandbox: true) == .production)
        let mac = Data("<key>com.apple.developer.aps-environment</key><string>development</string>".utf8)
        #expect(PushEnvironmentResolver.resolve(profile: mac, fallbackIsSandbox: false) == .sandbox)
    }

    @Test func environmentFallsBackWithoutAUsableProfile() {
        #expect(PushEnvironmentResolver.resolve(profile: nil, fallbackIsSandbox: true) == .sandbox)
        #expect(PushEnvironmentResolver.resolve(profile: nil, fallbackIsSandbox: false) == .production)
        #expect(PushEnvironmentResolver.resolve(profile: Data("no entitlements".utf8), fallbackIsSandbox: false) == .production)
        let odd = Data("<key>aps-environment</key><string>weird</string>".utf8)
        #expect(PushEnvironmentResolver.resolve(profile: odd, fallbackIsSandbox: true) == .sandbox)
    }

    @Test func newErrorCodesHaveGermanText() {
        for code in [APIErrorCode.pushUnavailable, .tooManyPushDevices, .pushFailed, .tooManyCalendarFeeds] {
            let error = TimetrackError.api(status: 409, code: code.rawValue, message: "x")
            #expect(error.knownCode == code)
            #expect(error.germanDescription != "error.\(code.rawValue)", "missing text for \(code.rawValue)")
            #expect(error.germanDescription != TimetrackError.api(status: 400, code: "zzz", message: "").germanDescription)
        }
    }
}

@Suite("P14c push registration") @MainActor struct PushRegistrationTests {
    private func make(_ transport: MockTransport, defaults: UserDefaults, now: @escaping @Sendable () -> Date = { .now }) -> PushRegistrationStore {
        PushRegistrationStore(client: Fixtures.client(transport), accountId: accountId, identity: identity, defaults: defaults, now: now)
    }

    @Test func registersTheTokenWithPlatformEnvironmentAndBundle() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/push-devices", status: 201, body: deviceJSON())
        let store = make(transport, defaults: freshDefaults())
        await store.setToken(token64.uppercased())
        #expect(store.device?.id.uuidString.lowercased() == deviceId)
        let sent = try #require(transport.requests(matching: "POST /api/v1/me/push-devices").first)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: String])
        #expect(body["token"] == token64, "token is sent as lowercase hex")
        #expect(body["platform"] == "ios")
        #expect(body["environment"] == "sandbox")
        #expect(body["appBundleId"] == "com.example.timetrack")
        #expect(body["label"] == "iPhone von Test")
    }

    @Test func sameTokenIsNotSentAgainWithinTheThrottleButAChangedTokenIs() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/push-devices", status: 201, body: deviceJSON())
        let defaults = freshDefaults()
        let clock = ClockBox(Date(timeIntervalSince1970: 1_800_000_000))
        let store = make(transport, defaults: defaults, now: { clock.value })
        await store.setToken(token64)
        clock.value += 60
        await store.register() // app start / foreground
        await store.setToken(token64)
        #expect(transport.requests(matching: "POST /api/v1/me/push-devices").count == 1)
        clock.value += PushRegistrationStore.minimumInterval + 1
        await store.register()
        #expect(transport.requests(matching: "POST /api/v1/me/push-devices").count == 2, "re-registers after the throttle")
        await store.setToken(String(repeating: "cd", count: 32))
        #expect(transport.requests(matching: "POST /api/v1/me/push-devices").count == 3, "a changed token registers at once")
    }

    @Test func registrationSurvivesARestartOfTheStore() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/push-devices", status: 201, body: deviceJSON())
        let defaults = freshDefaults()
        await make(transport, defaults: defaults).setToken(token64)
        let again = make(transport, defaults: defaults)
        #expect(again.isRegistered)
        await again.setToken(token64)
        #expect(transport.requests(matching: "POST /api/v1/me/push-devices").count == 1)
    }

    @Test func notConfiguredServerIsASilentNoOp() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/push-devices", status: 501, body: #"{"error":{"code":"push_unavailable","message":"x"}}"#)
        let store = make(transport, defaults: freshDefaults())
        await store.setToken(token64)
        #expect(store.state == .unavailable)
        #expect(!store.isRegistered)
    }

    @Test func tooManyDevicesIsReported() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/push-devices", status: 409, body: #"{"error":{"code":"too_many_push_devices","message":"x"}}"#)
        let store = make(transport, defaults: freshDefaults())
        await store.setToken(token64)
        #expect(store.state == .limitReached)
    }

    @Test func otherFailuresKeepTheErrorAndAllowARetry() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/push-devices", status: 429, body: #"{"error":{"code":"too_many_requests","message":"x"}}"#)
        transport.enqueue("POST /api/v1/me/push-devices", status: 201, body: deviceJSON())
        let store = make(transport, defaults: freshDefaults())
        await store.setToken(token64)
        if case .failed(let error) = store.state { #expect(error.status == 429) } else { Issue.record("expected .failed, got \(store.state)") }
        await store.register()
        #expect(store.isRegistered)
    }

    @Test func offlineKeepsTheDeviceUnregisteredWithoutCrashing() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/push-devices", error: .notConnectedToInternet)
        let store = make(transport, defaults: freshDefaults())
        await store.setToken(token64)
        if case .failed(let error) = store.state { #expect(error.isNetworkError) } else { Issue.record("expected .failed") }
    }

    @Test func tokenFailureOfTheSystemShowsUnlessAlreadyRegistered() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/push-devices", status: 201, body: deviceJSON())
        let store = make(transport, defaults: freshDefaults())
        store.tokenRequestFailed("kein Zugriff")
        #expect(store.state == .systemFailure("kein Zugriff"))
        await store.setToken(token64)
        store.tokenRequestFailed("später")
        #expect(store.isRegistered)
    }

    @Test func unregisterDeletesTheServerRowAndTheRecord() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/push-devices", status: 201, body: deviceJSON())
        transport.enqueue("DELETE /api/v1/me/push-devices/\(deviceId)", status: 204)
        let defaults = freshDefaults()
        let store = make(transport, defaults: defaults)
        await store.setToken(token64)
        #expect(await store.unregister())
        #expect(transport.requests(matching: "DELETE /api/v1/me/push-devices/\(deviceId)").count == 1)
        #expect(store.state == .idle)
        #expect(defaults.data(forKey: PushRegistrationStore.recordKey) == nil)
        // A second unregister has nothing to delete.
        #expect(await store.unregister())
        #expect(transport.requests(matching: "DELETE /api/v1/me/push-devices/\(deviceId)").count == 1)
    }

    @Test func unregisterTreatsGoneAsDoneAndReportsNetworkFailure() async {
        let gone = MockTransport()
        gone.enqueue("POST /api/v1/me/push-devices", status: 201, body: deviceJSON())
        gone.enqueue("DELETE /api/v1/me/push-devices/\(deviceId)", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let goneStore = make(gone, defaults: freshDefaults())
        await goneStore.setToken(token64)
        #expect(await goneStore.unregister())

        let offline = MockTransport()
        offline.enqueue("POST /api/v1/me/push-devices", status: 201, body: deviceJSON())
        offline.enqueue("DELETE /api/v1/me/push-devices/\(deviceId)", error: .timedOut)
        let offlineStore = make(offline, defaults: freshDefaults())
        await offlineStore.setToken(token64)
        #expect(await offlineStore.unregister() == false)
        #expect(offlineStore.state == .idle)
    }

    @Test func testPushUsesTheDeviceAndMapsErrors() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/push-devices", status: 201, body: deviceJSON())
        transport.enqueue("POST /api/v1/me/push-devices/\(deviceId)/test", status: 202)
        let store = make(transport, defaults: freshDefaults())
        await store.sendTest() // not registered: nothing happens
        #expect(transport.requests(matching: "POST /api/v1/me/push-devices/\(deviceId)/test").isEmpty)
        await store.setToken(token64)
        await store.sendTest()
        #expect(store.testState == .sent)

        transport.set("POST /api/v1/me/push-devices/\(deviceId)/test", status: 502, body: #"{"error":{"code":"push_failed","message":"x"}}"#)
        await store.sendTest()
        if case .failed(let error) = store.testState { #expect(error.knownCode == .pushFailed) } else { Issue.record("expected .failed") }
        transport.set("POST /api/v1/me/push-devices/\(deviceId)/test", status: 429, body: #"{"error":{"code":"too_many_requests","message":"x"}}"#)
        await store.sendTest()
        if case .failed(let error) = store.testState { #expect(error.status == 429) } else { Issue.record("expected .failed") }
    }

    @Test func testPushAgainstAServerThatDroppedTheDeviceRegistersAgain() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/push-devices", status: 201, body: deviceJSON())
        transport.enqueue("POST /api/v1/me/push-devices/\(deviceId)/test", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let store = make(transport, defaults: freshDefaults())
        await store.setToken(token64)
        await store.sendTest()
        #expect(transport.requests(matching: "POST /api/v1/me/push-devices").count == 2)
        #expect(store.isRegistered)
    }
}

private final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var value: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

@Suite("P14c app model push") @MainActor struct AppModelPushTests {
    private func signedInModel(_ transport: MockTransport, withIdentity: Bool = true) async -> AppModel {
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("GET /api/v1/modules", body: Fixtures.modulesJSON)
        transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        let model = AppModel(auth: AuthService(secrets: InMemorySecretStore(), transport: transport))
        if withIdentity { model.pushIdentity = identity }
        await model.signInWithSessionCookie(serverInput: "http://localhost:18090", cookie: "c")
        return model
    }

    @Test func tokenThatArrivedBeforeSignInRegistersAfterwards() async throws {
        UserDefaults.standard.removeObject(forKey: PushRegistrationStore.recordKey)
        defer { UserDefaults.standard.removeObject(forKey: PushRegistrationStore.recordKey) }
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/push-devices", status: 201, body: deviceJSON())
        transport.enqueue("DELETE /api/v1/me/push-devices/\(deviceId)", status: 204)
        let model = AppModel(auth: AuthService(secrets: InMemorySecretStore(), transport: transport))
        model.pushIdentity = identity
        model.setPushToken(token64)
        #expect(model.push == nil)
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("GET /api/v1/modules", body: Fixtures.modulesJSON)
        transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        await model.signInWithSessionCookie(serverInput: "http://localhost:18090", cookie: "c")
        for _ in 0..<50 where model.push?.isRegistered != true { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.push?.isRegistered == true)

        await model.signOut()
        #expect(transport.requests(matching: "DELETE /api/v1/me/push-devices/\(deviceId)").count == 1, "sign-out removes the device while the session is valid")
        #expect(model.push == nil)
    }

    @Test func withoutAnIdentityThereIsNoPushStore() async {
        let model = await signedInModel(MockTransport(), withIdentity: false)
        #expect(model.push == nil)
    }

    @Test func silentPushReloadsWhatTheScreensShowAndIgnoresSignedOut() async {
        let transport = MockTransport()
        let model = await signedInModel(transport)
        transport.enqueue("GET /api/v1/time/day", body: Fixtures.dayJSON)
        let before = transport.requests.count
        #expect(await model.refreshAfterPush())
        #expect(transport.requests.count > before, "the stores asked the server again")

        let out = AppModel(auth: AuthService(secrets: InMemorySecretStore(), transport: MockTransport()))
        #expect(await out.refreshAfterPush() == false)
    }
}

@Suite("P14c calendar feeds") struct CalendarFeedModelTests {
    @Test func linkPrefixesTheServerAndOffersWebcal() throws {
        let link = try #require(CalendarFeedLink(baseURL: URL(string: "https://timetrack.example.org")!, path: "/ics/tok123.ics"))
        #expect(link.https.absoluteString == "https://timetrack.example.org/ics/tok123.ics")
        #expect(link.webcal.absoluteString == "webcal://timetrack.example.org/ics/tok123.ics")
    }

    @Test func linkKeepsPortAndPathPrefix() throws {
        let link = try #require(CalendarFeedLink(baseURL: URL(string: "http://localhost:18090/tt/")!, path: "/ics/a.ics"))
        #expect(link.https.absoluteString == "http://localhost:18090/tt/ics/a.ics")
        #expect(link.webcal.absoluteString == "webcal://localhost:18090/tt/ics/a.ics")
    }

    @Test func linkRejectsPathsOutsideTheFeedArea() {
        #expect(CalendarFeedLink(baseURL: URL(string: "https://x.example")!, path: "/api/v1/me") == nil)
    }

    @Test func feedDecodesWithAndWithoutTheSecretAndKeepsUnknownContents() throws {
        let decoder = JSONCoding.makeDecoder()
        let listed = try decoder.decode(CalendarFeed.self, from: Data(feedJSON(id: deviceId, include: #"["absences","future_kind","plan"]"#).utf8))
        #expect(listed.token == nil && listed.path == nil)
        #expect(listed.include == ["absences", "future_kind", "plan"])
        #expect(listed.contents == [.absences, .plan])
        #expect(listed.contentSummary == "Abwesenheiten, Geplante Arbeitszeit")
        let created = try decoder.decode(CalendarFeed.self, from: Data(feedJSON(id: deviceId, withSecret: true).utf8))
        #expect(created.token == "tok123")
        #expect(created.path == "/ics/tok123.ics")
    }

    @Test func inputTrimsAndCapsTheLabelAndEncodesContents() throws {
        let input = CalendarFeedInput(label: "  " + String(repeating: "x", count: 100) + "  ", include: [.absences, .tracked], expiresInDays: 30)
        #expect(input.label.count == 80)
        let json = try JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(input)) as? [String: Any]
        #expect(json?["include"] as? [String] == ["absences", "tracked"])
        #expect(json?["expiresInDays"] as? Int == 30)
    }
}

@Suite("P14c calendar feeds store") @MainActor struct CalendarFeedsStoreTests {
    private let id1 = "66666666-6666-4666-8666-666666666661"
    private let id2 = "66666666-6666-4666-8666-666666666662"

    @Test func loadsNewestFirst() async {
        let transport = MockTransport()
        let older = feedJSON(id: id1, label: "alt").replacingOccurrences(of: "2026-10-26", with: "2026-10-20")
        transport.enqueue("GET /api/v1/me/calendar-feeds", body: "[\(older),\(feedJSON(id: id2, label: "neu"))]")
        let store = CalendarFeedsStore(client: Fixtures.client(transport))
        await store.load()
        #expect(store.feeds.map(\.label) == ["neu", "alt"])
        #expect(store.hasLoaded)
    }

    @Test func createKeepsTheOneTimeLinkOnlyInMemory() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/calendar-feeds", status: 201, body: feedJSON(id: id1, withSecret: true))
        transport.enqueue("GET /api/v1/me/calendar-feeds", body: "[\(feedJSON(id: id1))]")
        let store = CalendarFeedsStore(client: Fixtures.client(transport))
        #expect(await store.create(label: "iPhone", include: [.absences, .holidays], expiresInDays: nil))
        #expect(store.created?.link.https.absoluteString == "http://localhost:18090/ics/tok123.ics")
        #expect(store.feeds.count == 1)
        #expect(store.feeds.first?.token == nil, "the list never carries the secret")
        let sent = try #require(transport.requests(matching: "POST /api/v1/me/calendar-feeds").first)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any])
        #expect(body["label"] as? String == "iPhone")
        #expect(body["include"] as? [String] == ["absences", "holidays"])
        #expect(body["expiresInDays"] == nil)
        store.dismissCreated()
        #expect(store.created == nil)
    }

    @Test func createNeedsALabelAndAContent() async {
        let transport = MockTransport()
        let store = CalendarFeedsStore(client: Fixtures.client(transport))
        #expect(await store.create(label: "  ", include: [.plan]) == false)
        #expect(await store.create(label: "x", include: []) == false)
        #expect(transport.requests.isEmpty)
    }

    @Test func tenFeedsBlockCreationLocallyAndTheServerLimitIsMapped() async {
        let transport = MockTransport()
        let ids = (0..<10).map { String(format: "66666666-6666-4666-8666-%012d", $0) }
        transport.enqueue("GET /api/v1/me/calendar-feeds", body: "[\(ids.map { feedJSON(id: $0) }.joined(separator: ","))]")
        let store = CalendarFeedsStore(client: Fixtures.client(transport))
        await store.load()
        #expect(!store.canCreate)
        #expect(await store.create(label: "elf", include: [.plan]) == false)
        #expect(transport.requests(matching: "POST /api/v1/me/calendar-feeds").isEmpty)

        // Another device filled the last slot: the server says 409, the store reloads and shows the limit.
        let other = MockTransport()
        other.enqueue("POST /api/v1/me/calendar-feeds", status: 409, body: #"{"error":{"code":"too_many_calendar_feeds","message":"x"}}"#)
        other.enqueue("GET /api/v1/me/calendar-feeds", body: "[\(ids.map { feedJSON(id: $0) }.joined(separator: ","))]")
        let racing = CalendarFeedsStore(client: Fixtures.client(other))
        #expect(await racing.create(label: "elf", include: [.plan]) == false)
        #expect(racing.error?.knownCode == .tooManyCalendarFeeds)
        #expect(!racing.canCreate)
    }

    @Test func revokeRemovesLocallyAndTreatsGoneAsDone() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/calendar-feeds", body: "[\(feedJSON(id: id1)),\(feedJSON(id: id2))]")
        transport.enqueue("DELETE /api/v1/me/calendar-feeds/\(id1)", status: 204)
        transport.enqueue("DELETE /api/v1/me/calendar-feeds/\(id2)", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let store = CalendarFeedsStore(client: Fixtures.client(transport))
        await store.load()
        let first = try #require(store.feeds.first { $0.id.uuidString.lowercased() == id1 })
        #expect(await store.revoke(first))
        let second = try #require(store.feeds.first)
        #expect(await store.revoke(second))
        #expect(store.feeds.isEmpty)
    }

    @Test func revokeFailureKeepsTheFeed() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/calendar-feeds", body: "[\(feedJSON(id: id1))]")
        transport.enqueue("DELETE /api/v1/me/calendar-feeds/\(id1)", error: .notConnectedToInternet)
        let store = CalendarFeedsStore(client: Fixtures.client(transport))
        await store.load()
        #expect(await store.revoke(try #require(store.feeds.first)) == false)
        #expect(store.feeds.count == 1)
        #expect(store.error?.isNetworkError == true)
    }
}
