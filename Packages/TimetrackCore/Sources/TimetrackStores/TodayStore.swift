import Foundation
import Observation
import TimetrackCore

/// State of the "Heute" screen: running timer, today's evaluated day and the time account balance.
/// All numbers come from the backend; this store only starts/stops the timer and displays results.
@MainActor
@Observable
public final class TodayStore {
    public private(set) var running: Segment?
    public private(set) var day: DayEvaluation?
    public private(set) var account: TimeAccount?
    public private(set) var segments: [Segment] = []
    /// H3: context for the "Jetzt" sheet and the top of "Heute". Both are optional extras: a failed read leaves them as they were.
    /// Planned end of today (plan day), and the account's places by id (names for the running entry).
    public private(set) var plannedEnd: Date?
    public private(set) var places: [UUID: Place] = [:]
    private var contextDay: LocalDay?
    public private(set) var isLoading = false
    /// When the last successful load finished (widgets publish a fresh "updated" time from it).
    public private(set) var lastLoaded: Date?
    public var error: TimetrackError?
    /// Reports user-initiated start/stop results (never loads); the app maps them to feedback.
    public var onOutcome: StoreOutcomeHandler?
    /// Called after the displayed state changed (load finished, action queued or delivered); the watch app publishes its snapshot from it.
    public var onChange: (@MainActor () -> Void)?

    /// Timer actions that could not be delivered yet (offline queue, watch). Shown optimistically and sent when the server answers.
    public private(set) var pending: [QueuedTimerAction] = []
    /// X2: delayed "Fortführen" actions that were refused on delivery because the entries changed meanwhile; the user decides.
    public private(set) var attention: [QueuedTimerAction] = []
    /// True after the first successful server load of this store.
    public private(set) var hasLoadedLive = false
    /// Last cached display state (App Group snapshot), shown until live data arrives.
    private var cachedSnapshot: WidgetSnapshot?

    /// H4: counts own timer actions (begin and end of each). A load whose answer was read before the latest action reached the server
    /// would show the timer as it was before that action (a started timer "stops" when returning to Heute); such answers are discarded.
    private var actionEpoch = 0

    private let client: APIClient
    private let calendar: DayCalendar
    private let queue: TimerActionQueue?

    /// With a `queue`, start/stop that cannot reach the server are stored and delivered later instead of failing.
    public init(client: APIClient, calendar: DayCalendar, queue: TimerActionQueue? = nil) {
        self.client = client
        self.calendar = calendar
        self.queue = queue
    }

    /// Gives the screen something to show before the first server answer (and while offline).
    private func changed() { onChange?() }

    public func seed(snapshot: WidgetSnapshot?) { cachedSnapshot = snapshot }

    /// Restores actions persisted by an earlier launch.
    public func restorePending() async {
        guard let queue else { return }
        await refreshPending(queue)
    }

    private func refreshPending(_ queue: TimerActionQueue) async {
        pending = await queue.pending
        attention = await queue.needsAttention
    }

    /// X2: the user dismissed a delayed continue that could not be delivered (or started a new entry instead).
    public func dismissAttention(_ id: UUID) async {
        guard let queue else { return }
        await queue.discard(id: id)
        await refreshPending(queue)
        changed()
    }

    /// Explicit retry keeps the original event id; another conflict returns the item to the attention list.
    public func retryAttention(_ id: UUID) async {
        guard let queue, await queue.retry(id: id) else { return }
        await refreshPending(queue)
        changed()
        await drainQueue()
    }

    /// What a compact screen shows right now: live data, else queued actions on top of the cache.
    public var display: TodayDisplay {
        let base = hasLoadedLive
            ? TodayDisplay.live(running: running, day: day, account: account, segments: segments, updatedAt: lastLoaded)
            : TodayDisplay.cached(cachedSnapshot)
        return base.applying(pending)
    }

    /// H3: live outlook of the day (worked incl. the running entry, remaining, expected end, break status) at `now`.
    public func outlook(now: Date = .now) -> DayOutlook {
        DayOutlook(now: now, running: running, segments: segments, doneAtLoad: (day?.evaluatedWorkSeconds ?? 0) + (day?.creditSeconds ?? 0),
                   loadedAt: lastLoaded, targetSeconds: day?.targetSeconds ?? 0, plannedEnd: plannedEnd)
    }

