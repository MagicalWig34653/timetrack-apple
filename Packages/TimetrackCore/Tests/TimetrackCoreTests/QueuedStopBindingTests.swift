import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// Review finding 2: a queued offline stop belongs to the segment that ran when it was pressed. If another timer runs by the time
/// the stop is delivered (stopped and started again on another device), the stop is obsolete and must not end the new timer.
@Suite struct QueuedStopBindingTests {
    private let longAgo = Date(timeIntervalSince1970: 1_000)
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let segment22 = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    @Test func staleStopDoesNotEndATimerStartedLater() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/timer", body: Fixtures.segmentJSON) // segment 22 runs now
        transport.enqueue("POST /api/v1/time/timer/stop", body: Fixtures.segmentJSON)
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(.init(command: .stop, queuedAt: longAgo, expectedSegmentId: UUID()))
        let result = await queue.drain(client: Fixtures.client(transport), now: now)
        #expect(transport.requests(matching: "POST /api/v1/time/timer/stop").isEmpty)
        #expect(result.dropped == 1 && result.delivered == 0 && result.remaining == 0)
    }

    @Test func stopOfTheExpectedSegmentIsDelivered() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        transport.enqueue("POST /api/v1/time/timer/stop", body: Fixtures.segmentJSON)
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(.init(command: .stop, queuedAt: now, expectedSegmentId: segment22))
        let result = await queue.drain(client: Fixtures.client(transport), now: now)
        #expect(transport.requests(matching: "POST /api/v1/time/timer/stop").count == 1)
        #expect(result.delivered == 1)
    }

    @Test func expectedSegmentSurvivesPersistence() throws {
        let action = QueuedTimerAction(command: .stop, expectedSegmentId: segment22)
        let data = try JSONCoding.makeEncoder().encode(action)
        #expect(try JSONCoding.makeDecoder().decode(QueuedTimerAction.self, from: data).expectedSegmentId == segment22)
        let old = #"{"id":"\#(UUID().uuidString)","command":{"stop":{}},"queuedAt":"2026-10-16T06:00:00Z"}"#
        #expect(try JSONCoding.makeDecoder().decode(QueuedTimerAction.self, from: Data(old.utf8)).expectedSegmentId == nil)
    }

    @MainActor @Test func offlineStopRemembersTheRunningSegment() async {
        let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/days/\(calendar.day(for: .now))", body: Fixtures.dayJSON)
        let queue = TimerActionQueue(fileURL: nil)
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar, queue: queue)
        await store.load()
        #expect(store.running?.id == segment22)
        transport.set("POST /api/v1/time/timer/stop", error: .notConnectedToInternet)
        await store.stop()
        #expect(await queue.pending.first?.expectedSegmentId == segment22)
    }
}
