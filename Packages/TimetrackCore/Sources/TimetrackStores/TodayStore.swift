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
    /// True after the first successful server load of this store.
    public private(set) var hasLoadedLive = false
    /// Last cached display state (App Group snapshot), shown until live data arrives.
    private var cachedSnapshot: WidgetSnapshot?

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
        pending = await queue.pending
    }

    /// What a compact screen shows right now: live data, else queued actions on top of the cache.
    public var display: TodayDisplay {
        let base = hasLoadedLive
            ? TodayDisplay.live(running: running, day: day, account: account, segments: segments, updatedAt: lastLoaded)
            : TodayDisplay.cached(cachedSnapshot)
        return base.applying(pending)
    }

    /// UX3: delivery state for the status line (nothing when all is well).
    public var syncStatus: SyncStatus { SyncStatus(pending: pending.count, networkError: error?.isNetworkError == true) }

    public var timeZone: TimeZone { calendar.timeZone }
    public var todayLabel: LocalDay { calendar.day(for: .now) }

    /// `deferAccount`: the balance is fetched after the timer and the day are shown (compact screens; one round trip less before content).
    public func load(deferAccount: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        let today = calendar.day(for: .now)
        do {
            if deferAccount {
                async let timer = client.currentTimer()
                async let evaluation = client.getDay(today)
                let (timerValue, dayValue) = try await (timer, evaluation)
                apply(running: timerValue, day: dayValue, account: account)
                // Timer and day are on screen now; the balance follows without delaying them.
                error = nil
                lastLoaded = .now
                hasLoadedLive = true
                changed()
                account = try? await client.getTimeAccount(asOf: today)
            } else {
                async let timer = client.currentTimer()
                async let evaluation = client.getDay(today)
                async let balance = client.getTimeAccount(asOf: today)
                let (timerValue, dayValue, accountValue) = try await (timer, evaluation, balance)
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
        let result = await queue.drain(client: client)
        pending = await queue.pending
        changed()
        if result.delivered > 0, reload {
            await load(deferAccount: true)
        } else if result.unauthorized {
            error = .api(status: 401, code: APIErrorCode.unauthorized.rawValue, message: "Unauthorized")
        }
    }

    public func start(kind: SegmentKind = .work) async {
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

    public func stop() async {
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
        pending = await queue.pending
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