    /// H3: the place of the running entry by name, when the entry has one and the account's places are known.
    public var runningPlace: Place? { running?.placeId.flatMap { places[$0] } }

    /// UX3: delivery state for the status line (nothing when all is well).
    public var syncStatus: SyncStatus { SyncStatus(pending: pending.count, networkError: error?.isNetworkError == true) }

    public var timeZone: TimeZone { calendar.timeZone }
    public var todayLabel: LocalDay { calendar.day(for: .now) }

    /// `deferAccount`: the balance is fetched after the timer and the day are shown (compact screens; one round trip less before content).
    public func load(deferAccount: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        let today = calendar.day(for: .now)
        let epoch = actionEpoch
        do {
            if deferAccount {
                async let timer = client.currentTimer()
                async let evaluation = client.getDay(today)
                let (timerValue, dayValue) = try await (timer, evaluation)
                guard epoch == actionEpoch else { return }
                apply(running: timerValue, day: dayValue, account: account)
                // Timer and day are on screen now; the balance follows without delaying them.
                error = nil
                lastLoaded = .now
                hasLoadedLive = true
                changed()
                let balance = try? await client.getTimeAccount(asOf: today)
                // An action (or a newer load) may have started while the balance was in flight; its answer belongs to an older state.
                if epoch == actionEpoch, today == calendar.day(for: .now) { account = balance }
            } else {
                async let timer = client.currentTimer()
                async let evaluation = client.getDay(today)
                async let balance = client.getTimeAccount(asOf: today)
                let (timerValue, dayValue, accountValue) = try await (timer, evaluation, balance)
                guard epoch == actionEpoch else { return }
                apply(running: timerValue, day: dayValue, account: accountValue)
            }
            error = nil
            lastLoaded = .now
            hasLoadedLive = true
            changed()
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
            return
        } catch {
            self.error = .cancelled
            return
        }
        await drainQueue(reload: deferAccount)
        await loadContext(day: today)
    }

