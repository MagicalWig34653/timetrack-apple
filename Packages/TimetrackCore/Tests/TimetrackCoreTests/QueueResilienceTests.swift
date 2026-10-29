import Foundation
import Testing
@testable import TimetrackCore

/// AUD3 finding 8: a refused backdating correction is reported, and a permanent 5xx/429 neither blocks the queue forever nor loses the entry.
@Suite struct QueueResilienceTests {
    private let longAgo = Date(timeIntervalSince1970: 1_000)
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let segment22 = "PATCH /api/v1/time/segments/22222222-2222-4222-8222-222222222222"

    @Test func refusedBackdatingIsReportedNotSwallowed() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        transport.enqueue(segment22, status: 409, body: #"{"error":{"code":"segment_overlap","message":"x"}}"#)
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(.init(command: .start(.work), queuedAt: longAgo))
        let result = await queue.drain(client: Fixtures.client(transport), now: now)
        #expect(result.delivered == 1 && result.correctionFailed == 1 && result.remaining == 0)
    }

    @Test func serverErrorDuringBackdatingKeepsTheEntryForRetry() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        transport.enqueue(segment22, status: 503, body: "{}")
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(.init(command: .start(.work), queuedAt: longAgo))
        let result = await queue.drain(client: Fixtures.client(transport), now: now)
        #expect(result.delivered == 0 && result.offline && result.remaining == 1 && result.correctionFailed == 0)
    }

    @Test func permanentServerErrorBacksOffThenMovesToAttentionAndUnblocksTheRest() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/timer/start", status: 500, body: "{}")
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(.init(command: .start(.work)))
        await queue.enqueue(.init(command: .stop))
        let client = Fixtures.client(transport)
        var clock = now
        var first = await queue.drain(client: client, now: clock)
        #expect(first.offline && first.remaining == 2)
        // inside the backoff window nothing is sent again
        let sent = transport.requests(matching: "POST /api/v1/time/timer/start").count
        first = await queue.drain(client: client, now: clock.addingTimeInterval(5))
        #expect(first.offline && transport.requests(matching: "POST /api/v1/time/timer/start").count == sent)
        // transport: later entries deliver once the poisoned one waits for the user
        transport.enqueue("POST /api/v1/time/timer/stop", body: Fixtures.segmentJSON)
        for _ in 0..<TimerActionQueue.maxServerFailures {
            clock = clock.addingTimeInterval(3_600)
            _ = await queue.drain(client: client, now: clock)
        }
        let waiting = await queue.needsAttention
        #expect(waiting.count == 1 && waiting.first?.attention?.status == 500)
        #expect(await queue.pending.isEmpty, "the stop behind it was delivered")
    }

    @Test func retryClearsTheFailureStateAndKeepsTheKey() async {
        let queue = TimerActionQueue(fileURL: nil)
        var action = QueuedTimerAction(command: .start(.work))
        action.attention = .init(status: 500, code: nil)
        action.serverFailures = 5
        await queue.enqueue(action)
        #expect(await queue.retry(id: action.id))
        let entry = await queue.pending.first
        #expect(entry?.id == action.id && entry?.serverFailures == nil && entry?.retryNotBefore == nil)
    }

    @Test func backoffGrowsAndIsCapped() {
        #expect(TimerActionQueue.backoff(afterFailures: 1) == 30)
        #expect(TimerActionQueue.backoff(afterFailures: 3) == 120)
        #expect(TimerActionQueue.backoff(afterFailures: 20) == 900)
    }
}
