import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

@Suite("Q1 review list") struct ReviewListTests {
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func segment(_ id: Int, start: Double = 0, end: Double? = nil, review: Bool = true, voided: Bool = false) -> Segment {
        Segment(id: UUID(uuidString: "00000000-0000-4000-8000-00000000000\(id)")!, kind: .work, startedAt: t0.addingTimeInterval(start),
                endedAt: end.map { t0.addingTimeInterval($0) }, source: .automation, voided: voided, needsReview: review)
    }

    func suggestion(for segment: Segment, end: Double?) -> TimeSuggestion {
        TimeSuggestion(id: UUID(), type: .end, proposedEndedAt: end.map { t0.addingTimeInterval($0) }, segmentId: segment.id)
    }

    @Test func onlyFlaggedLiveEntriesAreListed() {
        let items = ReviewList.items(segments: [segment(1), segment(2, review: false), segment(3, voided: true)], suggestions: [], dismissed: [], calendar: calendar)
        #expect(items.map(\.id) == [segment(1).id])
    }

    @Test func openEntryWithProposalNamesTheProposedEnd() {
        let open = segment(1)
        let items = ReviewList.items(segments: [open], suggestions: [suggestion(for: open, end: 3_600)], dismissed: [], calendar: calendar)
        #expect(items.first?.reason == .endMissingProposed(t0.addingTimeInterval(3_600)))
        #expect(items.first?.proposedEnd == t0.addingTimeInterval(3_600))
    }

    @Test func openEntryWithoutUsableProposalIsJustMissingTheEnd() {
        let open = segment(1)
        let none = ReviewList.items(segments: [open], suggestions: [suggestion(for: open, end: nil)], dismissed: [], calendar: calendar)
        #expect(none.first?.reason == .endMissing)
        let beforeStart = ReviewList.items(segments: [open], suggestions: [suggestion(for: open, end: -60)], dismissed: [], calendar: calendar)
        #expect(beforeStart.first?.reason == .endMissing) // a proposal before the start is not offered
        #expect(none.first?.proposedEnd == nil)
    }

    @Test func endedButStillFlaggedIsMarkedByAutomation() {
        let items = ReviewList.items(segments: [segment(1, end: 600)], suggestions: [], dismissed: [], calendar: calendar)
        #expect(items.first?.reason == .markedByAutomation)
    }

    @Test func otherSuggestionsDoNotMatch() {
        let open = segment(1), other = segment(2, review: false)
        let items = ReviewList.items(segments: [open], suggestions: [suggestion(for: other, end: 60), TimeSuggestion(id: UUID(), type: .start, segmentId: open.id)],
                                     dismissed: [], calendar: calendar)
        #expect(items.first?.suggestion == nil)
    }

    @Test func dismissedAreLeftOutAndOldestComesFirst() {
        let items = ReviewList.items(segments: [segment(1, start: 200_000), segment(2, start: 0), segment(3, start: 100_000)],
                                     suggestions: [], dismissed: [segment(3).id], calendar: calendar)
        #expect(items.map(\.id) == [segment(2).id, segment(1).id])
        #expect(items.first?.day == calendar.day(for: t0))
    }

    @Test func dismissalsPersistAndAreCapped() {
        let suite = "q1.review.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = ReviewDismissals(suiteName: suite)
        #expect(store.read().isEmpty)
        let id = UUID()
        store.add(id); store.add(id)
        #expect(store.read() == [id])
        for _ in 0..<(ReviewDismissals.limit + 20) { store.add(UUID()) }
        #expect(store.read().count == ReviewDismissals.limit)
    }

    @Test func suggestionDecodesAndToleratesUnknownType() throws {
        let json = #"[{"id":"11111111-1111-4111-8111-111111111111","type":"end","placeId":null,"proposedStartedAt":null,"proposedEndedAt":"2026-10-16T17:00:00Z","segmentId":"22222222-2222-4222-8222-222222222222","createdAt":"2026-10-17T00:01:00Z"},{"id":"11111111-1111-4111-8111-111111111112","type":"future","createdAt":"2026-10-17T00:01:00Z"}]"#
        let decoded = try JSONCoding.makeDecoder().decode([TimeSuggestion].self, from: Data(json.utf8))
        #expect(decoded[0].type == .end)
        #expect(decoded[0].proposedEndedAt != nil)
        #expect(decoded[1].type == .unknown)
    }
}

@MainActor
@Suite("Q1 review store") struct ReviewStoreTests {
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let openId = "22222222-2222-4222-8222-222222222222"
    let suggestionId = "11111111-1111-4111-8111-111111111111"

