import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// Review finding 4: the watch (fast launch) keeps its today store across restores. A session handed over for ANOTHER server must
/// replace that store, otherwise timer reads and actions keep going to the old server.
@MainActor
@Suite struct FastLaunchServerSwitchTests {
    @Test func handedOverSessionForAnotherServerRebuildsTheTodayStore() async throws {
        let secrets = InMemorySecretStore()
        secrets.write("http://localhost:18090", for: SecretKey.serverURL)
        secrets.write("cookie-of-a", for: SecretKey.sessionCookie)
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("GET /api/v1/time/timer", body: "null")
        let model = AppModel(auth: AuthService(secrets: secrets, transport: transport))
        model.fastLaunch = .init(snapshot: { nil }, queue: nil)
        await model.restore()
        let before = try #require(model.today)

        let other = URL(string: "https://b.example.org")!
        await model.adoptHandedOverSession(server: other, cookie: "cookie-of-b")
        let after = try #require(model.today)
        #expect(after !== before)
        let marker = transport.requests.count
        await after.load()
        let timerReads = transport.requests.dropFirst(marker).filter { $0.url?.path == "/api/v1/time/timer" }
        #expect(!timerReads.isEmpty)
        #expect(timerReads.allSatisfy { $0.url?.host == "b.example.org" })
    }
}
