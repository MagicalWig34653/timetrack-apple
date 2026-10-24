import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// SG1: automation suggestions as a decision list and the "Storniert" bin. Synthetic data only.

private let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }

private func suggestion(_ n: Int, _ type: TimeSuggestion.Kind, start: Double? = nil, end: Double? = nil, place: Int? = nil, segment: Int? = nil) -> TimeSuggestion {
    TimeSuggestion(id: uuid(n), type: type, placeId: place.map(uuid), proposedStartedAt: start.map { t0.addingTimeInterval($0) },
                   proposedEndedAt: end.map { t0.addingTimeInterval($0) }, segmentId: segment.map(uuid), createdAt: t0)
}

private func segment(_ n: Int, start: Double = 0, end: Double? = nil, review: Bool = false) -> Segment {
    Segment(id: uuid(n), kind: .work, startedAt: t0.addingTimeInterval(start), endedAt: end.map { t0.addingTimeInterval($0) }, source: .automation, needsReview: review)
}

@Suite("SG1 suggestion entries") struct SuggestionEntriesTests {
    @Test func consumedSuggestionsAreLeftOutAndTheRestIsChronological() {
        let list = SuggestionEntries.entries(
            suggestions: [suggestion(3, .start, start: 7_200), suggestion(1, .end, end: 600, segment: 9), suggestion(2, .start, start: 60)],
            consumed: [uuid(1)], segments: [], calendar: calendar)
        #expect(list.map(\.id) == [uuid(2), uuid(3)])
        #expect(list.first?.day == calendar.day(for: t0.addingTimeInterval(60)))
    }

    @Test func duplicatesAppearOnce() {
        let list = SuggestionEntries.entries(suggestions: [suggestion(1, .start, start: 0), suggestion(1, .start, start: 0)], consumed: [], segments: [], calendar: calendar)
        #expect(list.count == 1)
    }

    @Test func endSuggestionFindsItsSegment() {
        let list = SuggestionEntries.entries(suggestions: [suggestion(1, .end, end: 3_600, place: 5, segment: 9)], consumed: [], segments: [segment(9)], calendar: calendar)
        #expect(list.first?.segment?.id == uuid(9))
        #expect(list.first?.canAccept == true)
    }

    @Test func acceptabilityFollowsTheProposal() {
        func entry(_ s: TimeSuggestion, seg: Segment? = nil) -> SuggestionEntry { SuggestionEntry(suggestion: s, segment: seg, day: "2027-01-15") }
        #expect(entry(suggestion(1, .start, start: 0)).canAccept)
        #expect(!entry(suggestion(1, .start)).canAccept)
        #expect(!entry(suggestion(1, .end)).canAccept)
        #expect(!entry(suggestion(1, .end, end: -60, segment: 9), seg: segment(9)).canAccept) // end before the entry's start
        #expect(!entry(suggestion(1, .unknown, start: 0)).canAccept)
        #expect(!entry(suggestion(1, .unknown, start: 0)).canAdjust)
    }
}

@Suite("SG1 suggestion draft") struct SuggestionDraftTests {
    let now = t0.addingTimeInterval(86_400)

    @Test func startSuggestionStartsRunningUnlessAnEndIsSet() {
        let entry = SuggestionEntry(suggestion: suggestion(1, .start, start: 600), day: "d")
        var draft = SuggestionDraft(entry: entry, now: now)
        #expect(draft.start == t0.addingTimeInterval(600))
        #expect(!draft.hasEnd)
        #expect(draft.overrides.startedAt == t0.addingTimeInterval(600))
        #expect(draft.overrides.endedAt == nil)
        draft.hasEnd = true
        draft.end = draft.start.addingTimeInterval(1_800)
        #expect(draft.isValid(now: now))
        #expect(draft.overrides.endedAt == draft.end)
        draft.end = draft.start.addingTimeInterval(-1)
        #expect(!draft.isValid(now: now))
    }

