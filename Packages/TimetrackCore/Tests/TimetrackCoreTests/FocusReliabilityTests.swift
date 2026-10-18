import Foundation
import Testing
import TimetrackCore
@testable import TimetrackStores

/// F3: delivery pipeline of the Focus filter (idempotence, ordering, durable local state, retry queue, time budget, diagnostics).
@Suite("Focus reliability (F3)", .serialized)
struct FocusReliabilityTests {
    typealias Backend = FocusRunnerTests.Backend
    typealias Notifier = FocusRunnerTests.Notifier

    /// A runner with a controllable clock, an in-memory retry queue and a mock-transport client for the drain.
    final class Rig: @unchecked Sendable {
        let store: FocusStateStore, log: FocusActionLog, queue = TimerActionQueue(fileURL: nil)
        let backend = Backend(), notifier = Notifier(), transport = MockTransport()
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        var queuedSignals = 0
        var snapshot: WidgetSnapshot?
        init() {
            let suite = "focus-f3-\(UUID().uuidString)"
            store = FocusStateStore(suiteName: suite)
            log = FocusActionLog(suiteName: suite)
        }
        func advance(_ seconds: TimeInterval) { clock = clock.addingTimeInterval(seconds) }
        var runner: FocusRunner {
            FocusRunner(store: store, log: log, backend: { [self] in backend }, notifier: notifier, sessionAvailable: { true },
                        snapshot: { [self] in snapshot }, now: { [self] in clock }, queue: queue,
                        clientProvider: { [self] in Fixtures.client(transport) }, onQueued: { [self] in queuedSignals += 1 }, networkBudget: 0.5, drainBudget: 2)
        }
    }

    private let direct = FocusConfiguration(mode: .direct, kind: .work, focusName: "Arbeit")

    @Test func offlineStartIsQueuedKeepsStateAndIsRetriedWithTheSameEventId() async {
        let rig = Rig(); rig.backend.failing = true
        await rig.runner.handle(incoming: direct, trigger: .focusOn)
        let state = rig.store.load()
        #expect(state.active == direct) // the local effect is durable even though the network failed
        #expect(rig.log.entries().first?.result == .queued)
        #expect(await rig.queue.count == 1)
        #expect(rig.queuedSignals == 1)
        let queuedId = await rig.queue.pending[0].id
        #expect(queuedId == state.activationId) // stable id: a replay can never book twice
        #expect(state.queuedStartEventId == queuedId)

        rig.transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        rig.backend.failing = false
        rig.backend.timer = Segment(id: UUID(), kind: .work, startedAt: Date(timeIntervalSince1970: 1_800_000_100))
        rig.advance(120)
        let result = await rig.runner.retryPending()
        #expect(result?.delivered == 1 && result?.remaining == 0)
        #expect(await rig.queue.count == 0)
        #expect(rig.store.load().queuedStartEventId == nil)
        #expect(rig.store.load().startedTimer != nil) // the delivered start is now known as the Focus's own timer
        #expect(rig.log.entries().first?.trigger == .retry)
    }

