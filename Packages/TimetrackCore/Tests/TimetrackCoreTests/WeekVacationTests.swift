import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

private enum WeekFixtures {
    // Example of docs/handoffs/V2-backend.md (contract 0.22.0).
    static let suggestions = #"""
    {"from":"2026-05-01","to":"2026-07-31",
     "budget":{"entitlementDays":30,"takenDays":2,"plannedDays":1,"remainingDays":27},
     "suggestions":[
      {"id":"6aca3cad71036dfc","kind":"bridge","start":"2026-05-14","end":"2026-05-17","vacationDates":["2026-05-15"],"vacationDaysNeeded":1,
       "totalDaysOff":4,"efficiency":4,"holidays":[{"date":"2026-05-14","name":"Christi Himmelfahrt"}],"schoolHolidays":[],
       "conflicts":[{"date":"2026-05-15","type":"school_day"}],"fitsBudget":true,"remainingAfter":26},
      {"id":"3a8bfd511a66c0fb","kind":"bridge","start":"2026-05-22","end":"2026-05-25","vacationDates":["2026-05-22"],"vacationDaysNeeded":1,
       "totalDaysOff":4,"efficiency":4,"holidays":[{"date":"2026-05-25","name":"Pfingstmontag"}],"schoolHolidays":[],
       "conflicts":[{"date":"2026-05-22","type":"absence"},{"date":"2026-05-22","type":"plan"}],"fitsBudget":true,"remainingAfter":26.5},
      {"id":"ffffffffffffffff","kind":"future_kind","start":"2026-06-01","end":"2026-06-07","vacationDates":["2026-06-01","2026-06-02","2026-06-04"],"vacationDaysNeeded":3,
       "totalDaysOff":7,"efficiency":2.33,"holidays":[],"schoolHolidays":[{"startDate":"2026-06-01","endDate":"2026-06-07","name":"Ferien"}],
       "conflicts":[{"date":"2026-06-03","type":"already_vacation"},{"date":"2026-06-04","type":"surprise"}],"fitsBudget":false,"remainingAfter":-0.5}
     ]}
    """#

    static func weekDay(_ date: String, weekday: Int, mark: String = "work", planned: String = "null", future: Bool = false, balance: String = "0") -> String {
        #"{"date":"\#(date)","weekday":\#(weekday),"mark":"\#(mark)","markSource":"none","targetSeconds":27720,"plannedSeconds":\#(planned),"planMode":null,"workSeconds":27000,"creditSeconds":0,"rawWorkSeconds":27300,"breakSeconds":1800,"breakDeductionSeconds":0,"travelSeconds":0,"schoolSeconds":0,"balanceSeconds":\#(balance),"firstStart":"2026-10-26T06:00:00Z","lastEnd":"2026-10-26T14:30:00.500Z","segmentsCount":2,"absences":[{"kind":"vacation","status":"planned","halfDay":true}],"provisional":false,"isToday":false,"isFuture":\#(future),"newField":1}"#
    }

    static let timeWeek = #"""
    {"week":"2026-W44","from":"2026-10-26","to":"2026-11-01","days":[
    \#(weekDay("2026-10-26", weekday: 1)),\#(weekDay("2026-10-27", weekday: 2, mark: "vacation_x")),\#(weekDay("2026-10-28", weekday: 3, planned: "28800", future: true, balance: "null")),
    \#(weekDay("2026-10-29", weekday: 4)),\#(weekDay("2026-10-30", weekday: 5)),\#(weekDay("2026-10-31", weekday: 6, mark: "off")),\#(weekDay("2026-11-01", weekday: 7, mark: "holiday"))],
    "summary":{"targetSeconds":138600,"targetToDateSeconds":55440,"workSeconds":54000,"creditSeconds":0,"balanceSeconds":-1440,"plannedSeconds":null,
    "accountBalanceBeforeSeconds":3600,"accountBalanceAfterSeconds":2160,"accountBalanceAsOf":"2026-10-27","vacationDays":1.5,"sickDays":0,"schoolDays":1,"holidayDays":1,
    "workDays":2,"travelSeconds":0,"breakSeconds":3600,"averageStart":"08:00","averageEnd":"16:30","longestDay":{"date":"2026-10-26","seconds":27000},"provisional":true}}
    """#

    static let planWeek = #"""
    {"week":"2026-W44","from":"2026-10-26","to":"2026-11-01","days":[
     {"date":"2026-10-26","weekday":1,"targetSeconds":27720,"plannedSeconds":28800,"blockedBy":null,"plan":{"date":"2026-10-26","mode":"office","placeId":null,"note":null,"plannedStart":"08:00","plannedEnd":"16:30","plannedBreakMinutes":30,"plannedSeconds":28800}},
     {"date":"2026-10-27","weekday":2,"targetSeconds":0,"plannedSeconds":0,"blockedBy":"holiday","plan":{"date":"2026-10-27","mode":"home","placeId":null,"note":"x","plannedStart":null,"plannedEnd":null,"plannedBreakMinutes":null,"plannedSeconds":null}},
     {"date":"2026-10-28","weekday":3,"targetSeconds":27720,"plannedSeconds":null,"blockedBy":null,"plan":null},
     {"date":"2026-10-29","weekday":4,"targetSeconds":27720,"plannedSeconds":null,"blockedBy":"future_reason","plan":null},
     {"date":"2026-10-30","weekday":5,"targetSeconds":27720,"plannedSeconds":null,"blockedBy":null,"plan":null},
     {"date":"2026-10-31","weekday":6,"targetSeconds":0,"plannedSeconds":null,"blockedBy":null,"plan":null},
     {"date":"2026-11-01","weekday":7,"targetSeconds":0,"plannedSeconds":null,"blockedBy":null,"plan":null}],
     "totals":{"targetSeconds":110880,"plannedSeconds":28800,"differenceSeconds":-82080}}
    """#
}

@Suite struct WeekDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONCoding.makeDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func suggestionsDecodeWithUnknownValues() throws {
        let result = try decode(VacationSuggestions.self, WeekFixtures.suggestions)
        #expect(result.budget.remainingDays == 27)
        #expect(result.suggestions.count == 3)
        let first = result.suggestions[0]
        #expect(first.kind == .bridge && first.efficiency == 4 && first.conflicts == [VacationConflict(date: "2026-05-15", type: .schoolDay)])
        #expect(result.suggestions[1].remainingAfter == 26.5)
        let odd = result.suggestions[2]
        #expect(odd.kind == .unknown)
        #expect(odd.conflicts.map(\.type) == [.alreadyVacation, .unknown])
        #expect(odd.schoolHolidays.first?.name == "Ferien")
        #expect(odd.fitsBudget == false && odd.remainingAfter == -0.5)
    }

    @Test func timeWeekDecodes() throws {
        let week = try decode(TimeWeek.self, WeekFixtures.timeWeek)
        #expect(week.days.count == 7)
        #expect(week.days[0].hoursSeconds == 27000 && week.days[0].lastEnd != nil)
        #expect(week.days[1].mark == .unknown)
        #expect(week.days[2].balanceSeconds == nil && week.days[2].isFuture && week.days[2].plannedSeconds == 28800)
        #expect(week.days[0].absences == [TimeWeekAbsence(kind: .vacation, status: .planned, halfDay: true)])
        #expect(week.summary.vacationDays == 1.5 && week.summary.longestDay?.seconds == 27000 && week.summary.plannedSeconds == nil)
        #expect(WeekOverview.noteworthy(week.summary).map(\.mark) == [.vacation, .school, .holiday])
    }

    @Test func planWeekDecodesAndBlocks() throws {
        let week = try decode(PlanWeek.self, WeekFixtures.planWeek)
        #expect(week.days[0].plan?.plannedStart == "08:00" && week.days[0].plan?.plannedSeconds == 28800)
        #expect(week.days[1].blockedBy == .holiday && week.days[1].isBlocked && week.days[1].plan?.mode == .home)
        #expect(week.days[3].blockedBy == .unknown && week.days[3].isBlocked)
        #expect(week.days[2].isBlocked == false)
        #expect(week.totals.differenceSeconds == -82080)
    }

    @Test func planWeekRequestEncodesFlatEntries() throws {
        let drafts = [DayDraft(date: "2026-10-26", mode: .office, start: "08:00", end: "16:30", breakMinutes: 30, note: " Büro "), DayDraft(date: "2026-10-27")]
        let data = try JSONCoding.makeEncoder().encode(WeekPlan.request(drafts))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["replace"] as? Bool == true)
        let days = try #require(object["days"] as? [[String: Any]])
        #expect(days.count == 1)
        #expect(days[0]["date"] as? String == "2026-10-26" && days[0]["mode"] as? String == "office")
        #expect(days[0]["plannedStart"] as? String == "08:00" && days[0]["plannedEnd"] as? String == "16:30" && days[0]["plannedBreakMinutes"] as? Int == 30)
        #expect(days[0]["note"] as? String == "Büro")
    }
}

@Suite struct IsoWeekTests {
    @Test func labels() {
        #expect(IsoWeek.label(containing: "2026-10-26") == "2026-W44")
        #expect(IsoWeek.label(containing: "2026-01-01") == "2026-W01")
        #expect(IsoWeek.label(containing: "2027-01-01") == "2026-W53")
        #expect(IsoWeek.label(containing: "2024-12-30") == "2025-W01")
    }

    @Test func mondays() {
        #expect(IsoWeek.monday(of: "2026-W44") == "2026-10-26")
        #expect(IsoWeek.monday(of: "2026-W53") == "2026-12-28")
        #expect(IsoWeek.monday(of: "2025-W53") == nil)
        #expect(IsoWeek.monday(of: "garbage") == nil)
        #expect(IsoWeek.number(of: "2026-W44") == 44)
    }
}

@Suite struct WeekPlanLogicTests {
    private func days(blocked: Set<Int> = []) throws -> [PlanWeekDay] {
        var week = try JSONCoding.makeDecoder().decode(PlanWeek.self, from: Data(WeekFixtures.planWeek.utf8))
        week = PlanWeek.testing(week, blocked: blocked)
        return week.days
    }

    @Test func clockAndProblems() {
        #expect(WeekPlan.parseClock("08:30") == 510 && WeekPlan.parseClock("24:00") == nil && WeekPlan.parseClock("8:30") == nil)
        #expect(WeekPlan.problem(DayDraft(date: "d", mode: .office, start: "09:00", end: "08:00")) == .endBeforeStart)
        #expect(WeekPlan.problem(DayDraft(date: "d", mode: .office, start: "09:00")) == .timesRequired)
        #expect(WeekPlan.problem(DayDraft(date: "d", mode: .office, start: "08:00", end: "09:00", breakMinutes: 601)) == .breakInvalid)
        #expect(WeekPlan.problem(DayDraft(date: "d", mode: .office)) == nil)
        #expect(WeekPlan.problem(DayDraft(date: "d", mode: .off, start: "x")) == nil)
        #expect(WeekPlan.plannedSeconds(DayDraft(date: "d", mode: .office, start: "08:00", end: "16:30", breakMinutes: 30)) == 28800)
        #expect(WeekPlan.plannedSeconds(DayDraft(date: "d", mode: .office, start: "08:00", end: "08:15", breakMinutes: 60)) == 0)
    }

    @Test func suggestionFromHistoryAndFallback() throws {
        let week = try JSONCoding.makeDecoder().decode(TimeWeek.self, from: Data(WeekFixtures.timeWeek.utf8))
        let history = WeekPlan.suggestWindow(history: [week.summary], targetSeconds: 27720)
        #expect(history.source == .history && history.start == "08:00" && history.end == "16:30" && history.breakMinutes == 30)
        let fallback = WeekPlan.suggestWindow(history: [], targetSeconds: 27720)
        #expect(fallback.source == .fallback && fallback.start == "08:00" && fallback.end == "16:15" && fallback.breakMinutes == 30)
        #expect(WeekPlan.fallbackWindow(targetSeconds: 4 * 3600).breakMinutes == 0)
    }

    @Test func modeChangeAndWeekActions() throws {
        let days = try days(blocked: [1])
        let suggestion = WeekPlan.fallbackWindow(targetSeconds: 27720)
        var drafts = days.map(WeekPlan.draft(from:))
        drafts[2] = WeekPlan.withMode(drafts[2], .home, suggestion: suggestion, targetSeconds: 27720)
        #expect(drafts[2].start == "08:00" && drafts[2].end == "16:15")
        drafts[2] = WeekPlan.withMode(drafts[2], .off, suggestion: suggestion, targetSeconds: 27720)
        #expect(drafts[2].start.isEmpty && drafts[2].breakMinutes == 0)

        let standard = WeekPlan.standardWeek(days: days, current: drafts, suggestion: suggestion)
        #expect(standard[0].mode == .office && standard[1] == drafts[1]) // blocked keeps its draft
        #expect(standard[2].mode == .office && standard[5].mode == nil)

        let same = WeekPlan.sameForWorkdays(days: days, current: drafts)
        #expect(same[4].mode == .office && same[4].start == "08:00" && same[5].mode == nil)

        let cleared = WeekPlan.clearWeek(days: days, current: drafts)
        #expect(cleared[0].mode == nil && cleared[1].mode == .home)

        let totals = WeekPlan.totals(days: days, drafts: standard)
        #expect(totals.plannedSeconds == 4 * 27900 && totals.targetSeconds == 110880)
    }
}

extension PlanWeek {
    /// Test helper: marks the given day indexes as blocked by holiday.
    static func testing(_ week: PlanWeek, blocked: Set<Int>) -> PlanWeek {
        var json = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(week))) as? [String: Any] ?? [:]
        var days = json["days"] as? [[String: Any]] ?? []
        for index in days.indices { days[index]["blockedBy"] = blocked.contains(index) ? "holiday" : NSNull() }
        json["days"] = days
        guard let data = try? JSONSerialization.data(withJSONObject: json), let result = try? JSONDecoder().decode(PlanWeek.self, from: data) else { return week }
        return result
    }
}

@Suite struct VacationPlannerLogicTests {
    private func suggestion(_ json: String) throws -> VacationSuggestion { try JSONCoding.makeDecoder().decode(VacationSuggestion.self, from: Data(json.utf8)) }

    @Test func blocksSplitAtBookedDays() throws {
        let s = try suggestion(#"{"id":"a","kind":"long_break","start":"2026-06-01","end":"2026-06-14","vacationDates":["2026-06-01","2026-06-02","2026-06-04","2026-06-05","2026-06-08"],"vacationDaysNeeded":5,"totalDaysOff":14,"efficiency":2.8,"holidays":[],"schoolHolidays":[],"conflicts":[{"date":"2026-06-03","type":"already_vacation"}],"fitsBudget":true,"remainingAfter":10}"#)
        let blocks = VacationPlanner.blocks(for: s)
        #expect(blocks.map(\.start) == ["2026-06-01", "2026-06-04"])
        #expect(blocks.map(\.end) == ["2026-06-02", "2026-06-08"])
        #expect(VacationPlanner.alreadyBookedDates(s) == ["2026-06-03"])
        #expect(VacationPlanner.requirements(for: s).needsAny == false)
    }

    @Test func requirementsGroupConflicts() throws {
        let result = try JSONCoding.makeDecoder().decode(VacationSuggestions.self, from: Data(WeekFixtures.suggestions.utf8))
        let second = VacationPlanner.requirements(for: result.suggestions[1])
        #expect(second.conflicts.map(\.type) == [.absence, .plan] && second.needsConflictAcknowledgement && !second.exceedsBudget)
        #expect(VacationPlanner.requirements(for: result.suggestions[2]).exceedsBudget)
    }

    @Test func cellsAndVisible() throws {
        let result = try JSONCoding.makeDecoder().decode(VacationSuggestions.self, from: Data(WeekFixtures.suggestions.utf8))
        let cells = VacationPlanner.cells(for: result.suggestions[0])
        #expect(cells.map(\.kind) == [.holiday, .vacation, .weekend, .weekend])
        #expect(cells[1].conflict == .schoolDay && cells[0].holidayName == "Christi Himmelfahrt")
        let visible = VacationPlanner.visible(result.suggestions, minEfficiency: 2.5, count: 10)
        #expect(visible.shown.count == 2 && visible.hidden == 1)
        #expect(VacationPlanner.visible(result.suggestions, minEfficiency: 1, count: 1).shown.count == 1)
    }

    @Test func filterValidation() {
        let f = VacationPlannerFilters.defaults(today: "2026-10-19")
        #expect(f.to == "2027-12-31" && f.minEfficiency == 2 && f.isValid)
        var wide = f; wide.to = "2028-04-20"
        #expect(!wide.isValid)
        wide.to = "2028-04-19"
        #expect(wide.isValid)
        var bad = f; bad.maxVacationDays = 0
        #expect(!bad.isValid)
        var old = f; old.from = "2026-01-01"; old.to = "2026-02-01"
        #expect(old.sanitized(today: "2026-10-19") == f)
        var pastStart = f; pastStart.from = "2026-09-01"
        #expect(pastStart.sanitized(today: "2026-10-19").from == "2026-10-19")
        #expect(f.query.limit == 100 && f.needsFetch(comparedTo: f) == false)
    }
}

@Suite @MainActor struct WeekStoreTests {
    private let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    private let now = ISO8601DateFormatter().date(from: "2026-10-21T10:00:00Z")!

    @Test func weekStoreLoadsAndShifts() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/weeks/2026-W43", body: WeekFixtures.timeWeek)
        transport.enqueue("GET /api/v1/time/weeks/2026-W42", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let store = WeekStore(client: Fixtures.client(transport), calendar: calendar, now: now)
        #expect(store.monday == "2026-10-19" && store.isoWeek == "2026-W43" && store.isCurrentWeek)
        await store.load()
        #expect(store.week?.days.count == 7 && store.error == nil)
        await store.shiftWeeks(-1)
        #expect(store.monday == "2026-10-12" && store.week == nil && store.isUnavailable)
    }

    @Test func plannerSavesAllOrNothingAndTracksDirty() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/plan/weeks/2026-W44", body: WeekFixtures.planWeek)
        transport.enqueue("PUT /api/v1/plan/weeks/2026-W44", body: WeekFixtures.planWeek)
        transport.enqueue("GET /api/v1/time/weeks/2026-W43", status: 500, body: "{}")
        let store = WeekPlanStore(client: Fixtures.client(transport), calendar: calendar, now: now)
        #expect(store.isoWeek == "2026-W44")
        var outcomes: [StoreOutcome] = []
        store.onOutcome = { outcomes.append($0) }
        await store.load()
        #expect(!store.isDirty && store.suggestion.source == .fallback)
        store.setMode(2, .home)
        #expect(store.isDirty && store.drafts[2].start == "08:00")
        store.update(4, DayDraft(date: "2026-10-30", mode: .office, start: "10:00", end: "09:00"))
        #expect(await store.save() == false && store.showProblems)
        #expect(transport.requests(matching: "PUT /api/v1/plan/weeks/2026-W44").isEmpty)
        store.update(4, DayDraft(date: "2026-10-30"))
        #expect(await store.save())
        #expect(!store.isDirty && outcomes == [.saved])
        let body = transport.requests(matching: "PUT /api/v1/plan/weeks/2026-W44").first?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        // blocked day 27th keeps its stored plan in the request (replace would delete it otherwise)
        #expect((body?["days"] as? [[String: Any]])?.contains { $0["date"] as? String == "2026-10-27" } == true)
        store.setMode(2, .office)
        store.discard()
        #expect(!store.isDirty)
    }

    @Test func takeBooksOneAbsencePerBlockAndGuards() async throws {
        let transport = MockTransport()
        let s = try JSONCoding.makeDecoder().decode(VacationSuggestions.self, from: Data(WeekFixtures.suggestions.utf8))
        let absence = #"{"id":"11111111-1111-4111-8111-111111111111","version":1,"kind":"vacation","startDate":"2026-05-22","endDate":"2026-05-22","status":"planned","countedHalfDays":2}"#
        transport.enqueue("POST /api/v1/absences", body: absence)
        transport.enqueue("GET /api/v1/vacation/suggestions", body: WeekFixtures.suggestions)
        let suite = UserDefaults(suiteName: "n1a-\(UUID().uuidString)")
        let store = VacationPlannerStore(client: Fixtures.client(transport), calendar: calendar, defaults: suite, now: now)
        let conflicting = s.suggestions[1]
        #expect(await store.take(conflicting, acknowledgedConflicts: false, acknowledgedBudget: false) == .needsAcknowledgement)
        #expect(transport.requests(matching: "POST /api/v1/absences").isEmpty)
        let result = await store.take(conflicting, acknowledgedConflicts: true, acknowledgedBudget: false)
        #expect(result == .booked(blocks: 1, first: "2026-05-22", last: "2026-05-22"))
        let sent = transport.requests(matching: "POST /api/v1/absences")
        #expect(sent.count == 1)
        #expect(store.createdAbsences.map(\.id.uuidString) == ["11111111-1111-4111-8111-111111111111"]) // AUD3-B: offered for the request PDF
        let body = sent[0].httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(body?["kind"] as? String == "vacation" && body?["status"] as? String == "planned" && body?["startDate"] as? String == "2026-05-22")
        // budget overrun needs its own acknowledgement
        #expect(await store.take(s.suggestions[2], acknowledgedConflicts: true, acknowledgedBudget: false) == .needsAcknowledgement)
    }
}

@Suite struct UnavailableRetryTests {
    @Test func readsRetryAfter503ThenSucceeds() async throws {
        let transport = RetryTransport()
        let client = Fixtures.client(MockTransport())
        _ = client
        let api = APIClient(baseURL: Fixtures.baseURL, transport: transport)
        let waits = WaitLog()
        await api.setRetrySleeper { waits.add($0) }
        let result = try await api.getVacationSuggestions()
        #expect(result.suggestions.isEmpty)
        #expect(transport.calls == 3)
        #expect(waits.values == [.seconds(3), .seconds(10)]) // Retry-After 3, then 99 capped at 10
    }

    @Test func writesAreNotRepeatedAndErrorIsMapped() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/absences", status: 503, body: #"{"error":{"code":"database_unavailable","message":"x"}}"#)
        let api = Fixtures.client(transport)
        do {
            _ = try await api.createAbsence(AbsenceInput(kind: .vacation, startDate: "2026-05-22", endDate: "2026-05-22", status: .planned))
            Issue.record("expected failure")
        } catch let error as TimetrackError {
            #expect(error.knownCode == .databaseUnavailable)
            #expect(error.germanDescription.contains("Datenbank"))
        } catch { Issue.record("wrong error") }
        #expect(transport.requests(matching: "POST /api/v1/absences").count == 1)
    }

    @Test func giveUpAfterTwoRetries() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/vacation/suggestions", status: 503, body: #"{"error":{"code":"database_unavailable","message":"x"}}"#)
        let api = Fixtures.client(transport)
        await api.setRetrySleeper { _ in }
        do { _ = try await api.getVacationSuggestions(); Issue.record("expected failure") } catch {}
        #expect(transport.requests(matching: "GET /api/v1/vacation/suggestions").count == 3)
    }
}

private final class WaitLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Duration] = []
    func add(_ d: Duration) { lock.withLock { items.append(d) } }
    var values: [Duration] { lock.withLock { items } }
}

private final class RetryTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let n = lock.withLock { count += 1; return count }
        let url = request.url!
        if n == 1 { return (Data(#"{"error":{"code":"database_unavailable","message":"x"}}"#.utf8), HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: ["Retry-After": "3"])!) }
        if n == 2 { return (Data(#"{"error":{"code":"database_unavailable","message":"x"}}"#.utf8), HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: ["Retry-After": "99"])!) }
        return (Data(#"{"from":"2026-05-01","to":"2026-07-31","budget":{"entitlementDays":30,"takenDays":0,"plannedDays":0,"remainingDays":30},"suggestions":[]}"#.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// AUD3 finding 1: a slow PUT must neither overwrite edits made meanwhile nor write into another week.
@Suite @MainActor struct WeekPlanSaveRaceTests {
    private let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    private let now = ISO8601DateFormatter().date(from: "2026-10-21T10:00:00Z")!

    private func loadedStore(_ transport: MockTransport) async -> WeekPlanStore {
        transport.enqueue("GET /api/v1/plan/weeks/2026-W44", body: WeekFixtures.planWeek)
        transport.enqueue("GET /api/v1/time/weeks/2026-W43", status: 500, body: "{}")
        let store = WeekPlanStore(client: Fixtures.client(transport), calendar: calendar, now: now)
        await store.load()
        return store
    }

    @Test func editsMadeWhileSavingSurvive() async {
        let transport = MockTransport()
        let store = await loadedStore(transport)
        transport.enqueue("PUT /api/v1/plan/weeks/2026-W44", body: WeekFixtures.planWeek)
        store.setMode(2, .home)
        let gate = transport.hold("PUT /api/v1/plan/weeks/2026-W44")
        let saving = Task { await store.save() }
        while !store.isSaving { await Task.yield() }
        store.setMode(3, .office) // edited while the PUT is in flight
        let edited = store.drafts
        gate.release()
        #expect(await saving.value)
        #expect(store.drafts == edited)
        #expect(store.isDirty)
        #expect(!store.isSaving)
    }

    @Test func weekSwitchDuringSaveIsQueuedAndNeverCrossesWeeks() async {
        let transport = MockTransport()
        let store = await loadedStore(transport)
        transport.enqueue("PUT /api/v1/plan/weeks/2026-W44", body: WeekFixtures.planWeek)
        transport.enqueue("GET /api/v1/plan/weeks/2026-W45", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        transport.enqueue("GET /api/v1/time/weeks/2026-W44", status: 500, body: "{}")
        store.setMode(2, .home)
        let gate = transport.hold("PUT /api/v1/plan/weeks/2026-W44")
        let saving = Task { await store.save() }
        while !store.isSaving { await Task.yield() }
        await store.shiftWeeks(1) // must not switch yet
        #expect(store.monday == "2026-10-26" && store.isoWeek == "2026-W44")
        gate.release()
        #expect(await saving.value)
        // the queued switch ran after the save; nothing of W44 leaked into W45
        #expect(store.monday == "2026-11-02" && store.week == nil && store.drafts.isEmpty)
        #expect(transport.requests(matching: "PUT /api/v1/plan/weeks/2026-W44").count == 1)
        #expect(transport.requests(matching: "PUT /api/v1/plan/weeks/2026-W45").isEmpty)
    }
}

/// AUD3 finding 9: switching weeks keeps the previous week visible (stale-while-revalidate) and caches neighbors.
@Suite @MainActor struct WeekStoreStaleTests {
    private let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    private let now = ISO8601DateFormatter().date(from: "2026-10-21T10:00:00Z")!

    private func tw(_ label: String) -> String { WeekFixtures.timeWeek.replacingOccurrences(of: #""week":"2026-W44""#, with: #""week":"\#(label)""#) }

    @Test func previousWeekStaysVisibleUntilTheNewOneArrives() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/weeks/2026-W43", body: tw("2026-W43"))
        let store = WeekStore(client: Fixtures.client(transport), calendar: calendar, now: now)
        await store.load()
        #expect(store.week?.week == "2026-W43" && !store.isStale)
        transport.enqueue("GET /api/v1/time/weeks/2026-W44", body: tw("2026-W44"))
        let gate = transport.hold("GET /api/v1/time/weeks/2026-W44")
        let shifting = Task { await store.shiftWeeks(1) }
        while !store.isLoading { await Task.yield() }
        #expect(store.week?.week == "2026-W43" && store.isStale) // not emptied
        gate.release()
        await shifting.value
        #expect(store.week?.week == "2026-W44" && !store.isStale)
    }

    @Test func cachedWeekShowsAtOnceAndNeighborIsPrefetched() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/weeks/2026-W43", body: tw("2026-W43"))
        transport.enqueue("GET /api/v1/time/weeks/2026-W44", body: tw("2026-W44"))
        transport.enqueue("GET /api/v1/time/weeks/2026-W45", body: tw("2026-W45"))
        let store = WeekStore(client: Fixtures.client(transport), calendar: calendar, now: now)
        await store.load()
        await store.shiftWeeks(1) // loads W44 and prefetches W45
        #expect(transport.requests(matching: "GET /api/v1/time/weeks/2026-W45").count == 1)
        let gate = transport.hold("GET /api/v1/time/weeks/2026-W45")
        let shifting = Task { await store.shiftWeeks(1) }
        while !store.isLoading { await Task.yield() }
        #expect(store.week?.week == "2026-W45" && !store.isStale) // from the cache, revalidation still pending
        gate.release()
        await shifting.value
    }
}
