import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// U3: a timer started elsewhere (location automation on the server, link, watch) must show without a manual refresh, and a start
/// refused with 409 `timer_already_running` is not an error: the state is reloaded and the running timer is shown.
@Suite @MainActor struct TimerConflictTests {
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let conflictBody = #"{"error":{"code":"timer_already_running","message":"x"}}"#

    private func store(transport: MockTransport, queue: TimerActionQueue? = nil, timer: String = "null") -> TodayStore {
        let day = calendar.day(for: .now)
        transport.set("GET /api/v1/time/timer", body: timer)
        transport.set("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.set("GET /api/v1/time/days/\(day)", body: Fixtures.dayJSON)
        return TodayStore(client: Fixtures.client(transport), calendar: calendar, queue: queue)
    }

    @Test func startRefusedAsAlreadyRunningShowsTheRunningTimerWithoutError() async {
        let transport = MockTransport()
        let today = store(transport: transport)
        await today.load(deferAccount: true)
        #expect(today.running == nil)
        // Meanwhile the server (location automation) started a work timer; the user presses start for "work".
        transport.set("POST /api/v1/time/timer/start", status: 409, body: conflictBody)
        transport.set("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        var outcomes: [StoreOutcome] = []
        today.onOutcome = { outcomes.append($0) }
        await today.start(kind: .work)
        #expect(today.running != nil)
        #expect(today.error == nil)
        #expect(today.conflict == nil) // same kind: nothing to decide
        #expect(!outcomes.contains(.failed))
    }

    @Test func differentKindOffersSwitchingAndSwitchStopsThenStarts() async {
        let transport = MockTransport()
        let queue = TimerActionQueue(fileURL: nil)
        let today = store(transport: transport, queue: queue)
        await today.load(deferAccount: true)
        transport.set("POST /api/v1/time/timer/start", status: 409, body: conflictBody)
        transport.set("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        await today.start(kind: .travel)
        #expect(today.error == nil)
        #expect(today.running?.kind == .work)
        #expect(today.conflict?.requested == .travel)
        #expect(today.conflict?.running.id == today.running?.id)
        // "Wechseln": stop the running timer, then start the requested kind.
        transport.set("POST /api/v1/time/timer/stop", body: Fixtures.closedSegmentJSON)
        transport.set("GET /api/v1/time/timer", body: "null")
        transport.set("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON.replacingOccurrences(of: "\"kind\":\"work\"", with: "\"kind\":\"travel\""))
        await today.switchRunning(to: .travel)
        #expect(today.conflict == nil)
        #expect(transport.requests(matching: "POST /api/v1/time/timer/stop").count == 1)
        #expect(transport.requests(matching: "POST /api/v1/time/timer/start").count == 2)
    }

    @Test func queuedStoreHandlesTheConflictTheSameWay() async {
        let transport = MockTransport()
        let today = store(transport: transport, queue: TimerActionQueue(fileURL: nil))
        await today.load(deferAccount: true)
        transport.set("POST /api/v1/time/timer/start", status: 409, body: conflictBody)
        transport.set("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        await today.start(kind: .school)
        #expect(today.error == nil)
        #expect(today.pending.isEmpty)
        #expect(today.running != nil)
        #expect(today.conflict?.requested == .school)
        today.clearConflict()
        #expect(today.conflict == nil)
    }

    @Test func startIsStillAnErrorWhenNothingRunsAfterReload() async {
        let transport = MockTransport()
        let today = store(transport: transport)
        await today.load(deferAccount: true)
        transport.set("POST /api/v1/time/timer/start", status: 409, body: conflictBody)
        await today.start(kind: .work) // the reload still says "no timer": inconsistent server, keep the honest error
        #expect(today.error?.knownCode == .timerAlreadyRunning)
    }

    @Test func refreshRunningLoadsOnlyWhenTheTimerChanged() async {
        let transport = MockTransport()
        let today = store(transport: transport)
        await today.load(deferAccount: true)
        let daysBefore = transport.requests(matching: "GET /api/v1/time/days/\(calendar.day(for: .now))").count
        await today.refreshRunning() // unchanged: one cheap request only
        #expect(transport.requests(matching: "GET /api/v1/time/days/\(calendar.day(for: .now))").count == daysBefore)
        // Started by the server-side automation.
        transport.set("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        await today.refreshRunning()
        #expect(today.running != nil)
        #expect(transport.requests(matching: "GET /api/v1/time/days/\(calendar.day(for: .now))").count == daysBefore + 1)
        // Stopped elsewhere.
        transport.set("GET /api/v1/time/timer", body: "null")
        await today.refreshRunning()
        #expect(today.running == nil)
    }

    @Test func refreshRunningKeepsQueuedActionsUntouched() async {
        let transport = MockTransport()
        let queue = TimerActionQueue(fileURL: nil)
        let today = store(transport: transport, queue: queue)
        await today.load(deferAccount: true)
        transport.set("POST /api/v1/time/timer/start", error: .notConnectedToInternet)
        await today.start(kind: .work)
        #expect(today.pending.count == 1)
        transport.set("GET /api/v1/time/timer", body: "null")
        await today.refreshRunning()
        #expect(today.pending.count == 1) // the optimistic start is not wiped by a read that predates its delivery
        #expect(today.display.isRunning)
    }
}
