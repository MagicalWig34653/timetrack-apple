import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// Mock WatchConnectivity: records sent contexts and lets tests inject events.
final class MockChannel: WatchSessionChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (WatchChannelEvent) -> Void)?
    private(set) var sent: [[String: String]] = []
    private(set) var resendRequests = 0
    var received: [String: String] = [:]
    var link: WatchLinkState = .reachable
    var failSend = false

    func activate(handler: @escaping @Sendable (WatchChannelEvent) -> Void) { lock.withLock { self.handler = handler } }
    func send(context: [String: String]) throws {
        if failSend { throw URLError(.unknown) }
        lock.withLock { sent.append(context) }
    }
    var receivedContext: [String: String] { lock.withLock { received } }
    func requestResend() { lock.withLock { resendRequests += 1 } }
    func emit(_ event: WatchChannelEvent) { lock.withLock { handler }?(event) }
    func clearSent() { lock.withLock { sent.removeAll() } }
}

actor Recorder {
    var sessions: [String] = []
    var signedOutCount = 0
    func session(_ server: URL, _ cookie: String) { sessions.append("\(server.absoluteString)|\(cookie)") }
    func signedOut() { signedOutCount += 1 }
}

@Suite struct WatchHandoffTests {
    let server = URL(string: "http://localhost:18090")!

    @Test func payloadRoundTrip() throws {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000.123)
        let encoded = HandoffPayload.session(server: server, cookie: "abc").encoded(stamp: stamp)
        #expect(Set(encoded.keys) == ["v", "stamp", "server", "cookie"]) // nothing else travels
        let decoded = try #require(HandoffPayload.decode(encoded))
        #expect(decoded.payload == .session(server: server, cookie: "abc"))
        #expect(abs(decoded.stamp.timeIntervalSince(stamp)) < 0.01)
        #expect(HandoffPayload.decode(HandoffPayload.signedOut.encoded(stamp: stamp))?.payload == .signedOut)
    }

    @Test func rejectsMalformedPayloads() {
        let stamp = Date().timeIntervalSince1970
        #expect(HandoffPayload.decode([:]) == nil)
        #expect(HandoffPayload.decode(["v": "2", "stamp": "2026-10-16T08:00:00.000Z"]) == nil)
        #expect(HandoffPayload.decode(["v": "1", "stamp": "garbage"]) == nil)
        let ok = HandoffPayload.session(server: server, cookie: "x").encoded(stamp: Date(timeIntervalSince1970: stamp))
        var badScheme = ok; badScheme["server"] = "ftp://x.org"
        #expect(HandoffPayload.decode(badScheme) == nil)
        var emptyCookie = ok; emptyCookie["cookie"] = ""
        #expect(HandoffPayload.decode(emptyCookie) == nil)
    }

    @Test func senderPushesSessionFromKeychainAndSignOut() async throws {
        let channel = MockChannel()
        let secrets = InMemorySecretStore()
        secrets.write(server.absoluteString, for: SecretKey.serverURL)
        secrets.write("cookie-1", for: SecretKey.sessionCookie)
        let sender = WatchHandoffSender(channel: channel, secrets: secrets, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        await sender.start()
        channel.emit(.activated) // state still unknown (restoring): must not sign the watch out
        try await Task.sleep(for: .milliseconds(50))
        #expect(channel.sent.isEmpty)
        await sender.update(isSignedIn: true)
        await sender.update(isSignedIn: false)
        #expect(channel.sent.count == 2)
        #expect(HandoffPayload.decode(channel.sent[0])?.payload == .session(server: server, cookie: "cookie-1"))
        #expect(HandoffPayload.decode(channel.sent[1])?.payload == .signedOut)
        #expect(channel.sent[1]["cookie"] == nil) // no credentials in a sign-out message
        let stamps = channel.sent.compactMap { HandoffPayload.decode($0)?.stamp }
        #expect(stamps[1] > stamps[0]) // strictly increasing even with a frozen clock
    }

    @Test func senderAnswersResendRequestAndActivation() async throws {
        let channel = MockChannel()
        let secrets = InMemorySecretStore()
        secrets.write(server.absoluteString, for: SecretKey.serverURL)
        secrets.write("c", for: SecretKey.sessionCookie)
        let sender = WatchHandoffSender(channel: channel, secrets: secrets)
        await sender.start()
        await sender.update(isSignedIn: true)
        channel.emit(.resendRequested)
        channel.emit(.activated)
        try await waitUntil { channel.sent.count == 3 }
    }

    @Test func receiverAppliesNewerAndIgnoresOlderOrDuplicate() async throws {
        let channel = MockChannel()
        let secrets = InMemorySecretStore()
        let recorder = Recorder()
        let receiver = WatchHandoffReceiver(channel: channel, secrets: secrets,
                                            onSession: { await recorder.session($0, $1) }, onSignedOut: { await recorder.signedOut() })
        let t1 = Date(timeIntervalSince1970: 1_800_000_000), t2 = t1.addingTimeInterval(5)
        let first = HandoffPayload.session(server: server, cookie: "one").encoded(stamp: t1)
        let second = HandoffPayload.session(server: server, cookie: "two").encoded(stamp: t2)
        #expect(await receiver.apply(second, force: false))
        #expect(await receiver.apply(first, force: false) == false) // stale
        #expect(await receiver.apply(second, force: false) == false) // duplicate (keeps a possibly rotated local cookie)
        #expect(await recorder.sessions == ["http://localhost:18090|two"])
        #expect(await receiver.apply(second, force: true)) // explicit "Sitzung übernehmen"
        #expect(await recorder.sessions.count == 2)
    }

    @Test func receiverClearsOnSignedOutAndPullRequestsResend() async throws {
        let channel = MockChannel()
        let recorder = Recorder()
        let receiver = WatchHandoffReceiver(channel: channel, secrets: InMemorySecretStore(),
                                            onSession: { await recorder.session($0, $1) }, onSignedOut: { await recorder.signedOut() })
        await receiver.start()
        channel.emit(.context(HandoffPayload.signedOut.encoded(stamp: Date(timeIntervalSince1970: 1_800_000_100))))
        try await waitUntil { await recorder.signedOutCount == 1 }
        channel.received = HandoffPayload.session(server: server, cookie: "pulled").encoded(stamp: Date(timeIntervalSince1970: 1_800_000_200))
        await receiver.pullNow()
        #expect(channel.resendRequests == 1)
        #expect(await recorder.sessions == ["http://localhost:18090|pulled"])
    }

    @Test func receiverAppliesWaitingContextOnActivation() async throws {
        let channel = MockChannel()
        channel.received = HandoffPayload.session(server: server, cookie: "waiting").encoded(stamp: Date(timeIntervalSince1970: 1_800_000_300))
        let recorder = Recorder()
        let receiver = WatchHandoffReceiver(channel: channel, secrets: InMemorySecretStore(),
                                            onSession: { await recorder.session($0, $1) }, onSignedOut: { await recorder.signedOut() })
        await receiver.start()
        channel.emit(.activated)
        try await waitUntil { await recorder.sessions.count == 1 }
    }

    @Test func handedOverSessionIsValidatedAndStoredInSecretStore() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("GET /api/v1/modules", body: Fixtures.modulesJSON)
        transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        let secrets = InMemorySecretStore()
        let model = await AppModel(auth: AuthService(secrets: secrets, transport: transport))
        await model.adoptHandedOverSession(server: server, cookie: "from-phone")
        #expect(await model.phase == .signedIn)
        #expect(secrets.read(SecretKey.sessionCookie) == "from-phone")
        #expect(secrets.read(SecretKey.serverURL) == "http://localhost:18090")
        await model.discardSessionLocally()
        #expect(await model.phase == .signedOut)
        #expect(secrets.read(SecretKey.sessionCookie) == nil)
        #expect(transport.requests(matching: "POST /api/v1/auth/logout").isEmpty) // watch never revokes the shared session
    }

    @Test func expiredHandedOverSessionEndsSignedOut() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", status: 401, body: #"{"error":{"code":"unauthorized","message":"no"}}"#)
        let secrets = InMemorySecretStore()
        let model = await AppModel(auth: AuthService(secrets: secrets, transport: transport))
        await model.adoptHandedOverSession(server: server, cookie: "stale")
        #expect(await model.phase == .signedOut)
        #expect(secrets.read(SecretKey.sessionCookie) == nil)
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("condition not reached")
    }
}