    /// H3: planned end of today and the place names; read once per day, silently (not part of the day's numbers).
    private func loadContext(day: LocalDay) async {
        guard contextDay != day else { return }
        let planned = try? await client.listPlanDays(from: day, to: day)
        let placeList = try? await client.listPlaces()
        if let planned { plannedEnd = PlannedDay(plan: planned.first { $0.date == day }, zone: calendar.timeZone).end }
        if let placeList { places = Dictionary(placeList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
        if planned != nil, placeList != nil { contextDay = day }
        changed()
    }

    private func apply(running timerValue: Segment?, day dayValue: DayEvaluation, account accountValue: TimeAccount?) {
        running = timerValue
        day = dayValue
        account = accountValue
        segments = (dayValue.segments ?? []).filter { !$0.voided }.sorted { $0.startedAt < $1.startedAt }
    }

    /// Sends queued actions (after a successful load, i.e. the server is reachable). Reloads once when something was delivered.
    public func drainQueue(reload: Bool = true) async {
        guard let queue, await queue.count > 0 else { return }
        actionEpoch += 1
        let result = await queue.drain(client: client)
        actionEpoch += 1
        await refreshPending(queue)
        changed()
        if result.needsAttention > 0, let refused = attention.last?.attention {
            // Surface the conflict (409 segment_overlap / 412 stale_version) and show the real state instead of guessing.
            error = .api(status: refused.status, code: refused.code ?? "conflict", message: "Fortführen nicht mehr möglich")
        }
        if result.delivered > 0 || result.needsAttention > 0, reload {
            let surfaced = error
            await load(deferAccount: true)
            if result.needsAttention > 0, error == nil { error = surfaced }
        } else if result.unauthorized {
            error = .api(status: 401, code: APIErrorCode.unauthorized.rawValue, message: "Unauthorized")
        }
    }

    public func start(kind: SegmentKind = .work) async {
        actionEpoch += 1
        defer { actionEpoch += 1 }
        let eventId = UUID()
        let client = client
        if let queue {
            await performQueued(.init(id: eventId, command: .start(kind), queuedAt: .now), queue: queue, success: .timerStarted) {
                self.running = try await client.startTimer(clientEventId: eventId, kind: kind)
            }
            return
        }
        await perform(success: .timerStarted) {
            let segment = try await retryOnNetworkError { try await client.startTimer(clientEventId: eventId, kind: kind) }
            self.running = segment
        }
    }

    /// H4: what "Fortführen" did, for an honest message ("Eintrag wieder geöffnet" / "Neuer Eintrag ab jetzt, die Lücke bleibt Pause" / "wird gesendet").
    public enum ContinueNotice: Sendable, Equatable { case reopened, startedNew, queued }
    public private(set) var continueNotice: ContinueNotice?
    public func clearContinueNotice() { continueNotice = nil }

    /// H4: the most recent finished entry of today that can be continued (nothing runs, nothing waits in the queue, kind is startable).
    public var continuableSegment: Segment? {
        guard running == nil, !pending.contains(where: { if case .stop = $0.command { false } else { true } }) else { return nil }
        return TimerCommand.continuable(in: segments)
    }

    /// H5: what every platform shows for "Fortführen" (kind, end of the entry, gap). Nil when nothing can be continued.
    public var continueOffer: ContinueOffer? {
        continuableSegment.flatMap { ContinueOffer(segment: $0) }
    }

    /// H4: gaps longer than this get two explicit options in the UI ("Fortführen (Lücke zählt mit)" / "Neu starten (Lücke bleibt Pause)").
    public static let longContinueGap: TimeInterval = ContinueOffer.longGap

    /// H4: how long ago the continuable entry ended. Reopening counts this gap as time of the entry (server rule since contract 0.27.0).
    public func continueGap(now: Date = .now) -> TimeInterval? {
        continuableSegment?.endedAt.map { max(0, now.timeIntervalSince($0)) }
    }

    /// H4: continues `continuableSegment`: reopens it (`endedAt: null`); a server that cannot or will not reopen gets a new segment of the same
    /// kind/place/note from now instead (the gap stays a pause). Unreachable server: queued like start/stop.
    @discardableResult
    public func continueLast(startNew: Bool = false) async -> Bool {
        guard let segment = continuableSegment else { return false }
        actionEpoch += 1
        defer { actionEpoch += 1 }
        continueNotice = nil
        let target = QueuedTimerAction.ContinueTarget(segment)
        let eventId = UUID()
        let client = client
        let attempt: () async throws -> Void = {
            let result = try await TimerActionQueue.resume(target, client: client, clientEventId: eventId, startNewOnly: startNew)
            self.running = result.segment
            self.continueNotice = result.mode == .reopened ? .reopened : .startedNew
        }
        if let queue {
            await performQueued(.init(id: eventId, command: startNew ? .start(target.kind) : .resume(target), queuedAt: .now, placeId: startNew ? target.placeId : nil), queue: queue, success: .timerStarted, attempt)
            if pending.contains(where: { $0.id == eventId }) { continueNotice = .queued }
            return running != nil || continueNotice == .queued
        }
        await perform(success: .timerStarted) {
            let result = try await retryOnNetworkError { try await TimerActionQueue.resume(target, client: client, clientEventId: eventId, startNewOnly: startNew) }
            self.running = result.segment
            self.continueNotice = result.mode == .reopened ? .reopened : .startedNew
        }
        return running != nil
    }

    public func stop() async {
        actionEpoch += 1
        defer { actionEpoch += 1 }
        let eventId = UUID()
        let client = client
        if let queue {
            await performQueued(.init(id: eventId, command: .stop, queuedAt: .now), queue: queue, success: .timerStopped) {
                _ = try await client.stopTimer(clientEventId: eventId)
                self.running = nil
            }
            return
        }
        await perform(success: .timerStopped) {
            _ = try await retryOnNetworkError { try await client.stopTimer(clientEventId: eventId) }
            self.running = nil
        }
    }

    /// H2: corrects the running segment (start time, kind, note) from the "Jetzt" sheet. Needs the server; returns true on success.
    @discardableResult
    public func correctRunning(_ correction: SegmentCorrection) async -> Bool {
        guard let segment = running else { return false }
        actionEpoch += 1
        defer { actionEpoch += 1 }
        let client = client
        do {
            _ = try await client.correctSegment(id: segment.id, correction, ifMatchVersion: segment.version)
            onOutcome?(.saved)
            await load(deferAccount: true)
            return true
        } catch let thrown as TimetrackError {
            if thrown != .cancelled { onOutcome?(.failed); error = thrown }
        } catch {
            self.error = .cancelled
        }
        return false
    }

    /// H3: moves the start of the running entry by `minutes` earlier (negative: later), never into the future. Needs the server.
    @discardableResult
    public func shiftRunningStart(byMinutes minutes: Int, now: Date = .now) async -> Bool {
        guard let segment = running else { return false }
        let target = min(now, segment.startedAt.addingTimeInterval(TimeInterval(-minutes * 60)))
        return await correctRunning(SegmentCorrection(startedAt: target, reason: "Korrektur im laufenden Eintrag"))
    }

    /// H3: "start at a custom time" = start now, then move the beginning back (two honest steps with existing endpoints).
    /// If the correction is refused (e.g. an overlap) the timer keeps running from now and the error is shown.
    public func start(kind: SegmentKind, since: Date, now: Date = .now) async {
        await start(kind: kind)
        guard running != nil, since < now.addingTimeInterval(-60) else { return }
        await correctRunning(SegmentCorrection(startedAt: since, reason: "Korrektur im laufenden Eintrag"))
    }

    /// One attempt; unreachable server (transport error, 5xx, 429) stores the action with the same event id instead of failing.
    private func performQueued(_ action: QueuedTimerAction, queue: TimerActionQueue, success: StoreOutcome, _ attempt: () async throws -> Void) async {
        // Earlier queued actions go first, otherwise the order of the user's presses would be lost.
        if await queue.count > 0 {
            await enqueue(action, queue: queue, success: success)
            await drainQueue()
            return
        }
        do {
            try await attempt()
            onOutcome?(success)
            await load(deferAccount: true)
        } catch let thrown as TimetrackError {
            if thrown.isNetworkError || (thrown.status ?? 0) >= 500 || thrown.status == 429 {
                await enqueue(action, queue: queue, success: success)
            } else {
                if thrown != .cancelled { onOutcome?(.failed) }
                await load(deferAccount: true)
                if thrown != .cancelled { error = thrown }
            }
        } catch {
            self.error = .cancelled
        }
    }

    private func enqueue(_ action: QueuedTimerAction, queue: TimerActionQueue, success: StoreOutcome) async {
        await queue.enqueue(action)
        await refreshPending(queue)
        changed()
        onOutcome?(success)
    }

    private func perform(success: StoreOutcome, _ action: () async throws -> Void) async {
        var failure: TimetrackError?
        do {
            try await action()
            onOutcome?(success)
        } catch let thrown as TimetrackError {
            failure = thrown
        } catch {
            failure = .cancelled
        }
        if let failure, failure != .cancelled { onOutcome?(.failed) }
        await load()
        if let failure { error = failure }
    }
}

/// H5: UI-agnostic description of the "Fortführen" offer, so iPhone, iPad, Mac and Watch decide identically when to ask about the gap.
public struct ContinueOffer: Sendable, Equatable {
    public let segmentId: UUID
    public let kind: SegmentKind
    public let endedAt: Date

    public init?(segment: Segment) {
        guard let ended = segment.endedAt else { return nil }
        self.segmentId = segment.id; self.kind = segment.kind; self.endedAt = ended
    }

    public func gap(now: Date = .now) -> TimeInterval { max(0, now.timeIntervalSince(endedAt)) }
    /// Longer than `TodayStore.longContinueGap`: the user chooses between "Fortführen (Lücke zählt mit)" and "Neu starten".
    public func isLongGap(now: Date = .now) -> Bool { gap(now: now) > Self.longGap }
    public static let longGap: TimeInterval = 15 * 60
}
