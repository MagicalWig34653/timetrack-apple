import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// L4: stop (or offer to stop) a running timer when leaving a place.

private let officeID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

private func office(mode: AutomationMode = .direct) -> AutomationPlace {
    AutomationPlace(id: officeID, name: "Büro Test", center: GeoPoint(latitude: 52.5200, longitude: 13.4050), savedRadius: 150, mode: mode, confirmAfterSeconds: 300)
}

private func fix(offsetMeters: Double) -> LocationFix {
    LocationFix(latitude: 52.5200 + offsetMeters / 111_195, longitude: 13.4050, horizontalAccuracy: 20, speed: 1, timestamp: t0)
}

private func exitResult(_ decision: AutomationDecision, stay: TimeInterval? = 3600) -> FilterResult {
    FilterResult(decision: decision, stay: stay)
}

private let leaveID = UUID(uuidString: "CCCCCCCC-0000-4000-8000-000000000001")!

private func pending(visitReported: Bool = false, leftAt: Date = t0) -> PendingLeave {
    PendingLeave(placeId: officeID, leftAt: leftAt, dueAt: leftAt.addingTimeInterval(180), eventId: leaveID, visitReported: visitReported)
}

// MARK: - Pure filter

@Suite struct LeaveStopFilterTests {
    let filter = LeaveStopFilter(config: AutomationConfig())

    @Test func schedulesAfterLongStayWithoutArrival() {
        let result = filter.schedule(place: office(), leftAt: t0, exit: exitResult(.noArrival), eventId: leaveID)
        #expect(result.decision == .leaveScheduled)
        #expect(result.leave?.dueAt == t0.addingTimeInterval(180))
        #expect(result.leave?.visitReported == false)
    }

    @Test func schedulesWhenTheEntryWasNeverSeen() {
        let result = filter.schedule(place: office(), leftAt: t0, exit: exitResult(.noArrival, stay: nil), eventId: leaveID)
        #expect(result.leave != nil)
    }

    @Test func confirmedVisitIsMarkedAsReported() {
        #expect(filter.schedule(place: office(), leftAt: t0, exit: exitResult(.departureQueued), eventId: leaveID).leave?.visitReported == true)
        #expect(filter.schedule(place: office(), leftAt: t0, exit: exitResult(.confirmedOnExit), eventId: leaveID).leave?.visitReported == true)
    }

    @Test func shortStayIsAPassBy() {
        let result = filter.schedule(place: office(), leftAt: t0, exit: exitResult(.noArrival, stay: 60), eventId: leaveID)
        #expect(result.leave == nil)
        #expect(result.decision == .leaveStayTooShort)
    }

    @Test func passByAndDisabledPlacesNeverSchedule() {
        #expect(filter.schedule(place: office(), leftAt: t0, exit: exitResult(.passBy), eventId: leaveID).leave == nil)
        #expect(filter.schedule(place: office(mode: .off), leftAt: t0, exit: exitResult(.noArrival), eventId: leaveID).leave == nil)
        var config = AutomationConfig()
        config.stopOnLeaveOverrides[officeID.uuidString] = false
        #expect(LeaveStopFilter(config: config).schedule(place: office(), leftAt: t0, exit: exitResult(.noArrival), eventId: leaveID).leave == nil)
        config = AutomationConfig()
        config.enabled = false
        #expect(LeaveStopFilter(config: config).schedule(place: office(), leftAt: t0, exit: exitResult(.noArrival), eventId: leaveID).leave == nil)
    }

    @Test func waitsUntilDue() {
        let check = filter.check(pending(), place: office(), now: t0.addingTimeInterval(120), verification: .outside, timer: .running(startedAt: t0 - 3600, source: .timer))
        #expect(check.keepWaiting)
        #expect(check.action == .none)
    }

    @Test func directStopsAManuallyStartedTimer() {
        let check = filter.check(pending(), place: office(), now: t0.addingTimeInterval(200), verification: .outside, timer: .running(startedAt: t0 - 3600, source: .timer))
        #expect(check.action == .stop)
        #expect(check.decision == .leaveStopped)
    }

    @Test func unavailableFixStillStops() {
        let check = filter.check(pending(), place: office(), now: t0.addingTimeInterval(200), verification: .unavailable, timer: .running(startedAt: t0 - 3600, source: .timer))
        #expect(check.action == .stop)
    }

    @Test func suggestionModeOffersInsteadOfStopping() {
        let check = filter.check(pending(), place: office(mode: .suggest), now: t0.addingTimeInterval(200), verification: .outside, timer: .running(startedAt: t0 - 3600, source: .manual))
        #expect(check.action == .offer)
    }

