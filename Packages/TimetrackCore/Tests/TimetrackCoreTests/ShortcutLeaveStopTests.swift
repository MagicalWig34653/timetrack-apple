import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// H1: a Shortcuts departure ("Wenn ich gehe") stops any running timer, also one started by hand, without waiting and without a
// location check. Same mode / toggle rules as the region path (L4); without a running timer it is a harmless no-op.

private let officeID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000011")!
private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

private func office(mode: AutomationMode) -> AutomationPlace {
    AutomationPlace(id: officeID, name: "Büro Test", center: GeoPoint(latitude: 52.5200, longitude: 13.4050), savedRadius: 150, mode: mode, confirmAfterSeconds: 300)
}

private final class Actions: LeaveStopActing, @unchecked Sendable {
    private let lock = NSLock()
    var timer: TimerObservation = .running(startedAt: t0 - 7200, source: .timer)
    var stopResult: LeaveStopResult = .stopped
    private(set) var stops: [(UUID, Date)] = []
    private(set) var offers: [(String, Date)] = []

    func observeTimer() async -> TimerObservation { lock.withLock { timer } }
    func stopTimer(eventId: UUID, at: Date) async -> LeaveStopResult { lock.withLock { stops.append((eventId, at)); return stopResult } }
    func offerStop(placeName: String, leftAt: Date, eventId: UUID) async -> Bool { lock.withLock { offers.append((placeName, leftAt)); return true } }
}

private final class NoLocation: LocationFixProviding, @unchecked Sendable {
    func currentFix() async -> LocationFix? { nil } // a Shortcuts departure must not need one
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

private final class IDs: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> UUID { lock.withLock { value += 1; return UUID(uuidString: String(format: "EEEEEEEE-0000-4000-8000-%012d", value))! } }
}

private final class NullSender: AutomationEventSending, @unchecked Sendable {
    func send(_ event: AutomationEventPayload) async throws -> AutomationEventResult { AutomationEventResult(result: .recorded) }
}

private func makeEngine(clock: Clock, actions: Actions?, mode: AutomationMode = .direct, configure: (inout AutomationConfig) -> Void = { _ in }) -> AutomationEngine {
    let storage = InMemoryBlobStorage()
    var state = AutomationState()
    state.places = [office(mode: mode)]
    configure(&state.config)
    storage.save(try! JSONCoding.makeEncoder().encode(state))
    let ids = IDs()
    return AutomationEngine(storage: storage, queue: AutomationEventQueue(storage: InMemoryBlobStorage(), now: { clock.now }), location: NoLocation(), deviceId: "ios-test",
                            senderFactory: { NullSender() }, now: { clock.now }, makeID: { ids.next() }, leaveStop: actions)
}

@Suite struct ShortcutLeaveStopTests {
    @Test func manualStartThenLeaveStopsImmediatelyBackdatedToTheDeparture() async {
        let clock = Clock(t0), actions = Actions() // timer started by hand (source .timer), the app never saw an arrival
        let engine = makeEngine(clock: clock, actions: actions)
        let outcome = await engine.shortcutLeft(officeID)
        #expect(outcome.decision == .leaveStopped)
        #expect(actions.stops.count == 1)
        #expect(actions.stops.first?.1 == t0) // the time of the departure
        #expect(await engine.snapshot.pendingLeaves.isEmpty)
        #expect(await engine.snapshot.log.last?.decision == .leaveStopped)
    }

    @Test func noRunningTimerIsAHarmlessNoOp() async {
        let clock = Clock(t0), actions = Actions()
        actions.timer = .idle
        let engine = makeEngine(clock: clock, actions: actions)
        let outcome = await engine.shortcutLeft(officeID)
        #expect(outcome.decision == .leaveNoTimer)
        #expect(actions.stops.isEmpty)
        #expect(actions.offers.isEmpty)
        #expect(await engine.snapshot.pendingLeaves.isEmpty)
    }

    @Test func shortStayAfterAShortcutArrivalStillStops() async {
        let clock = Clock(t0), actions = Actions()
        let engine = makeEngine(clock: clock, actions: actions)
        _ = await engine.shortcutArrived(officeID)
        clock.advance(60) // far shorter than the dwell time: a region exit would call this a pass-by
        let outcome = await engine.shortcutLeft(officeID)
        #expect(outcome.decision == .leaveStopped)
        #expect(actions.stops.first?.1 == t0 + 60)
    }