    func segmentJSON(version: Int = 1, ended: Bool = false) -> String {
        let start = JSONCoding.formatInstant(.now.addingTimeInterval(-90_000))
        let end = ended ? "\"\(JSONCoding.formatInstant(.now.addingTimeInterval(-60_000)))\"" : "null"
        return #"{"id":"\#(openId)","kind":"work","placeId":null,"startedAt":"\#(start)","endedAt":\#(end),"rawStartedAt":"\#(start)","rawEndedAt":\#(end),"source":"automation","note":null,"version":\#(version),"voided":false,"needsReview":true,"revisions":0}"#
    }

    var suggestionJSON: String {
        let end = JSONCoding.formatInstant(.now.addingTimeInterval(-60_000))
        return #"[{"id":"\#(suggestionId)","type":"end","placeId":null,"proposedStartedAt":null,"proposedEndedAt":"\#(end)","segmentId":"\#(openId)","createdAt":"\#(end)"}]"#
    }

    func store(_ transport: MockTransport, suite: String) -> ReviewStore {
        let client = Fixtures.client(transport)
        return ReviewStore(client: client, calendar: calendar, dismissals: ReviewDismissals(suiteName: suite))
    }

    @Test func loadsFlaggedEntryWithItsProposal() async {
        let suite = "q1.store.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/suggestions", body: suggestionJSON)
        transport.enqueue("GET /api/v1/time/segments", body: "[\(segmentJSON())]")
        let review = store(transport, suite: suite)
        await review.load()
        #expect(review.count == 1)
        guard case .endMissingProposed = review.items.first?.reason else { Issue.record("expected a proposal"); return }
    }

    @Test func acceptingTheProposalEndsTheEntryAndClearsTheCount() async {
        let suite = "q1.store.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/suggestions", body: suggestionJSON)
        transport.enqueue("GET /api/v1/time/segments", body: "[\(segmentJSON())]")
        transport.enqueue("POST /api/v1/time/suggestions/\(suggestionId)/accept", body: segmentJSON(version: 2, ended: true))
        let review = store(transport, suite: suite)
        await review.load()
        let item = review.items[0]
        #expect(await review.acceptProposal(item))
        #expect(transport.requests(matching: "POST /api/v1/time/suggestions/\(suggestionId)/accept").count == 1)
        #expect(review.count == 0) // the backend keeps the flag; the local list does not show it again
    }

    @Test func confirmingDropsThePendingProposalAndTheItem() async {
        let suite = "q1.store.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/suggestions", body: suggestionJSON)
        transport.enqueue("GET /api/v1/time/segments", body: "[\(segmentJSON(ended: true))]")
        transport.enqueue("POST /api/v1/time/suggestions/\(suggestionId)/reject", status: 204)
        let review = store(transport, suite: suite)
        await review.load()
        #expect(await review.confirm(review.items[0]))
        #expect(transport.requests(matching: "POST /api/v1/time/suggestions/\(suggestionId)/reject").count == 1)
        #expect(review.count == 0)
    }

    @Test func aCancelledEditorKeepsTheItemButASavedOneClearsIt() async {
        let suite = "q1.store.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/suggestions", body: "[]")
        transport.enqueue("GET /api/v1/time/segments", body: "[\(segmentJSON())]")
        let review = store(transport, suite: suite)
        await review.load()
        let item = review.items[0]
        await review.afterEditing(item) // same version: nothing was saved
        #expect(review.count == 1)
        transport.set("GET /api/v1/time/segments", body: "[\(segmentJSON(version: 2, ended: true))]")
        await review.afterEditing(item) // new version: dealt with
        #expect(review.count == 0)
    }

    @Test func aFailedReadNeverClearsAnItem() async {
        let suite = "q1.store.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/suggestions", body: "[]")
        transport.enqueue("GET /api/v1/time/segments", body: "[\(segmentJSON())]")
        let review = store(transport, suite: suite)
        await review.load()
        let item = review.items[0]
        transport.set("GET /api/v1/time/segments", status: 500, body: #"{"error":{"code":"internal","message":"x"}}"#)
        await review.afterEditing(item)
        #expect(review.count == 1)
        #expect(review.error != nil)
    }

    @Test func removedEntryCountsAsDealtWith() async {
        let suite = "q1.store.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/suggestions", body: "[]")
        transport.enqueue("GET /api/v1/time/segments", body: "[\(segmentJSON())]")
        let review = store(transport, suite: suite)
        await review.load()
        let item = review.items[0]
        transport.set("GET /api/v1/time/segments", body: "[]") // voided entries are not listed
        await review.afterEditing(item)
        #expect(review.count == 0)
    }
}
