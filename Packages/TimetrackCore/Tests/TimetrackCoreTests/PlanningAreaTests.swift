import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// PL1: multi-week plan overview and plan shares.

private enum PL1Fixtures {
    static func planDay(_ date: String, weekday: Int, target: Int = 27720, planned: String = "null", blocked: String = "null", plan: Bool = false) -> String {
        let planJSON = plan ? #"{"date":"\#(date)","mode":"office","placeId":null,"note":null,"plannedStart":"08:00","plannedEnd":"16:00","plannedBreakMinutes":30,"plannedSeconds":27000}"# : "null"
        return #"{"date":"\#(date)","weekday":\#(weekday),"targetSeconds":\#(target),"plannedSeconds":\#(planned),"blockedBy":\#(blocked),"plan":\#(planJSON)}"#
    }

    /// `monday` is a real Monday; `plannedWorkdays` of the five work days get a plan, `blockedOn` is a weekday index (0-based) held by a holiday.
    static func planWeek(label: String, monday: String, plannedWorkdays: Int, blockedOn: Int? = nil) -> String {
        var days: [String] = []
        for index in 0..<7 {
            let date = LocalDays.adding(index, to: monday)!
            let work = index < 5
            let blocked = blockedOn == index
            days.append(planDay(date, weekday: index + 1, target: work ? (blocked ? 0 : 27720) : 0,
                                planned: blocked ? "0" : (work && index < plannedWorkdays ? "27000" : "null"),
                                blocked: blocked ? #""holiday""# : "null",
                                plan: work && index < plannedWorkdays))
        }
        let sunday = LocalDays.adding(6, to: monday)!
        let planned = 27000 * min(plannedWorkdays, 5)
        let target = 27720 * (blockedOn == nil ? 5 : 4)
        return #"{"week":"\#(label)","from":"\#(monday)","to":"\#(sunday)","days":[\#(days.joined(separator: ","))],"totals":{"targetSeconds":\#(target),"plannedSeconds":\#(planned),"differenceSeconds":\#(planned - target)}}"#
    }

