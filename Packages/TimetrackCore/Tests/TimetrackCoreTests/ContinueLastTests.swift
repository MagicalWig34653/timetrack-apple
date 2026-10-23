import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// H4: "Letzten Timerblock fortführen": reopen via PATCH `endedAt: null`, fallback to a new segment, offline queue.
@MainActor
@Suite struct ContinueLastTests {
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    static let closedId = "33333333-3333-4333-8333-333333333333"

    /// A day with one finished entry (the closed fixture) and no running timer.
    func idleDay() -> String { Fixtures.dayJSON.replacingOccurrences(of: "\"segments\":[\(Fixtures.segmentJSON)]", with: "\"segments\":[\(Fixtures.closedSegmentJSON)]") }

    func prepare(queue: TimerActionQueue? = nil) async -> (MockTransport, TodayStore) {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/timer", body: "null")
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/days/\(calendar.day(for: .now))", body: idleDay())
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar, queue: queue)
        await store.load()
        return (transport, store)
    }

    func reopenedJSON() -> String { Fixtures.closedSegmentJSON.replacingOccurrences(of: "\"endedAt\":\"2026-10-16T09:30:00Z\"", with: "\"endedAt\":null").replacingOccurrences(of: "\"rawEndedAt\":\"2026-10-16T09:30:00Z\"", with: "\"rawEndedAt\":null") }

    @Test func reopenBodySendsExplicitNull() throws {
        let data = try JSONCoding.makeEncoder().encode(SegmentCorrection(reason: "x", reopen: true))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["endedAt"] is NSNull)
        let plain = try JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(SegmentCorrection(reason: "x"))) as? [String: Any]
        #expect(plain?["endedAt"] == nil)
    }

    @Test func offersTheLastFinishedEntryOnlyWhenIdle() async {
        let (_, store) = await prepare()
        #expect(store.continuableSegment?.id == UUID(uuidString: Self.closedId))
    }

    @Test func reopensWhenTheServerSupportsIt() async {
        let (transport, store) = await prepare()
        transport.enqueue("PATCH /api/v1/time/segments/\(Self.closedId)", body: reopenedJSON())
        transport.set("GET /api/v1/time/timer", body: reopenedJSON())
        #expect(await store.continueLast())
        #expect(store.continueNotice == .reopened)
        #expect(store.running?.isRunning == true)
        #expect(transport.requests(matching: "POST /api/v1/time/timer/start").isEmpty)
        let patch = transport.requests(matching: "PATCH /api/v1/time/segments/\(Self.closedId)")
        #expect(patch.count == 1)
        #expect(patch[0].value(forHTTPHeaderField: "If-Match") == "3")
        let patchBody = String(decoding: patch[0].httpBody ?? Data(), as: UTF8.self)
        #expect(patchBody.contains("\"endedAt\":null"))
        #expect(patchBody.contains("Timer fortgesetzt"))
    }

    @Test(arguments: [(400, "validation_failed"), (409, "segment_overlap"), (422, "validation_failed"), (404, "not_found"), (405, "not_found")])
    func fallsBackToANewSegmentWhenReopenIsRefused(status: Int, code: String) async {
        let (transport, store) = await prepare()
        transport.enqueue("PATCH /api/v1/time/segments/\(Self.closedId)", status: status, body: #"{"error":{"code":"\#(code)","message":"x"}}"#)
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        transport.enqueue("PATCH /api/v1/time/segments/22222222-2222-4222-8222-222222222222", body: Fixtures.segmentJSON)
        transport.set("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        #expect(await store.continueLast())
        #expect(store.continueNotice == .startedNew)
        #expect(store.running?.isRunning == true)
        let start = transport.requests(matching: "POST /api/v1/time/timer/start")
        let startBody = String(decoding: start.first?.httpBody ?? Data(), as: UTF8.self)
        #expect(startBody.contains("\"kind\":\"school\""))
        // The note of the continued entry is carried over to the new one.
        #expect(transport.requests(matching: "PATCH /api/v1/time/segments/22222222-2222-4222-8222-222222222222").count == 1)
    }

    @Test func aServerThatIgnoresNullIsTreatedAsUnsupported() async {
        let (transport, store) = await prepare()
        transport.enqueue("PATCH /api/v1/time/segments/\(Self.closedId)", body: Fixtures.closedSegmentJSON) // still closed
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        transport.set("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        #expect(await store.continueLast())
        #expect(store.continueNotice == .startedNew)
    }

    @Test func offlineQueuesTheContinueAndShowsItRunning() async {
        let queue = TimerActionQueue(fileURL: nil)
        let (transport, store) = await prepare(queue: queue)
        transport.enqueue("PATCH /api/v1/time/segments/\(Self.closedId)", error: .notConnectedToInternet)
        #expect(await store.continueLast())
        #expect(store.continueNotice == .queued)
        #expect(await queue.count == 1)
        #expect(store.display.isRunning)
        #expect(store.display.kind == .school)
        #expect(store.continuableSegment == nil, "no second continue while one waits")
    }

    @Test func queuedContinueIsDeliveredLaterWithFallback() async {
        let queue = TimerActionQueue(fileURL: nil)
        let transport = MockTransport()
        let target = QueuedTimerAction.ContinueTarget(segmentId: UUID(uuidString: Self.closedId)!, version: 3, kind: .school, placeId: nil, note: nil)
        await queue.enqueue(.init(command: .resume(target), queuedAt: .now))
        transport.enqueue("PATCH /api/v1/time/segments/\(Self.closedId)", status: 422, body: #"{"error":{"code":"validation_failed","message":"x"}}"#)
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        let result = await queue.drain(client: Fixtures.client(transport))
        #expect(result.delivered == 1)
        #expect(transport.requests(matching: "POST /api/v1/time/timer/start").count == 1)
    }

    @Test func nothingToContinueWhileRunning() async {
        let transport = MockTransport()
        transport.set("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/days/\(calendar.day(for: .now))", body: idleDay())
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar)
        await store.load()
        #expect(store.continuableSegment == nil)
        #expect(await store.continueLast() == false)
    }

    @Test func startNewSkipsTheReopenAndKeepsTheGapAsPause() async {
        let (transport, store) = await prepare()
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        transport.enqueue("PATCH /api/v1/time/segments/22222222-2222-4222-8222-222222222222", body: Fixtures.segmentJSON)
        transport.set("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        #expect(await store.continueLast(startNew: true))
        #expect(transport.requests(matching: "PATCH /api/v1/time/segments/\(Self.closedId)").isEmpty)
        #expect(transport.requests(matching: "POST /api/v1/time/timer/start").count == 1)
        #expect(store.continueNotice == .startedNew)
    }

    @Test func gapIsMeasuredFromTheEndOfTheEntry() async {
        let (_, store) = await prepare()
        let ended = store.continuableSegment!.endedAt!
        #expect(store.continueGap(now: ended.addingTimeInterval(25 * 60)) == 1500, "\(String(describing: store.continueGap(now: ended.addingTimeInterval(25 * 60))))")
        #expect(store.continueGap(now: ended.addingTimeInterval(-5)) == 0)
        #expect(25 * 60 > TodayStore.longContinueGap && 10 * 60 < TodayStore.longContinueGap)
    }
}
