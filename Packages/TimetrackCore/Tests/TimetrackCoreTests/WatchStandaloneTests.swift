import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

private func tempQueueURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("tt-queue-\(UUID().uuidString)/queue.json")
}

@Suite struct SessionLifecycleTests {
    @Test func credentialsMakeTheClientUsableBeforeTheServerAnswers() {
        var life = SessionLifecycle()
        life.apply(.credentialsFound)
        #expect(life.state == .active(.unverified))
        life.apply(.validated)
        #expect(life.state == .active(.verified))
    }

    @Test func offlineKeepsCredentialsAndRecovers() {
        var life = SessionLifecycle()
        life.apply(.credentialsFound)
        life.apply(.networkFailed)
        #expect(life.state == .active(.offline))
        #expect(life.isActive)
        life.apply(.validated)
        #expect(life.state == .active(.verified))
    }

    @Test func oneFailedRefreshDoesNotMakeVerifiedSessionOffline() {
        var life = SessionLifecycle(state: .active(.verified))
        life.apply(.networkFailed)
        #expect(life.state == .active(.verified))
    }

    @Test func serverRejectionIsTheOnlyWayToExpire() {
        var life = SessionLifecycle(state: .active(.offline))
        life.apply(.serverRejected)
        #expect(life.state == .signedOut(.expired))
        life.apply(.networkFailed)
        #expect(life.state == .signedOut(.expired))
    }

    @Test func handoffEventsAndReasons() {
        var life = SessionLifecycle(state: .active(.verified))
        life.apply(.handoffSignedOut)
        #expect(life.state == .signedOut(.endedOnPhone))
        life.apply(.handoffSession)
        #expect(life.state == .active(.unverified))
        life.apply(.userSignedOut)
        #expect(life.state == .signedOut(.userSignedOut))
        life.apply(.noCredentials)
        #expect(life.state == .signedOut(.noCredentials))
    }

    @Test func restoringWithoutAnswerStaysUntilEvent() {
        var life = SessionLifecycle()
        #expect(life.state == .restoring)
        life.apply(.networkFailed)
        #expect(life.state == .active(.offline))
    }
}

@Suite struct TodayDisplayTests {
    let now = Date(timeIntervalSince1970: 1_792_130_820) // Fri 2026-10-16 06:07 UTC

    func snapshot(running: Bool = true, day: String = "2026-10-16", updated: Date? = nil) -> WidgetSnapshot {
        WidgetSnapshot(isRunning: running, kind: .travel, startedAt: running ? now.addingTimeInterval(-600) : nil, todaySeconds: 3600, day: day,
                       timeZone: "Europe/Berlin", updatedAt: updated ?? now.addingTimeInterval(-60), targetSeconds: 27720, balanceSeconds: -300,
                       segments: [WidgetSegment(kind: .work, startedAt: now.addingTimeInterval(-7200), endedAt: now.addingTimeInterval(-3600))])
    }

    @Test func cachedSnapshotRendersWithoutNetwork() {
        let display = TodayDisplay.cached(snapshot(), now: now)
        #expect(display.source == .cached)
        #expect(display.isRunning && display.kind == .travel)
        #expect(display.doneSeconds == 3600 && display.targetSeconds == 27720 && display.balanceSeconds == -300)
        #expect(display.segments.count == 1)
    }

    @Test func snapshotFromAnEarlierDayDropsTotalsButKeepsRunningTimer() {
        let display = TodayDisplay.cached(snapshot(day: "2026-10-15"), now: now)
        #expect(display.doneSeconds == 0 && display.targetSeconds == 0 && display.segments.isEmpty)
        #expect(display.isRunning)
    }

    @Test func missingOrEmptySnapshotIsEmptyDisplay() {
        #expect(TodayDisplay.cached(nil).source == .empty)
        #expect(TodayDisplay.cached(.empty).source == .empty)
    }

