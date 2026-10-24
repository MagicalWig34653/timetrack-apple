import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// WM2: new work model version, ending, account adjustments and statistics.
@MainActor
@Suite struct WorkModelStatsTests {
    static let idA = "33333333-3333-4333-8333-333333333333"
    static let idB = "44444444-4444-4444-8444-444444444444"

    static func modelJSON(id: String, from: String, to: String?) -> String {
        #"{"id":"\#(id)","validFrom":"\#(from)","validTo":\#(to.map { "\"\($0)\"" } ?? "null"),"timezone":"Europe/Berlin","weeklyTargetSeconds":138600,"workdays":[1,2,3,4,5],"travelCountsAsWork":true,"roundingEnabled":true,"roundingMinutes":15,"schoolFullDayThresholdSeconds":10800,"schoolCreditSeconds":null,"dayBoundaryMinutes":0,"fixedBreaks":[],"version":1}"#
    }

    func json(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func decode(_ json: String) throws -> WorkModel { try JSONCoding.makeDecoder().decode(WorkModel.self, from: Data(json.utf8)) }

    // MARK: Work model timeline

    @Test func newVersionEndsTheOpenPredecessorTheDayBefore() throws {
        let open = try decode(Self.modelJSON(id: Self.idA, from: "2026-01-01", to: nil))
        #expect([WorkModel]().checkNewVersion(validFrom: "2026-01-01") == .ok(endsPredecessor: nil, predecessorEnd: nil))
        #expect([open].checkNewVersion(validFrom: "2026-11-01") == .ok(endsPredecessor: open, predecessorEnd: "2026-10-31"))
        #expect([open].checkNewVersion(validFrom: "2026-01-01") == .overlaps(open), "same start day")
        #expect([open].checkNewVersion(validFrom: "2025-12-31") == .overlaps(open), "before the newest start")
        #expect([open].checkNewVersion(validFrom: "2026-03-01") == .ok(endsPredecessor: open, predecessorEnd: "2026-02-28"))
    }

    @Test func closedPredecessorOnlyBlocksOverlap() throws {
        let closed = try decode(Self.modelJSON(id: Self.idA, from: "2026-01-01", to: "2026-06-30"))
        #expect([closed].checkNewVersion(validFrom: "2026-06-30") == .overlaps(closed))
        #expect([closed].checkNewVersion(validFrom: "2026-07-01") == .ok(endsPredecessor: nil, predecessorEnd: nil), "a gap is allowed")
        #expect([closed].checkNewVersion(validFrom: "2026-09-01") == .ok(endsPredecessor: nil, predecessorEnd: nil))
    }

    @Test func endingChecksStartAndLaterVersions() throws {
        let first = try decode(Self.modelJSON(id: Self.idA, from: "2026-01-01", to: "2026-06-30"))
        let second = try decode(Self.modelJSON(id: Self.idB, from: "2026-07-01", to: nil))
        let all = [first, second]
        #expect(all.endable == [second])
        #expect(all.checkEnd(of: second, on: "2026-07-01") == nil, "last valid day may equal the start")
        #expect(all.checkEnd(of: second, on: "2026-06-30") == .beforeStart)
        #expect(all.checkEnd(of: second, on: "2026-02-30") == .invalidDate)
        #expect(all.checkEnd(of: first, on: "2026-07-01") == .overlapsLater(second))
        #expect(all.checkEnd(of: first, on: "2026-06-15") == nil)
    }

    @Test func timelineGapsAreReportedBetweenVersions() throws {
        let a = try decode(Self.modelJSON(id: Self.idA, from: "2026-01-01", to: "2026-06-30"))
        let b = try decode(Self.modelJSON(id: Self.idB, from: "2026-07-01", to: "2026-08-31"))
        let c = try decode(Self.modelJSON(id: "55555555-5555-4555-8555-555555555555", from: "2026-10-01", to: nil))
        let gaps = [c, a, b].gaps
        #expect(gaps.count == 1 && gaps[c.id]?.from == "2026-09-01" && gaps[c.id]?.to == "2026-09-30", "adjacent versions have no gap")
    }

    @Test func newVersionFormStartsOpenEnded() throws {
        let base = try decode(Self.modelJSON(id: Self.idA, from: "2026-01-01", to: "2026-06-30"))
        let form = WorkModelForm(basedOn: base, startingOn: "2026-09-01")
        #expect(form.validFrom == "2026-09-01" && form.validTo.isEmpty && form.weeklyTarget == "38:30")
        let blank = WorkModelForm(validFrom: "2026-09-01")
        guard case .success(let input) = blank.build() else { Issue.record("valid defaults"); return }
        #expect(input.weeklyTargetSeconds == 138600 && input.workdays == [1, 2, 3, 4, 5] && input.roundingMinutes == 15)
    }

    @Test func createSendsPostAndRefreshesTheList() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok"))
        let open = Self.modelJSON(id: Self.idA, from: "2026-01-01", to: nil)
        transport.enqueue("GET /api/v1/work-models", body: "[\(open)]")
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        let store = WorkModelStore(client: client)
        await store.load()
        var saved = 0
        store.onSaved = { saved += 1 }

        var form = WorkModelForm(basedOn: try #require(store.models.first), startingOn: "2026-01-01")
        #expect(await store.create(form: form) == nil, "same start day is rejected locally")
        #expect(store.error?.knownCode == .modelOverlap && transport.requests(matching: "POST /api/v1/work-models").isEmpty)

        form.validFrom = "2026-11-01"
        form.weeklyTarget = "35:00"
        transport.set("POST /api/v1/work-models", status: 201, body: Self.modelJSON(id: Self.idB, from: "2026-11-01", to: nil))
        transport.set("GET /api/v1/work-models", body: "[\(Self.modelJSON(id: Self.idA, from: "2026-01-01", to: "2026-10-31")),\(Self.modelJSON(id: Self.idB, from: "2026-11-01", to: nil))]")
        #expect(await store.create(form: form) != nil)
        let post = transport.requests(matching: "POST /api/v1/work-models")
        #expect(post.count == 1 && post[0].value(forHTTPHeaderField: "X-CSRF-Token") == "tok")
        let body = try json(post[0])
        #expect(body["validFrom"] as? String == "2026-11-01" && body["weeklyTargetSeconds"] as? Int == 126000 && body["validTo"] is NSNull)
        #expect(store.models.count == 2 && saved == 1 && store.error == nil)
    }

    @Test func endSendsPatchWithValidTo() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok"))
        transport.enqueue("GET /api/v1/work-models", body: "[\(Self.modelJSON(id: Self.idA, from: "2026-01-01", to: nil))]")
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        let store = WorkModelStore(client: client)
        await store.load()
        let model = try #require(store.models.first)

        #expect(await store.end(model, on: "2025-12-31") == nil && store.error?.status == 400)
        #expect(transport.requests(matching: "PATCH /api/v1/work-models/\(Self.idA)").isEmpty)

        transport.set("PATCH /api/v1/work-models/\(Self.idA)", body: Self.modelJSON(id: Self.idA, from: "2026-01-01", to: "2026-08-31"))
        transport.set("GET /api/v1/work-models", body: "[\(Self.modelJSON(id: Self.idA, from: "2026-01-01", to: "2026-08-31"))]")
        #expect(await store.end(model, on: "2026-08-31") != nil)
        let patch = transport.requests(matching: "PATCH /api/v1/work-models/\(Self.idA)")
        let body = try json(try #require(patch.first))
        #expect(patch.count == 1 && body["validTo"] as? String == "2026-08-31" && body.count == 1)
        #expect(store.models.first?.validTo == "2026-08-31" && store.error == nil)
    }

    // MARK: Account adjustments

    @Test func adjustmentFormValidates() {
        var form = AccountAdjustmentForm(kind: .correction, date: "2026-10-20", value: "-2:30", reason: " Zeitausgleich ")
        guard case .success(let input) = form.build() else { Issue.record("valid"); return }
        #expect(input == AccountAdjustmentInput(kind: .correction, date: "2026-10-20", seconds: -9000, reason: "Zeitausgleich"))
        form.value = "1,5"; form.date = "2026-13-01"; form.reason = "  "
        guard case .failure(let errors) = form.build() else { Issue.record("invalid"); return }
        #expect(errors.fields == [.date, .value, .reason])
        form.reason = String(repeating: "x", count: 201)
        if case .failure(let long) = form.build() { #expect(long.fields.contains(.reason)) }
    }

    @Test func bookingPostsAndUpdatesTheAccount() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok"))
        transport.enqueue("GET /api/v1/time/account", body: #"{"asOf":"2026-10-24","accountStart":null,"balanceSeconds":0,"openingSeconds":0,"adjustmentSeconds":0,"provisional":false}"#)
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        let store = TimeAccountStore(client: client)
        await store.load()
        #expect(store.canSetOpening)
        transport.set("POST /api/v1/time/account/adjustments", status: 201, body: #"{"asOf":"2026-10-24","accountStart":"2026-10-01","balanceSeconds":3600,"openingSeconds":3600,"adjustmentSeconds":0,"provisional":false}"#)
        #expect(await store.book(AccountAdjustmentForm(kind: .opening, date: "2026-10-01", value: "1:00", reason: "Anfangsstand")))
        let post = transport.requests(matching: "POST /api/v1/time/account/adjustments")
        let body = try json(try #require(post.first))
        #expect(body["kind"] as? String == "opening" && body["seconds"] as? Int == 3600 && body["reason"] as? String == "Anfangsstand")
        #expect(store.account?.balanceSeconds == 3600)

        transport.set("POST /api/v1/time/account/adjustments", status: 409, body: #"{"error":{"code":"conflict","message":"x"}}"#)
        #expect(await store.book(AccountAdjustmentForm(kind: .opening, date: "2026-10-02", value: "2:00", reason: "x")) == false)
        #expect(store.error?.status == 409)
        #expect(await store.book(AccountAdjustmentForm(kind: .correction, date: "2026-10-02", value: "", reason: "x")) == false, "invalid forms send nothing")
    }

    // MARK: Statistics

    static let statisticsJSON = """
    {"from":"2026-10-01","to":"2026-10-31","granularity":"week","basis":"evaluated","timezone":"Europe/Berlin","accountStart":"2026-09-01","openingBalanceSeconds":3600,
     "buckets":[
      {"label":"2026-W40","from":"2026-10-01","to":"2026-10-04","days":4,"targetSeconds":100800,"targetToDateSeconds":100800,"actualSeconds":90000,"creditSeconds":10800,"evaluatedWorkSeconds":90000,"rawWorkSeconds":91800,"roundingSeconds":900,"deltaSeconds":0,"overtimeSeconds":0,"undertimeSeconds":0,"balanceSeconds":3600,"balanceAsOf":"2026-10-04","kindSeconds":{"work":86400,"school":10800,"travel":3600},"absences":{"vacation":0,"sick":0,"excused":0,"holiday":0,"school":1},"absenceDays":0,"breakSeconds":3600,"breakDeductionSeconds":1800,"workDays":3,"provisional":false},
      {"label":"2026-W41","from":"2026-10-05","to":"2026-10-11","days":7,"targetSeconds":138600,"targetToDateSeconds":138600,"actualSeconds":144000,"creditSeconds":0,"evaluatedWorkSeconds":144000,"rawWorkSeconds":145000,"roundingSeconds":0,"deltaSeconds":5400,"overtimeSeconds":5400,"undertimeSeconds":0,"balanceSeconds":9000,"balanceAsOf":"2026-10-11","kindSeconds":{"work":144000,"school":0,"travel":0},"absences":{"vacation":0.5,"sick":1,"excused":0,"holiday":0,"school":0},"absenceDays":1.5,"breakSeconds":0,"breakDeductionSeconds":0,"workDays":5,"provisional":false},
      {"label":"2026-W44","from":"2026-10-26","to":"2026-10-31","days":6,"targetSeconds":138600,"targetToDateSeconds":0,"actualSeconds":0,"creditSeconds":0,"evaluatedWorkSeconds":0,"rawWorkSeconds":0,"roundingSeconds":0,"deltaSeconds":0,"overtimeSeconds":0,"undertimeSeconds":0,"balanceSeconds":null,"balanceAsOf":null,"kindSeconds":{"work":0,"school":0,"travel":0},"absences":{"vacation":0,"sick":0,"excused":0,"holiday":0,"school":0},"absenceDays":0,"breakSeconds":0,"breakDeductionSeconds":0,"workDays":0,"provisional":false}
     ],
     "totals":{"targetSeconds":378000,"targetToDateSeconds":239400,"actualSeconds":234000,"creditSeconds":10800,"deltaSeconds":5400,"overtimeSeconds":5400,"undertimeSeconds":0,"breakSeconds":3600,"breakDeductionSeconds":1800,"kindSeconds":{"work":230400,"school":10800,"travel":3600},"absenceDays":1.5}}
    """

    @Test func statisticsDecodeAndDeriveChartData() throws {
        let stats = try JSONCoding.makeDecoder().decode(TimeStatistics.self, from: Data(Self.statisticsJSON.utf8))
        #expect(stats.granularity == .week && stats.basis == .evaluated && stats.buckets.count == 3 && stats.buckets[2].balanceSeconds == nil)
        let data = StatisticsChartData(statistics: stats, today: "2026-10-24")
        // Balance: baseline (day before `from`) plus the two buckets that have a balance.
        #expect(data.balance.map(\.seconds) == [3600, 3600, 9000] && data.balance.first?.day == "2026-09-30" && data.balanceChange == 5400)
        #expect(data.hasBalance)
        // The last bucket starts after today: no performance point.
        #expect(data.performance.map(\.id) == ["2026-W40", "2026-W41"])
        #expect(data.performance[0].workedSeconds == 100800 && data.performance[0].targetSeconds == 100800)
        #expect(data.kindSlices.map(\.kind) == [.work, .travel, .school])
        #expect(abs(data.kindSlices.map(\.share).reduce(0, +) - 1) < 0.0001)
        #expect(data.absenceSeries.count == 3 && data.absenceTotals.map(\.kind) == [.vacation, .sick, .school])
        #expect(data.absenceTotals.first { $0.kind == .vacation }?.days == 0.5)
        #expect(data.hasBreaks && data.breaks[0].actualSeconds == 3600 && data.breaks[0].fixedSeconds == 1800)
        #expect(stats.buckets[0].shortTitle(granularity: .week) == "KW 40" && stats.buckets[1].shortTitle(granularity: .day) == "5.10.")
        #expect(stats.buckets[0].shortTitle(granularity: .month) == "Okt" && stats.buckets[0].longTitle(granularity: .month) == "Oktober 2026")
    }

    @Test func selectionFindsTheBucketAndBalancePoint() throws {
        let stats = try JSONCoding.makeDecoder().decode(TimeStatistics.self, from: Data(Self.statisticsJSON.utf8))
        let data = StatisticsChartData(statistics: stats, today: "2026-10-24")
        #expect(data.bucket(near: StatisticsBucket.noonUTC("2026-10-08"))?.label == "2026-W41")
        #expect(data.bucket(near: StatisticsBucket.noonUTC("2026-10-31"))?.label == "2026-W44")
        #expect(data.bucket(near: StatisticsBucket.noonUTC("2026-10-15"))?.label == "2026-W41", "a gap between buckets snaps to the nearest start")
        #expect(data.balancePoint(near: StatisticsBucket.noonUTC("2026-10-10"))?.seconds == 9000)
    }

    @Test func emptyRangeHasNoCharts() throws {
        let empty = TimeStatistics(from: "2026-10-01", to: "2026-10-07", granularity: .day, basis: .raw, buckets: [], totals: StatisticsTotals())
        let data = StatisticsChartData(statistics: empty, today: "2026-10-24")
        #expect(!data.hasAnyTime && !data.hasBalance && data.balance.isEmpty && data.kindSlices.isEmpty && data.balanceChange == nil)
    }

    @Test func rangePresetsStayWithinTheServerLimit() {
        let today = "2026-10-24"
        #expect(StatisticsRangePreset.last4Weeks.resolve(today: today) == ("2026-09-27", today))
        #expect(StatisticsRangePreset.thisYear.resolve(today: today) == ("2026-01-01", today))
        #expect(StatisticsRangePreset.sinceStart.resolve(today: today, accountStart: "2020-01-01").from == LocalDays.adding(-1099, to: today))
        #expect(StatisticsRangePreset.sinceStart.resolve(today: today, accountStart: "2026-09-01").from == "2026-09-01")
        #expect(StatisticsRangePreset.custom.resolve(today: today, custom: ("2026-10-10", "2026-10-01")) == ("2026-10-01", "2026-10-10"), "swapped bounds are fixed")
        for preset in StatisticsRangePreset.allCases {
            let range = preset.resolve(today: today, accountStart: "2000-01-01", custom: ("2000-01-01", today))
            #expect((LocalDays.daysBetween(range.from, range.to) ?? 0) < StatisticsGranularity.maxDays)
        }
    }

    @Test func granularityFollowsTheRange() {
        #expect(StatisticsGranularity.allowed(forDays: 28) == [.day, .week, .month])
        #expect(StatisticsGranularity.allowed(forDays: 91) == [.day, .week, .month])
        #expect(StatisticsGranularity.allowed(forDays: 94) == [.week, .month])
        #expect(StatisticsGranularity.allowed(forDays: 5) == [.day])
        #expect(StatisticsGranularity.resolved(.day, forDays: 365) == .week, "day buckets are too fine for a year")
        #expect(StatisticsGranularity.resolved(.month, forDays: 10) == .week || StatisticsGranularity.resolved(.month, forDays: 10) == .day)
        #expect(StatisticsGranularity.resolved(.week, forDays: 60) == .week)
    }

    @Test func storeLoadsWithTheChosenSettings() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("GET /api/v1/time/statistics", body: Self.statisticsJSON)
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        let store = StatisticsStore(client: client, calendar: DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!))
        store.select(.last12Months)
        #expect(store.granularity == .month)
        store.basis = .raw
        await store.reload()
        let request = try #require(transport.requests(matching: "GET /api/v1/time/statistics").first)
        let url = try #require(request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query["granularity"] == "month" && query["basis"] == "raw" && query["from"] == store.range.from && query["to"] == store.range.to)
        #expect(store.data != nil && store.accountStart == "2026-09-01")
    }

    @Test func olderServerMeansUnsupportedNotAnError() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("GET /api/v1/time/statistics", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        let store = StatisticsStore(client: client, calendar: DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!))
        await store.reload()
        #expect(store.state == .unsupported)
        transport.set("GET /api/v1/time/statistics", status: 400, body: #"{"error":{"code":"range_too_large","message":"x"}}"#)
        await store.reload()
        guard case .failed(let error) = store.state else { Issue.record("failed"); return }
        #expect(error.knownCode == .rangeTooLarge)
    }
}
