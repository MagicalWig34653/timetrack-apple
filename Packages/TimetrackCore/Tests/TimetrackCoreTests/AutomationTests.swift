import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

private func jsonObject(_ data: Data?) -> [String: Any] {
    guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
}

// MARK: - Fixtures

private let officeID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
private let homeID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000002")!
private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

private func office(mode: AutomationMode = .direct, radius: Int = 150, confirm: Int = 300) -> AutomationPlace {
    AutomationPlace(id: officeID, name: "Büro Test", center: GeoPoint(latitude: 52.5200, longitude: 13.4050), savedRadius: radius, mode: mode, confirmAfterSeconds: confirm)
}

private func fix(at place: AutomationPlace, offsetMeters: Double = 0, accuracy: Double = 20, speed: Double? = 0) -> LocationFix {
    // 1 degree of latitude is about 111,195 m.
    LocationFix(latitude: place.center!.latitude + offsetMeters / 111_195, longitude: place.center!.longitude, horizontalAccuracy: accuracy, speed: speed, timestamp: t0)
}

private func counterIDs() -> @Sendable () -> UUID {
    let counter = Counter()
    return { counter.next() }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> UUID {
        lock.withLock {
            value += 1
            return UUID(uuidString: String(format: "BBBBBBBB-0000-4000-8000-%012d", value))!
        }
    }
}

private final class FakeSender: AutomationEventSending, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var sent: [AutomationEventPayload] = []
    var failures: [TimetrackError] = []
    var kind: AutomationEventResult.Kind = .recorded

    func send(_ event: AutomationEventPayload) async throws -> AutomationEventResult {
        let failure: TimetrackError? = lock.withLock { failures.isEmpty ? nil : failures.removeFirst() }
        if let failure { throw failure }
        lock.withLock { sent.append(event) }
        return AutomationEventResult(result: kind)
    }
}

private final class FakeLocation: LocationFixProviding, @unchecked Sendable {
    var fix: LocationFix?
    private(set) var requests = 0
    func currentFix() async -> LocationFix? { requests += 1; return fix }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

private func makeEngine(clock: Clock, sender: FakeSender?, location: FakeLocation = FakeLocation(), places: [AutomationPlace]? = nil,
                        config: AutomationConfig = AutomationConfig()) async -> AutomationEngine {
    let storage = InMemoryBlobStorage()
    var state = AutomationState()
    state.config = config
    state.places = places ?? [office()]
    storage.save(try! JSONCoding.makeEncoder().encode(state))
    let queue = AutomationEventQueue(storage: InMemoryBlobStorage(), now: { clock.now })
    return AutomationEngine(storage: storage, queue: queue, location: location, deviceId: "ios-test",
                            senderFactory: { sender }, now: { clock.now }, makeID: counterIDs())
}

// MARK: - Planner

@Suite struct PlaceMonitorPlannerTests {
    private func place(_ n: Int, lat: Double, mode: AutomationMode = .suggest, radius: Int = 150) -> AutomationPlace {
        AutomationPlace(id: UUID(), name: "Ort \(n)", center: GeoPoint(latitude: lat, longitude: 13.4), savedRadius: radius, mode: mode)
    }

    @Test func choosesTwentyNearestAndReportsOmitted() {
        let places = (0..<25).map { place($0, lat: 52.0 + Double($0) * 0.01) }
        let plan = PlaceMonitorPlanner.plan(places: places.reversed(), near: GeoPoint(latitude: 52.0, longitude: 13.4))
        #expect(plan.monitored.count == 20)
        #expect(plan.omitted.count == 5)
        #expect(plan.monitored.first?.name == "Ort 0")
        #expect(plan.omitted.map(\.name).sorted() == (20..<25).map { "Ort \($0)" }.sorted())
    }

    @Test func switchedOffPlacesAreNotMonitoredAndDoNotCountAgainstTheLimit() {
        let places = [place(1, lat: 52.0, mode: .off)] + (2..<23).map { place($0, lat: 52.0 + Double($0) * 0.01) }
        let plan = PlaceMonitorPlanner.plan(places: places, near: nil)
        #expect(!plan.monitored.contains { $0.name == "Ort 1" })
        #expect(plan.monitored.count == 20)
        #expect(plan.omitted.count == 1)
    }

    @Test func withoutPositionDirectPlacesComeFirst() {
        let plan = PlaceMonitorPlanner.plan(places: [place(1, lat: 52, mode: .suggest), place(2, lat: 52, mode: .direct)], near: nil, limit: 1)
        #expect(plan.monitored.first?.name == "Ort 2")
    }