    @Test func offlineStopAfterOfflineStartKeepsOrderAndBothAreDelivered() async {
        let rig = Rig(); rig.backend.failing = true
        await rig.runner.handle(incoming: direct, trigger: .focusOn)
        rig.advance(600)
        rig.transport.enqueue("POST /api/v1/time/timer/start", error: .notConnectedToInternet) // the drain before the decision finds the server still away
        await rig.runner.handle(incoming: nil, trigger: .focusOff)
        #expect(await rig.queue.pending.map(\.command) == [.start(.work), .stop])
        rig.transport.set("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        rig.transport.set("POST /api/v1/time/timer/stop", body: Fixtures.closedSegmentJSON)
        rig.backend.failing = false
        let result = await rig.runner.retryPending()
        #expect(result?.delivered == 2 && result?.remaining == 0)
    }

    @Test func stillOfflineKeepsTheQueueAndAsksForAnotherAttempt() async {
        let rig = Rig(); rig.backend.failing = true
        await rig.runner.handle(incoming: direct, trigger: .focusOn)
        rig.transport.enqueue("POST /api/v1/time/timer/start", error: .notConnectedToInternet)
        let signals = rig.queuedSignals
        let result = await rig.runner.retryPending(verbose: true)
        #expect(result?.offline == true && result?.remaining == 1)
        #expect(rig.queuedSignals > signals)
        #expect(rig.log.entries().first?.result == .queued)
    }

    @Test func slowServerHitsTheTimeBudgetAndIsQueuedInsteadOfBlocking() async {
        final class Slow: FocusTimerBackend, @unchecked Sendable {
            func currentTimer() async throws -> Segment? { try await Task.sleep(for: .seconds(30)); return nil }
            func start(kind: SegmentKind, placeId: UUID?, eventId: UUID) async throws -> TimerCommand.Outcome { try await Task.sleep(for: .seconds(30)); return .notRunning }
            func stop(eventId: UUID) async throws -> TimerCommand.Outcome { try await Task.sleep(for: .seconds(30)); return .notRunning }
        }
        let rig = Rig()
        let runner = FocusRunner(store: rig.store, log: rig.log, backend: { Slow() }, notifier: rig.notifier, snapshot: { nil }, queue: rig.queue, networkBudget: 0.4)
        let started = Date()
        await runner.handle(incoming: direct, trigger: .focusOn)
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(rig.log.entries().first?.result == .queued)
        #expect(await rig.queue.count == 1)
    }

    @Test func hangingNotificationSystemDoesNotFreezeTheDelivery() async {
        final class Hanging: FocusNotifier, @unchecked Sendable {
            func postStart(_ configuration: FocusConfiguration, eventId: UUID, sequence: Int64) async -> Bool { await withCheckedContinuation { (_: CheckedContinuation<Bool, Never>) in } }
            func postStop(_ configuration: FocusConfiguration, eventId: UUID, sequence: Int64) async -> Bool { await withCheckedContinuation { (_: CheckedContinuation<Bool, Never>) in } }
            func postSignIn() async -> Bool { true }
        }
        let rig = Rig()
        let runner = FocusRunner(store: rig.store, log: rig.log, backend: { rig.backend }, notifier: Hanging(), snapshot: { nil })
        await runner.handle(incoming: FocusConfiguration(mode: .suggest), trigger: .focusOn) // returns after the 5 s budget
        if case .failed = rig.log.entries().first?.result {} else { Issue.record("expected a failure entry") }
        // The gate is free again: the next delivery is processed.
        await runner.handle(incoming: nil, trigger: .focusOff)
        #expect(rig.log.entries().count == 2)
    }

    @Test func offlineWithStoredSessionIsNotReportedAsSignedOut() async {
        // Regression: the previous design validated the session first; "offline" then looked like "no session" and showed the sign-in hint.
        let rig = Rig(); rig.backend.failing = true
        await rig.runner.handle(incoming: direct, trigger: .focusOn)
        #expect(!rig.notifier.posted.contains("signin"))
        if case .failed = rig.log.entries().first?.result { Issue.record("offline must not be a failure") }
    }

    @Test func rejectedSessionAsksToSignInAndDoesNotQueue() async {
        final class Rejected: FocusTimerBackend, @unchecked Sendable {
            func currentTimer() async throws -> Segment? { nil }
            func start(kind: SegmentKind, placeId: UUID?, eventId: UUID) async throws -> TimerCommand.Outcome { throw TimetrackError.api(status: 401, code: "unauthorized", message: "x") }
            func stop(eventId: UUID) async throws -> TimerCommand.Outcome { throw TimetrackError.api(status: 401, code: "unauthorized", message: "x") }
        }
        let rig = Rig()
        let runner = FocusRunner(store: rig.store, log: rig.log, backend: { Rejected() }, notifier: rig.notifier, snapshot: { nil }, queue: rig.queue)
        await runner.handle(incoming: direct, trigger: .focusOn)
        #expect(rig.notifier.posted == ["signin"])
        #expect(await rig.queue.count == 0)
    }

    @Test func duplicateActivationIsIgnoredButLogged() async {
        let rig = Rig()
        await rig.runner.handle(incoming: direct, trigger: .focusOn)
        rig.advance(1)
        let reports = await rig.runner.handle(incoming: direct, trigger: .focusOn)
        #expect(reports.first?.decision == .noop(.duplicate))
        #expect(rig.backend.starts.count == 1)
        #expect(rig.log.entries().first?.result == .skipped(.duplicate))
        #expect(rig.store.load().lastDelivery?.classification == .duplicate)
    }

    @Test func endWithoutActiveFocusIsLoggedNotSilent() async {
        let rig = Rig()
        let reports = await rig.runner.handle(incoming: nil, trigger: .focusOff)
        #expect(reports.first?.decision == .noop(.notActive))
        #expect(rig.log.entries().count == 1)
        #expect(rig.log.entries().first?.received?.contains("keine Angaben") == true)
        #expect(rig.store.load().lastDelivery?.classification == .notActive)
    }

    @Test func repeatedEndsNeverInvertTheState() async {
        let rig = Rig()
        await rig.runner.handle(incoming: direct, trigger: .focusOn)
        rig.advance(60)
        await rig.runner.handle(incoming: nil, trigger: .focusOff)
        rig.advance(1)
        await rig.runner.handle(incoming: nil, trigger: .focusOff) // second "off": must not start or stop anything
        #expect(rig.backend.starts.count == 1 && rig.backend.stops.count == 1)
        #expect(rig.store.load().active == nil)
    }

    @Test func sequenceIsMonotonicEvenWhenTheClockStepsBack() async {
        let rig = Rig()
        await rig.runner.handle(incoming: direct, trigger: .focusOn)
        let first = rig.store.load().sequence ?? 0
        rig.advance(-3600)
        await rig.runner.handle(incoming: nil, trigger: .focusOff)
        #expect((rig.store.load().sequence ?? 0) > first)
    }

    @Test func receivedParametersAreRecorded() async {
        let rig = Rig()
        let params = FocusParameters(mode: .suggest, kind: .school, placeName: "Schule", focusName: "Lernen")
        await rig.runner.handle(incoming: params.configuration, trigger: .focusOn, received: params)
        let summary = rig.store.load().lastDelivery
        #expect(summary?.parameters == "Modus Nachfragen, Art Schule, Ort Schule, Name „Lernen“")
        #expect(rig.log.entries().first?.received == summary?.parameters)
        #expect(summary?.result != nil)
        #expect(FocusParameters(mode: nil).summary.contains("Fokus beendet"))
    }

    @Test func staleAndRepeatedNotificationAnswersAreIgnored() async {
        let rig = Rig()
        let config = FocusConfiguration(mode: .suggest, kind: .work)
        await rig.runner.handle(incoming: config, trigger: .focusOn)
        let sequence = rig.store.load().sequence!
        #expect(rig.notifier.sequences == [sequence])
        let eventId = rig.notifier.eventIds[0]
        let first = await rig.runner.confirmStart(config, eventId: eventId, sequence: sequence)
        #expect(first.entry.result == .done)
        let repeated = await rig.runner.confirmStart(config, eventId: eventId, sequence: sequence) // the same tap delivered twice
        #expect(repeated.entry.result == .skipped(.duplicate))
        #expect(rig.backend.starts.count == 1)

        rig.advance(60)
        await rig.runner.handle(incoming: nil, trigger: .focusOff) // the Focus ended; the user now answers an old question
        let stale = await rig.runner.confirmStop(config, eventId: UUID(), sequence: sequence)
        #expect(stale.entry.result == .skipped(.stale))
        #expect(rig.backend.stops.isEmpty) // the old answer must not stop anything
    }

    @Test func serialisedDeliveriesDoNotLoseUpdates() async {
        let rig = Rig()
        let runner = rig.runner
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    let config = FocusConfiguration(mode: .off, kind: .work, focusName: "F\(index)")
                    await runner.handle(incoming: config, trigger: .test)
                }
            }
        }
        #expect(rig.log.entries().count == 8) // read-modify-write of the ring buffer was atomic
    }

    @Test func manualResetClearsAStuckFocus() async {
        let rig = Rig()
        await rig.runner.handle(incoming: direct, trigger: .focusOn)
        await rig.runner.resetState()
        #expect(rig.store.load().active == nil)
        #expect(rig.log.entries().first?.summary.contains("zurückgesetzt") == true)
    }

    @Test func oldStoredStateAndLogEntriesStillDecode() throws {
        let legacyState = #"{"active":{"mode":"direct","kind":"work"},"settings":{"stopManuallyStarted":false},"places":[]}"#
        let state = try JSONDecoder().decode(FocusState.self, from: Data(legacyState.utf8))
        #expect(state.active?.mode == .direct && state.sequence == nil && state.lastDelivery == nil)
        let legacyEntry = #"{"id":"11111111-1111-4111-8111-111111111111","date":0,"trigger":"focusOn","mode":"direct","kind":"work","summary":"x","result":{"done":{}}}"#
        let entry = try JSONDecoder().decode(FocusLogEntry.self, from: Data(legacyEntry.utf8))
        #expect(entry.received == nil)
        // A queue entry written before F3 has no placeId and must still load.
        let action = QueuedTimerAction(command: .stop)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(action)) as? [String: Any])
        object.removeValue(forKey: "placeId")
        let decoded = try JSONDecoder().decode(QueuedTimerAction.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.placeId == nil && decoded.id == action.id)
    }

    @Test func diagnosticsTextHasNoSecrets() {
        let state = FocusState(active: FocusConfiguration(mode: .direct), automationEnabled: true)
        let text = FocusDiagnostics.text(state: state, entries: [], pending: 2, notifications: "erlaubt")
        #expect(text.contains("Wartende Aktionen: 2"))
        #expect(!text.lowercased().contains("cookie") && !text.lowercased().contains("token"))
    }
}
