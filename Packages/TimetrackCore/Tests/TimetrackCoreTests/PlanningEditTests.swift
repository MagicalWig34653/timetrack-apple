import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

private func body(_ request: URLRequest?) -> [String: Any] {
    guard let data = request?.httpBody, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
}

@Suite struct PlanningModelTests {
    @Test func decodesContractExamples() throws {
        let decoder = JSONCoding.makeDecoder()
        let absence = try decoder.decode(Absence.self, from: Data(#"""
        {"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","version":3,"kind":"sick","startDate":"2026-10-19","endDate":"2026-10-21","halfDayStart":false,
         "halfDayEnd":true,"status":"taken","note":"Erkältung","countedHalfDays":0,"documentStatus":"pending","documentSubmittedOn":null,
         "documentReferenceStart":"2026-10-19","documentReferenceEnd":"2026-10-23","extra":1}
        """#.utf8))
        #expect(absence.documentStatus == .pending && absence.documentReferenceEnd == "2026-10-23" && absence.version == 3)

        let holidays = try decoder.decode([CalendarDay].self, from: Data(#"""
        [{"id":null,"startDate":"2026-10-31","endDate":"2026-10-31","name":"Reformationstag","kind":"holiday","source":"builtin"},
         {"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","startDate":"2026-10-12","endDate":"2026-10-23","name":"Herbstferien","kind":"school_holiday","source":"custom"},
         {"id":null,"startDate":"2026-12-24","endDate":"2026-12-24","name":"Neu","kind":"future","source":"other"}]
        """#.utf8))
        #expect(holidays[0].id == nil && holidays[0].kind == .holiday && holidays[0].source == .builtin)
        #expect(holidays[1].kind == .schoolHoliday && holidays[1].covers("2026-10-20") && !holidays[1].covers("2026-10-24"))
        #expect(holidays[2].kind == .unknown && holidays[2].source == .unknown)

        let plan = try decoder.decode(PlanDay.self, from: Data(#"{"date":"2026-10-20","mode":"home","placeId":null,"note":"x"}"#.utf8))
        #expect(plan.mode == .home)
        let settings = try decoder.decode(VacationSettings.self, from: Data(#"{"configured":false,"region":"DE-ST","annualEntitlementHalfDays":60,"carryOverByYear":{"2026":8},"carryOverExpiry":null}"#.utf8))
        #expect(settings.configured == false && settings.carryOverByYear?["2026"] == 8)
    }

    @Test func inputEncodesExplicitNulls() throws {
        let encoder = JSONCoding.makeEncoder()
        let input = AbsenceInput(kind: .sick, startDate: "2026-10-19", endDate: "2026-10-19", status: .taken, documentStatus: .pending)
        let json = try JSONSerialization.jsonObject(with: encoder.encode(input)) as? [String: Any] ?? [:]
        #expect(json["kind"] as? String == "sick" && json["documentStatus"] as? String == "pending")
        #expect(json["note"] is NSNull && json["documentSubmittedOn"] is NSNull)
        #expect(json["halfDayStart"] as? Bool == false)

        let settings = try JSONSerialization.jsonObject(with: encoder.encode(VacationSettings(configured: true, region: "DE-SN"))) as? [String: Any] ?? [:]
        #expect(settings["configured"] == nil && settings["carryOverExpiry"] is NSNull && settings["region"] as? String == "DE-SN")
    }

    @Test func parsesHalfDays() {
        #expect(HalfDayFormat.parseHalfDays("12,5") == 25)
        #expect(HalfDayFormat.parseHalfDays(" 30 ") == 60)
        #expect(HalfDayFormat.parseHalfDays("-0.5") == -1)
        #expect(HalfDayFormat.parseHalfDays("1,3") == nil)
        #expect(HalfDayFormat.parseHalfDays("abc") == nil)
        #expect(HalfDayFormat.parseHalfDays("") == nil)
    }

    @Test func isoWeeks() {
        #expect(LocalDays.isoWeek(of: "2026-10-19") == 43)
        #expect(LocalDays.isoWeek(of: "2026-01-01") == 1)
        #expect(LocalDays.isoWeek(of: "2027-01-01") == 53)
        #expect(LocalDays.isoWeek(of: "bad") == nil)
    }

    @Test func overlapErrorIsGerman() {
        let error = TimetrackError.api(status: 409, code: "absence_overlap", message: "x")
        #expect(error.knownCode == .absenceOverlap)
        #expect(error.germanDescription.contains("Abwesenheit"))
        #expect(TimetrackError.api(status: 412, code: "stale_version", message: "x").germanDescription.contains("geändert"))
    }
}

@MainActor
@Suite struct PlanningEditingTests {
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let now = Date(timeIntervalSince1970: 1_792_130_820) // Fri 2026-10-16
    static let absenceJSON = #"{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","version":2,"kind":"vacation","startDate":"2026-10-19","endDate":"2026-10-21","status":"planned","countedHalfDays":6}"#
    static let balanceJSON = PlanningTests.balanceJSON

    func planningStore(_ transport: MockTransport) -> PlanningStore {
        transport.enqueue("GET /api/v1/vacation/balance", body: Self.balanceJSON)
        transport.enqueue("GET /api/v1/absences", body: "[\(Self.absenceJSON)]")
        return PlanningStore(client: Fixtures.client(transport), calendar: calendar, now: now)
    }

    func calendarStore(_ transport: MockTransport) -> CalendarStore {
        transport.enqueue("GET /api/v1/absences", body: "[\(Self.absenceJSON)]")
        transport.enqueue("GET /api/v1/plan/days", body: #"[{"date":"2026-10-20","mode":"office","placeId":null,"note":null}]"#)
        transport.enqueue("GET /api/v1/calendar/holidays", body: #"[{"id":null,"startDate":"2026-10-31","endDate":"2026-10-31","name":"Reformationstag","kind":"holiday","source":"builtin"}]"#)
        return CalendarStore(client: Fixtures.client(transport), calendar: calendar, now: now)
    }

    @Test func createAbsenceSendsBodyAndReloads() async {
        let transport = MockTransport()
        let store = planningStore(transport)
        transport.enqueue("POST /api/v1/absences", status: 201, body: Self.absenceJSON)
        let input = AbsenceInput(kind: .vacation, startDate: "2026-10-19", endDate: "2026-10-21", status: .planned)
        let stored = await store.saveAbsence(input, editing: nil)
        #expect(stored?.countedHalfDays == 6)
        let request = transport.requests(matching: "POST /api/v1/absences").last
        #expect(body(request)["status"] as? String == "planned")
        #expect(store.absences.count == 1)
        #expect(!transport.requests(matching: "GET /api/v1/vacation/balance").isEmpty)
    }

    @Test func updateUsesIfMatchAndCsrf() async throws {
        let transport = MockTransport()
        let client = Fixtures.client(transport)
        await client.setCSRFToken("tok")
        transport.enqueue("PUT /api/v1/absences/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", body: Self.absenceJSON)
        let absence = try JSONCoding.makeDecoder().decode(Absence.self, from: Data(Self.absenceJSON.utf8))
        _ = try await client.updateAbsence(id: absence.id, AbsenceInput(absence), ifMatchVersion: absence.version)
        let request = transport.requests(matching: "PUT /api/v1/absences/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa").last
        #expect(request?.value(forHTTPHeaderField: "If-Match") == "2")
        #expect(request?.value(forHTTPHeaderField: "X-CSRF-Token") == "tok")
    }

    @Test func overlapAndStaleErrorsSurface() async {
        let transport = MockTransport()
        let store = planningStore(transport)
        transport.enqueue("POST /api/v1/absences", status: 409, body: #"{"error":{"code":"absence_overlap","message":"x"}}"#)
        let input = AbsenceInput(kind: .sick, startDate: "2026-10-20", endDate: "2026-10-20", status: .taken)
        #expect(await store.saveAbsence(input, editing: nil) == nil)
        #expect(store.error?.knownCode == .absenceOverlap)

        let absence = try! JSONCoding.makeDecoder().decode(Absence.self, from: Data(Self.absenceJSON.utf8))
        transport.enqueue("PUT /api/v1/absences/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", status: 412, body: #"{"error":{"code":"stale_version","message":"x"}}"#)
        #expect(await store.saveAbsence(AbsenceInput(absence), editing: absence) == nil)
        #expect(store.error?.knownCode == .staleVersion)
    }

    @Test func deleteAbsence() async throws {
        let transport = MockTransport()
        let store = planningStore(transport)
        await store.load()
        transport.enqueue("DELETE /api/v1/absences/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", status: 204)
        transport.set("GET /api/v1/absences", body: "[]")
        #expect(await store.deleteAbsence(store.absences[0]))
        #expect(store.absences.isEmpty)
    }

    @Test func settingsRoundTrip() async {
        let transport = MockTransport()
        let store = planningStore(transport)
        transport.enqueue("GET /api/v1/vacation/settings", body: #"{"configured":false,"region":"DE-ST","annualEntitlementHalfDays":60}"#)
        transport.enqueue("GET /api/v1/vacation/entries", body: #"{"snapshots":[],"adjustments":[{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","date":"2026-02-01","halfDays":2,"reason":"Test"}]}"#)
        await store.loadSettings()
        #expect(store.settings?.configured == false && store.entries.adjustments.count == 1)
        transport.enqueue("PUT /api/v1/vacation/settings", body: #"{"configured":true,"region":"DE-SN","annualEntitlementHalfDays":50}"#)
        var edited = store.settings ?? VacationSettings()
        edited.region = "DE-SN"
        edited.annualEntitlementHalfDays = 50
        #expect(await store.saveSettings(edited))
        #expect(store.settings?.region == "DE-SN")
        #expect(body(transport.requests(matching: "PUT /api/v1/vacation/settings").last)["annualEntitlementHalfDays"] as? Int == 50)
    }

    @Test func gridStartsOnMondayAndMergesData() async {
        let transport = MockTransport()
        let store = calendarStore(transport)
        let grid = store.gridDays
        #expect(grid.first == "2026-09-28" && grid.last == "2026-11-01" && grid.count == 35)
        await store.load()
        #expect(store.info(for: "2026-10-20").absences.count == 1)
        #expect(store.info(for: "2026-10-20").plan?.mode == .office)
        #expect(store.info(for: "2026-10-31").holidays.first?.name == "Reformationstag")
        #expect(store.info(for: "2026-10-22").absences.isEmpty)
        #expect(transport.requests(matching: "GET /api/v1/absences").first?.url?.query == "from=2026-09-28&to=2026-11-08") // Z2: the visible month is fetched first, always as six rows
    }

    @Test func monthNavigationAcrossYears() async {
        let transport = MockTransport()
        let store = calendarStore(transport)
        await store.goTo(year: 2026, month: 12)
        await store.shiftMonths(1)
        #expect(store.year == 2027 && store.month == 1)
        await store.shiftMonths(-2)
        #expect(store.year == 2026 && store.month == 11)
        // a grid spanning two years loads holidays for both
        await store.goTo(year: 2026, month: 12)
        let years = transport.requests(matching: "GET /api/v1/calendar/holidays").compactMap { $0.url?.query }
        #expect(years.contains("year=2027"))
    }

    @Test func optimisticCreateReconcilesAndRevertsOnFailure() async {
        let transport = MockTransport()
        let store = calendarStore(transport)
        await store.load()
        transport.enqueue("POST /api/v1/absences", status: 201, body: #"{"id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","version":1,"kind":"sick","startDate":"2026-10-26","endDate":"2026-10-27","status":"taken","countedHalfDays":0,"documentStatus":"pending"}"#)
        let sick = AbsenceInput(kind: .sick, startDate: "2026-10-26", endDate: "2026-10-27", status: .taken, documentStatus: .pending)
        let stored = await store.saveAbsence(sick, editing: nil)
        #expect(stored?.version == 1)
        #expect(store.info(for: "2026-10-27").absences.map(\.id) == [stored!.id]) // reconciled: no temporary duplicate
        #expect(store.absences.count == 2)

        transport.set("POST /api/v1/absences", status: 409, body: #"{"error":{"code":"absence_overlap","message":"x"}}"#)
        let clash = AbsenceInput(kind: .vacation, startDate: "2026-10-26", endDate: "2026-10-26", status: .planned)
        #expect(await store.saveAbsence(clash, editing: nil) == nil)
        #expect(store.absences.count == 2)
        #expect(store.error?.knownCode == .absenceOverlap)
    }

    @Test func optimisticStateIsVisibleWhileRequestRuns() async {
        let transport = MockTransport()
        let store = calendarStore(transport)
        await store.load()
        transport.delay = .milliseconds(200)
        transport.enqueue("POST /api/v1/absences", status: 201, body: #"{"id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","version":1,"kind":"other","startDate":"2026-10-28","endDate":"2026-10-28","status":"planned","countedHalfDays":0}"#)
        let task = Task { await store.saveAbsence(AbsenceInput(kind: .other, startDate: "2026-10-28", endDate: "2026-10-28", status: .planned), editing: nil) }
        try? await Task.sleep(for: .milliseconds(60))
        #expect(store.info(for: "2026-10-28").absences.count == 1)
        _ = await task.value
    }

    @Test func cancelAndSubmitDocument() async throws {
        let transport = MockTransport()
        let store = calendarStore(transport)
        await store.load()
        let vacation = store.absences[0]
        transport.enqueue("PUT /api/v1/absences/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", body: #"{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","version":3,"kind":"vacation","startDate":"2026-10-19","endDate":"2026-10-21","status":"cancelled","countedHalfDays":0}"#)
        #expect(await store.cancelAbsence(vacation))
        #expect(store.absences.isEmpty)
        #expect(body(transport.requests(matching: "PUT /api/v1/absences/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa").last)["status"] as? String == "cancelled")
    }

    @Test func planDayUpdateAndRemoval() async {
        let transport = MockTransport()
        let store = calendarStore(transport)
        await store.load()
        transport.enqueue("PUT /api/v1/plan/days/2026-10-22", body: #"{"date":"2026-10-22","mode":"customer","placeId":null,"note":"Kunde A"}"#)
        #expect(await store.savePlan(day: "2026-10-22", PlanDayInput(mode: .customer, note: "Kunde A")))
        #expect(store.info(for: "2026-10-22").plan?.note == "Kunde A")
        transport.enqueue("DELETE /api/v1/plan/days/2026-10-22", status: 204)
        #expect(await store.removePlan(day: "2026-10-22"))
        #expect(store.info(for: "2026-10-22").plan == nil)
        transport.enqueue("PUT /api/v1/plan/days/2026-10-23", status: 400, body: #"{"error":{"code":"bad_request","message":"x"}}"#)
        #expect(await store.savePlan(day: "2026-10-23", PlanDayInput(mode: .home)) == false)
        #expect(store.info(for: "2026-10-23").plan == nil && store.error?.knownCode == .badRequest)
    }

    @Test func customDays() async {
        let transport = MockTransport()
        let store = calendarStore(transport)
        await store.load()
        transport.enqueue("POST /api/v1/calendar/custom-days", status: 201, body: #"{"id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","startDate":"2026-10-30","endDate":"2026-10-30","name":"Brückentag","kind":"holiday","source":"custom"}"#)
        #expect(await store.createCustomDay(CustomDayInput(kind: .holiday, startDate: "2026-10-30", endDate: "2026-10-30", name: "Brückentag")))
        let created = store.info(for: "2026-10-30").holidays.first
        #expect(created?.name == "Brückentag")
        transport.enqueue("DELETE /api/v1/calendar/custom-days/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", status: 204)
        #expect(await store.deleteCustomDay(created!))
        #expect(store.info(for: "2026-10-30").holidays.isEmpty)
    }

    @Test func rangeSelection() {
        let store = CalendarStore(client: Fixtures.client(MockTransport()), calendar: calendar, now: now)
        store.beginRange(at: "2026-10-21")
        #expect(store.chosenRange?.start == "2026-10-21" && store.chosenRange?.end == "2026-10-21")
        store.tapInRangeMode("2026-10-19")
        #expect(store.chosenRange?.start == "2026-10-19" && store.chosenRange?.end == "2026-10-21")
        #expect(store.isInRange("2026-10-20") && !store.isInRange("2026-10-22"))
        store.tapInRangeMode("2026-10-25") // third tap starts over
        #expect(store.chosenRange?.start == "2026-10-25" && store.chosenRange?.end == "2026-10-25")
        store.cancelRange()
        #expect(store.chosenRange == nil && !store.isRangeMode)
    }

    @Test func appModelProvidesCalendarOnlyWithPlanning() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("GET /api/v1/modules", body: #"[{"key":"planning","serverEnabled":true,"accountEnabled":true,"effective":true,"lockedByOperator":false}]"#)
        transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        let model = AppModel(auth: AuthService(secrets: InMemorySecretStore(), transport: transport))
        await model.signInWithSessionCookie(serverInput: "http://localhost:18090", cookie: "c")
        #expect(model.calendar != nil && model.planning != nil)
        transport.set("GET /api/v1/modules", body: #"[{"key":"planning","serverEnabled":true,"accountEnabled":false,"effective":false,"lockedByOperator":false}]"#)
        await model.refreshModules()
        #expect(model.calendar == nil && model.planning == nil)
    }
}
