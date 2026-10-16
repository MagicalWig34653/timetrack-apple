import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

@MainActor
@Suite struct StoresTests {
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    func today(_ transport: MockTransport) -> TodayStore { TodayStore(client: Fixtures.client(transport), calendar: calendar) }

    func enqueueToday(_ transport: MockTransport, timer: String) {
        transport.enqueue("GET /api/v1/time/timer", body: timer)
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        let day = calendar.day(for: .now)
        transport.enqueue("GET /api/v1/time/days/\(day)", body: Fixtures.dayJSON)
    }

    @Test func todayLoadsTimerDayAndBalance() async {
        let transport = MockTransport()
        enqueueToday(transport, timer: Fixtures.segmentJSON)
        let store = today(transport)
        await store.load()
        #expect(store.running?.isRunning == true)
        #expect(store.account?.balanceSeconds == -1080)
        #expect(store.segments.count == 1)
        #expect(store.error == nil)
    }

    @Test func startReplaysSameEventIdAfterNetworkLoss() async {
        let transport = MockTransport()
        enqueueToday(transport, timer: "null")
        transport.enqueue("POST /api/v1/time/timer/start", error: .timedOut)
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        let store = today(transport)
        await store.start()
        let posts = transport.requests(matching: "POST /api/v1/time/timer/start")
        #expect(posts.count == 2)
        #expect(posts[0].httpBody == posts[1].httpBody)
    }

    @Test func serverErrorSurfacesAndStopRefreshes() async {
        let transport = MockTransport()
        enqueueToday(transport, timer: "null")
        transport.enqueue("POST /api/v1/time/timer/stop", status: 409, body: #"{"error":{"code":"no_running_timer","message":"x"}}"#)
        let store = today(transport)
        await store.stop()
        #expect(store.error?.knownCode == .noRunningTimer)
        #expect(store.running == nil)
    }

    @Test func timeListLoadsWeekAndNavigates() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/days", body: "[\(Fixtures.dayJSON)]")
        let now = Date(timeIntervalSince1970: 1_792_130_820) // Fri 2026-10-16
        let store = TimeListStore(client: Fixtures.client(transport), calendar: calendar, now: now)
        #expect(store.weekStart == "2026-10-12")
        #expect(store.weekEnd == "2026-10-18")
        await store.load()
        #expect(store.days.count == 1)
        await store.shiftWeeks(-1)
        #expect(store.weekStart == "2026-10-05")
        #expect(transport.requests(matching: "GET /api/v1/time/days").last?.url?.query == "from=2026-10-05&to=2026-10-11")
    }

    @Test func timeListMutationFailureKeepsError() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/segments", status: 409, body: #"{"error":{"code":"segment_overlap","message":"x"}}"#)
        let store = TimeListStore(client: Fixtures.client(transport), calendar: calendar)
        let ok = await store.create(SegmentInput(kind: .work, startedAt: .now, endedAt: .now.addingTimeInterval(60)))
        #expect(!ok)
        #expect(store.error?.knownCode == .segmentOverlap)
    }

    @Test func appModelSignInLoadsModulesAndRecoveryIsRestricted() async {
        let transport = MockTransport()
        let secrets = InMemorySecretStore()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("GET /api/v1/modules", body: Fixtures.modulesJSON)
        transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        let model = AppModel(auth: AuthService(secrets: secrets, transport: transport))
        await model.signInWithSessionCookie(serverInput: "localhost:18090", cookie: "c")
        // "localhost:18090" without scheme normalizes to https; the mock ignores the scheme.
        #expect(model.phase == .signedIn)
        #expect(!model.isEnabled(.planning))
        #expect(model.isEnabled(.reports))
        #expect(model.workModel?.timeZone.identifier == "Europe/Berlin")

        let restrictedTransport = MockTransport()
        restrictedTransport.enqueue("POST /api/v1/auth/recovery/start", status: 202, body: #"{"recoveryId":"r"}"#)
        restrictedTransport.enqueue("POST /api/v1/auth/recovery/complete", body: Fixtures.sessionJSON(recovery: true))
        let restricted = AppModel(auth: AuthService(secrets: InMemorySecretStore(), transport: restrictedTransport))
        await restricted.signInWithRecovery(serverInput: "http://localhost:18090", method: .recoveryCode, handle: "anna", proof: "x")
        #expect(restricted.phase == .recoveryRestricted)
        #expect(restricted.today == nil)
        #expect(restrictedTransport.requests(matching: "GET /api/v1/modules").isEmpty, "no feature calls in a recovery session")
    }

    @Test func appModelReportsSignInErrors() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/auth/recovery/start", status: 202, body: #"{"recoveryId":"r"}"#)
        transport.enqueue("POST /api/v1/auth/recovery/complete", status: 401, body: #"{"error":{"code":"invalid_code","message":"x"}}"#)
        let model = AppModel(auth: AuthService(secrets: InMemorySecretStore(), transport: transport))
        await model.signInWithRecovery(serverInput: "http://localhost:18090", method: .fallbackPassword, handle: "anna", proof: "wrong")
        #expect(model.phase == .restoring || model.phase == .signedOut)
        #expect(model.lastError?.knownCode == .invalidCode)
    }
}