    static let shareA = #"{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","recipientHandle":"ben","scopes":{"plan":true,"actual":false,"vacation":false},"createdAt":"2026-10-01T08:00:00Z"}"#
    static let shareAUpdated = #"{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","recipientHandle":"ben","scopes":{"plan":true,"actual":true,"vacation":false},"createdAt":"2026-10-01T08:00:00.123Z"}"#
    static let incoming = #"[{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","ownerDisplayName":"Ben Beispiel","scopes":{"plan":true,"vacation":true}}]"#
    static let sharedView = #"""
    {"plan":[{"date":"2026-10-26","mode":"home","plannedStart":"08:00","plannedEnd":"16:00","plannedBreakMinutes":30,"plannedSeconds":27000},{"date":"2026-10-27","mode":"future_mode"}],
     "vacation":[{"startDate":"2026-11-02","endDate":"2026-11-06"}]}
    """#
    static let sharedActual = #"{"actual":[{"date":"2026-10-26","evaluatedStart":"2026-10-26T07:00:00Z","evaluatedEnd":"2026-10-26T15:30:00.500Z","evaluatedWorkSeconds":28800},{"date":"2026-10-27","evaluatedStart":null,"evaluatedEnd":null,"evaluatedWorkSeconds":0}]}"#
}

@Suite struct PlanHorizonLogicTests {
    private func decode(_ json: String) throws -> PlanWeek { try JSONCoding.makeDecoder().decode(PlanWeek.self, from: Data(json.utf8)) }

    @Test func coverageUnplannedPartialComplete() throws {
        let none = PlanHorizon.row(for: try decode(PL1Fixtures.planWeek(label: "2026-W44", monday: "2026-10-26", plannedWorkdays: 0)))
        #expect(none.coverage == .unplanned && none.plannableDays == 5 && none.plannedDays == 0 && none.openDays == 5)
        let part = PlanHorizon.row(for: try decode(PL1Fixtures.planWeek(label: "2026-W44", monday: "2026-10-26", plannedWorkdays: 3)))
        #expect(part.coverage == .partial && part.openDays == 2 && part.plannedSeconds == 81_000)
        let full = PlanHorizon.row(for: try decode(PL1Fixtures.planWeek(label: "2026-W44", monday: "2026-10-26", plannedWorkdays: 5)))
        #expect(full.coverage == .complete && full.weekNumber == 44 && full.sunday == "2026-11-01")
        #expect(full.differenceSeconds == 135_000 - 138_600)
    }

    @Test func blockedDaysAreNotPlannable() throws {
        let row = PlanHorizon.row(for: try decode(PL1Fixtures.planWeek(label: "2026-W44", monday: "2026-10-26", plannedWorkdays: 5, blockedOn: 1)))
        // Tuesday is a holiday: it neither needs a plan nor counts as open.
        #expect(row.blockedDays == 1)
        #expect(row.plannableDays == 4)
    }

    @Test func mondaysStartAtCurrentWeek() {
        #expect(PlanHorizon.mondays(from: "2026-10-21", count: 3) == ["2026-10-19", "2026-10-26", "2026-11-02"])
        #expect(PlanHorizon.mondays(from: "2026-10-21", count: 0).isEmpty)
        #expect(PlanHorizon.mondays(from: "2026-12-30", count: 2) == ["2026-12-28", "2027-01-04"])
    }
}

@Suite struct SharingDecodingTests {
    private let decoder = JSONCoding.makeDecoder()

    @Test func sharesDecodeWithMissingScopesAsOff() throws {
        let share = try decoder.decode(Share.self, from: Data(PL1Fixtures.shareA.utf8))
        #expect(share.recipientHandle == "ben" && share.scopes == ShareScopes(plan: true) && share.scopes.enabled == [.plan])
        let incoming = try decoder.decode([IncomingShare].self, from: Data(PL1Fixtures.incoming.utf8))
        #expect(incoming[0].scopes.plan && incoming[0].scopes.vacation && !incoming[0].scopes.actual)
    }

    @Test func sharedViewKeepsMissingScopesNilAndUnknownModes() throws {
        let view = try decoder.decode(SharedView.self, from: Data(PL1Fixtures.sharedView.utf8))
        #expect(view.actual == nil && view.plan?.count == 2 && view.vacation?.count == 1)
        #expect(view.plan?[0].mode == .home && view.plan?[1].mode == .unknown && view.plan?[1].plannedSeconds == nil)
        let actual = try decoder.decode(SharedView.self, from: Data(PL1Fixtures.sharedActual.utf8))
        #expect(actual.plan == nil && actual.actual?[0].evaluatedWorkSeconds == 28800 && actual.actual?[0].evaluatedEnd != nil && actual.actual?[1].evaluatedStart == nil)
        #expect(try decoder.decode(SharedView.self, from: Data("{}".utf8)).isEmpty)
    }

    @Test func formChecks() {
        let plan = ShareScopes(plan: true)
        #expect(SharePolicy.problem(handle: "  ", scopes: plan, ownHandle: "anna") == .handleMissing)
        #expect(SharePolicy.problem(handle: "Anna", scopes: plan, ownHandle: "anna") == .toSelf)
        #expect(SharePolicy.problem(handle: "ben", scopes: ShareScopes(), ownHandle: "anna") == .noScope)
        #expect(SharePolicy.problem(handle: " ben ", scopes: plan, ownHandle: "anna") == nil)
    }

    @Test func errorCodesHaveGermanText() {
        for code in ["recipient_not_found", "share_exists", "cannot_share_with_self"] {
            let text = TimetrackError.api(status: 400, code: code, message: "x").germanDescription
            #expect(!text.hasPrefix("error."), "missing text for \(code)")
        }
    }
}

@Suite @MainActor struct PlanningAreaStoreTests {
    private let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    @Test func horizonLoadsWeeksInOrderAndSurvivesOneFailure() async {
        let transport = MockTransport()
        let monday = PlanHorizonStore(client: Fixtures.client(transport), calendar: calendar, weekCount: 3).currentMonday
        let labels = PlanHorizon.mondays(from: monday, count: 3).map { IsoWeek.label(containing: $0)! }
        transport.enqueue("GET /api/v1/plan/weeks/\(labels[0])", body: PL1Fixtures.planWeek(label: labels[0], monday: monday, plannedWorkdays: 5))
        transport.enqueue("GET /api/v1/plan/weeks/\(labels[1])", status: 500, body: "{}")
        transport.enqueue("GET /api/v1/plan/weeks/\(labels[2])", body: PL1Fixtures.planWeek(label: labels[2], monday: PlanHorizon.mondays(from: monday, count: 3)[2], plannedWorkdays: 0))
        let store = PlanHorizonStore(client: Fixtures.client(transport), calendar: calendar, weekCount: 3)
        await store.load()
        #expect(store.entries.count == 3 && !store.isUnavailable && store.error == nil)
        if case .loaded(let first) = store.entries[0] { #expect(first.coverage == .complete) } else { Issue.record("first week should load") }
        if case .failed(_, let label) = store.entries[1] { #expect(label == labels[1]) } else { Issue.record("second week should fail") }
        #expect(store.openWeeks == 1)
    }

    @Test func horizonIsUnavailableWhenEveryWeekIs404() async {
        let transport = MockTransport()
        let store = PlanHorizonStore(client: Fixtures.client(transport), calendar: calendar, weekCount: 2)
        for monday in PlanHorizon.mondays(from: store.today, count: 2) {
            transport.enqueue("GET /api/v1/plan/weeks/\(IsoWeek.label(containing: monday)!)", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        }
        await store.load()
        #expect(store.isUnavailable && store.entries.isEmpty)
    }

    @Test func sharingCreatesTogglesAndRevokes() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/shares", body: "[]")
        transport.enqueue("GET /api/v1/shares/incoming", body: PL1Fixtures.incoming)
        transport.enqueue("POST /api/v1/shares", status: 201, body: PL1Fixtures.shareA)
        transport.enqueue("GET /api/v1/shares", body: "[\(PL1Fixtures.shareA)]")
        transport.enqueue("PATCH /api/v1/shares/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", body: PL1Fixtures.shareAUpdated)
        transport.enqueue("DELETE /api/v1/shares/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", status: 204)
        let store = SharingStore(client: Fixtures.client(transport), calendar: calendar, ownHandle: "anna")
        var outcomes: [StoreOutcome] = []
        store.onOutcome = { outcomes.append($0) }
        await store.load()
        #expect(store.outgoing.isEmpty && store.incoming.count == 1)
        // Local checks send nothing.
        #expect(await store.create(handle: "anna", scopes: ShareScopes(plan: true)) == false && store.formProblem == .toSelf)
        #expect(await store.create(handle: "ben", scopes: ShareScopes()) == false && store.formProblem == .noScope)
        #expect(transport.requests(matching: "POST /api/v1/shares").isEmpty)
        #expect(await store.create(handle: " ben ", scopes: ShareScopes(plan: true)))
        let body = transport.requests(matching: "POST /api/v1/shares").first?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(body?["recipientHandle"] as? String == "ben" && (body?["scopes"] as? [String: Bool])?["plan"] == true)
        #expect(store.outgoing.count == 1)
        await store.setScope(.actual, to: true, of: store.outgoing[0])
        #expect(store.outgoing[0].scopes == ShareScopes(plan: true, actual: true))
        let patch = transport.requests(matching: "PATCH /api/v1/shares/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa").first?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect((patch?["scopes"] as? [String: Bool])?["actual"] == true)
        #expect(await store.revoke(store.outgoing[0]) && store.outgoing.isEmpty)
        #expect(outcomes == [.saved, .saved, .saved])
    }

    @Test func serverErrorOnCreateIsKeptAndShown() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/shares", status: 409, body: #"{"error":{"code":"share_exists","message":"x"}}"#)
        let store = SharingStore(client: Fixtures.client(transport), calendar: calendar, ownHandle: "anna")
        var outcomes: [StoreOutcome] = []
        store.onOutcome = { outcomes.append($0) }
        #expect(await store.create(handle: "ben", scopes: ShareScopes(vacation: true)) == false)
        #expect(store.error?.knownCode == .shareExists && outcomes == [.failed])
    }

    @Test func incomingViewLoadsAndRevokedShareDisappears() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/shares", body: "[]")
        transport.enqueue("GET /api/v1/shares/incoming", body: PL1Fixtures.incoming)
        transport.enqueue("GET /api/v1/shares/incoming/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/view", body: PL1Fixtures.sharedView)
        transport.enqueue("GET /api/v1/shares/incoming/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/view", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let store = SharingStore(client: Fixtures.client(transport), calendar: calendar, ownHandle: "anna")
        await store.load()
        await store.select(store.incoming[0])
        #expect(store.view?.plan?.count == 2 && !store.viewGone)
        let request = transport.requests(matching: "GET /api/v1/shares/incoming/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/view").first
        #expect(request?.url?.query?.contains("from=") == true && request?.url?.query?.contains("to=") == true)
        await store.loadView()
        #expect(store.viewGone && store.selected == nil && store.incoming.isEmpty && store.view == nil)
    }

    @Test func invalidRangeSendsNothing() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/shares", body: "[]")
        transport.enqueue("GET /api/v1/shares/incoming", body: PL1Fixtures.incoming)
        let store = SharingStore(client: Fixtures.client(transport), calendar: calendar, ownHandle: nil)
        await store.load()
        store.from = "2026-11-10"
        store.to = "2026-11-01"
        await store.select(store.incoming[0])
        #expect(store.rangeInvalid && transport.requests(matching: "GET /api/v1/shares/incoming/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/view").isEmpty)
    }
}