@Suite struct ManualHandoffTests {
    let server = URL(string: "http://localhost:18090")!

    private func makeSender(_ channel: MockChannel, signedIn: Bool?, withSecrets: Bool = true) async -> WatchHandoffSender {
        let secrets = InMemorySecretStore()
        if withSecrets {
            secrets.write(server.absoluteString, for: SecretKey.serverURL)
            secrets.write("cookie-1", for: SecretKey.sessionCookie)
        }
        let sender = WatchHandoffSender(channel: channel, secrets: secrets)
        if let signedIn { await sender.update(isSignedIn: signedIn) }
        channel.clearSent()
        return sender
    }

    @Test func sendsSessionWhenWatchIsReachable() async {
        let channel = MockChannel()
        let sender = await makeSender(channel, signedIn: true)
        #expect(await sender.sendNow() == .sent)
        #expect(channel.sent.count == 1)
        #expect(HandoffPayload.decode(channel.sent[0])?.payload == .session(server: server, cookie: "cookie-1"))
    }

    @Test func reportsNotPairedWithoutSending() async {
        let channel = MockChannel()
        channel.link = .notPaired
        let sender = await makeSender(channel, signedIn: true)
        #expect(await sender.sendNow() == .notPaired)
        #expect(channel.sent.isEmpty)
    }

    @Test func queuesWhenUnreachable() async {
        let channel = MockChannel()
        channel.link = .unreachable
        let sender = await makeSender(channel, signedIn: true)
        #expect(await sender.sendNow() == .queuedUnreachable)
        #expect(channel.sent.count == 1) // application context is delivered later by the system
    }

    @Test func neverSignsTheWatchOutManually() async {
        let channel = MockChannel()
        let signedOut = await makeSender(channel, signedIn: false)
        #expect(await signedOut.sendNow() == .notSignedIn)
        let unknown = await makeSender(channel, signedIn: nil)
        #expect(await unknown.sendNow() == .notSignedIn)
        let noSecrets = await makeSender(channel, signedIn: true, withSecrets: false)
        #expect(await noSecrets.sendNow() == .notSignedIn)
        #expect(channel.sent.isEmpty)
    }

    @Test func reportsFailureWhenChannelThrows() async {
        let channel = MockChannel()
        let sender = await makeSender(channel, signedIn: true)
        channel.failSend = true
        #expect(await sender.sendNow() == .failed)
    }
}