    @Test func smallRadiusIsMonitoredWithTheMinimumAndFlagged() {
        let small = place(1, lat: 52, radius: 40)
        #expect(small.monitoringRadius == 100)
        #expect(small.hasTooSmallRadius)
        let plan = PlaceMonitorPlanner.plan(places: [small, place(2, lat: 52.1, radius: 300)], near: nil)
        #expect(plan.smallRadius.map(\.name) == ["Ort 1"])
        #expect(place(3, lat: 52, radius: 300).monitoringRadius == 300)
    }

    @Test func placesWithoutCoordinatesAreCachedButNeverMonitored() {
        let id = UUID()
        #expect(AutomationPlace(Place(id: id, name: "x", automationMode: "direct"))?.center == nil)
        #expect(AutomationPlace(Place(id: id, name: "x", archived: true, latitude: 1, longitude: 1)) == nil)
        #expect(AutomationPlace(Place(id: id, name: "x", latitude: 95, longitude: 1))?.center == nil)
        let noCoordinates = AutomationPlace(Place(id: id, name: "x", automationMode: "direct"))!
        #expect(PlaceMonitorPlanner.plan(places: [noCoordinates], near: nil).monitored.isEmpty)
        let ok = AutomationPlace(Place(id: id, name: "x", automationMode: "direct", latitude: 52, longitude: 13, radiusMeters: 120))
        #expect(ok?.mode == .direct)
        #expect(ok?.savedRadius == 120)
    }

    @Test func distanceIsRoughlyCorrect() {
        let a = GeoPoint(latitude: 52.0, longitude: 13.0), b = GeoPoint(latitude: 52.01, longitude: 13.0)
        #expect(abs(a.distance(to: b) - 1112) < 5)
    }
}

// MARK: - Filter

@Suite struct ArrivalFilterTests {
    private func filter(dwell: Int = 4, cooldown: Int = 10) -> ArrivalFilter {
        var config = AutomationConfig()
        config.dwellMinutes = dwell
        config.cooldownMinutes = cooldown
        return ArrivalFilter(config: config, makeID: counterIDs())
    }

    @Test func enterStartsPendingWithoutEvents() {
        var state = PlaceRuntimeState()
        let result = filter().enter(&state, place: office(), at: t0, origin: .region)
        #expect(result.decision == .pendingStarted)
        #expect(result.events.isEmpty)
        #expect(state.phase == .pending)
        #expect(state.dueAt == t0.addingTimeInterval(300)) // the place's confirmAfterSeconds (300) exceeds the 4 min setting
    }

    @Test func dwellIsTheLongerOfSettingAndPlaceConfirmation() {
        #expect(filter(dwell: 10).dwell(for: office(confirm: 300)) == 600)
        #expect(filter(dwell: 2).dwell(for: office(confirm: 300)) == 300)
    }

    @Test func offAndGlobalOffDoNothing() {
        var state = PlaceRuntimeState()
        #expect(filter().enter(&state, place: office(mode: .off), at: t0, origin: .region).decision == .modeOff)
        var config = AutomationConfig()
        config.enabled = false
        #expect(ArrivalFilter(config: config).enter(&state, place: office(), at: t0, origin: .region).decision == .globalOff)
        #expect(state.phase == .outside)
    }

    @Test func verifiedPresenceAfterDwellEmitsArrivalAndConfirmation() {
        let f = filter()
        var state = PlaceRuntimeState()
        _ = f.enter(&state, place: office(), at: t0, origin: .region)
        let early = f.check(&state, place: office(), now: t0.addingTimeInterval(120), verification: .inside(speed: 0))
        #expect(early.decision == .stillWaiting)
        #expect(early.events.isEmpty)
        let result = f.check(&state, place: office(), now: t0.addingTimeInterval(330), verification: .inside(speed: 1))
        #expect(result.decision == .confirmed)
        #expect(result.confidence == .verified)
        #expect(result.events.map(\.type) == [.arrival, .presenceConfirmed])
        #expect(result.events[0].occurredAt == t0) // booking is back-dated to the arrival
        #expect(result.events[1].occurredAt >= t0.addingTimeInterval(300))
        #expect(state.phase == .confirmed)
    }

    @Test func fastDeviceIsNotBookedButStaysPending() {
        let f = filter()
        var state = PlaceRuntimeState()
        _ = f.enter(&state, place: office(), at: t0, origin: .region)
        let fast = f.check(&state, place: office(), now: t0.addingTimeInterval(400), verification: .inside(speed: 15))
        #expect(fast.decision == .speedTooHigh)
        #expect(fast.events.isEmpty)
        #expect(state.phase == .pending)
        // parked later: slow now
        let later = f.check(&state, place: office(), now: t0.addingTimeInterval(900), verification: .inside(speed: 0.2))
        #expect(later.decision == .confirmed)
    }

