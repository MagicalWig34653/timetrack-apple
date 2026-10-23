import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// HG1: runloop hang (build 36). Main-thread Keychain queries and a root `.task` that tore down a signed-in UI.
@Suite struct HangRegressionTests {
    /// Counts the queries that reach the (slow) base store.
    private final class CountingStore: SecretStore, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String] = [:]
        private(set) var reads: [String] = []
        func read(_ key: String) -> String? { lock.withLock { reads.append(key); return values[key] } }
        func write(_ value: String, for key: String) { lock.withLock { values[key] = value } }
        func delete(_ key: String) { lock.withLock { values[key] = nil } }
    }

    @Test func cachedKeysQueryTheBaseStoreOnlyOnce() {
        let base = CountingStore()
        base.write("tok", for: AutomationSecretKey.deviceToken)
        let store = CachedSecretStore(base, cachedKeys: AutomationSecretKey.all)
        #expect(store.read(AutomationSecretKey.deviceToken) == "tok")
        #expect(store.read(AutomationSecretKey.deviceToken) == "tok")
        #expect(store.read(AutomationSecretKey.deviceTokenId) == nil)
        #expect(store.read(AutomationSecretKey.deviceTokenId) == nil, "a missing item is cached too")
        #expect(base.reads == [AutomationSecretKey.deviceToken, AutomationSecretKey.deviceTokenId])
    }

    @Test func writesAndDeletesKeepCacheAndBaseInStep() {
        let base = CountingStore()
        let store = CachedSecretStore(base, cachedKeys: AutomationSecretKey.all)
        store.write("a", for: AutomationSecretKey.deviceToken)
        #expect(store.read(AutomationSecretKey.deviceToken) == "a")
        #expect(base.reads.isEmpty, "a written value is served from memory")
        store.delete(AutomationSecretKey.deviceToken)
        #expect(store.read(AutomationSecretKey.deviceToken) == nil)
        #expect(base.read(AutomationSecretKey.deviceToken) == nil, "the delete reached the base store")
    }

    @Test func otherKeysAlwaysPassThrough() {
        let base = CountingStore()
        let store = CachedSecretStore(base, cachedKeys: AutomationSecretKey.all)
        base.write("old", for: SecretKey.serverURL)
        #expect(store.read(SecretKey.serverURL) == "old")
        base.write("new", for: SecretKey.serverURL) // changed by another component (sign-in, widget): never stale
        #expect(store.read(SecretKey.serverURL) == "new")
    }

    @Test func prefetchWarmsEveryCachedKey() {
        let base = CountingStore()
        let store = CachedSecretStore(base, cachedKeys: AutomationSecretKey.all)
        store.prefetch()
        let afterPrefetch = base.reads.count
        #expect(afterPrefetch == AutomationSecretKey.all.count)
        _ = store.read(AutomationSecretKey.deviceId)
        _ = store.read(AutomationSecretKey.deviceToken)
        #expect(base.reads.count == afterPrefetch, "reads after the prefetch never reach the Keychain")
    }

    @MainActor @Test func restoreIfNeededKeepsASignedInModel() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("GET /api/v1/modules", body: Fixtures.modulesJSON)
        transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        let model = AppModel(auth: AuthService(secrets: InMemorySecretStore(), transport: transport))
        await model.signInWithSessionCookie(serverInput: "localhost:18090", cookie: "c")
        #expect(model.phase == .signedIn)
        let today = model.today
        let sessionCalls = transport.requests(matching: "GET /api/v1/auth/session").count

        await model.restoreIfNeeded() // the root view's task ran again

        #expect(model.phase == .signedIn, "no detour through .restoring: the tab hierarchy stays alive")
        #expect(model.today === today, "the stores are not rebuilt")
        #expect(transport.requests(matching: "GET /api/v1/auth/session").count == sessionCalls)
    }

    @MainActor @Test func restoreIfNeededRestoresStoredCredentialsOnce() async {
        let secrets = InMemorySecretStore()
        secrets.write("http://localhost:18090", for: SecretKey.serverURL)
        secrets.write("stored-cookie", for: SecretKey.sessionCookie)
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("GET /api/v1/modules", body: Fixtures.modulesJSON)
        transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        let model = AppModel(auth: AuthService(secrets: secrets, transport: transport))
        #expect(model.phase == .restoring)
        await model.restoreIfNeeded()
        #expect(model.phase == .signedIn)
        await model.restoreIfNeeded()
        #expect(transport.requests(matching: "GET /api/v1/auth/session").count == 1)
    }

    @MainActor @Test func restoreIfNeededStillRetriesWhenOffline() async {
        let secrets = InMemorySecretStore()
        secrets.write("http://localhost:18090", for: SecretKey.serverURL)
        secrets.write("stored-cookie", for: SecretKey.sessionCookie)
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", error: .cannotConnectToHost)
        let model = AppModel(auth: AuthService(secrets: secrets, transport: transport))
        await model.restoreIfNeeded()
        #expect(model.phase == .offline)
        transport.set("GET /api/v1/auth/session", body: Fixtures.sessionJSON()) // the server is reachable again
        transport.enqueue("GET /api/v1/modules", body: Fixtures.modulesJSON)
        transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        await model.restoreIfNeeded()
        #expect(model.phase == .signedIn)
    }
}