    @Test func endSuggestionOnlyChangesTheEndAndStaysAfterTheStart() {
        let seg = segment(9)
        let entry = SuggestionEntry(suggestion: suggestion(1, .end, end: 3_600, segment: 9), segment: seg, day: "d")
        var draft = SuggestionDraft(entry: entry, now: now)
        #expect(draft.end == t0.addingTimeInterval(3_600))
        #expect(draft.overrides.startedAt == nil)
        #expect(draft.isValid(now: now))
        draft.end = t0.addingTimeInterval(-10)
        #expect(!draft.isValid(now: now))
        draft.end = now.addingTimeInterval(60) // the future cannot be booked
        #expect(!draft.isValid(now: now))
    }

    @Test func startInTheFutureIsInvalid() {
        let entry = SuggestionEntry(suggestion: suggestion(1, .start, start: 0), day: "d")
        var draft = SuggestionDraft(entry: entry, now: now)
        draft.start = now.addingTimeInterval(60)
        #expect(!draft.isValid(now: now))
    }
}

private func iso(_ seconds: Double) -> String { JSONCoding.formatInstant(t0.addingTimeInterval(seconds)) }

private func suggestionJSON(_ s: TimeSuggestion) -> String {
    func field(_ d: Date?) -> String { d.map { "\"\(JSONCoding.formatInstant($0))\"" } ?? "null" }
    let type = s.type == .start ? "start" : "end"
    return #"{"id":"\#(s.id.uuidString.lowercased())","type":"\#(type)","placeId":\#(s.placeId.map { "\"\($0.uuidString.lowercased())\"" } ?? "null"),"proposedStartedAt":\#(field(s.proposedStartedAt)),"proposedEndedAt":\#(field(s.proposedEndedAt)),"segmentId":\#(s.segmentId.map { "\"\($0.uuidString.lowercased())\"" } ?? "null"),"createdAt":"\#(JSONCoding.formatInstant(s.createdAt))"}"#
}

private func segmentJSON(_ n: Int, start: Double = 0, end: Double? = nil, voided: Bool = false, review: Bool = false, version: Int = 1) -> String {
    let endValue = end.map { "\"\(iso($0))\"" } ?? "null"
    return #"{"id":"\#(uuid(n).uuidString.lowercased())","kind":"work","placeId":null,"startedAt":"\#(iso(start))","endedAt":\#(endValue),"rawStartedAt":"\#(iso(start))","rawEndedAt":\#(endValue),"source":"automation","note":null,"version":\#(version),"voided":\#(voided),"needsReview":\#(review),"revisions":0}"#
}

@MainActor
@Suite("SG1 review store with suggestions") struct SuggestionStoreTests {
    func store(_ transport: MockTransport, suite: String) -> ReviewStore {
        ReviewStore(client: Fixtures.client(transport), calendar: calendar, dismissals: ReviewDismissals(suiteName: suite))
    }

    func loaded(suggestions: [TimeSuggestion], segments: [String] = []) async -> (ReviewStore, MockTransport, String) {
        let suite = "sg1.store.\(UUID().uuidString)"
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/suggestions", body: "[\(suggestions.map(suggestionJSON).joined(separator: ","))]")
        transport.enqueue("GET /api/v1/time/segments", body: "[\(segments.joined(separator: ","))]")
        let review = store(transport, suite: suite)
        await review.load()
        return (review, transport, suite)
    }

    @Test func countAddsStandaloneSuggestionsToFlaggedEntries() async {
        let flagged = suggestion(1, .end, end: 3_600, segment: 9)
        let (review, _, suite) = await loaded(suggestions: [flagged, suggestion(2, .start, start: 100, place: 5)],
                                              segments: [segmentJSON(9, start: -90_000, review: true)])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        #expect(review.items.count == 1) // the flagged entry carries its own end proposal
        #expect(review.suggestions.map(\.id) == [uuid(2)]) // not listed twice
        #expect(review.count == 2)
    }