    @Test func outsideAtCheckCancelsSilently() {
        let f = filter()
        var state = PlaceRuntimeState()
        _ = f.enter(&state, place: office(), at: t0, origin: .region)
        let result = f.check(&state, place: office(), now: t0.addingTimeInterval(400), verification: .outside)
        #expect(result.decision == .outsideAtCheck)
        #expect(result.events.isEmpty)
        #expect(state.phase == .outside)
        #expect(state.lastDepartureAt == nil) // no cooldown after a pass-by
    }

    @Test func exitBeforeDwellIsDrivingPast() {
        let f = filter()
        var state = PlaceRuntimeState()
        _ = f.enter(&state, place: office(), at: t0, origin: .region)
        let result = f.exit(&state, place: office(), at: t0.addingTimeInterval(60))
        #expect(result.decision == .passBy)
        #expect(result.events.isEmpty)
        // a real arrival right after is accepted (no cooldown for pass-bys)
        #expect(f.enter(&state, place: office(), at: t0.addingTimeInterval(120), origin: .region).decision == .pendingStarted)
    }

    @Test func unavailableFixKeepsRegionArrivalPendingButTrustsShortcut() {
        let f = filter()
        var region = PlaceRuntimeState(), shortcut = PlaceRuntimeState()
        _ = f.enter(&region, place: office(), at: t0, origin: .region)
        _ = f.enter(&shortcut, place: office(), at: t0, origin: .shortcut)
        #expect(f.check(&region, place: office(), now: t0.addingTimeInterval(400), verification: .unavailable).decision == .stillWaiting)
        let trusted = f.check(&shortcut, place: office(), now: t0.addingTimeInterval(400), verification: .unavailable)
        #expect(trusted.decision == .confirmed)
        #expect(trusted.confidence == .trigger)
    }

    @Test func exitAfterDwellConfirmsRetroactivelyThenDeparts() {
        let f = filter()
        var state = PlaceRuntimeState()
        _ = f.enter(&state, place: office(), at: t0, origin: .region)
        let exit = t0.addingTimeInterval(3600)
        let result = f.exit(&state, place: office(), at: exit)
        #expect(result.decision == .confirmedOnExit)
        #expect(result.confidence == .regionOnly)
        #expect(result.events.map(\.type) == [.arrival, .presenceConfirmed, .departure])
        #expect(result.events[1].occurredAt == t0.addingTimeInterval(300))
        #expect(result.events[2].occurredAt == exit)
        #expect(state.phase == .outside)
    }

    @Test func confirmedVisitDepartsAndCooldownBlocksJitter() {
        let f = filter(cooldown: 10)
        var state = PlaceRuntimeState()
        _ = f.enter(&state, place: office(), at: t0, origin: .region)
        _ = f.check(&state, place: office(), now: t0.addingTimeInterval(400), verification: .inside(speed: 0))
        let exit = t0.addingTimeInterval(4000)
        let departure = f.exit(&state, place: office(), at: exit)
        #expect(departure.decision == .departureQueued)
        #expect(departure.events.map(\.type) == [.departure])
        #expect(f.enter(&state, place: office(), at: exit.addingTimeInterval(300), origin: .region).decision == .cooldown)
        #expect(f.enter(&state, place: office(), at: exit.addingTimeInterval(601), origin: .region).decision == .pendingStarted)
    }

    @Test func duplicateEnterAndStrayExitAreIgnored() {
        let f = filter()
        var state = PlaceRuntimeState()
        #expect(f.exit(&state, place: office(), at: t0).decision == .noArrival)
        _ = f.enter(&state, place: office(), at: t0, origin: .region)
        #expect(f.enter(&state, place: office(), at: t0.addingTimeInterval(5), origin: .region).decision == .alreadyInside)
    }

    @Test func staleArrivalExpires() {
        let f = filter()
        var state = PlaceRuntimeState()
        _ = f.enter(&state, place: office(), at: t0, origin: .region)
        let result = f.check(&state, place: office(), now: t0.addingTimeInterval(13 * 3600), verification: .unavailable)
        #expect(result.decision == .expired)
        #expect(state.phase == .outside)
    }

    @Test func verificationUsesAccuracyAndRadius() {
        let place = office(radius: 150)
        #expect(PresenceVerification.from(fix: fix(at: place, offsetMeters: 50), place: place) == .inside(speed: 0))
        #expect(PresenceVerification.from(fix: fix(at: place, offsetMeters: 170, accuracy: 50), place: place) == .inside(speed: 0))
        #expect(PresenceVerification.from(fix: fix(at: place, offsetMeters: 800, accuracy: 20), place: place) == .outside)
        #expect(PresenceVerification.from(fix: fix(at: place, offsetMeters: 220, accuracy: 20), place: place) == .unavailable) // ambiguous band
        #expect(PresenceVerification.from(fix: nil, place: place) == .unavailable)
        // a tiny saved radius is verified with the 100 m minimum
        let tiny = office(radius: 30)
        #expect(PresenceVerification.from(fix: fix(at: tiny, offsetMeters: 90), place: tiny) == .inside(speed: 0))
    }

