import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// H4: "the timer stops when I go back to Heute". Every return to Heute starts a reload (`.task`, scene activation, pull to
/// refresh). A reload whose answer was decided BEFORE the user's own start/stop reached the server must not overwrite the
/// result of that action (stale read), otherwise a running timer shows as stopped (and the bar offers "Start" again).
@MainActor
@Suite struct RunningTimerRaceTests {
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    private func prepare(timerAnswer: String) -> MockTransport {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/timer", body: timerAnswer)
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/days/\(calendar.day(for: .now))", body: Fixtures.dayJSON)
        return transport
    }

    private func waitForRequests(_ transport: MockTransport, _ key: String, count: Int) async {
        for _ in 0..<200 where transport.requests(matching: key).count < count { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func staleReloadDoesNotHideAStartedTimer() async {
        for withQueue in [false, true] {
            let transport = prepare(timerAnswer: "null")
            let store = TodayStore(client: Fixtures.client(transport), calendar: calendar, queue: withQueue ? TimerActionQueue(fileURL: nil) : nil)
            let gate = transport.hold("GET /api/v1/time/timer")
            // The reload from returning to Heute: the server answered "no timer" and the answer is still on its way.
            let stale = Task { await store.load() }
            await waitForRequests(transport, "GET /api/v1/time/timer", count: 1)
            // Meanwhile the user starts the timer; the server knows it from now on.
            transport.set("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
            transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
            await store.start()
            #expect(store.running?.isRunning == true)
            gate.release()
            await stale.value
            #expect(store.running?.isRunning == true, "withQueue=\(withQueue): the stale answer must not end the running timer")
        }
    }

    @Test func staleReloadDoesNotRestartAStoppedTimer() async {
        let transport = prepare(timerAnswer: Fixtures.segmentJSON)
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar, queue: TimerActionQueue(fileURL: nil))
        await store.load()
        #expect(store.running != nil)
        let gate = transport.hold("GET /api/v1/time/timer")
        let stale = Task { await store.load() }
        await waitForRequests(transport, "GET /api/v1/time/timer", count: 2)
        transport.set("GET /api/v1/time/timer", body: "null")
        transport.enqueue("POST /api/v1/time/timer/stop", body: Fixtures.closedSegmentJSON)
        await store.stop()
        #expect(store.running == nil)
        gate.release()
        await stale.value
        #expect(store.running == nil, "the stale answer must not bring a stopped timer back")
    }

    @Test func reloadStartedWhileTheStartIsInFlightIsDiscarded() async {
        let transport = prepare(timerAnswer: "null")
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar, queue: TimerActionQueue(fileURL: nil))
        let startGate = transport.hold("POST /api/v1/time/timer/start")
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        let start = Task { await store.start() }
        await waitForRequests(transport, "POST /api/v1/time/timer/start", count: 1)
        // A reload begins while the start is still being processed and reads "no timer" (it overtook the start on the server).
        let readGate = transport.hold("GET /api/v1/time/timer")
        let reload = Task { await store.load() }
        await waitForRequests(transport, "GET /api/v1/time/timer", count: 1)
        transport.set("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        startGate.release()
        await start.value
        readGate.release()
        await reload.value
        #expect(store.running?.isRunning == true)
    }

    @Test func staleBalanceAnswerAfterAnActionDoesNotOverwriteTheFreshBalance() async {
        // X2: the balance of a deferred load is fetched after the day was applied; an action in between must win.
        let transport = prepare(timerAnswer: "null")
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar, queue: TimerActionQueue(fileURL: nil))
        await store.load(deferAccount: true)
        #expect(store.account?.balanceSeconds == -1080)
        let gate = transport.hold("GET /api/v1/time/account")
        transport.set("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON.replacingOccurrences(of: "-1080", with: "5000")) // the old state
        let stale = Task { await store.load(deferAccount: true) }
        await waitForRequests(transport, "GET /api/v1/time/account", count: 2)
        // The user acts meanwhile; the reload after the action reads the new state.
        transport.set("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON.replacingOccurrences(of: "-1080", with: "-1000"))
        transport.set("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        await store.start()
        #expect(store.account?.balanceSeconds == -1000)
        gate.release()
        await stale.value
        #expect(store.account?.balanceSeconds == -1000, "the stale balance must not overwrite the newer one")
    }

    @Test func plainReloadStillAppliesServerChanges() async {
        // The guard must only drop answers that overlap an own action: a timer stopped on another device shows up.
        let transport = prepare(timerAnswer: Fixtures.segmentJSON)
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar)
        await store.load()
        #expect(store.running != nil)
        transport.set("GET /api/v1/time/timer", body: "null")
        await store.load()
        #expect(store.running == nil)
    }
}