    @Test func suggestionModeLeavesServerCreatedSegmentsToTheServer() {
        let check = filter.check(pending(visitReported: true), place: office(mode: .suggest), now: t0.addingTimeInterval(200), verification: .outside, timer: .running(startedAt: t0 - 3600, source: .suggestion))
        #expect(check.action == .none)
        #expect(check.decision == .leaveHandledByServer)
        let manual = filter.check(pending(visitReported: true), place: office(mode: .suggest), now: t0.addingTimeInterval(200), verification: .outside, timer: .running(startedAt: t0 - 3600, source: .timer))
        #expect(manual.action == .offer)
    }

    @Test func returningCancels() {
        let check = filter.check(pending(), place: office(), now: t0.addingTimeInterval(200), verification: .inside(speed: 1), timer: .running(startedAt: t0 - 3600, source: .timer))
        #expect(check.decision == .leaveReturned)
        #expect(check.action == .none)
    }

    @Test func idleOrRestartedTimerIsLeftAlone() {
        let idle = filter.check(pending(), place: office(), now: t0.addingTimeInterval(200), verification: .outside, timer: .idle)
        #expect(idle.decision == .leaveNoTimer)
        let restarted = filter.check(pending(), place: office(), now: t0.addingTimeInterval(200), verification: .outside, timer: .running(startedAt: t0 + 60, source: .timer))
        #expect(restarted.decision == .leaveTimerRestarted)
        #expect(restarted.action == .none)
    }

    @Test func unknownTimerWaitsForTheNextWakeUp() {
        let check = filter.check(pending(), place: office(), now: t0.addingTimeInterval(200), verification: .outside, timer: .unknown)
        #expect(check.keepWaiting)
    }

    @Test func oldLeavesExpire() {
        let check = filter.check(pending(), place: office(), now: t0.addingTimeInterval(13 * 3600), verification: .outside, timer: .running(startedAt: t0 - 3600, source: .timer))
        #expect(check.decision == .leaveExpired)
        #expect(check.action == .none)
    }