    @Test func negativeSpeedMeansUnknown() {
        #expect(LocationFix(latitude: 0, longitude: 0, horizontalAccuracy: 5, speed: -1).speed == nil)
    }

    @Test func configIsClamped() {
        var config = AutomationConfig()
        config.dwellMinutes = 1
        config.cooldownMinutes = 5
        #expect(config.clamped.dwellMinutes == 2)
        #expect(config.clamped.cooldownMinutes == 10)
        config.dwellMinutes = 99
        #expect(config.clamped.dwellMinutes == 15)
    }
}

// MARK: - Queue

@Suite struct AutomationEventQueueTests {
    private func event(_ n: Int, type: AutomationEventType = .arrival) -> AutomationEventPayload {
        AutomationEventPayload(eventId: UUID(uuidString: String(format: "CCCCCCCC-0000-4000-8000-%012d", n))!, deviceId: "ios-test", placeId: officeID, type: type, occurredAt: t0)
    }

    @Test func enqueueIsIdempotentAndPersistent() async {
        let storage = InMemoryBlobStorage()
        let queue = AutomationEventQueue(storage: storage, now: { t0 })
        #expect(await queue.enqueue(event(1), placeName: "Büro Test"))
        #expect(await !queue.enqueue(event(1), placeName: "Büro Test"))
        #expect(await queue.count == 1)
        let reloaded = AutomationEventQueue(storage: storage, now: { t0 })
        #expect(await reloaded.count == 1)
        #expect(await reloaded.pending.first?.event.eventId == event(1).eventId)
    }

    @Test func drainSendsInOrderAndEmptiesTheQueue() async {
        let queue = AutomationEventQueue(storage: InMemoryBlobStorage(), now: { t0 })
        await queue.enqueue(event(1), placeName: "A")
        await queue.enqueue(event(2, type: .presenceConfirmed), placeName: "A")
        let sender = FakeSender()
        sender.kind = .booked
        let summary = await queue.drain(using: sender)
        #expect(summary.stop == .finished)
        #expect(sender.sent.map(\.type) == [.arrival, .presenceConfirmed])
        #expect(summary.reports.map(\.outcome) == [.sent(.booked), .sent(.booked)])
        #expect(await queue.count == 0)
    }

    /// Crash seen in TestFlight build 15: two overlapping drains both removed the same head ("Can't remove first element from an empty collection").
    @Test func overlappingDrainsNeitherCrashNorSendTwice() async {
        let queue = AutomationEventQueue(storage: InMemoryBlobStorage(), now: { t0 })
        await queue.enqueue(event(1), placeName: "A")
        let sender = FakeSender()
        sender.kind = .booked
        async let a = queue.drain(using: sender)
        async let b = queue.drain(using: sender)
        _ = await (a, b)
        #expect(sender.sent.count == 1)
        #expect(await queue.count == 0)
    }

    @Test func offlineKeepsEventsWithTheSameIdForTheRetry() async {
        let queue = AutomationEventQueue(storage: InMemoryBlobStorage(), now: { t0 })
        await queue.enqueue(event(1), placeName: "A")
        await queue.enqueue(event(2), placeName: "A")
        let sender = FakeSender()
        sender.failures = [.network(.notConnectedToInternet)]
        let first = await queue.drain(using: sender)
        #expect(first.stop == .retryLater)
        #expect(await queue.count == 2)
        #expect(await queue.pending.first?.attempts == 1)
        let second = await queue.drain(using: sender)
        #expect(second.stop == .finished)
        #expect(sender.sent.map(\.eventId) == [event(1).eventId, event(2).eventId])
    }

    @Test func unauthorizedStopsAndKeepsEvents() async {
        let queue = AutomationEventQueue(storage: InMemoryBlobStorage(), now: { t0 })
        await queue.enqueue(event(1), placeName: "A")
        let sender = FakeSender()
        sender.failures = [.api(status: 401, code: "unauthorized", message: "x")]
        #expect(await queue.drain(using: sender).stop == .unauthorized)
        #expect(await queue.count == 1)
    }

    @Test func permanentRejectionIsDroppedAndLaterEventsStillGo() async {
        let queue = AutomationEventQueue(storage: InMemoryBlobStorage(), now: { t0 })
        await queue.enqueue(event(1), placeName: "A")
        await queue.enqueue(event(2), placeName: "A")
        let sender = FakeSender()
        sender.failures = [.api(status: 404, code: "not_found", message: "x")]
        let summary = await queue.drain(using: sender)
        #expect(summary.reports.first?.outcome == .dropped(code: "not_found"))
        #expect(sender.sent.count == 1)
        #expect(await queue.count == 0)
    }

