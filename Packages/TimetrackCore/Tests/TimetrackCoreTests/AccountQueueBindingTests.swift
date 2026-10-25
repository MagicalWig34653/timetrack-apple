import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// X4: timer actions belong to the account that pressed them. They are never delivered with another account's session,
/// whatever the order of sign-out cleanup and the next sign-in.
@MainActor
@Suite struct AccountQueueBindingTests {
    let accountA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let accountB = UUID(uuidString: "22222222-2222-4222-8222-22222222bbbb")!
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    func sessionJSON(for id: UUID) -> String {
        Fixtures.sessionJSON().replacingOccurrences(of: "11111111-1111-4111-8111-111111111111", with: id.uuidString.lowercased())
    }

    func starts(_ transport: MockTransport) -> Int {
        transport.requests(matching: "POST /api/v1/time/timer/start").count + transport.requests(matching: "POST /api/v1/time/timer/stop").count
    }

    @Test func entriesAreStampedWithTheBoundAccount() async {
        let queue = TimerActionQueue(fileURL: nil)
        await queue.bind(accountId: accountA)
        await queue.enqueue(.init(command: .start(.work)))
        #expect(await queue.pending.first?.accountId == accountA)
    }

    @Test func bindingAnotherAccountPurgesTheForeignEntries() async {
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(.init(command: .start(.work), accountId: accountA))
        await queue.bind(accountId: accountB)
        #expect(await queue.pending.isEmpty)
        #expect(await queue.boundAccount == accountB)
    }

    @Test func legacyEntriesWithoutAnAccountAreAdoptedByTheFirstBoundAccount() async throws {
        let json = #"[{"id":"33333333-3333-4333-8333-333333333333","command":{"stop":{}},"queuedAt":"2026-10-16T06:00:00Z"}]"#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("x4-legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(json.utf8).write(to: url)
        let queue = TimerActionQueue(fileURL: url)
        let before = await queue.pending
        #expect(before.count == 1 && before.first?.accountId == nil)
        await queue.bind(accountId: accountA)
        #expect(await queue.pending.first?.accountId == accountA)
    }

    @Test func drainNeverDeliversAnotherAccountsEntries() async {
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(.init(command: .start(.work), accountId: accountA))
        let transport = MockTransport()
        let result = await queue.drain(client: Fixtures.client(transport), accountId: accountB)
        #expect(starts(transport) == 0 && result.delivered == 0 && result.remaining == 0)
        #expect(await queue.pending.isEmpty, "purged on mismatch")
    }

    @Test func drainWithoutAnyAccountContextLeavesStampedEntriesToTheApp() async {
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(.init(command: .start(.work), accountId: accountA))
        let transport = MockTransport()
        let result = await queue.drain(client: Fixtures.client(transport))
        #expect(starts(transport) == 0 && result.delivered == 0)
        #expect(await queue.pending.count == 1)
    }

    @Test func lateSignOutCleanupOfAccountANeverTouchesAccountBsEntries() async {
        let queue = TimerActionQueue(fileURL: nil)
        await queue.bind(accountId: accountA)
        await queue.enqueue(.init(command: .start(.work)))
        await queue.bind(accountId: accountB) // B signs in before A's cleanup ran
        await queue.enqueue(.init(command: .stop))
        await queue.release(accountId: accountA) // the late cleanup
        #expect(await queue.pending.map(\.accountId) == [accountB])
        #expect(await queue.boundAccount == accountB)
    }

    @Test func aTodayStoreOfAccountBNeverDeliversAccountAsActions() async {
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(.init(command: .start(.work), queuedAt: .now.addingTimeInterval(-600), accountId: accountA))
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/timer", body: "null")
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/days/\(calendar.day(for: .now))", body: Fixtures.dayJSON)
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar, queue: queue, accountId: accountB)
        await store.load()
        #expect(starts(transport) == 0)
        #expect(store.pending.isEmpty)
    }

    /// The race itself: A signs out (cleanup still pending), B signs in at once with a queue entry of A on disk.
    @Test func signOutFollowedByImmediateSignInOfAnotherAccountNeverDeliversTheOldEntries() async {
        let queue = TimerActionQueue(fileURL: nil)
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: sessionJSON(for: accountA))
        transport.enqueue("GET /api/v1/modules", body: Fixtures.modulesJSON)
        transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        transport.enqueue("GET /api/v1/time/timer", body: "null")
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/days/\(calendar.day(for: .now))", body: Fixtures.dayJSON)
        let model = AppModel(auth: AuthService(secrets: InMemorySecretStore(), transport: transport))
        model.actionQueue = queue
        await model.signInWithSessionCookie(serverInput: "localhost:18090", cookie: "a")
        #expect(model.phase == .signedIn)
        try? await Task.sleep(for: .milliseconds(150)) // A's own first load finishes (it may deliver A's entries legitimately)
        await queue.enqueue(.init(command: .start(.work), queuedAt: .now.addingTimeInterval(-600)))
        #expect(await queue.pending.first?.accountId == accountA)

        await model.signOut()
        transport.set("GET /api/v1/auth/session", body: sessionJSON(for: accountB))
        await model.signInWithSessionCookie(serverInput: "localhost:18090", cookie: "b")
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(model.phase == .signedIn)
        #expect(starts(transport) == 0, "account A's press was never sent with account B's session")
        #expect(await queue.pending.isEmpty)
        #expect(await queue.boundAccount == accountB)
    }
}