    @Test func settingsFromBeforeL4StillDecode() throws {
        let old = Data(#"{"enabled":true,"dwellMinutes":6,"cooldownMinutes":15}"#.utf8)
        let config = try JSONCoding.makeDecoder().decode(AutomationConfig.self, from: old)
        #expect(config.dwellMinutes == 6)
        #expect(config.leaveWaitMinutes == 3)
        #expect(config.stopOnLeaveOverrides.isEmpty)
        let state = try JSONCoding.makeDecoder().decode(AutomationState.self, from: Data(#"{"config":{"enabled":true},"places":[],"runtime":{"x":{"phase":"outside"}},"log":[]}"#.utf8))
        #expect(state.pendingLeaves.isEmpty)
    }

    @Test func entryTimeIsTrackedEvenWhenTheArrivalIsIgnored() {
        var config = AutomationConfig()
        config.cooldownMinutes = 30
        let arrival = ArrivalFilter(config: config)
        var runtime = PlaceRuntimeState()
        runtime.lastDepartureAt = t0 - 60
        _ = arrival.enter(&runtime, place: office(), at: t0, origin: .region)
        #expect(runtime.phase == .outside) // cooldown
        let result = arrival.exit(&runtime, place: office(), at: t0 + 90)
        #expect(result.decision == .noArrival)
        #expect(result.stay == 90)
        #expect(runtime.enteredAt == nil)
    }
}

// MARK: - Engine (full pipeline with fakes)

private final class FakeActions: LeaveStopActing, @unchecked Sendable {
    private let lock = NSLock()
    var timer: TimerObservation = .running(startedAt: t0 - 7200, source: .timer)
    var stopResult: LeaveStopResult = .stopped
    var offerAllowed = true
    private(set) var stops: [(UUID, Date)] = []
    private(set) var offers: [(String, Date)] = []

    func observeTimer() async -> TimerObservation { lock.withLock { timer } }
    func stopTimer(eventId: UUID, at: Date) async -> LeaveStopResult {
        lock.withLock { stops.append((eventId, at)); return stopResult }
    }
    func offerStop(placeName: String, leftAt: Date, eventId: UUID) async -> Bool {
        lock.withLock { offers.append((placeName, leftAt)); return offerAllowed }
    }
}

private final class StubLocation: LocationFixProviding, @unchecked Sendable {
    var fix: LocationFix?
    func currentFix() async -> LocationFix? { fix }
}

private final class StubClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

private final class IDs: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> UUID { lock.withLock { value += 1; return UUID(uuidString: String(format: "DDDDDDDD-0000-4000-8000-%012d", value))! } }
}

private final class NullSender: AutomationEventSending, @unchecked Sendable {
    func send(_ event: AutomationEventPayload) async throws -> AutomationEventResult { AutomationEventResult(result: .recorded) }
}

private func makeEngine(clock: StubClock, actions: FakeActions, location: StubLocation, mode: AutomationMode = .direct) -> AutomationEngine {
    let storage = InMemoryBlobStorage()
    var state = AutomationState()
    state.places = [office(mode: mode)]
    storage.save(try! JSONCoding.makeEncoder().encode(state))
    let ids = IDs()
    return AutomationEngine(storage: storage, queue: AutomationEventQueue(storage: InMemoryBlobStorage(), now: { clock.now }), location: location, deviceId: "ios-test",
                            senderFactory: { NullSender() }, now: { clock.now }, makeID: { ids.next() }, leaveStop: actions)
}

@Suite struct LeaveStopEngineTests {
    @Test func manualTimerIsStoppedAtTheLeaveTimeAfterTheWait() async {
        let clock = StubClock(t0), actions = FakeActions(), location = StubLocation()
        location.fix = fix(offsetMeters: 600)
        let engine = makeEngine(clock: clock, actions: actions, location: location)
        let outcome = await engine.regionExited(officeID, at: t0) // the app never saw the arrival: ArrivalFilter says noArrival
        #expect(outcome.decision == .noArrival)
        #expect(await engine.snapshot.pendingLeaves.count == 1)
        clock.advance(120)
        await engine.evaluate()
        #expect(actions.stops.isEmpty) // still inside the wait
        clock.advance(70)
        await engine.evaluate()
        #expect(actions.stops.count == 1)
        #expect(actions.stops.first?.1 == t0)
        #expect(await engine.snapshot.pendingLeaves.isEmpty)
        let entry = await engine.snapshot.log.last
        #expect(entry?.decision == .leaveStopped)
        #expect(entry?.detail == "Timer gestoppt um \(LeaveStopFilter.clockText(t0))")
    }

    @Test func noDoubleStopWhenEvaluatedAgain() async {
        let clock = StubClock(t0), actions = FakeActions(), location = StubLocation()
        location.fix = fix(offsetMeters: 600)
        let engine = makeEngine(clock: clock, actions: actions, location: location)
        await engine.regionExited(officeID, at: t0)
        clock.advance(200)
        async let first = engine.evaluate()
        async let second = engine.evaluate()
        _ = await (first, second)
        await engine.evaluate()
        #expect(actions.stops.count == 1)
    }

    @Test func timerRestartedAfterLeavingIsNotStopped() async {
        let clock = StubClock(t0), actions = FakeActions(), location = StubLocation()
        location.fix = fix(offsetMeters: 600)
        actions.timer = .running(startedAt: t0 + 100, source: .timer)
        let engine = makeEngine(clock: clock, actions: actions, location: location)
        await engine.regionExited(officeID, at: t0)
        clock.advance(200)
        await engine.evaluate()
        #expect(actions.stops.isEmpty)
        #expect(await engine.snapshot.log.last?.decision == .leaveTimerRestarted)
    }

    @Test func returningWithinTheWaitCancels() async {
        let clock = StubClock(t0), actions = FakeActions(), location = StubLocation()
        location.fix = fix(offsetMeters: 600)
        let engine = makeEngine(clock: clock, actions: actions, location: location)
        await engine.regionExited(officeID, at: t0)
        clock.advance(60)
        await engine.regionEntered(officeID, at: clock.now)
        #expect(await engine.snapshot.pendingLeaves.isEmpty)
        clock.advance(300)
        await engine.evaluate()
        #expect(actions.stops.isEmpty)
        #expect(await engine.snapshot.log.contains { $0.decision == .leaveReturned })
    }

    @Test func fixInsideThePlaceCancels() async {
        let clock = StubClock(t0), actions = FakeActions(), location = StubLocation()
        location.fix = fix(offsetMeters: 10) // GPS jumped back
        let engine = makeEngine(clock: clock, actions: actions, location: location)
        await engine.regionExited(officeID, at: t0)
        clock.advance(200)
        await engine.evaluate()
        #expect(actions.stops.isEmpty)
        #expect(await engine.snapshot.log.last?.decision == .leaveReturned)
    }

    @Test func passByWithoutBookedArrivalIsIgnored() async {
        let clock = StubClock(t0), actions = FakeActions(), location = StubLocation()
        let engine = makeEngine(clock: clock, actions: actions, location: location)
        await engine.regionEntered(officeID, at: t0)
        clock.advance(30)
        let outcome = await engine.regionExited(officeID, at: clock.now)
        #expect(outcome.decision == .passBy)
        #expect(await engine.snapshot.pendingLeaves.isEmpty)
    }

    @Test func shortStayWhileCooldownIgnoredTheArrivalIsIgnored() async {
        let clock = StubClock(t0), actions = FakeActions(), location = StubLocation()
        let engine = makeEngine(clock: clock, actions: actions, location: location)
        await engine.regionEntered(officeID, at: t0)
        clock.advance(400)
        await engine.regionExited(officeID, at: clock.now) // booked visit ends, cooldown starts
        clock.advance(20)
        await engine.regionEntered(officeID, at: clock.now) // ignored: cooldown
        clock.advance(40)
        await engine.regionExited(officeID, at: clock.now)
        #expect(await engine.snapshot.log.contains { $0.decision == .leaveStayTooShort })
        #expect(await engine.snapshot.pendingLeaves.isEmpty) // the first leave was cancelled by the return, the second is a pass-by
        #expect(await engine.snapshot.log.contains { $0.decision == .leaveReturned })
    }

    @Test func offlineStopIsQueuedAndLogged() async {
        let clock = StubClock(t0), actions = FakeActions(), location = StubLocation()
        actions.stopResult = .queued
        let engine = makeEngine(clock: clock, actions: actions, location: location)
        await engine.regionExited(officeID, at: t0)
        clock.advance(200)
        await engine.evaluate() // no fix possible: unavailable still stops
        #expect(actions.stops.count == 1)
        #expect(await engine.snapshot.log.last?.decision == .leaveStopQueued)
        #expect(await engine.snapshot.pendingLeaves.isEmpty)
    }

    @Test func unknownTimerKeepsTheLeaveUntilItCanBeSeen() async {
        let clock = StubClock(t0), actions = FakeActions(), location = StubLocation()
        actions.timer = .unknown
        let engine = makeEngine(clock: clock, actions: actions, location: location)
        await engine.regionExited(officeID, at: t0)
        clock.advance(200)
        await engine.evaluate()
        #expect(actions.stops.isEmpty)
        #expect(await engine.snapshot.pendingLeaves.count == 1)
        actions.timer = .running(startedAt: t0 - 600, source: .timer)
        clock.advance(300)
        await engine.evaluate()
        #expect(actions.stops.count == 1)
        #expect(actions.stops.first?.1 == t0) // still ended at the time of leaving
    }

    @Test func failedStopIsRetried() async {
        let clock = StubClock(t0), actions = FakeActions(), location = StubLocation()
        actions.stopResult = .failed
        let engine = makeEngine(clock: clock, actions: actions, location: location)
        await engine.regionExited(officeID, at: t0)
        clock.advance(200)
        await engine.evaluate()
        #expect(await engine.snapshot.pendingLeaves.count == 1)
        actions.stopResult = .stopped
        await engine.evaluate()
        #expect(actions.stops.count == 2)
        #expect(actions.stops[0].0 == actions.stops[1].0) // same idempotency key
        #expect(await engine.snapshot.pendingLeaves.isEmpty)
    }

    @Test func suggestionModeAsksInsteadOfStopping() async {
        let clock = StubClock(t0), actions = FakeActions(), location = StubLocation()
        let engine = makeEngine(clock: clock, actions: actions, location: location, mode: .suggest)
        await engine.regionExited(officeID, at: t0)
        clock.advance(200)
        await engine.evaluate()
        #expect(actions.stops.isEmpty)
        #expect(actions.offers.count == 1)
        #expect(actions.offers.first?.0 == "Büro Test")
        #expect(await engine.snapshot.log.last?.decision == .leaveOffered)
    }

    @Test func nextDueDateIncludesTheLeaveCheck() async {
        let clock = StubClock(t0), actions = FakeActions(), location = StubLocation()
        let engine = makeEngine(clock: clock, actions: actions, location: location)
        await engine.regionExited(officeID, at: t0)
        #expect(await engine.nextDueDate() == t0.addingTimeInterval(180))
    }

    @Test func withoutPlatformActionsNothingIsScheduled() async {
        let engine = AutomationEngine(storage: InMemoryBlobStorage(), queue: AutomationEventQueue(storage: InMemoryBlobStorage()), location: StubLocation(), deviceId: "x", senderFactory: { nil })
        await engine.setPlaces([])
        #expect(await engine.snapshot.pendingLeaves.isEmpty)
    }
}