    @Test func rateLimitAndServerErrorsRetryLater() async {
        let queue = AutomationEventQueue(storage: InMemoryBlobStorage(), now: { t0 })
        await queue.enqueue(event(1), placeName: "A")
        let sender = FakeSender()
        sender.failures = [.api(status: 429, code: "too_many_requests", message: "x")]
        #expect(await queue.drain(using: sender).stop == .retryLater)
        sender.failures = [.api(status: 503, code: "http_503", message: "x")]
        #expect(await queue.drain(using: sender).stop == .retryLater)
        #expect(await queue.count == 1)
    }

    @Test func oldEventsExpire() async {
        let clock = Clock(t0)
        let queue = AutomationEventQueue(storage: InMemoryBlobStorage(), now: { clock.now })
        await queue.enqueue(event(1), placeName: "A")
        clock.advance(AutomationEventQueue.maxAge + 60)
        let summary = await queue.drain(using: FakeSender())
        #expect(summary.reports.first?.outcome == .dropped(code: "expired"))
    }
}

// MARK: - Engine (full pipeline with fakes)

@Suite struct AutomationEngineTests {
    @Test func regionVisitSendsArrivalConfirmationAndDepartureInOrder() async {
        let clock = Clock(t0)
        let sender = FakeSender()
        let location = FakeLocation()
        let engine = await makeEngine(clock: clock, sender: sender, location: location)
        #expect(await engine.regionEntered(officeID).decision == .pendingStarted)
        #expect(sender.sent.isEmpty) // nothing is booked on entry
        clock.advance(120)
        _ = await engine.evaluate()
        #expect(location.requests == 0) // not due: no location request at all
        clock.advance(240)
        location.fix = fix(at: office(), offsetMeters: 20)
        let outcomes = await engine.evaluate()
        #expect(outcomes.first?.decision == .confirmed)
        #expect(location.requests == 1)
        #expect(sender.sent.map(\.type) == [.arrival, .presenceConfirmed])
        #expect(sender.sent[0].occurredAt == t0)
        clock.advance(3600)
        #expect(await engine.regionExited(officeID).decision == .departureQueued)
        #expect(sender.sent.map(\.type) == [.arrival, .presenceConfirmed, .departure])
        #expect(Set(sender.sent.map(\.eventId)).count == 3)
        #expect(sender.sent.allSatisfy { $0.deviceId == "ios-test" && $0.placeId == officeID })
        let log = await engine.snapshot.log
        #expect(log.contains { $0.decision == .confirmed && $0.confidence == .verified })
        #expect(log.contains { $0.decision == .sent })
    }

    @Test func drivingPastBooksNothingAndSendsNothing() async {
        let clock = Clock(t0)
        let sender = FakeSender()
        let engine = await makeEngine(clock: clock, sender: sender)
        _ = await engine.regionEntered(officeID)
        clock.advance(40)
        #expect(await engine.regionExited(officeID).decision == .passBy)
        #expect(sender.sent.isEmpty)
        #expect(await engine.queuedCount == 0)
    }

    @Test func fastFixAtCheckKeepsWaitingAndSendsNothing() async {
        let clock = Clock(t0)
        let sender = FakeSender()
        let location = FakeLocation()
        let engine = await makeEngine(clock: clock, sender: sender, location: location)
        _ = await engine.regionEntered(officeID)
        clock.advance(400)
        location.fix = fix(at: office(), offsetMeters: 10, speed: 20)
        #expect(await engine.evaluate().first?.decision == .speedTooHigh)
        #expect(sender.sent.isEmpty)
    }

    @Test func offlineQueueDrainsLaterWithoutDuplicates() async {
        let clock = Clock(t0)
        let sender = FakeSender()
        sender.failures = [.network(.notConnectedToInternet)]
        let location = FakeLocation()
        let engine = await makeEngine(clock: clock, sender: sender, location: location)
        _ = await engine.regionEntered(officeID)
        clock.advance(400)
        location.fix = fix(at: office())
        _ = await engine.evaluate()
        #expect(sender.sent.isEmpty)
        #expect(await engine.queuedCount == 2)
        await engine.flush()
        #expect(sender.sent.map(\.type) == [.arrival, .presenceConfirmed])
        #expect(await engine.queuedCount == 0)
    }

    @Test func missingTokenKeepsEventsQueued() async {
        let clock = Clock(t0)
        let location = FakeLocation()
        let engine = await makeEngine(clock: clock, sender: nil, location: location)
        _ = await engine.regionEntered(officeID)
        clock.advance(400)
        location.fix = fix(at: office())
        _ = await engine.evaluate()
        #expect(await engine.queuedCount == 2)
    }

