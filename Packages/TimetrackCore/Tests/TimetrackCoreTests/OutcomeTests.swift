import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// The stores report one `StoreOutcome` per user-initiated action (the app maps them to haptics) and nothing for loads.
@MainActor
@Suite struct OutcomeTests {
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    @MainActor final class Recorder {
        var events: [StoreOutcome] = []
        func attach(_ set: (@escaping StoreOutcomeHandler) -> Void) { set { [self] in events.append($0) } }
    }

    func enqueueToday(_ transport: MockTransport, timer: String) {
        transport.enqueue("GET /api/v1/time/timer", body: timer)
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/days/\(calendar.day(for: .now))", body: Fixtures.dayJSON)
    }

    @Test func startStopFlowReportsOnlyTheActions() async {
        let transport = MockTransport()
        enqueueToday(transport, timer: "null")
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar)
        let recorder = Recorder()
        recorder.attach { store.onOutcome = $0 }
        await store.load() // passive: no outcome
        #expect(recorder.events.isEmpty)
        await store.start()
        transport.set("POST /api/v1/time/timer/stop", body: Fixtures.segmentJSON)
        await store.stop()
        await store.load()
        #expect(recorder.events == [.timerStarted, .timerStopped])
    }

    @Test func failedStartReportsOneFailureEvenAfterRetry() async {
        let transport = MockTransport()
        enqueueToday(transport, timer: "null")
        transport.enqueue("POST /api/v1/time/timer/start", error: .timedOut)
        transport.enqueue("POST /api/v1/time/timer/start", error: .timedOut)
        transport.enqueue("POST /api/v1/time/timer/start", error: .timedOut)
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar)
        let recorder = Recorder()
        recorder.attach { store.onOutcome = $0 }
        await store.start()
        #expect(recorder.events == [.failed])
    }

    @Test func serverRejectionIsOneFailure() async {
        let transport = MockTransport()
        enqueueToday(transport, timer: "null")
        transport.enqueue("POST /api/v1/time/timer/stop", status: 409, body: #"{"error":{"code":"no_running_timer","message":"x"}}"#)
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar)
        let recorder = Recorder()
        recorder.attach { store.onOutcome = $0 }
        await store.stop()
        #expect(recorder.events == [.failed])
    }

    @Test func saveSuccessAndFailureOnTimeList() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/segments", status: 201, body: Fixtures.segmentJSON)
        transport.enqueue("GET /api/v1/time/days", body: "[\(Fixtures.dayJSON)]")
        let store = TimeListStore(client: Fixtures.client(transport), calendar: calendar)
        let recorder = Recorder()
        recorder.attach { store.onOutcome = $0 }
        let input = SegmentInput(kind: .work, startedAt: .now, endedAt: .now.addingTimeInterval(60))
        #expect(await store.create(input))
        transport.set("POST /api/v1/time/segments", status: 409, body: #"{"error":{"code":"segment_overlap","message":"x"}}"#)
        #expect(await store.create(input) == false)
        #expect(recorder.events == [.saved, .failed])
    }

    @Test func voidReportsDeletedOrFailed() async throws {
        let transport = MockTransport()
        transport.enqueue("DELETE /api/v1/time/segments/33333333-3333-4333-8333-333333333333", status: 204)
        transport.enqueue("GET /api/v1/time/days", body: "[\(Fixtures.dayJSON)]")
        let store = TimeListStore(client: Fixtures.client(transport), calendar: calendar)
        let recorder = Recorder()
        recorder.attach { store.onOutcome = $0 }
        let segment = try JSONCoding.makeDecoder().decode(Segment.self, from: Data(Fixtures.closedSegmentJSON.utf8))
        #expect(await store.void(segment, reason: "Test"))
        transport.set("DELETE /api/v1/time/segments/33333333-3333-4333-8333-333333333333", status: 500, body: #"{"error":{"code":"internal","message":"x"}}"#)
        #expect(await store.void(segment, reason: "Test") == false)
        #expect(recorder.events == [.deleted, .failed])
    }

    @Test func absenceSaveFailureAndLoadFailureDiffer() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/vacation/balance", status: 500, body: #"{"error":{"code":"internal","message":"x"}}"#)
        transport.enqueue("GET /api/v1/absences", status: 500, body: #"{"error":{"code":"internal","message":"x"}}"#)
        transport.enqueue("POST /api/v1/absences", status: 409, body: #"{"error":{"code":"absence_overlap","message":"x"}}"#)
        let store = PlanningStore(client: Fixtures.client(transport), calendar: calendar)
        let recorder = Recorder()
        recorder.attach { store.onOutcome = $0 }
        await store.load() // a failed read shows the banner, but no failure haptic
        #expect(recorder.events.isEmpty)
        let input = AbsenceInput(kind: .sick, startDate: "2026-10-20", endDate: "2026-10-20", status: .taken)
        #expect(await store.saveAbsence(input, editing: nil) == nil)
        #expect(recorder.events == [.failed])
    }
}
