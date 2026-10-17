import Foundation
import Testing
import TimetrackCore
@testable import TimetrackStores

@Suite("Focus decision truth table")
struct FocusDecisionTests {
    private func cfg(_ mode: FocusMode, _ kind: SegmentKind = .work) -> FocusConfiguration { FocusConfiguration(mode: mode, kind: kind) }

    struct Row: CustomStringConvertible {
        var activating: Bool
        var mode: FocusMode
        var timer: FocusTimerState
        var stopManual = false
        var session = true
        var automation = true
        var expected: FocusDecision
        var description: String { "\(activating ? "on" : "off") \(mode) \(timer) manual=\(stopManual) session=\(session) automation=\(automation)" }
    }

    static let idle = FocusTimerState.idle
    static let work = FocusTimerState(running: true, kind: .work, startedByFocus: false)
    static let workByFocus = FocusTimerState(running: true, kind: .work, startedByFocus: true)
    static let travel = FocusTimerState(running: true, kind: .travel, startedByFocus: true)

    static let rows: [Row] = [
        // mode off never acts
        Row(activating: true, mode: .off, timer: idle, expected: .noop(.modeOff)),
        Row(activating: false, mode: .off, timer: workByFocus, expected: .noop(.modeOff)),
        // activation
        Row(activating: true, mode: .suggest, timer: idle, expected: .notifyStart),
        Row(activating: true, mode: .direct, timer: idle, expected: .start),
        Row(activating: true, mode: .suggest, timer: work, expected: .noop(.alreadyRunning)),
        Row(activating: true, mode: .direct, timer: workByFocus, expected: .noop(.alreadyRunning)),
        Row(activating: true, mode: .direct, timer: travel, expected: .noop(.otherTimerRunning)),
        Row(activating: true, mode: .suggest, timer: travel, expected: .noop(.otherTimerRunning)),
        Row(activating: true, mode: .direct, timer: idle, session: false, expected: .askSignIn),
        Row(activating: true, mode: .suggest, timer: idle, session: false, expected: .askSignIn),
        Row(activating: true, mode: .direct, timer: work, session: false, expected: .noop(.alreadyRunning)),
        Row(activating: true, mode: .direct, timer: idle, automation: false, expected: .noop(.automationOff)),
        // deactivation
        Row(activating: false, mode: .suggest, timer: workByFocus, expected: .notifyStop),
        Row(activating: false, mode: .direct, timer: workByFocus, expected: .stop),
        Row(activating: false, mode: .direct, timer: idle, expected: .noop(.notRunning)),
        Row(activating: false, mode: .suggest, timer: idle, expected: .noop(.notRunning)),
        Row(activating: false, mode: .direct, timer: travel, expected: .noop(.otherKind)),
        Row(activating: false, mode: .direct, timer: work, expected: .noop(.startedManually)),
        Row(activating: false, mode: .suggest, timer: work, expected: .noop(.startedManually)),
        Row(activating: false, mode: .direct, timer: work, stopManual: true, expected: .stop),
        Row(activating: false, mode: .suggest, timer: work, stopManual: true, expected: .notifyStop),
        Row(activating: false, mode: .direct, timer: travel, stopManual: true, expected: .noop(.otherKind)),
        Row(activating: false, mode: .direct, timer: workByFocus, session: false, expected: .askSignIn),
        Row(activating: false, mode: .direct, timer: idle, session: false, expected: .noop(.notRunning)),
        Row(activating: false, mode: .direct, timer: workByFocus, automation: false, expected: .noop(.automationOff)),
    ]

    @Test("explicit table", arguments: rows)
    func table(_ row: Row) {
        let config = cfg(row.mode)
        let event: FocusEvent = row.activating ? .activated(config) : .deactivated(config)
        let result = FocusDecision.decide(event: event, timer: row.timer, settings: FocusSettings(stopManuallyStarted: row.stopManual),
                                          hasSession: row.session, automationEnabled: row.automation)
        #expect(result == row.expected, "\(row)")
    }