    @Test func shortcutsShareThePipelineModeAndCooldown() async {
        let clock = Clock(t0)
        let sender = FakeSender()
        let engine = await makeEngine(clock: clock, sender: sender)
        let arrived = await engine.shortcutArrived(officeID)
        #expect(arrived.decision == .pendingStarted)
        #expect(arrived.mode == .direct)
        #expect(arrived.dwellMinutes == 5)
        #expect(await engine.shortcutArrived(officeID).decision == .alreadyInside)
        clock.advance(400)
        _ = await engine.evaluate() // no fix available: the shortcut trigger counts
        #expect(sender.sent.map(\.type) == [.arrival, .presenceConfirmed])
        clock.advance(100)
        #expect(await engine.shortcutLeft(officeID).decision == .departureQueued)
        #expect(await engine.shortcutArrived(officeID).decision == .cooldown)
    }

    @Test func offPlaceAndGlobalSwitchDoNotPost() async {
        let clock = Clock(t0)
        let sender = FakeSender()
        let engine = await makeEngine(clock: clock, sender: sender, places: [office(mode: .off)])
        #expect(await engine.shortcutArrived(officeID).decision == .modeOff)
        var config = AutomationConfig()
        config.enabled = false
        await engine.setConfig(config)
        #expect(await engine.regionEntered(officeID).decision == .globalOff)
        #expect(await engine.shortcutArrived(UUID()).decision == .unknownPlace)
        #expect(sender.sent.isEmpty)
    }

    @Test func reconcileEndsVisitsWhoseExitWasMissed() async {
        let clock = Clock(t0)
        let sender = FakeSender()
        let engine = await makeEngine(clock: clock, sender: sender)
        _ = await engine.regionEntered(officeID)
        clock.advance(2 * 3600)
        await engine.reconcile(insidePlaceIds: [])
        #expect(sender.sent.map(\.type) == [.arrival, .presenceConfirmed, .departure])
    }

    @Test func reconcileKeepsVisitsStillInside() async {
        let clock = Clock(t0)
        let sender = FakeSender()
        let engine = await makeEngine(clock: clock, sender: sender)
        _ = await engine.regionEntered(officeID)
        clock.advance(3600)
        await engine.reconcile(insidePlaceIds: [officeID])
        #expect(sender.sent.isEmpty)
    }

    @Test func stateSurvivesRestart() async {
        let clock = Clock(t0)
        let storage = InMemoryBlobStorage()
        let queueStorage = InMemoryBlobStorage()
        var state = AutomationState()
        state.places = [office()]
        storage.save(try! JSONCoding.makeEncoder().encode(state))
        let sender = FakeSender()
        func engine() -> AutomationEngine {
            AutomationEngine(storage: storage, queue: AutomationEventQueue(storage: queueStorage, now: { clock.now }), location: FakeLocation(), deviceId: "ios-test",
                             senderFactory: { sender }, now: { clock.now }, makeID: counterIDs())
        }
        _ = await engine().regionEntered(officeID)
        #expect(await engine().nextDueDate() == t0.addingTimeInterval(300))
        #expect(await engine().regionEntered(officeID).decision == .alreadyInside)
    }

    @Test func logIsCappedAtFifty() async {
        let clock = Clock(t0)
        let engine = await makeEngine(clock: clock, sender: FakeSender())
        for _ in 0..<60 {
            _ = await engine.regionEntered(officeID)
            _ = await engine.regionExited(officeID)
        }
        #expect(await engine.snapshot.log.count == AutomationState.logLimit)
    }

    @Test func setPlacesDropsProgressOfRemovedPlaces() async {
        let clock = Clock(t0)
        let engine = await makeEngine(clock: clock, sender: FakeSender())
        _ = await engine.regionEntered(officeID)
        await engine.setPlaces([Place(id: homeID, name: "Zuhause Test", automationMode: "suggest", latitude: 52.4, longitude: 13.3, radiusMeters: 120)])
        let snapshot = await engine.snapshot
        #expect(snapshot.runtime.isEmpty)
        #expect(snapshot.places.map(\.id) == [homeID])
    }
}

// MARK: - API client and store

@MainActor
@Suite struct AutomationAPITests {
    static let placeJSON = #"{"id":"aaaaaaaa-0000-4000-8000-000000000001","name":"Büro Test","kind":"office","automationMode":"suggest","archived":false,"latitude":52.52,"longitude":13.405,"radiusMeters":150,"confirmAfterSeconds":300}"#
    static let tokenJSON = #"{"id":"dddddddd-0000-4000-8000-000000000001","name":"Timetrack App (ios-test)","scope":"automation","createdAt":"2026-10-17T08:00:00Z","token":"ttdev_secret_value"}"#