    @Test func acceptingSendsTheProposedTimesAndNothingIsBookedBefore() async {
        let (review, transport, suite) = await loaded(suggestions: [suggestion(2, .start, start: 100, place: 5)])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        #expect(transport.requests(matching: "POST /api/v1/time/suggestions/\(uuid(2).uuidString.lowercased())/accept").isEmpty)
        transport.enqueue("POST /api/v1/time/suggestions/\(uuid(2).uuidString.lowercased())/accept", body: segmentJSON(20, start: 100))
        transport.set("GET /api/v1/time/suggestions", body: "[]")
        #expect(await review.accept(review.suggestions[0]))
        let sent = transport.requests(matching: "POST /api/v1/time/suggestions/\(uuid(2).uuidString.lowercased())/accept")
        #expect(sent.count == 1)
        let body = String(data: sent[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("startedAt"))
        #expect(!body.contains("endedAt\":\"")) // a start suggestion starts a timer
        #expect(review.count == 0)
    }

    @Test func adjustedTimesReplaceTheProposal() async {
        let (review, transport, suite) = await loaded(suggestions: [suggestion(1, .end, end: 3_600, place: 5, segment: 9)],
                                                      segments: [segmentJSON(9, start: 0)])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let key = "POST /api/v1/time/suggestions/\(uuid(1).uuidString.lowercased())/accept"
        transport.enqueue(key, body: segmentJSON(9, start: 0, end: 1_800, version: 2))
        let chosen = t0.addingTimeInterval(1_800)
        #expect(await review.accept(review.suggestions[0], endedAt: chosen))
        let body = String(data: transport.requests(matching: key)[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains(JSONCoding.formatInstant(chosen)))
        #expect(!body.contains(iso(3_600)))
    }

    @Test func rejectingCallsRejectOnly() async {
        let (review, transport, suite) = await loaded(suggestions: [suggestion(2, .start, start: 100, place: 5)])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let key = "POST /api/v1/time/suggestions/\(uuid(2).uuidString.lowercased())/reject"
        transport.enqueue(key, status: 204)
        transport.set("GET /api/v1/time/suggestions", body: "[]")
        #expect(await review.reject(review.suggestions[0]))
        #expect(transport.requests(matching: key).count == 1)
        #expect(transport.requests(matching: "POST /api/v1/time/suggestions/\(uuid(2).uuidString.lowercased())/accept").isEmpty)
    }

    @Test func aRefusedAcceptKeepsTheSuggestionAndShowsTheError() async {
        let (review, transport, suite) = await loaded(suggestions: [suggestion(2, .start, start: 100, place: 5)])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        transport.enqueue("POST /api/v1/time/suggestions/\(uuid(2).uuidString.lowercased())/accept", status: 409,
                          body: #"{"error":{"code":"segment_overlap","message":"x"}}"#)
        #expect(!(await review.accept(review.suggestions[0])))
        #expect(review.error?.knownCode == .segmentOverlap)
        #expect(review.suggestions.count == 1)
    }

    @Test func bulkAcceptTakesTheOnesThatWorkAndReportsTheRest() async {
        let (review, transport, suite) = await loaded(suggestions: [suggestion(1, .start, start: 100, place: 5), suggestion(2, .start, start: 5_000, place: 5),
                                                                    suggestion(3, .unknown)])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let base = "POST /api/v1/time/suggestions/"
        transport.enqueue("\(base)\(uuid(1).uuidString.lowercased())/accept", body: segmentJSON(20, start: 100))
        transport.enqueue("\(base)\(uuid(2).uuidString.lowercased())/accept", status: 409, body: #"{"error":{"code":"segment_overlap","message":"x"}}"#)
        let outcome = await review.acceptAll()
        #expect(outcome.done == 1)
        #expect(outcome.failed == 1) // the unknown kind is never sent
        #expect(outcome.firstError?.knownCode == .segmentOverlap)
        #expect(transport.requests(matching: "\(base)\(uuid(3).uuidString.lowercased())/accept").isEmpty)
    }

    @Test func bulkRejectCountsEach() async {
        let (review, transport, suite) = await loaded(suggestions: [suggestion(1, .start, start: 100, place: 5), suggestion(2, .start, start: 5_000, place: 5)])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        for n in [1, 2] { transport.enqueue("POST /api/v1/time/suggestions/\(uuid(n).uuidString.lowercased())/reject", status: 204) }
        let outcome = await review.rejectAll()
        #expect(outcome.done == 2)
        #expect(outcome.failed == 0)
    }
}

// MARK: - Cancelled bin

private func cancelledJSON(_ n: Int, start: Double, reason: String? = "Falsch") -> String {
    let reasonValue = reason.map { "\"\($0)\"" } ?? "null"
    return #"{"segment":\#(segmentJSON(n, start: start, end: start + 3_600, voided: true)),"cancelledAt":"\#(iso(start + 7_200))","cancelReason":\#(reasonValue)}"#
}

private func pageJSON(_ items: [String], total: Int, offset: Int = 0) -> String {
    #"{"items":[\#(items.joined(separator: ","))],"total":\#(total),"limit":50,"offset":\#(offset)}"#
}

private let purgeJSON = #"{"dryRun":true,"segments":2,"revisions":5,"suggestions":1,"timerEvents":2,"automationEvents":0}"#

@MainActor
@Suite("SG1 cancelled bin") struct CancelledStoreTests {
    func loaded(_ transport: MockTransport, items: Int = 2, total: Int? = nil) async -> CancelledStore {
        transport.enqueue("GET /api/v1/time/segments/cancelled", body: pageJSON((1...items).map { cancelledJSON($0, start: Double($0) * 10_000) }, total: total ?? items))
        let store = CancelledStore(client: Fixtures.client(transport))
        await store.load()
        return store
    }

    @Test func decodesTheListWithReasonAndDate() async {
        let store = await loaded(MockTransport())
        #expect(store.items.count == 2)
        #expect(store.items[0].cancelReason == "Falsch")
        #expect(store.items[0].segment.voided)
        #expect(store.total == 2)
        #expect(!store.hasMore)
    }

    @Test func emptyBinIsEmptyOnlyAfterLoading() async {
        let transport = MockTransport()
        let store = CancelledStore(client: Fixtures.client(transport))
        #expect(!store.isEmpty)
        transport.enqueue("GET /api/v1/time/segments/cancelled", body: pageJSON([], total: 0))
        await store.load()
        #expect(store.isEmpty)
    }

    @Test func loadMorePagesByOffset() async {
        let transport = MockTransport()
        let store = await loaded(transport, items: 2, total: 3)
        #expect(store.hasMore)
        transport.set("GET /api/v1/time/segments/cancelled", body: pageJSON([cancelledJSON(3, start: 90_000)], total: 3, offset: 2))
        await store.loadMore()
        #expect(store.items.count == 3)
        let last = transport.requests(matching: "GET /api/v1/time/segments/cancelled").last
        #expect(last?.url?.query?.contains("offset=2") == true)
        #expect(!store.hasMore)
    }

    @Test func restoreSendsVersionAndReloads() async {
        let transport = MockTransport()
        let store = await loaded(transport)
        let key = "POST /api/v1/time/segments/\(uuid(1).uuidString.lowercased())/restore"
        transport.enqueue(key, body: segmentJSON(1, start: 10_000, end: 13_600, version: 2))
        transport.set("GET /api/v1/time/segments/cancelled", body: pageJSON([cancelledJSON(2, start: 20_000)], total: 1))
        #expect(await store.restore(store.items[0]))
        let sent = transport.requests(matching: key)[0]
        #expect(sent.value(forHTTPHeaderField: "If-Match") == "1")
        #expect(store.items.map(\.id) == [uuid(2)])
        #expect(store.restoreFailure == nil)
    }

    @Test func restoreConflictsAreExplainedAndTheEntryStays() async {
        let transport = MockTransport()
        let store = await loaded(transport)
        let key = "POST /api/v1/time/segments/\(uuid(1).uuidString.lowercased())/restore"
        transport.enqueue(key, status: 409, body: #"{"error":{"code":"segment_overlap","message":"x"}}"#)
        #expect(!(await store.restore(store.items[0])))
        #expect(store.restoreFailure == .overlap)
        #expect(store.items.count == 2)
        transport.set(key, status: 409, body: #"{"error":{"code":"timer_already_running","message":"x"}}"#)
        #expect(!(await store.restore(store.items[0])))
        #expect(store.restoreFailure == .timerRunning)
    }

    @Test func restoreOfAnEntryChangedElsewhereReloads() async {
        let transport = MockTransport()
        let store = await loaded(transport)
        let key = "POST /api/v1/time/segments/\(uuid(1).uuidString.lowercased())/restore"
        transport.enqueue(key, status: 409, body: #"{"error":{"code":"segment_not_cancelled","message":"x"}}"#)
        transport.set("GET /api/v1/time/segments/cancelled", body: pageJSON([cancelledJSON(2, start: 20_000)], total: 1))
        #expect(!(await store.restore(store.items[0])))
        #expect(store.restoreFailure == .changedElsewhere)
        #expect(store.items.count == 1)
    }

    @Test func previewIsADryRunAndDeletesNothing() async {
        let transport = MockTransport()
        let store = await loaded(transport)
        transport.enqueue("DELETE /api/v1/time/segments/cancelled", body: purgeJSON)
        let summary = await store.preview(.ids([uuid(1), uuid(2)]))
        #expect(summary?.segments == 2)
        #expect(summary?.revisions == 5)
        let query = transport.requests(matching: "DELETE /api/v1/time/segments/cancelled")[0].url?.query ?? ""
        #expect(query.contains("dryRun=true"))
        #expect(query.contains("ids=\(uuid(1).uuidString.lowercased()),\(uuid(2).uuidString.lowercased())"))
        #expect(store.items.count == 2)
    }

    @Test func purgeAllUsesTheAllFlag() async {
        let transport = MockTransport()
        let store = await loaded(transport)
        transport.enqueue("DELETE /api/v1/time/segments/cancelled", body: purgeJSON.replacingOccurrences(of: "true", with: "false"))
        transport.set("GET /api/v1/time/segments/cancelled", body: pageJSON([], total: 0))
        let summary = await store.purge(.all)
        #expect(summary?.dryRun == false)
        let query = transport.requests(matching: "DELETE /api/v1/time/segments/cancelled")[0].url?.query ?? ""
        #expect(query.contains("all=true"))
        #expect(!query.contains("dryRun"))
        #expect(store.isEmpty)
    }

    @Test func purgingOneEntryUsesThePermanentFlagOnThatEntry() async {
        let transport = MockTransport()
        let store = await loaded(transport)
        let key = "DELETE /api/v1/time/segments/\(uuid(1).uuidString.lowercased())"
        transport.enqueue(key, body: purgeJSON.replacingOccurrences(of: "true", with: "false"))
        transport.set("GET /api/v1/time/segments/cancelled", body: pageJSON([cancelledJSON(2, start: 20_000)], total: 1))
        #expect(await store.purge(.ids([uuid(1)])) != nil)
        #expect(transport.requests(matching: key)[0].url?.query == "permanent=true")
        #expect(store.items.count == 1)
    }

    @Test func aFailedPurgeKeepsTheList() async {
        let transport = MockTransport()
        let store = await loaded(transport)
        transport.enqueue("DELETE /api/v1/time/segments/cancelled", status: 409, body: #"{"error":{"code":"segment_not_cancelled","message":"x"}}"#)
        transport.set("GET /api/v1/time/segments/cancelled", body: pageJSON([cancelledJSON(1, start: 10_000)], total: 1))
        #expect(await store.purge(.ids([uuid(1), uuid(2)])) == nil)
        #expect(store.error?.knownCode == .segmentNotCancelled)
    }
}
