import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// P15: legal profiles per work model, time account adjustments (list/delete) and the needsReview acknowledgement (contract 0.29.0+).

private func body(_ request: URLRequest) -> [String: Any] {
    guard let data = request.httpBody else { return [:] }
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

@MainActor
@Suite struct LegalProfileTests {
    static let modelID = "22222222-2222-4222-8222-222222222222"
    static func modelJSON(profile: String?) -> String {
        let p = profile.map { #","legalProfileId":"\#($0)""# } ?? ""
        return #"{"id":"\#(modelID)","createdAt":"2026-09-01T08:00:00Z","validFrom":"2026-09-01","validTo":null,"timezone":"Europe/Berlin","weeklyTargetSeconds":138600,"workdays":[1,2,3,4,5],"travelCountsAsWork":true,"roundingEnabled":true,"roundingMinutes":15,"schoolFullDayThresholdSeconds":10800,"schoolCreditSeconds":null,"dayBoundaryMinutes":0,"fixedBreaks":[],"version":2\#(p)}"#
    }
    static let profilesJSON = #"""
    [{"id":"arbzg-adult-de","name":"Arbeitszeitgesetz (Erwachsene)","breakRules":[{"afterSeconds":21600,"requiredSeconds":1800}],"minimumBreakPartSeconds":900,"maximumContinuousSeconds":21600,"maxDailySeconds":36000,"maxWeeklySeconds":null,"maxWorkdaysPerWeek":null,"minimumRestSeconds":39600,"restrictedWeekdays":[],"school":null,"sources":["https://www.gesetze-im-internet.de/arbzg/__4.html"],"informationalOnly":true},
     {"id":"jarbschg-minor-de","name":"Jugendarbeitsschutzgesetz","breakRules":[],"minimumBreakPartSeconds":900,"maximumContinuousSeconds":16200,"maxDailySeconds":28800,"maxWeeklySeconds":144000,"maxWorkdaysPerWeek":5,"minimumRestSeconds":43200,"restrictedWeekdays":[6,7],"school":{"fullDayLessons":6,"fullDayCreditSeconds":28800,"fullDaysPerWeek":1,"blockWeekLessons":25,"blockWeekDays":5,"blockWeekCreditSeconds":144000,"noWorkBeforeMinutes":540},"sources":["https://www.gesetze-im-internet.de/jarbschg/__9.html"],"informationalOnly":true,"futureField":1}]
    """#

    @Test func decodesProfilesAndSchoolRules() throws {
        let profiles = try JSONCoding.makeDecoder().decode([LegalProfile].self, from: Data(Self.profilesJSON.utf8))
        #expect(profiles.map(\.id) == [LegalProfileID.adult, LegalProfileID.minor])
        #expect(profiles[0].school == nil && !profiles[0].recordsSchoolLessons)
        #expect(profiles[1].recordsSchoolLessons && profiles[1].school?.fullDayCreditSeconds == 28_800 && profiles[1].school?.noWorkBeforeMinutes == 540)
        #expect(profiles[1].ruleSummary == "8 h pro Tag, 40 h pro Woche, höchstens 5 Arbeitstage pro Woche, 12 h Ruhezeit")
        #expect(profiles[0].sources.count == 1)
    }

    @Test func modelWithoutProfileMeansAdult() throws {
        let old = try JSONCoding.makeDecoder().decode(WorkModel.self, from: Data(Self.modelJSON(profile: nil).utf8))
        #expect(old.legalProfileId == nil && old.effectiveLegalProfileId == LegalProfileID.adult)
        #expect(WorkModelForm(model: old).legalProfileId == LegalProfileID.adult)
        let minor = try JSONCoding.makeDecoder().decode(WorkModel.self, from: Data(Self.modelJSON(profile: LegalProfileID.minor).utf8))
        #expect(WorkModelForm(model: minor).legalProfileId == LegalProfileID.minor)
        #expect(WorkModelForm(validFrom: "2026-09-01").legalProfileId == LegalProfileID.adult)
    }

    @Test func inputEncodesTheChosenProfileAndNewVersionKeepsIt() throws {
        let minor = try JSONCoding.makeDecoder().decode(WorkModel.self, from: Data(Self.modelJSON(profile: LegalProfileID.minor).utf8))
        var form = WorkModelForm(basedOn: minor, startingOn: "2027-01-01")
        guard case .success(let input) = form.build() else { Issue.record("valid"); return }
        let json = try #require(try JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(input)) as? [String: Any])
        #expect(json["legalProfileId"] as? String == LegalProfileID.minor)
        form.legalProfileId = " "
        guard case .failure(let errors) = form.build() else { Issue.record("invalid"); return }
        #expect(errors.fields == [.legalProfile])
    }

    @Test func storeLoadsProfilesAndFallsBackOnOldServers() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/legal-profiles", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let store = WorkModelStore(client: Fixtures.client(transport))
        #expect(store.profiles.map(\.id) == LegalProfileID.all && !store.profilesFromServer)
        await store.loadProfiles()
        #expect(store.profiles.map(\.id) == LegalProfileID.all && !store.profilesFromServer, "fallback stays")
        transport.set("GET /api/v1/legal-profiles", body: Self.profilesJSON)
        await store.loadProfiles()
        #expect(store.profilesFromServer && store.profile(id: LegalProfileID.minor)?.maxWeeklySeconds == 144_000)
    }

    @Test func createSendsProfileAndServerValidationErrorIsMappedToGerman() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok"))
        transport.enqueue("GET /api/v1/work-models", body: "[\(Self.modelJSON(profile: nil))]")
        transport.enqueue("POST /api/v1/work-models", status: 400, body: #"{"error":{"code":"invalid","message":"unknown legal profile"}}"#)
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        let store = WorkModelStore(client: client)
        await store.load()
        var form = WorkModelForm(basedOn: try #require(store.models.first), startingOn: "2027-01-01")
        form.legalProfileId = "nonsense"
        #expect(await store.create(form: form) == nil)
        let sent = body(try #require(transport.requests(matching: "POST /api/v1/work-models").first))
        #expect(sent["legalProfileId"] as? String == "nonsense")
        let message = try #require(store.error).germanMessage(in: .workModel)
        #expect(message.contains("Rechtsprofil") && message != store.error?.germanDescription)
    }

    @Test func dayEvaluationDecodesLegalFieldsAndOldServersLeaveThemNil() throws {
        let withLegal = Fixtures.dayJSON.replacingOccurrences(of: #""breakHints":[{"code":"break_missing_30"}]"#, with:
            #""breakHints":[{"code":"break_missing_60"}],"legalProfileId":"jarbschg-minor-de","legalWarnings":[{"code":"work_before_school"},{"code":"zzz"}],"schoolLessonCount":7"#)
        let day = try JSONCoding.makeDecoder().decode(DayEvaluation.self, from: Data(withLegal.utf8))
        #expect(day.legalProfileId == LegalProfileID.minor && day.schoolLessonCount == 7)
        #expect(day.legalWarnings?.map(\.germanText) == ["Arbeit vor 9 Uhr am Berufsschultag", "Weiterer Hinweis des Servers"])
        #expect(day.breakHints.first?.germanText == "Pause von 60 Minuten fehlt")
        let old = try JSONCoding.makeDecoder().decode(DayEvaluation.self, from: Data(Fixtures.dayJSON.utf8))
        #expect(old.legalProfileId == nil && old.legalWarnings == nil && old.schoolLessonCount == nil)
        #expect(DayEvaluation(copying: day, segments: nil).schoolLessonCount == 7, "copies keep the legal fields")
    }

    @Test func schoolLessonCountIsSentAsExplicitValueOrNull() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok"))
        transport.enqueue("PUT /api/v1/time/days/2026-10-16", body: Fixtures.dayJSON)
        transport.enqueue("PUT /api/v1/time/days/2026-10-16", body: Fixtures.dayJSON)
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        _ = try await client.setSchoolLessonCount(6, on: "2026-10-16")
        _ = try await client.setSchoolLessonCount(nil, on: "2026-10-16")
        let puts = transport.requests(matching: "PUT /api/v1/time/days/2026-10-16").map(body)
        #expect(puts[0]["schoolLessonCount"] as? Int == 6)
        #expect(puts[1]["schoolLessonCount"] is NSNull && puts[1].count == 1)
    }
}

@MainActor
@Suite struct AccountAdjustmentListTests {
    static let a1 = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let a2 = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    static func page(_ items: [(String, String, Int)], total: Int, offset: Int = 0) -> String {
        let rows = items.map { #"{"id":"\#($0.0)","kind":"\#($0.1)","date":"2026-10-12","seconds":\#($0.2),"reason":"Grund","createdAt":"2026-10-20T08:00:00Z"}"# }
        return #"{"items":[\#(rows.joined(separator: ","))],"total":\#(total),"limit":50,"offset":\#(offset)}"#
    }
    static let balanceAfter = #"{"asOf":"2026-10-16","accountStart":"2026-09-01","balanceSeconds":-4680,"openingSeconds":0,"adjustmentSeconds":-3600,"provisional":false}"#

    private func store(_ transport: MockTransport) async throws -> TimeAccountStore {
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok"))
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        return TimeAccountStore(client: client)
    }

    @Test func decodesPageWithUnknownKind() throws {
        let json = Self.page([(Self.a1, "opening", 3600), (Self.a2, "future_kind", -60)], total: 2)
        let page = try JSONCoding.makeDecoder().decode(AccountAdjustmentPage.self, from: Data(json.utf8))
        #expect(page.total == 2 && page.items.map(\.kind) == [.opening, .unknown] && page.items[1].seconds == -60 && page.items[0].createdAt != nil)
    }

    @Test func loadReadsAccountAndAdjustmentsAndPagesWithOffset() async throws {
        let transport = MockTransport()
        let store = try await store(transport)
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/account/adjustments", body: Self.page([(Self.a1, "correction", -3600)], total: 2))
        await store.load()
        #expect(store.adjustments.count == 1 && store.adjustmentTotal == 2 && store.canLoadMore && store.listSupported)
        transport.set("GET /api/v1/time/account/adjustments", body: Self.page([(Self.a2, "opening", 7200)], total: 2, offset: 1))
        await store.loadMore()
        #expect(store.adjustments.map { $0.id.uuidString.lowercased() } == [Self.a1, Self.a2] && !store.canLoadMore)
        let queries = transport.requests(matching: "GET /api/v1/time/account/adjustments").map { $0.url?.query ?? "" }
        #expect(queries == ["limit=50&offset=0", "limit=50&offset=1"])
    }

    @Test func olderServerWithoutListIsNotAnError() async throws {
        let transport = MockTransport()
        let store = try await store(transport)
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/account/adjustments", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        await store.load()
        #expect(!store.listSupported && store.adjustments.isEmpty && store.error == nil && store.account != nil)
    }

    @Test func deleteReplacesBalanceReloadsListAndNotifies() async throws {
        let transport = MockTransport()
        let store = try await store(transport)
        var outcomes: [StoreOutcome] = []
        var saved = 0
        store.onOutcome = { outcomes.append($0) }
        store.onSaved = { saved += 1 }
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/account/adjustments", body: Self.page([(Self.a1, "correction", -3600), (Self.a2, "correction", 60)], total: 2))
        await store.load()
        transport.enqueue("DELETE /api/v1/time/account/adjustments/\(Self.a1)", body: Self.balanceAfter)
        transport.set("GET /api/v1/time/account/adjustments", body: Self.page([(Self.a2, "correction", 60)], total: 1))
        let target = try #require(store.adjustments.first)
        #expect(await store.delete(target))
        #expect(store.account?.balanceSeconds == -4680 && store.adjustments.map(\.id) == [UUID(uuidString: Self.a2)!] && store.adjustmentTotal == 1)
        #expect(store.deletingId == nil && saved == 1 && outcomes == [.deleted])
        let delete = try #require(transport.requests(matching: "DELETE /api/v1/time/account/adjustments/\(Self.a1)").first)
        #expect(delete.value(forHTTPHeaderField: "X-CSRF-Token") == "tok")
    }

    @Test func deleteOfUnknownIdReloadsListAndReportsGermanError() async throws {
        let transport = MockTransport()
        let store = try await store(transport)
        var outcomes: [StoreOutcome] = []
        store.onOutcome = { outcomes.append($0) }
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/account/adjustments", body: Self.page([(Self.a1, "correction", -3600)], total: 1))
        await store.load()
        transport.enqueue("DELETE /api/v1/time/account/adjustments/\(Self.a1)", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        transport.set("GET /api/v1/time/account/adjustments", body: Self.page([], total: 0))
        #expect(!(await store.delete(try #require(store.adjustments.first))))
        #expect(store.adjustments.isEmpty && outcomes == [.failed])
        #expect(try #require(store.error).germanMessage(in: .accountAdjustment).hasPrefix("Diese Anpassung gibt es nicht"))
        #expect(store.account?.balanceSeconds == -1080, "balance stays untouched on failure")
    }

    @Test func bookingReloadsTheList() async throws {
        let transport = MockTransport()
        let store = try await store(transport)
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/account/adjustments", body: Self.page([], total: 0))
        await store.load()
        transport.enqueue("POST /api/v1/time/account/adjustments", status: 201, body: Self.balanceAfter)
        transport.set("GET /api/v1/time/account/adjustments", body: Self.page([(Self.a1, "correction", -3600)], total: 1))
        #expect(await store.book(AccountAdjustmentForm(kind: .correction, date: "2026-10-12", value: "-1:00", reason: "Korrektur")))
        #expect(store.adjustments.count == 1 && store.account?.adjustmentSeconds == -3600)
    }

    @Test func secondOpeningBalanceConflictGetsExplanation() {
        let conflict = TimetrackError.api(status: 409, code: "conflict", message: "x")
        #expect(conflict.germanMessage(in: .accountAdjustment).contains("Anfangsstand"))
        #expect(TimetrackError.api(status: 400, code: "invalid", message: "x").germanMessage(in: .accountAdjustment).contains("200 Zeichen"))
        #expect(TimetrackError.network(.notConnectedToInternet).germanMessage(in: .accountAdjustment) == TimetrackError.network(.notConnectedToInternet).germanDescription)
    }
}

@MainActor
@Suite struct ReviewAcknowledgeTests {
    static let id = "33333333-3333-4333-8333-333333333333"

    @Test func correctionBodyCarriesNeedsReviewFalseOnlyWhenAcknowledging() throws {
        let ack = try JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(SegmentCorrection(reason: "Geprüft", acknowledgeReview: true))) as? [String: Any]
        #expect(ack?["needsReview"] as? Bool == false && ack?["reason"] as? String == "Geprüft" && ack?.count == 2)
        let plain = try JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(SegmentCorrection(note: "x", reason: "r"))) as? [String: Any]
        #expect(plain?["needsReview"] == nil)
    }

    @Test func listStoreAcknowledgeSendsPatchWithIfMatchAndReloads() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok"))
        let flagged = Fixtures.closedSegmentJSON
        transport.enqueue("PATCH /api/v1/time/segments/\(Self.id)", body: flagged.replacingOccurrences(of: #""version":3"#, with: #""version":4"#).replacingOccurrences(of: #""needsReview":true"#, with: #""needsReview":false"#))
        transport.enqueue("GET /api/v1/time/days", body: "[]")
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        let store = TimeListStore(client: client, calendar: DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!))
        var outcomes: [StoreOutcome] = []
        store.onOutcome = { outcomes.append($0) }
        let segment = try JSONCoding.makeDecoder().decode(Segment.self, from: Data(flagged.utf8))
        #expect(segment.needsReview && segment.version == 3)
        #expect(await store.acknowledge(segment))
        let patch = try #require(transport.requests(matching: "PATCH /api/v1/time/segments/\(Self.id)").first)
        #expect(patch.value(forHTTPHeaderField: "If-Match") == "3" && body(patch)["needsReview"] as? Bool == false && body(patch)["reason"] as? String == "Geprüft")
        #expect(outcomes == [.saved])
    }

    @Test func staleVersionIsReportedWithAGermanReviewMessage() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok"))
        transport.enqueue("PATCH /api/v1/time/segments/\(Self.id)", status: 412, body: #"{"error":{"code":"stale_version","message":"x"}}"#)
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        let store = TimeListStore(client: client, calendar: DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!))
        let segment = try JSONCoding.makeDecoder().decode(Segment.self, from: Data(Fixtures.closedSegmentJSON.utf8))
        #expect(!(await store.acknowledge(segment)))
        #expect(try #require(store.error).germanMessage(in: .reviewAcknowledge).contains("inzwischen geändert"))
    }

    @Test func reviewConfirmAcknowledgesOnTheServerAndDismissesLocally() async throws {
        let suite = "p15.review.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok"))
        transport.enqueue("GET /api/v1/time/suggestions", body: "[]")
        transport.enqueue("GET /api/v1/time/segments", body: "[\(Fixtures.closedSegmentJSON)]")
        transport.enqueue("PATCH /api/v1/time/segments/\(Self.id)", body: Fixtures.closedSegmentJSON.replacingOccurrences(of: #""needsReview":true"#, with: #""needsReview":false"#))
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        let review = ReviewStore(client: client, calendar: DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!), dismissals: ReviewDismissals(suiteName: suite))
        await review.load()
        #expect(review.count == 1)
        #expect(await review.confirm(review.items[0]))
        let patch = try #require(transport.requests(matching: "PATCH /api/v1/time/segments/\(Self.id)").first)
        #expect(body(patch)["needsReview"] as? Bool == false && patch.value(forHTTPHeaderField: "If-Match") == "3")
        #expect(review.count == 0)
    }
}