    @Test func placeDecodesGeofenceFields() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", body: "[\(Self.placeJSON)]")
        let places = try await Fixtures.client(transport).listPlaces()
        #expect(places.first?.latitude == 52.52)
        #expect(places.first?.radiusMeters == 150)
        #expect(places.first?.confirmAfterSeconds == 300)
    }

    @Test func updatePlaceSendsTheWholePlaceWithTheNewMode() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("PUT /api/v1/places/aaaaaaaa-0000-4000-8000-000000000001", body: Self.placeJSON)
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        let place = try JSONCoding.makeDecoder().decode(Place.self, from: Data(Self.placeJSON.utf8))
        _ = try await client.updatePlace(id: place.id, PlaceInput(place, mode: .direct))
        let body = try #require(transport.requests(matching: "PUT /api/v1/places/aaaaaaaa-0000-4000-8000-000000000001").first?.httpBody)
        let json = jsonObject(body)
        #expect(json["automationMode"] as? String == "direct")
        #expect(json["radiusMeters"] as? Int == 150)
        #expect(json["name"] as? String == "Büro Test")
        #expect(json["latitude"] as? Double == 52.52)
    }

    @Test func eventSenderUsesBearerWithoutCsrfOrCookie() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/automation/events", body: #"{"result":"recorded"}"#)
        let sender = DeviceTokenEventSender(baseURL: Fixtures.baseURL, token: "ttdev_x", transport: transport)
        let payload = AutomationEventPayload(eventId: UUID(), deviceId: "ios-test", placeId: officeID, type: .presenceConfirmed, occurredAt: t0)
        let result = try await sender.send(payload)
        #expect(result.result == .recorded)
        let request = try #require(transport.requests(matching: "POST /api/v1/automation/events").first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ttdev_x")
        #expect(request.value(forHTTPHeaderField: "X-CSRF-Token") == nil)
        let json = jsonObject(request.httpBody)
        #expect(json["type"] as? String == "presence_confirmed")
        #expect(json["deviceId"] as? String == "ios-test")
        #expect(Set(json.keys) == ["eventId", "deviceId", "placeId", "type", "occurredAt"]) // no coordinates
    }

    @Test func eventSenderMapsStatusCodes() async {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/automation/events", status: 401, body: #"{"error":{"code":"unauthorized","message":"x"}}"#)
        let sender = DeviceTokenEventSender(baseURL: Fixtures.baseURL, token: "t", transport: transport)
        let payload = AutomationEventPayload(eventId: UUID(), deviceId: "d", placeId: officeID, type: .arrival, occurredAt: t0)
        await #expect(throws: TimetrackError.api(status: 401, code: "unauthorized", message: "x")) { try await sender.send(payload) }
    }

    @Test func unknownResultKindDecodesAsUnknown() throws {
        let result = try JSONCoding.makeDecoder().decode(AutomationEventResult.self, from: Data(#"{"result":"something_new"}"#.utf8))
        #expect(result.result == .unknown)
        let booked = try JSONCoding.makeDecoder().decode(AutomationEventResult.self, from: Data(#"{"result":"needs_review","segmentId":null}"#.utf8))
        #expect(booked.result == .needsReview)
    }

    private func makeStore(_ transport: MockTransport, secrets: SecretStore = InMemorySecretStore()) async throws -> (AutomationStore, AutomationEngine) {
        let engine = await makeEngine(clock: Clock(t0), sender: nil, places: [])
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        return (AutomationStore(client: client, engine: engine, secrets: secrets, deviceName: "ios-test"), engine)
    }

    @Test func loadPopulatesPlacesAndPlan() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", body: "[\(Self.placeJSON)]")
        let (store, engine) = try await makeStore(transport)
        await store.load()
        #expect(store.places.count == 1)
        #expect(store.plan.monitored.map(\.name) == ["Büro Test"])
        #expect(await engine.snapshot.places.count == 1)
    }

    @Test func enablingAPlaceCreatesTheDeviceTokenOnceAndStoresItSecurely() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", body: "[\(Self.placeJSON.replacingOccurrences(of: "suggest", with: "off"))]")
        transport.enqueue("PUT /api/v1/places/aaaaaaaa-0000-4000-8000-000000000001", body: Self.placeJSON)
        transport.enqueue("POST /api/v1/me/device-tokens", status: 201, body: Self.tokenJSON)
        let secrets = InMemorySecretStore()
        let (store, _) = try await makeStore(transport, secrets: secrets)
        await store.load()
        let place = try #require(store.places.first)
        await store.setMode(.suggest, for: place)
        #expect(store.mode(of: store.places[0]) == .suggest)
        #expect(secrets.read(AutomationSecretKey.deviceToken) == "ttdev_secret_value")
        #expect(store.hasLocalToken)
        await store.setMode(.direct, for: place)
        #expect(transport.requests(matching: "POST /api/v1/me/device-tokens").count == 1)
    }

    @Test func placeWithoutCoordinatesCannotBeEnabled() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", body: #"[{"id":"aaaaaaaa-0000-4000-8000-000000000009","name":"Ohne Ort","kind":"other","automationMode":"off","archived":false}]"#)
        let (store, _) = try await makeStore(transport)
        await store.load()
        await store.setMode(.suggest, for: store.places[0])
        #expect(store.error != nil)
        #expect(transport.requests(matching: "PUT /api/v1/places/aaaaaaaa-0000-4000-8000-000000000009").isEmpty)
    }

    @Test func revokeRemovesTheLocalSecret() async throws {
        let transport = MockTransport()
        let secrets = InMemorySecretStore()
        secrets.write("ttdev_x", for: AutomationSecretKey.deviceToken)
        secrets.write("dddddddd-0000-4000-8000-000000000001", for: AutomationSecretKey.deviceTokenId)
        transport.enqueue("DELETE /api/v1/me/device-tokens/dddddddd-0000-4000-8000-000000000001", status: 204)
        let (store, _) = try await makeStore(transport, secrets: secrets)
        await store.revokeDeviceToken()
        #expect(secrets.read(AutomationSecretKey.deviceToken) == nil)
        #expect(!store.hasLocalToken)
    }

    @Test func createPlaceSendsCoordinatesAndRadius() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/places", status: 201, body: Self.placeJSON)
        transport.enqueue("POST /api/v1/me/device-tokens", status: 201, body: Self.tokenJSON)
        let (store, _) = try await makeStore(transport)
        await store.createPlace(name: "Büro Test", coordinate: GeoPoint(latitude: 52.52, longitude: 13.405), radius: 150, mode: .suggest)
        #expect(store.places.count == 1)
        let body = try #require(transport.requests(matching: "POST /api/v1/places").first?.httpBody)
        let json = jsonObject(body)
        #expect(json["radiusMeters"] as? Int == 150)
        #expect(json["automationMode"] as? String == "suggest")
    }

    // U3: archiving a place.
    @Test func archiveSendsDeleteDropsThePlaceAndStopsWatchingIt() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", body: "[\(Self.placeJSON)]")
        transport.enqueue("DELETE /api/v1/places/aaaaaaaa-0000-4000-8000-000000000001", status: 204)
        let (store, engine) = try await makeStore(transport)
        await store.load()
        let place = try #require(store.places.first)
        #expect(await store.archive(place))
        #expect(store.places.isEmpty)
        #expect(store.plan.monitored.isEmpty)
        #expect(await engine.snapshot.places.isEmpty)
        #expect(store.error == nil)
    }

    @Test func archiveFailureKeepsThePlaceAndShowsTheError() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", body: "[\(Self.placeJSON)]")
        transport.enqueue("DELETE /api/v1/places/aaaaaaaa-0000-4000-8000-000000000001", status: 500, body: #"{"error":{"code":"internal","message":"x"}}"#)
        let (store, engine) = try await makeStore(transport)
        await store.load()
        #expect(await store.archive(store.places[0]) == false)
        #expect(store.places.count == 1)
        #expect(await engine.snapshot.places.count == 1)
        #expect(store.error != nil)
    }

    @Test func archivingAnAlreadyArchivedPlaceCountsAsDone() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", body: "[\(Self.placeJSON)]")
        transport.enqueue("DELETE /api/v1/places/aaaaaaaa-0000-4000-8000-000000000001", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let (store, _) = try await makeStore(transport)
        await store.load()
        #expect(await store.archive(store.places[0]))
        #expect(store.places.isEmpty && store.error == nil)
    }

    @Test func archivedPlacesAreNeverAutomated() async throws {
        // A server that does list an archived place (future contract) must not make the app watch it.
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", body: "[\(Self.placeJSON.replacingOccurrences(of: "\"archived\":false", with: "\"archived\":true"))]")
        let (store, engine) = try await makeStore(transport)
        await store.load()
        #expect(store.places.isEmpty)
        #expect(store.plan.monitored.isEmpty)
        #expect(await engine.snapshot.places.isEmpty)
    }

    @Test func settingsAreClampedAndPersistedInTheEngine() async throws {
        let transport = MockTransport()
        let (store, engine) = try await makeStore(transport)
        await store.setDwellMinutes(1)
        await store.setCooldownMinutes(90)
        await store.setEnabled(false)
        let config = await engine.snapshot.config
        #expect(config.dwellMinutes == 2)
        #expect(config.cooldownMinutes == 60)
        #expect(!config.enabled)
    }
}