    @Test("exhaustive invariants")
    func invariants() {
        let timers: [FocusTimerState] = [.idle, Self.work, Self.workByFocus, Self.travel, FocusTimerState(running: true, kind: .school, startedByFocus: false)]
        for mode in FocusMode.allCases { for activating in [true, false] { for timer in timers { for manual in [false, true] { for session in [false, true] {
            let config = FocusConfiguration(mode: mode, kind: .work)
            let decision = FocusDecision.decide(event: activating ? .activated(config) : .deactivated(config), timer: timer,
                                                settings: FocusSettings(stopManuallyStarted: manual), hasSession: session)
            // A stop never touches a timer of another kind, and a start never happens while any timer runs.
            if decision == .stop || decision == .notifyStop { #expect(timer.running && timer.kind == .work && !activating) }
            if decision == .start || decision == .notifyStart { #expect(!timer.running && activating) }
            // Without a session nothing is executed.
            if !session { #expect(![.start, .stop, .notifyStart, .notifyStop].contains(decision)) }
            // Off never acts.
            if mode == .off { #expect(decision == .noop(.modeOff)) }
            // Manual timers are only stopped when the setting says so.
            if (decision == .stop || decision == .notifyStop) && !timer.startedByFocus { #expect(manual) }
        } } } } }
    }
}

@Suite("Focus transitions and runner")
struct FocusRunnerTests {
    final class Backend: FocusTimerBackend, @unchecked Sendable {
        var timer: Segment?
        var starts: [(SegmentKind, UUID?, UUID)] = []
        var stops: [UUID] = []
        var failing = false
        func currentTimer() async throws -> Segment? { timer }
        func start(kind: SegmentKind, placeId: UUID?, eventId: UUID) async throws -> TimerCommand.Outcome {
            if failing { throw TimetrackError.network(.notConnectedToInternet) }
            if let timer { return .alreadyRunning(timer) }
            starts.append((kind, placeId, eventId))
            let seg = Segment(id: UUID(), kind: kind, placeId: placeId, startedAt: Date(timeIntervalSince1970: 1_000))
            timer = seg
            return .started(seg)
        }
        func stop(eventId: UUID) async throws -> TimerCommand.Outcome {
            guard let timer else { return .notRunning }
            stops.append(eventId)
            self.timer = nil
            return .stopped(timer)
        }
    }

    final class Notifier: FocusNotifier, @unchecked Sendable {
        var allowed = true
        var posted: [String] = []
        func postStart(_ configuration: FocusConfiguration, eventId: UUID) async -> Bool { if allowed { posted.append("start") }; return allowed }
        func postStop(_ configuration: FocusConfiguration) async -> Bool { if allowed { posted.append("stop") }; return allowed }
        func postSignIn() async -> Bool { posted.append("signin"); return true }
    }

    private func make(_ backend: Backend?, _ notifier: Notifier, snapshot: WidgetSnapshot? = nil) -> (FocusRunner, FocusStateStore, FocusActionLog) {
        let suite = "focus-test-\(UUID().uuidString)"
        let store = FocusStateStore(suiteName: suite)
        let log = FocusActionLog(suiteName: suite)
        let runner = FocusRunner(store: store, log: log, backend: { backend }, notifier: notifier, sessionAvailable: { backend != nil }, snapshot: { snapshot })
        return (runner, store, log)
    }

    @Test func transitions() {
        let a = FocusConfiguration(mode: .direct), b = FocusConfiguration(mode: .suggest, kind: .school), off = FocusConfiguration(mode: .off)
        #expect(FocusTransition.events(previous: nil, incoming: nil).isEmpty)
        #expect(FocusTransition.events(previous: nil, incoming: a) == [.activated(a)])
        #expect(FocusTransition.events(previous: a, incoming: nil) == [.deactivated(a)])
        #expect(FocusTransition.events(previous: a, incoming: b) == [.activated(b)]) // hand-over: no stop
        #expect(FocusTransition.events(previous: a, incoming: off) == [.deactivated(a)])
        #expect(FocusTransition.events(previous: nil, incoming: off) == [.activated(off)])
    }

    @Test func directStartsAndStopsOwnTimer() async {
        let backend = Backend(), notifier = Notifier()
        let (runner, store, log) = make(backend, notifier)
        let config = FocusConfiguration(mode: .direct, kind: .work, placeId: UUID())
        await runner.handle(incoming: config, trigger: .focusOn)
        #expect(backend.starts.count == 1)
        #expect(backend.starts[0].1 == config.placeId)
        #expect(store.load().active == config)
        #expect(store.load().startedTimer != nil)
        await runner.handle(incoming: nil, trigger: .focusOff)
        #expect(backend.stops.count == 1)
        #expect(store.load().active == nil)
        #expect(store.load().startedTimer == nil)
        #expect(log.entries().count == 2)
        #expect(log.entries().first?.result == .done)
    }

    @Test func repeatedActivationReusesEventIdAndDoesNotDoubleStart() async {
        let backend = Backend(), (runner, store, _) = make(backend, Notifier())
        let config = FocusConfiguration(mode: .direct)
        await runner.handle(incoming: config, trigger: .focusOn)
        let first = store.load().activationId
        await runner.handle(incoming: config, trigger: .focusOn)
        #expect(store.load().activationId == first)
        #expect(backend.starts.count == 1)
    }

    @Test func manualTimerIsNotStoppedByDefault() async {
        let backend = Backend(); backend.timer = Segment(id: UUID(), kind: .work, startedAt: Date(timeIntervalSince1970: 5))
        let (runner, store, _) = make(backend, Notifier())
        store.update { $0.active = FocusConfiguration(mode: .direct) }
        let reports = await runner.handle(incoming: nil, trigger: .focusOff)
        #expect(reports.first?.decision == .noop(.startedManually))
        #expect(backend.stops.isEmpty)
        store.update { $0.active = FocusConfiguration(mode: .direct); $0.settings.stopManuallyStarted = true }
        await runner.handle(incoming: nil, trigger: .focusOff)
        #expect(backend.stops.count == 1)
    }

    @Test func differentKindIsNeverStopped() async {
        let backend = Backend(); backend.timer = Segment(id: UUID(), kind: .travel, startedAt: Date(timeIntervalSince1970: 5))
        let (runner, store, _) = make(backend, Notifier())
        store.update { $0.active = FocusConfiguration(mode: .direct, kind: .work); $0.settings.stopManuallyStarted = true }
        let reports = await runner.handle(incoming: nil, trigger: .focusOff)
        #expect(reports.first?.decision == .noop(.otherKind))
        #expect(backend.timer != nil)
    }

    @Test func suggestPostsOnlyWhenNeeded() async {
        let backend = Backend(), notifier = Notifier()
        let (runner, _, log) = make(backend, notifier) // no snapshot: idle
        await runner.handle(incoming: FocusConfiguration(mode: .suggest), trigger: .focusOn)
        #expect(notifier.posted == ["start"])
        #expect(backend.starts.isEmpty) // suggestion only
        await runner.handle(incoming: nil, trigger: .focusOff) // nothing runs -> no stop question
        #expect(notifier.posted == ["start"])
        #expect(log.entries().first?.result == .skipped(.notRunning))
    }

    @Test func suggestStopUsesSnapshotAndRemembersFocusTimer() async {
        let started = Date(timeIntervalSince1970: 2_000)
        let snap = WidgetSnapshot(isRunning: true, kind: .work, startedAt: started, todaySeconds: 0, day: "2026-10-17", timeZone: "Europe/Berlin", updatedAt: started)
        let notifier = Notifier()
        let (runner, store, _) = make(Backend(), notifier, snapshot: snap)
        store.update { $0.active = FocusConfiguration(mode: .suggest); $0.startedTimer = FocusStartedTimer(segmentId: UUID(), startedAt: started) }
        await runner.handle(incoming: nil, trigger: .focusOff)
        #expect(notifier.posted == ["stop"])
    }

    @Test func deniedNotificationsAreLogged() async {
        let notifier = Notifier(); notifier.allowed = false
        let (runner, _, log) = make(Backend(), notifier)
        await runner.handle(incoming: FocusConfiguration(mode: .suggest), trigger: .focusOn)
        #expect(log.entries().first?.result == .notificationsDenied)
    }

    @Test func noSessionAsksToSignIn() async {
        let notifier = Notifier()
        let (runner, _, log) = make(nil, notifier)
        await runner.handle(incoming: FocusConfiguration(mode: .direct), trigger: .focusOn)
        #expect(notifier.posted == ["signin"])
        #expect(log.entries().first?.result == .askedSignIn)
    }

    @Test func dryRunChangesNothing() async {
        let backend = Backend(), notifier = Notifier()
        let (runner, store, log) = make(backend, notifier)
        let reports = await runner.handle(incoming: FocusConfiguration(mode: .direct), trigger: .test, dryRun: true)
        #expect(reports.first?.decision == .start)
        #expect(reports.first?.entry.result == .wouldDo)
        #expect(backend.starts.isEmpty && notifier.posted.isEmpty)
        #expect(store.load().active == nil)
        #expect(log.entries().isEmpty)
    }

    @Test func failureIsLoggedAndStateKept() async {
        let backend = Backend(); backend.failing = true
        let (runner, store, log) = make(backend, Notifier())
        await runner.handle(incoming: FocusConfiguration(mode: .direct), trigger: .focusOn)
        if case .failed = log.entries().first?.result {} else { Issue.record("expected failure entry") }
        #expect(store.load().active != nil)
    }

    @Test func automationOffBlocks() async {
        let backend = Backend(), (runner, store, _) = make(backend, Notifier())
        store.update { $0.automationEnabled = false }
        await runner.handle(incoming: FocusConfiguration(mode: .direct), trigger: .focusOn)
        #expect(backend.starts.isEmpty)
    }
}

@Suite("Focus log and text")
struct FocusLogTests {
    @Test func ringBufferKeepsNewestFirstAndCaps() {
        let log = FocusActionLog(suiteName: "focus-log-\(UUID().uuidString)")
        for index in 0..<(FocusActionLog.capacity + 5) {
            log.append(FocusLogEntry(trigger: .test, mode: .off, kind: .work, summary: "\(index)", result: .done))
        }
        let entries = log.entries()
        #expect(entries.count == FocusActionLog.capacity)
        #expect(entries.first?.summary == "\(FocusActionLog.capacity + 4)")
        log.clear()
        #expect(log.entries().isEmpty)
    }

    @Test func stateRoundTripsWithoutSecrets() throws {
        let store = FocusStateStore(suiteName: "focus-state-\(UUID().uuidString)")
        let place = UUID()
        store.save(FocusState(active: FocusConfiguration(mode: .suggest, kind: .school, placeId: place, placeName: "Schule", focusName: " Arbeit "),
                              activationId: UUID(), automationEnabled: true, settings: FocusSettings(stopManuallyStarted: true), places: [FocusPlace(id: place, name: "Schule")]))
        let loaded = store.load()
        #expect(loaded.active?.focusName == "Arbeit")
        #expect(loaded.settings.stopManuallyStarted)
        #expect(loaded.places.count == 1)
        let json = String(decoding: try JSONEncoder().encode(loaded), as: UTF8.self).lowercased()
        #expect(!json.contains("cookie") && !json.contains("token") && !json.contains("http"))
    }

    @Test func germanTexts() {
        let named = FocusConfiguration(mode: .suggest, kind: .work, focusName: "Arbeit")
        #expect(FocusText.activeSummary(named) == "Aktiv: Fokus „Arbeit“ → Nachfragen, Art Arbeit")
        #expect(FocusText.startNotification(named).title == "Fokus „Arbeit“ ist an")
        #expect(FocusText.stopNotification(FocusConfiguration(mode: .direct, kind: .travel)).body == "Timer stoppen? (Fahrt)")
        #expect(FocusConfiguration(mode: .off, kind: .unknown).kind == .work)
    }
}
