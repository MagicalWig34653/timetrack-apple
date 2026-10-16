import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

@MainActor
@Suite struct PlanningTests {
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let now = Date(timeIntervalSince1970: 1_792_130_820) // Fri 2026-10-16

    static let balanceJSON = #"{"year":2026,"snapshotDate":null,"snapshotRemainingHalfDays":null,"entitlementHalfDays":60,"carryOverHalfDays":3,"adjustmentHalfDays":0,"bookedHalfDays":21,"plannedHalfDays":10,"availableHalfDays":42,"availableAfterPlannedHalfDays":32,"future":1}"#

    static let absencesJSON = #"""
    [{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","version":2,"kind":"vacation","startDate":"2026-12-21","endDate":"2026-12-23","halfDayStart":false,"halfDayEnd":true,"status":"planned","note":null,"countedHalfDays":5},
     {"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","version":1,"kind":"sick","startDate":"2026-03-02","endDate":"2026-03-03","status":"taken","countedHalfDays":0},
     {"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","version":1,"kind":"vacation","startDate":"2026-05-04","endDate":"2026-05-05","status":"cancelled","countedHalfDays":0},
     {"id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","version":1,"kind":"future_kind","startDate":"2026-06-01","endDate":"2026-06-01","status":"surprise","countedHalfDays":0}]
    """#

    @Test func decodesBalanceAndLenientEnums() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/vacation/balance", body: Self.balanceJSON)
        transport.enqueue("GET /api/v1/absences", body: Self.absencesJSON)
        let store = PlanningStore(client: Fixtures.client(transport), calendar: calendar, now: now)
        #expect(store.year == 2026)
        await store.load()
        #expect(store.balance?.availableHalfDays == 42)
        // cancelled is hidden, sorted by start date, unknown values do not break decoding
        #expect(store.absences.map(\.startDate) == ["2026-03-02", "2026-06-01", "2026-12-21"])
        #expect(store.absences[1].kind == .unknown && store.absences[1].status == .unknown)
        #expect(store.error == nil)
        #expect(transport.requests(matching: "GET /api/v1/absences").last?.url?.query == "from=2026-01-01&to=2026-12-31")
        #expect(transport.requests(matching: "GET /api/v1/vacation/balance").last?.url?.query == "year=2026")
    }

    @Test func shiftYearLoadsOtherYear() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/vacation/balance", body: Self.balanceJSON)
        transport.enqueue("GET /api/v1/absences", body: "[]")
        let store = PlanningStore(client: Fixtures.client(transport), calendar: calendar, now: now)
        await store.shiftYears(1)
        #expect(store.year == 2027)
        #expect(transport.requests(matching: "GET /api/v1/absences").last?.url?.query == "from=2027-01-01&to=2027-12-31")
    }

    @Test func moduleDisabledSurfacesError() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/vacation/balance", status: 404, body: #"{"error":{"code":"module_disabled","message":"x"}}"#)
        transport.enqueue("GET /api/v1/absences", status: 404, body: #"{"error":{"code":"module_disabled","message":"x"}}"#)
        let store = PlanningStore(client: Fixtures.client(transport), calendar: calendar, now: now)
        await store.load()
        #expect(store.error?.knownCode == .moduleDisabled)
        #expect(store.balance == nil)
    }

    @Test func appModelCreatesPlanningStoreOnlyWhenModuleIsOn() async {
        func signIn(modules: String) async -> AppModel {
            let transport = MockTransport()
            transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
            transport.enqueue("GET /api/v1/modules", body: modules)
            transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
            let model = AppModel(auth: AuthService(secrets: InMemorySecretStore(), transport: transport))
            await model.signInWithSessionCookie(serverInput: "http://localhost:18090", cookie: "c")
            return model
        }
        let off = await signIn(modules: Fixtures.modulesJSON) // planning effective=false
        #expect(off.planning == nil)
        let on = await signIn(modules: #"[{"key":"planning","serverEnabled":true,"accountEnabled":true,"effective":true,"lockedByOperator":false}]"#)
        #expect(on.planning != nil)
    }

    @Test func halfDayFormat() {
        #expect(HalfDayFormat.days(61) == "30,5")
        #expect(HalfDayFormat.days(60) == "30")
        #expect(HalfDayFormat.days(1) == "0,5")
        #expect(HalfDayFormat.days(-3) == "-1,5")
    }
}

@Suite struct TimerCommandTests {
    @Test func startReportsAlreadyRunningWithoutPosting() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        let outcome = try await TimerCommand.start(client: Fixtures.client(transport))
        guard case .alreadyRunning = outcome else { Issue.record("expected alreadyRunning, got \(outcome)"); return }
        #expect(transport.requests(matching: "POST /api/v1/time/timer/start").isEmpty)
    }

    @Test func startPostsWhenIdleAndStopOnlyWhenRunning() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/timer", body: "null")
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        guard case .started = try await TimerCommand.start(client: Fixtures.client(transport)) else { Issue.record("expected started"); return }
        #expect(try await TimerCommand.stop(client: Fixtures.client(transport)) == .notRunning)
        #expect(transport.requests(matching: "POST /api/v1/time/timer/stop").isEmpty)

        let running = MockTransport()
        running.enqueue("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        running.enqueue("POST /api/v1/time/timer/stop", body: Fixtures.closedSegmentJSON)
        guard case .stopped = try await TimerCommand.stop(client: Fixtures.client(running)) else { Issue.record("expected stopped"); return }
    }
}