    @Test func queuedStartShowsRunningImmediatelyAndStopEndsIt() {
        let base = TodayDisplay.cached(snapshot(running: false), now: now)
        let started = base.applying([QueuedTimerAction(command: .start(.school), queuedAt: now)])
        #expect(started.isRunning && started.kind == .school && started.startedAt == now && started.pendingActions == 1)
        let stopped = started.applying([]).applying([QueuedTimerAction(command: .start(.work), queuedAt: now), QueuedTimerAction(command: .stop, queuedAt: now.addingTimeInterval(300))])
        #expect(!stopped.isRunning && stopped.doneSeconds == 3600 + 300 && stopped.pendingActions == 2)
    }

    @Test func snapshotRoundTripFromDisplayKeepsContent() {
        let zone = TimeZone(identifier: "Europe/Berlin")!
        let display = TodayDisplay.cached(snapshot(), now: now)
        let made = WidgetSnapshot.make(display: display, zone: zone, now: now)
        #expect(made.todaySeconds == 3600 && made.isRunning && made.targetSeconds == 27720)
        #expect(made.sameContent(as: made.withDifferentUpdate(now.addingTimeInterval(500))))
    }
}

private extension WidgetSnapshot {
    func withDifferentUpdate(_ date: Date) -> WidgetSnapshot { var copy = self; copy.updatedAt = date; return copy }
}

@Suite struct TimerActionQueueTests {
    @Test func persistsAcrossInstancesAndCapsSize() async {
        let url = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = TimerActionQueue(fileURL: url, limit: 3)
        for index in 0..<5 { await queue.enqueue(QueuedTimerAction(command: index.isMultiple(of: 2) ? .start(.work) : .stop)) }
        #expect(await queue.count == 3)
        let reloaded = TimerActionQueue(fileURL: url, limit: 3)
        #expect(await reloaded.pending.map(\.id) == (await queue.pending).map(\.id)) // dates persist at whole-second precision
        #expect(await reloaded.pending.map(\.command) == (await queue.pending).map(\.command))
    }

    @Test func ignoresRepeatedSameCommand() async {
        let queue = TimerActionQueue(fileURL: nil)
        #expect(await queue.enqueue(QueuedTimerAction(command: .start(.work))))
        #expect(await queue.enqueue(QueuedTimerAction(command: .start(.travel))) == false)
        #expect(await queue.enqueue(QueuedTimerAction(command: .stop)))
        #expect(await queue.count == 2)
    }

    @Test func drainDeliversInOrderWithTheOriginalEventIds() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        transport.enqueue("POST /api/v1/time/timer/stop", body: Fixtures.closedSegmentJSON)
        let queue = TimerActionQueue(fileURL: nil)
        let start = QueuedTimerAction(command: .start(.work), queuedAt: .now)
        let stop = QueuedTimerAction(command: .stop, queuedAt: .now)
        await queue.enqueue(start)
        await queue.enqueue(stop)
        let result = await queue.drain(client: Fixtures.client(transport))
        #expect(result.delivered == 2 && result.remaining == 0 && !result.offline)
        let startBody = String(decoding: transport.requests(matching: "POST /api/v1/time/timer/start")[0].httpBody ?? Data(), as: UTF8.self)
        #expect(startBody.contains(start.id.uuidString))
    }

    @Test func networkErrorKeepsEverythingAndStops() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/timer/start", error: .notConnectedToInternet)
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(QueuedTimerAction(command: .start(.work)))
        await queue.enqueue(QueuedTimerAction(command: .stop))
        let result = await queue.drain(client: Fixtures.client(transport))
        #expect(result.offline && result.delivered == 0 && result.remaining == 2)
        #expect(transport.requests(matching: "POST /api/v1/time/timer/stop").isEmpty)
    }

    @Test func serverErrorsCountAsOfflineButRejectionsAreDropped() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/timer/start", status: 503)
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(QueuedTimerAction(command: .start(.work)))
        #expect(await queue.drain(client: Fixtures.client(transport)).offline)
        transport.set("POST /api/v1/time/timer/start", status: 409, body: #"{"error":{"code":"timer_already_running","message":"x"}}"#)
        let result = await queue.drain(client: Fixtures.client(transport))
        #expect(result.dropped == 1 && result.remaining == 0)
    }

    @Test func unauthorizedStopsAndKeepsTheQueue() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/timer/stop", status: 401, body: #"{"error":{"code":"unauthorized","message":"x"}}"#)
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(QueuedTimerAction(command: .stop))
        let result = await queue.drain(client: Fixtures.client(transport))
        #expect(result.unauthorized && result.remaining == 1)
    }

    @Test func lateStartIsCorrectedToThePressTime() async {
        let transport = MockTransport()
        let pressed = Date(timeIntervalSince1970: 1_792_130_000)
        // The server stamps the delivery time (segmentJSON starts at 2026-10-16T06:07:00Z); the press was 10 minutes earlier.
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        transport.enqueue("PATCH /api/v1/time/segments/22222222-2222-4222-8222-222222222222", body: Fixtures.segmentJSON)
        let queue = TimerActionQueue(fileURL: nil)
        await queue.enqueue(QueuedTimerAction(command: .start(.work), queuedAt: pressed))
        let result = await queue.drain(client: Fixtures.client(transport), now: pressed.addingTimeInterval(600))
        #expect(result.delivered == 1)
        #expect(transport.requests(matching: "PATCH /api/v1/time/segments/22222222-2222-4222-8222-222222222222").count == 1)
    }
}