    @Test func confirmedVisitAndManualTimerAreBothHandled() async {
        let clock = Clock(t0), actions = Actions()
        let engine = makeEngine(clock: clock, actions: actions)
        _ = await engine.shortcutArrived(officeID)
        clock.advance(600)
        _ = await engine.evaluate() // the shortcut arrival is confirmed without a fix (trigger evidence)
        clock.advance(600)
        let outcome = await engine.shortcutLeft(officeID)
        #expect(outcome.decision == .leaveStopped)
        #expect(actions.stops.count == 1)
    }

    @Test func suggestionModeAsksInsteadOfStopping() async {
        let clock = Clock(t0), actions = Actions()
        let engine = makeEngine(clock: clock, actions: actions, mode: .suggest)
        let outcome = await engine.shortcutLeft(officeID)
        #expect(outcome.decision == .leaveOffered)
        #expect(actions.stops.isEmpty)
        #expect(actions.offers.count == 1)
        #expect(actions.offers.first?.1 == t0)
    }

    @Test func offModeNeverStops() async {
        let clock = Clock(t0), actions = Actions()
        let engine = makeEngine(clock: clock, actions: actions, mode: .off)
        _ = await engine.shortcutLeft(officeID)
        #expect(actions.stops.isEmpty)
        #expect(actions.offers.isEmpty)
    }

    @Test func stopOnLeaveToggleOffKeepsTheTimerRunning() async {
        let clock = Clock(t0), actions = Actions()
        let engine = makeEngine(clock: clock, actions: actions) { $0.stopOnLeaveOverrides[officeID.uuidString] = false }
        _ = await engine.shortcutLeft(officeID)
        #expect(actions.stops.isEmpty)
        #expect(await engine.snapshot.pendingLeaves.isEmpty)
    }

    @Test func globalAutomationOffKeepsTheTimerRunning() async {
        let clock = Clock(t0), actions = Actions()
        let engine = makeEngine(clock: clock, actions: actions) { $0.enabled = false }
        _ = await engine.shortcutLeft(officeID)
        #expect(actions.stops.isEmpty)
    }

    @Test func timerStartedAfterTheDepartureIsLeftAlone() async {
        let clock = Clock(t0), actions = Actions()
        actions.timer = .running(startedAt: t0 + 30, source: .timer)
        let engine = makeEngine(clock: clock, actions: actions)
        let outcome = await engine.shortcutLeft(officeID)
        #expect(outcome.decision == .leaveTimerRestarted)
        #expect(actions.stops.isEmpty)
    }

    @Test func offlineStopIsQueued() async {
        let clock = Clock(t0), actions = Actions()
        actions.stopResult = .queued
        let engine = makeEngine(clock: clock, actions: actions)
        let outcome = await engine.shortcutLeft(officeID)
        #expect(outcome.decision == .leaveStopQueued)
        #expect(actions.stops.count == 1)
    }

    @Test func unknownTimerStateKeepsTheLeaveForTheNextWakeUp() async {
        let clock = Clock(t0), actions = Actions()
        actions.timer = .unknown
        let engine = makeEngine(clock: clock, actions: actions)
        let outcome = await engine.shortcutLeft(officeID)
        #expect(outcome.decision == .leaveScheduled)
        #expect(actions.stops.isEmpty)
        #expect(await engine.snapshot.pendingLeaves.count == 1)
        actions.timer = .running(startedAt: t0 - 3600, source: .timer)
        clock.advance(200)
        await engine.evaluate()
        #expect(actions.stops.count == 1)
        #expect(actions.stops.first?.1 == t0)
    }

    @Test func repeatedShortcutDoesNotStopTwice() async {
        let clock = Clock(t0), actions = Actions()
        let engine = makeEngine(clock: clock, actions: actions)
        _ = await engine.shortcutLeft(officeID)
        actions.timer = .idle // the first stop ended it
        _ = await engine.shortcutLeft(officeID)
        #expect(actions.stops.count == 1)
    }

    @Test func withoutPlatformActionsTheShortcutOnlyReportsTheDeparture() async {
        let clock = Clock(t0)
        let engine = makeEngine(clock: clock, actions: nil)
        let outcome = await engine.shortcutLeft(officeID)
        #expect(outcome.decision == .noArrival)
        #expect(await engine.snapshot.pendingLeaves.isEmpty)
    }
}
