import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// BH1: Berichtsheft. Synthetic data only; the contract is openapi 0.27.0 (ADR-0008).

enum ReportFixtures {
    static let fieldA = "aaaaaaaa-0000-4000-8000-000000000001"
    static let fieldB = "aaaaaaaa-0000-4000-8000-000000000002"
    static let entry1 = "eeeeeeee-0000-4000-8000-000000000001"
    static let entry2 = "eeeeeeee-0000-4000-8000-000000000002"
    static let entry3 = "eeeeeeee-0000-4000-8000-000000000003"

    static let fields = #"""
    [{"id":"\#(fieldB)","number":2,"name":"Netzwerke planen","sortOrder":1},
     {"id":"\#(fieldA)","number":1,"name":"Arbeitsplatz einrichten","sortOrder":0,"futureField":true}]
    """#

    static func entry(_ id: String, date: String, field: String, fieldId: String? = nil, seconds: Int, notes: String, version: Int = 1, draft: Bool? = nil) -> String {
        let fieldIdJSON = fieldId.map { "\"\($0)\"" } ?? "null"
        let draftJSON = draft.map { ",\"draft\":\($0)" } ?? ""
        return #"{"id":"\#(id)","version":\#(version),"date":"\#(date)","learningFieldId":\#(fieldIdJSON),"learningField":"\#(field)","durationSeconds":\#(seconds),"notes":"\#(notes)","createdAt":"2026-10-26T08:00:00.250Z"\#(draftJSON)}"#
    }

    static let week44 = #"""
    {"year":2026,"week":44,"startDate":"2026-10-26","endDate":"2026-11-01","status":"draft",
     "entries":[\#(entry(entry1, date: "2026-10-26", field: "Arbeitsplatz einrichten", fieldId: fieldA, seconds: 5400, notes: "Rechner installiert")),
                \#(entry(entry2, date: "2026-10-27", field: "Netzwerke planen", fieldId: fieldB, seconds: 7200, notes: #"Zeile 1\nZeile 2"#, draft: true))],
     "totalSeconds":12600,"byLearningField":[{"learningField":"Arbeitsplatz einrichten","seconds":5400},{"learningField":"Netzwerke planen","seconds":7200}],
     "trackedWorkSeconds":99000,"sourceCount":1,"futureField":1}
    """#

    static let emptyWeek45 = #"""
    {"year":2026,"week":45,"startDate":"2026-11-02","endDate":"2026-11-08","status":"done","entries":[],"totalSeconds":0,"byLearningField":[],"sourceCount":0}
    """#

    static let sources = #"""
    [{"id":"bbbbbbbb-0000-4000-8000-000000000001","year":2026,"week":44,"date":null,"note":"Stichpunkte","fileId":null,"createdAt":"2026-10-26T09:00:00Z","file":null}]
    """#

    static let now = Date(timeIntervalSince1970: 1_793_000_000) // 2026-10-26, Monday of week 44 (UTC)
    static let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    @MainActor static func store(_ transport: MockTransport) -> ReportsStore {
        ReportsStore(client: Fixtures.client(transport), calendar: calendar, now: now)
    }

    static func loaded(_ transport: MockTransport) async -> ReportsStore {
        transport.set("GET /api/v1/reports/weeks/2026/44", body: week44)
        transport.set("GET /api/v1/reports/sources", body: sources)
        transport.set("GET /api/v1/reports/learning-fields", body: fields)
        let store = await Self.store(transport)
        await store.load()
        return store
    }

    static func jsonBody(_ request: URLRequest?) -> [String: Any]? {
        request?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

@MainActor
@Suite struct ReportModelTests {
    @Test func weekRefsFollowIsoWeeksAcrossTheYearBoundary() {
        let ref = ReportWeekRef(containing: "2026-12-31")
        #expect(ref == ReportWeekRef(year: 2026, week: 53))
        #expect(ReportWeekRef(containing: "2027-01-01") == ReportWeekRef(year: 2026, week: 53))
        #expect(ReportWeekRef(year: 2026, week: 53).shifted(by: 1) == ReportWeekRef(year: 2027, week: 1))
        #expect(ReportWeekRef(year: 2027, week: 1).shifted(by: -1) == ReportWeekRef(year: 2026, week: 53))
        #expect(ReportWeekRef.weeksIn(2026) == 53 && ReportWeekRef.weeksIn(2027) == 52)
        #expect(ReportWeekRef.valid(year: 2027, week: 53) == ReportWeekRef(year: 2027, week: 52))
        let w44 = ReportWeekRef(year: 2026, week: 44)
        #expect(w44.monday == "2026-10-26" && w44.sunday == "2026-11-01" && w44.days.count == 7 && w44.title == "KW 44/2026")
        #expect(ReportWeekRef(label: "2026-W44") == w44 && w44.label == "2026-W44")
    }

    @Test func weekDecodesWithUnknownFieldsAndStatuses() throws {
        let week = try JSONCoding.makeDecoder().decode(ReportWeek.self, from: Data(ReportFixtures.week44.utf8))
        #expect(week.entries.count == 2 && week.totalSeconds == 12600 && week.trackedWorkSeconds == 99000 && week.sourceCount == 1)
        #expect(week.entries[0].draft == false && week.entries[1].draft == true)
        #expect(week.entries[0].learningFieldId?.uuidString.lowercased() == ReportFixtures.fieldA)
        #expect(week.entries(on: "2026-10-27").count == 1)
        let odd = try JSONCoding.makeDecoder().decode(ReportWeek.self, from: Data(ReportFixtures.emptyWeek45.replacingOccurrences(of: "\"done\"", with: "\"archived\"").utf8))
        #expect(odd.status == .draft)
    }

    @Test func learningFieldsSortAndShowTheNumber() throws {
        let fields = try JSONCoding.makeDecoder().decode([LearningField].self, from: Data(ReportFixtures.fields.utf8))
        #expect(ReportsStore.ordered(fields).map(\.name) == ["Arbeitsplatz einrichten", "Netzwerke planen"])
        #expect(fields[0].displayName == "LF 2 · Netzwerke planen" && LearningField(name: "Frei").displayName == "Frei")
    }

    @Test func inputsEncodeExplicitNullsForRemovedLinks() throws {
        let input = ReportEntryInput(date: "2026-10-26", learningField: "Frei", durationSeconds: 60, notes: "x")
        let json = try #require(try JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(input)) as? [String: Any])
        #expect(json["learningFieldId"] is NSNull && json["durationSeconds"] as? Int == 60)
        let field = try #require(try JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(LearningFieldInput(name: "A"))) as? [String: Any])
        #expect(field["number"] is NSNull && field["sortOrder"] as? Int == 0)
    }
}

@Suite struct ReportDurationTests {
    @Test(arguments: [
        ("", 0, ReportDuration.Kind.empty), ("1:30", 5400, .clock), ("01:30", 5400, .clock), ("0:45", 2700, .clock),
        ("1,5", 5400, .decimal), ("1.5", 5400, .decimal), ("7,7", 27720, .decimal), (",5", 1800, .decimal), ("2", 7200, .hours), ("24", 86400, .hours),
    ])
    func accepted(input: String, seconds: Int, kind: ReportDuration.Kind) {
        #expect(ReportDuration.parse(input) == ReportDuration.Parsed(seconds: seconds, kind: kind))
    }

    @Test(arguments: ["abc", "1:75", "25", "24:01", "1,555", "-1", "1:5", "1h"])
    func rejected(input: String) { #expect(ReportDuration.parse(input) == nil) }

    @Test func inputValueRoundTrips() {
        #expect(ReportDuration.inputValue(5400) == "1:30" && ReportDuration.inputValue(0) == "" && ReportDuration.inputValue(27720) == "7:42")
    }
}

@Suite struct ReportTextTests {
    private func entries() throws -> [ReportEntry] {
        try JSONCoding.makeDecoder().decode(ReportWeek.self, from: Data(ReportFixtures.week44.utf8)).entries
    }

    @Test func plainTextFollowsTheStandardFormat() throws {
        let text = ReportText.plain(week: ReportWeekRef(year: 2026, week: 44), entries: try entries())
        #expect(text == """
        Berichtsheft KW 44/2026 (26.10.2026 – 01.11.2026)

        Montag, 26.10.2026
        Arbeitsplatz einrichten | 1:30 h | Rechner installiert

        Dienstag, 27.10.2026
        Netzwerke planen | 2:00 h | Zeile 1 / Zeile 2

        Summe: 3:30 h

        """)
    }

    @Test func emptyNotesOmitTheLastColumnAndLineBreaksBecomeSlashes() {
        let entry = ReportEntry(date: "2026-10-28", learningField: "A\nB", durationSeconds: 3599, notes: "  \n ")
        let text = ReportText.plain(week: ReportWeekRef(year: 2026, week: 44), entries: [entry])
        #expect(text.contains("Mittwoch, 28.10.2026\nA / B | 0:59 h\n"))
        #expect(ReportText.singleLine("a\r\n\r\n b \u{2028}c") == "a / b / c")
    }

    @Test func htmlEscapesAndKeepsStructure() {
        let entry = ReportEntry(date: "2026-10-26", learningField: "R&D <1>", durationSeconds: 1800, notes: "a\nb")
        let html = ReportText.html(week: ReportWeekRef(year: 2026, week: 44), entries: [entry])
        #expect(html.contains("R&amp;D &lt;1&gt;") && html.contains("a<br>b") && html.contains("<table") && html.contains("Summe: 0:30 h"))
    }
}

@MainActor
@Suite struct ReportsStoreTests {
    @Test func loadsWeekSourcesAndFieldsAndNavigates() async {
        let transport = MockTransport()
        let store = await ReportFixtures.loaded(transport)
        #expect(store.week == ReportWeekRef(year: 2026, week: 44) && store.isCurrentWeek)
        #expect(store.entries.count == 2 && store.sources.count == 1 && store.learningFields.map(\.name) == ["Arbeitsplatz einrichten", "Netzwerke planen"])
        transport.set("GET /api/v1/reports/weeks/2026/45", body: ReportFixtures.emptyWeek45)
        transport.set("GET /api/v1/reports/sources", body: "[]")
        await store.shiftWeeks(1)
        #expect(store.week.week == 45 && store.status == .done && store.entries.isEmpty && !store.isCurrentWeek)
        transport.set("GET /api/v1/reports/weeks/2026/44", body: ReportFixtures.week44)
        await store.goToCurrentWeek()
        #expect(store.week.week == 44 && store.entries.count == 2)
    }

    @Test func unknownEndpointMeansUnavailableNotAnError() async {
        let transport = MockTransport()
        transport.set("GET /api/v1/reports/weeks/2026/44", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let store = ReportFixtures.store(transport)
        await store.load()
        #expect(store.isUnavailable && store.error == nil && store.data == nil)
    }

    @Test func networkFailureIsShownAndKeepsTheOldWeek() async {
        let transport = MockTransport()
        let store = await ReportFixtures.loaded(transport)
        transport.set("GET /api/v1/reports/weeks/2026/44", error: .notConnectedToInternet)
        await store.load()
        #expect(store.error?.isNetworkError == true && store.entries.count == 2 && !store.isUnavailable)
    }

    @Test func statusChangeIsSentAndApplied() async {
        let transport = MockTransport()
        let store = await ReportFixtures.loaded(transport)
        transport.set("PUT /api/v1/reports/weeks/2026/44", body: ReportFixtures.week44.replacingOccurrences(of: "\"draft\",", with: "\"done\","))
        var outcomes: [StoreOutcome] = []
        store.onOutcome = { outcomes.append($0) }
        await store.setStatus(.done)
        #expect(ReportFixtures.jsonBody(transport.requests(matching: "PUT /api/v1/reports/weeks/2026/44").first)?["status"] as? String == "done")
        #expect(store.status == .done && outcomes == [.saved])
    }

    @Test func savingMergesEntriesAndRecomputesTheSums() async throws {
        let transport = MockTransport()
        let store = await ReportFixtures.loaded(transport)
        transport.set("POST /api/v1/reports/entries", status: 201,
                          body: ReportFixtures.entry(ReportFixtures.entry3, date: "2026-10-27", field: "Netzwerke planen", fieldId: ReportFixtures.fieldB, seconds: 1800, notes: ""))
        let created = try await store.save(ReportEntryInput(date: "2026-10-27", learningFieldId: UUID(uuidString: ReportFixtures.fieldB), learningField: "Netzwerke planen", durationSeconds: 1800), replacing: nil)
        #expect(store.entries.count == 3 && store.data?.totalSeconds == 14400)
        #expect(store.data?.byLearningField == [ReportFieldTotal(learningField: "Arbeitsplatz einrichten", seconds: 5400), ReportFieldTotal(learningField: "Netzwerke planen", seconds: 9000)])
        // Update: the old version travels in If-Match; the day moves out of the week, so the entry leaves the list.
        transport.set("PUT /api/v1/reports/entries/\(ReportFixtures.entry3)",
                          body: ReportFixtures.entry(ReportFixtures.entry3, date: "2026-11-03", field: "Netzwerke planen", seconds: 1800, notes: "", version: 2))
        _ = try await store.save(created.input.with(date: "2026-11-03"), replacing: created)
        let put = transport.requests(matching: "PUT /api/v1/reports/entries/\(ReportFixtures.entry3)").first
        #expect(put?.value(forHTTPHeaderField: "If-Match") == "1" && store.entries.count == 2 && store.data?.totalSeconds == 12600)
    }

    @Test func deletingRemovesLocallyAndTreats404AsDone() async {
        let transport = MockTransport()
        let store = await ReportFixtures.loaded(transport)
        transport.set("DELETE /api/v1/reports/entries/\(ReportFixtures.entry1)", status: 204)
        #expect(await store.delete(store.entries[0]))
        #expect(store.entries.count == 1 && store.data?.totalSeconds == 7200)
        transport.set("DELETE /api/v1/reports/entries/\(ReportFixtures.entry2)", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        #expect(await store.delete(store.entries[0]) && store.entries.isEmpty)
    }

    @Test func learningFieldsCreateRenameDeleteAndDuplicate() async {
        let transport = MockTransport()
        let store = await ReportFixtures.loaded(transport)
        #expect(ReportsStore.problem(name: "  ", number: nil) == .nameMissing && ReportsStore.problem(name: String(repeating: "x", count: 121), number: nil) == .nameTooLong)
        #expect(await store.saveLearningField(name: " ", number: nil, editing: nil) == false)
        #expect(transport.requests(matching: "POST /api/v1/reports/learning-fields").isEmpty)
        transport.set("POST /api/v1/reports/learning-fields", status: 201, body: #"{"id":"aaaaaaaa-0000-4000-8000-000000000003","number":3,"name":"Datenbanken","sortOrder":2}"#)
        #expect(await store.saveLearningField(name: " Datenbanken ", number: 3, editing: nil))
        let body = ReportFixtures.jsonBody(transport.requests(matching: "POST /api/v1/reports/learning-fields").first)
        #expect(body?["name"] as? String == "Datenbanken" && body?["sortOrder"] as? Int == 2 && store.learningFields.count == 3)
        transport.set("POST /api/v1/reports/learning-fields", status: 409, body: #"{"error":{"code":"learning_field_exists","message":"x"}}"#)
        #expect(await store.saveLearningField(name: "Datenbanken", number: nil, editing: nil) == false)
        #expect(store.error?.knownCode == .learningFieldExists && store.error?.germanDescription == "Ein Lernfeld mit diesem Namen gibt es schon.")
        transport.set("PUT /api/v1/reports/learning-fields/\(ReportFixtures.fieldA)", body: #"{"id":"\#(ReportFixtures.fieldA)","number":null,"name":"Einrichten","sortOrder":0}"#)
        #expect(await store.saveLearningField(name: "Einrichten", number: nil, editing: store.learningFields[0]))
        #expect(store.learningFields[0].name == "Einrichten" && store.learningFields[0].number == nil)
        transport.set("DELETE /api/v1/reports/learning-fields/\(ReportFixtures.fieldB)", status: 204)
        #expect(await store.deleteLearningField(store.learningFields[1]) && store.learningFields.count == 2)
    }

    @Test func reorderingStoresNewSortOrderOnlyForMovedFields() async {
        let transport = MockTransport()
        let store = await ReportFixtures.loaded(transport) // order: A (0), B (1)
        transport.set("PUT /api/v1/reports/learning-fields/\(ReportFixtures.fieldB)", body: #"{"id":"\#(ReportFixtures.fieldB)","number":2,"name":"Netzwerke planen","sortOrder":0}"#)
        transport.set("PUT /api/v1/reports/learning-fields/\(ReportFixtures.fieldA)", body: #"{"id":"\#(ReportFixtures.fieldA)","number":1,"name":"Arbeitsplatz einrichten","sortOrder":1}"#)
        await store.moveLearningField(from: IndexSet(integer: 1), to: 0)
        #expect(store.learningFields.map(\.name) == ["Netzwerke planen", "Arbeitsplatz einrichten"])
        #expect(ReportFixtures.jsonBody(transport.requests(matching: "PUT /api/v1/reports/learning-fields/\(ReportFixtures.fieldB)").first)?["sortOrder"] as? Int == 0)
    }

    @Test func sourcesNotesAndFilesUpdateTheCount() async {
        let transport = MockTransport()
        let store = await ReportFixtures.loaded(transport)
        #expect(await store.addNoteSource("  ", day: nil) == false)
        transport.set("POST /api/v1/reports/sources", status: 201, body: #"{"id":"bbbbbbbb-0000-4000-8000-000000000002","year":2026,"week":44,"date":"2026-10-27","note":"Plan","createdAt":"2026-10-27T09:00:00Z"}"#)
        #expect(await store.addNoteSource(" Plan ", day: "2026-10-27"))
        let body = ReportFixtures.jsonBody(transport.requests(matching: "POST /api/v1/reports/sources").first)
        #expect(body?["note"] as? String == "Plan" && body?["date"] as? String == "2026-10-27" && body?["year"] as? Int == 2026 && store.data?.sourceCount == 2)
        transport.set("POST /api/v1/files", status: 201, body: #"{"id":"cccccccc-0000-4000-8000-000000000001","name":"foto.jpg","size":4,"sha256":"x","contentType":"image/jpeg","createdAt":"2026-10-27T09:00:00Z"}"#)
        transport.set("POST /api/v1/reports/sources", status: 201, body: #"{"id":"bbbbbbbb-0000-4000-8000-000000000003","year":2026,"week":44,"fileId":"cccccccc-0000-4000-8000-000000000001","createdAt":"2026-10-27T09:00:00Z"}"#)
        #expect(await store.addFileSource(name: "foto.jpg", contentType: "image/jpeg", data: Data([1, 2, 3, 4]), day: nil))
        #expect(store.sources.count == 3 && store.sources.last?.isFile == true && store.data?.sourceCount == 3)
        let upload = transport.requests(matching: "POST /api/v1/files").first
        #expect(upload?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let text = String(decoding: upload?.httpBody ?? Data(), as: UTF8.self)
        #expect(text.contains("name=\"file\"; filename=\"foto.jpg\"") && text.contains("Content-Type: image/jpeg"))
        transport.set("DELETE /api/v1/reports/sources/bbbbbbbb-0000-4000-8000-000000000003", status: 204)
        #expect(await store.removeSource(store.sources[2]) && store.sources.count == 2 && store.data?.sourceCount == 2)
    }

    @Test func failedUploadKeepsEverythingAndReportsTheLimit() async {
        let transport = MockTransport()
        let store = await ReportFixtures.loaded(transport)
        transport.set("POST /api/v1/files", status: 413, body: #"{"error":{"code":"file_too_large","message":"x"}}"#)
        #expect(await store.addFileSource(name: "gross.pdf", contentType: "application/pdf", data: Data([1]), day: nil) == false)
        #expect(store.error?.knownCode == .fileTooLarge && store.sources.count == 1 && transport.requests(matching: "POST /api/v1/reports/sources").isEmpty)
    }

    @Test func copyUsesTheServerTextAndFallsBackToTheLocalFormat() async {
        let transport = MockTransport()
        let store = await ReportFixtures.loaded(transport)
        transport.set("GET /api/v1/reports/weeks/2026/44/text", body: "SERVER TEXT\n")
        let served = await store.copyPayload()
        #expect(served.plain == "SERVER TEXT\n" && served.html.contains("<table") && !served.isEmpty)
        #expect(transport.requests(matching: "GET /api/v1/reports/weeks/2026/44/text").first?.value(forHTTPHeaderField: "Accept") == "text/plain")
        transport.set("GET /api/v1/reports/weeks/2026/44/text", error: .timedOut)
        let local = await store.copyPayload()
        #expect(local.plain.hasPrefix("Berichtsheft KW 44/2026") && local.plain.contains("Summe: 3:30 h"))
    }
}

extension ReportEntryInput {
    fileprivate func with(date: LocalDay) -> ReportEntryInput {
        var copy = self
        copy.date = date
        return copy
    }
}

@MainActor
@Suite struct ReportEntryEditorTests {
    private func editor(_ transport: MockTransport, entry: ReportEntry? = nil, debounce: Duration = .zero,
                        sleeper: @escaping @Sendable (Duration) async throws -> Void = { _ in }) async -> (ReportsStore, ReportEntryEditor) {
        let store = await ReportFixtures.loaded(transport)
        let editor = ReportEntryEditor(store: store, entry: entry, day: "2026-10-28", debounce: debounce, sleeper: sleeper)
        return (store, editor)
    }

    @Test func newEntryIsOnlyCreatedOnceTheFieldIsSetAndThenUpdatedWithItsVersion() async {
        let transport = MockTransport()
        let (store, editor) = await editor(transport)
        #expect(editor.state == .idle && !editor.hasUnsavedChanges)
        editor.notes = "Notiz zuerst"
        await editor.flush()
        #expect(editor.state == .invalid && transport.requests(matching: "POST /api/v1/reports/entries").isEmpty)
        transport.set("POST /api/v1/reports/entries", status: 201,
                          body: ReportFixtures.entry(ReportFixtures.entry3, date: "2026-10-28", field: "Arbeitsplatz einrichten", fieldId: ReportFixtures.fieldA, seconds: 2700, notes: "Notiz zuerst"))
        editor.select(store.learningFields[0])
        editor.durationText = "0:45"
        await editor.flush()
        let created = ReportFixtures.jsonBody(transport.requests(matching: "POST /api/v1/reports/entries").first)
        #expect(created?["learningFieldId"] as? String == ReportFixtures.fieldA.uppercased() || created?["learningFieldId"] as? String == ReportFixtures.fieldA)
        #expect(created?["durationSeconds"] as? Int == 2700 && created?["date"] as? String == "2026-10-28")
        #expect(editor.state == .saved && editor.entry?.version == 1 && store.entries.count == 3)
        transport.set("PUT /api/v1/reports/entries/\(ReportFixtures.entry3)",
                          body: ReportFixtures.entry(ReportFixtures.entry3, date: "2026-10-28", field: "Arbeitsplatz einrichten", fieldId: ReportFixtures.fieldA, seconds: 2700, notes: "Neu", version: 2))
        editor.notes = "Neu"
        await editor.flush()
        #expect(transport.requests(matching: "PUT /api/v1/reports/entries/\(ReportFixtures.entry3)").first?.value(forHTTPHeaderField: "If-Match") == "1")
        #expect(editor.entry?.version == 2 && editor.state == .saved && !editor.hasUnsavedChanges)
    }

    @Test func typedNameLinksTheListFieldOtherwiseItStaysFreeText() async {
        let transport = MockTransport()
        let (_, editor) = await editor(transport)
        editor.fieldName = "netzwerke PLANEN"
        #expect(editor.fieldId?.uuidString.lowercased() == ReportFixtures.fieldB)
        editor.fieldName = "Eigenes Thema"
        #expect(editor.fieldId == nil && editor.problems.isEmpty)
        editor.durationText = "1:99"
        #expect(editor.problems == .durationInvalid && editor.state == .invalid)
        editor.durationText = ""
        editor.notes = String(repeating: "x", count: 4001)
        #expect(editor.problems == .notesTooLong)
    }

    @Test func debounceSendsOnlyTheLastStateOfFastTyping() async {
        let transport = MockTransport()
        let gate = SleepGate()
        let (_, editor) = await editor(transport, debounce: .seconds(1), sleeper: { _ in try await gate.wait() })
        transport.set("POST /api/v1/reports/entries", status: 201,
                          body: ReportFixtures.entry(ReportFixtures.entry3, date: "2026-10-28", field: "Frei", seconds: 0, notes: "abc"))
        editor.fieldName = "Frei"
        editor.notes = "a"
        editor.notes = "ab"
        editor.notes = "abc"
        #expect(editor.state == .pending && transport.requests(matching: "POST /api/v1/reports/entries").isEmpty)
        await gate.openAll()
        for _ in 0..<200 where editor.state != .saved { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(editor.state == .saved)
        #expect(transport.requests(matching: "POST /api/v1/reports/entries").count == 1)
        #expect(ReportFixtures.jsonBody(transport.requests(matching: "POST /api/v1/reports/entries").first)?["notes"] as? String == "abc")
    }

    @Test func offlineKeepsTheInputAndARetrySucceeds() async {
        let transport = MockTransport()
        let (_, editor) = await editor(transport)
        transport.set("POST /api/v1/reports/entries", error: .notConnectedToInternet)
        editor.fieldName = "Frei"
        editor.notes = "Wichtig"
        await editor.flush()
        guard case .failed(let failure) = editor.state else { Issue.record("expected failed, got \(editor.state)"); return }
        #expect(failure.isNetworkError && editor.notes == "Wichtig" && editor.hasUnsavedChanges && editor.entry == nil)
        transport.set("POST /api/v1/reports/entries", status: 201, body: ReportFixtures.entry(ReportFixtures.entry3, date: "2026-10-28", field: "Frei", seconds: 0, notes: "Wichtig"))
        await editor.flush()
        #expect(editor.state == .saved && editor.entry != nil && !editor.hasUnsavedChanges)
    }

    @Test func staleVersionOffersServerVersionOrKeepingMine() async throws {
        let transport = MockTransport()
        let store = await ReportFixtures.loaded(transport)
        let existing = store.entries[0]
        let editor = ReportEntryEditor(store: store, entry: existing, day: existing.date, debounce: .zero, sleeper: { _ in })
        let changedElsewhere = ReportFixtures.entry(ReportFixtures.entry1, date: "2026-10-26", field: "Arbeitsplatz einrichten", fieldId: ReportFixtures.fieldA, seconds: 3600, notes: "Von woanders", version: 5)
        transport.set("PUT /api/v1/reports/entries/\(ReportFixtures.entry1)", status: 412, body: #"{"error":{"code":"stale_version","message":"x"}}"#)
        transport.set("GET /api/v1/reports/weeks/2026/44", body: ReportFixtures.week44.replacingOccurrences(of: ReportFixtures.entry(ReportFixtures.entry1, date: "2026-10-26", field: "Arbeitsplatz einrichten", fieldId: ReportFixtures.fieldA, seconds: 5400, notes: "Rechner installiert"), with: changedElsewhere))
        editor.notes = "Meine Fassung"
        await editor.flush()
        guard case .conflict(let current) = editor.state else { Issue.record("expected conflict, got \(editor.state)"); return }
        #expect(current?.version == 5 && current?.notes == "Von woanders")
        // Keep mine: saved with the newest version in If-Match.
        transport.set("PUT /api/v1/reports/entries/\(ReportFixtures.entry1)", body: ReportFixtures.entry(ReportFixtures.entry1, date: "2026-10-26", field: "Arbeitsplatz einrichten", fieldId: ReportFixtures.fieldA, seconds: 5400, notes: "Meine Fassung", version: 6))
        await editor.keepMine()
        let puts = transport.requests(matching: "PUT /api/v1/reports/entries/\(ReportFixtures.entry1)")
        #expect(puts.last?.value(forHTTPHeaderField: "If-Match") == "5" && editor.state == .saved && editor.entry?.version == 6)
        // Second round: take the server version instead.
        transport.set("PUT /api/v1/reports/entries/\(ReportFixtures.entry1)", status: 412, body: #"{"error":{"code":"stale_version","message":"x"}}"#)
        transport.set("GET /api/v1/reports/weeks/2026/44", body: ReportFixtures.week44.replacingOccurrences(of: ReportFixtures.entry(ReportFixtures.entry1, date: "2026-10-26", field: "Arbeitsplatz einrichten", fieldId: ReportFixtures.fieldA, seconds: 5400, notes: "Rechner installiert"), with: changedElsewhere))
        editor.notes = "Noch eine"
        await editor.flush()
        editor.useServerVersion()
        #expect(editor.notes == "Von woanders" && editor.state == .saved && editor.entry?.version == 5 && !editor.hasUnsavedChanges)
    }

    @Test func entryDeletedElsewhereCanBeStoredAsNew() async {
        let transport = MockTransport()
        let store = await ReportFixtures.loaded(transport)
        let editor = ReportEntryEditor(store: store, entry: store.entries[0], day: "2026-10-26", debounce: .zero, sleeper: { _ in })
        transport.set("PUT /api/v1/reports/entries/\(ReportFixtures.entry1)", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        editor.notes = "Weiter"
        await editor.flush()
        #expect(editor.state == .gone)
        transport.set("POST /api/v1/reports/entries", status: 201, body: ReportFixtures.entry(ReportFixtures.entry3, date: "2026-10-26", field: "Arbeitsplatz einrichten", seconds: 5400, notes: "Weiter"))
        await editor.saveAsNew()
        #expect(editor.state == .saved && editor.entry?.id.uuidString.lowercased() == ReportFixtures.entry3)
    }
}

/// Test double for the debounce sleep: every `wait()` returns once `openAll()` ran. Cancelled debounce tasks wake as well and are
/// dropped by the editor's `Task.isCancelled` check, which is exactly what the test relies on.
actor SleepGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async throws {
        if opened { return }
        await withCheckedContinuation { continuation in
            if opened { continuation.resume() } else { waiters.append(continuation) }
        }
    }

    func openAll() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