@MainActor
@Suite struct OfflineTodayStoreTests {
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    @Test func offlineStartIsQueuedShownAndDeliveredLater() async {
        let transport = MockTransport()
        let day = calendar.day(for: .now)
        transport.enqueue("GET /api/v1/time/timer", body: "null")
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/days/\(day)", body: Fixtures.dayJSON)
        transport.enqueue("POST /api/v1/time/timer/start", error: .notConnectedToInternet)
        let queue = TimerActionQueue(fileURL: nil)
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar, queue: queue)
        var outcomes: [StoreOutcome] = []
        store.onOutcome = { outcomes.append($0) }
        await store.start(kind: .school)
        #expect(transport.requests(matching: "POST /api/v1/time/timer/start").count == 1) // one attempt, no long retry loop
        #expect(store.pending.count == 1)
        #expect(store.display.isRunning && store.display.kind == .school && store.display.pendingActions == 1)
        #expect(outcomes == [.timerStarted])
        // Back online: the next load delivers the queued start with the same event id and clears the pending state.
        transport.set("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        transport.set("GET /api/v1/time/timer", body: Fixtures.segmentJSON)
        await store.load(deferAccount: true)
        #expect(store.pending.isEmpty)
        #expect(store.display.source == .live && store.display.isRunning && store.display.pendingActions == 0)
    }

    @Test func cachedDisplayIsShownBeforeAnyLoadAndLiveReplacesIt() async {
        let transport = MockTransport()
        let day = calendar.day(for: .now)
        transport.enqueue("GET /api/v1/time/timer", body: "null")
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/days/\(day)", body: Fixtures.dayJSON)
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar)
        store.seed(snapshot: WidgetSnapshot(isRunning: true, kind: .work, startedAt: .now.addingTimeInterval(-60), todaySeconds: 100, day: day,
                                            timeZone: "Europe/Berlin", updatedAt: .now, targetSeconds: 200, balanceSeconds: 5))
        #expect(store.display.source == .cached && store.display.isRunning && store.display.doneSeconds == 100)
        await store.load(deferAccount: true)
        #expect(store.display.source == .live && !store.display.isRunning && store.display.doneSeconds == 26100)
    }

    @Test func rejectionIsNotQueued() async {
        let transport = MockTransport()
        let day = calendar.day(for: .now)
        transport.enqueue("GET /api/v1/time/timer", body: "null")
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/time/days/\(day)", body: Fixtures.dayJSON)
        transport.enqueue("POST /api/v1/time/timer/stop", status: 409, body: #"{"error":{"code":"no_running_timer","message":"x"}}"#)
        let queue = TimerActionQueue(fileURL: nil)
        let store = TodayStore(client: Fixtures.client(transport), calendar: calendar, queue: queue)
        await store.stop()
        #expect(store.pending.isEmpty)
        #expect(store.error?.knownCode == .noRunningTimer)
    }
}
