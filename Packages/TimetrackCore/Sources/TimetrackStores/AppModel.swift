import Foundation
import Observation
import TimetrackCore

/// Session and environment for all screens. One instance per app; platform views read it from the environment.
@MainActor
@Observable
public final class AppModel {
    public enum Phase: Equatable, Sendable {
        case restoring
        case signedOut
        /// Credentials are stored but the server could not be reached.
        case offline
        /// Signed in through a recovery path; only passkey setup is allowed server-side.
        case recoveryRestricted
        case signedIn
    }

    public private(set) var phase: Phase = .restoring
    public private(set) var account: Account?
    public private(set) var serverURL: URL?
    public private(set) var modules = ModuleSwitches()
    public private(set) var workModel: WorkModel?
    public private(set) var today: TodayStore?
    public private(set) var timeList: TimeListStore?
    /// Created only while the `planning` module is on.
    public private(set) var planning: PlanningStore?
    public private(set) var calendar: CalendarStore?
    public private(set) var isBusy = false
    /// Session state of clients that start from stored credentials (`restoreFast`); kept in step on all paths.
    public private(set) var lifecycle = SessionLifecycle()
    public var lastError: TimetrackError?

    /// Account-level accent / colour scheme: reconciles the local cache with the account (see `AppearanceSync`).
    public let appearance: AppearanceSync

    private let auth: AuthService
    private var context: AuthContext?

    /// Forwarded to every store created after sign-in: user-initiated results (start/stop/save/delete/failure), never loads.
    /// The app target maps it to haptics (see `TTHaptics.handle`).
    public var onOutcome: StoreOutcomeHandler?

    /// Compact-client launch settings (watch): when set, `restore()` shows stored content first and validates in the background.
    public struct FastLaunch: Sendable {
        public let snapshot: @Sendable () -> WidgetSnapshot?
        public let queue: TimerActionQueue?
        public init(snapshot: @escaping @Sendable () -> WidgetSnapshot?, queue: TimerActionQueue?) {
            self.snapshot = snapshot
            self.queue = queue
        }
    }

    public var fastLaunch: FastLaunch?
    /// Forwarded to the fast-launch today store (`TodayStore.onChange`).
    public var onTodayChanged: (@MainActor () -> Void)?

    public init(auth: AuthService, appearance: AppearanceSync = AppearanceSync()) {
        self.auth = auth
        self.appearance = appearance
    }

    private func forwardOutcome(_ outcome: StoreOutcome) { onOutcome?(outcome) }

    public var dayCalendar: DayCalendar {
        DayCalendar(timeZone: workModel?.timeZone ?? TimeZone(identifier: "Europe/Berlin") ?? .current)
    }

    public func isEnabled(_ module: ModuleKey) -> Bool { modules.isEnabled(module) }

    // MARK: - Lifecycle

    public func restore() async {
        if let fastLaunch { return await restoreFast(fastLaunch) }
        phase = .restoring
        switch await auth.restore() {
        case .signedIn(let context): await adopt(context)
        case .signedOut:
            serverURL = await auth.serverURL
            phase = .signedOut
        case .offline(let url):
            serverURL = url
            phase = .offline
        }
    }

    public func signInWithRecovery(serverInput: String, method: RecoveryMethod, handle: String, proof: String) async {
        await run { auth in
            let url = try AuthService.normalizeServerURL(serverInput)
            return try await auth.signInWithRecovery(server: url, method: method, handle: handle, proof: proof)
        }
    }

    public func signInWithPasskey(serverInput: String) async {
        await run { auth in try await auth.signInWithPasskey(server: try AuthService.normalizeServerURL(serverInput)) }
    }

    /// Development-only sign-in with a copied `tt_session` cookie value.
    public func signInWithSessionCookie(serverInput: String, cookie: String) async {
        await run { auth in try await auth.signInWithSessionCookie(server: try AuthService.normalizeServerURL(serverInput), cookieValue: cookie) }
    }

    public func addPasskey(name: String?) async {
        guard let context else { return }
        await run { auth in try await auth.addPasskey(context: context, name: name) }
    }

    /// Session handed over from another device (watch). Stores it and validates it against the server.
    public func adoptHandedOverSession(server: URL, cookie: String) async {
        await auth.importSession(server: server, cookieValue: cookie)
        await restore()
    }

    /// The other device signed out; forget the local session without contacting the server.
    public func discardSessionLocally(expired: Bool = false) async {
        lifecycle.apply(expired ? .serverRejected : .handoffSignedOut)
        await auth.discardSession()
        reset(to: .signedOut)
    }

    public func signOut() async {
        await auth.signOut()
        reset(to: .signedOut)
    }

    public func forgetServer() async {
        await auth.forgetServer()
        serverURL = nil
        reset(to: .signedOut)
    }

    private func run(_ operation: @Sendable (AuthService) async throws -> AuthContext) async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            await adopt(try await operation(auth))
        } catch let error as TimetrackError {
            lastError = error
        } catch {
            lastError = .cancelled
        }
    }

    // MARK: - Fast launch (watch, A12)

    /// Stored credentials make the app usable at once: stores are created from the stored client and the cached snapshot, then the
    /// session check and the first "today" load run IN PARALLEL (one round trip). Modules, work model and preferences follow.
    /// A network failure keeps the app usable (actions are queued); only a 401 signs out.
    private func restoreFast(_ launch: FastLaunch) async {
        if today == nil { phase = .restoring }
        guard let client = await auth.optimisticClient() else {
            serverURL = await auth.serverURL
            lifecycle.apply(.noCredentials)
            phase = .signedOut
            return
        }
        lifecycle.apply(.credentialsFound)
        serverURL = client.baseURL
        if today == nil {
            let snapshot = launch.snapshot()
            let zone = snapshot.flatMap { TimeZone(identifier: $0.timeZone) } ?? TimeZone(identifier: "Europe/Berlin") ?? .current
            let store = TodayStore(client: client, calendar: DayCalendar(timeZone: zone), queue: launch.queue)
            store.seed(snapshot: snapshot)
            store.onChange = { [weak self] in self?.onTodayChanged?() }
            store.onOutcome = { [weak self] in self?.forwardOutcome($0) }
            today = store
            await store.restorePending()
        }
        phase = .signedIn
        await revalidate()
    }

    /// Re-checks the session and reloads today (launch, app activation, connectivity back). Safe to call often.
    public func revalidate() async {
        guard let today, !validating else { return }
        validating = true
        defer { validating = false }
        async let loaded: Void = today.load(deferAccount: true)
        // Modules and work model start as soon as the session answers, in parallel with the balance that `load` fetches after the day.
        let outcome = await auth.validate()
        switch outcome {
        case .signedIn(let context):
            lifecycle.apply(.validated)
            await finishFastRestore(context)
        case .signedOut:
            lifecycle.apply(.serverRejected)
            reset(to: .signedOut)
        case .offline:
            lifecycle.apply(.networkFailed)
        }
        _ = await loaded
    }

    private var validating = false

    private func finishFastRestore(_ context: AuthContext) async {
        self.context = context
        account = context.session.account
        guard !context.session.recovery else {
            reset(to: .recoveryRestricted)
            return
        }
        await context.client.setModuleDisabledHandler { [weak self] in Task { @MainActor in await self?.refreshModules() } }
        async let statuses = try? context.client.listModules()
        async let models = try? context.client.listWorkModels()
        modules = ModuleSwitches(await statuses ?? [])
        workModel = await models?.current()
        // Not needed for the first frame: sync of the account appearance.
        await appearance.connect(accountId: context.session.account.id, service: context.client,
                                 serverPreferences: context.session.account.preferences, canWrite: true)
        if let zone = workModel?.timeZone, zone != today?.timeZone, let launch = fastLaunch {
            // The cached zone was wrong (first launch or the work model changed): rebuild with the right day boundaries.
            let store = TodayStore(client: context.client, calendar: dayCalendar, queue: launch.queue)
            store.onChange = { [weak self] in self?.onTodayChanged?() }
            store.onOutcome = { [weak self] in self?.forwardOutcome($0) }
            today = store
            await store.restorePending()
            await store.load(deferAccount: true)
        }
        if !modules.isEnabled(.planning) { planning = nil; calendar = nil }
    }

    private func adopt(_ context: AuthContext) async {
        self.context = context
        account = context.session.account
        serverURL = context.client.baseURL
        // Recovery sessions may read but not write preferences (403): they only apply them.
        await appearance.connect(accountId: context.session.account.id, service: context.client,
                                 serverPreferences: context.session.account.preferences, canWrite: !context.session.recovery)
        guard !context.session.recovery else {
            phase = .recoveryRestricted
            return
        }
        await context.client.setModuleDisabledHandler { [weak self] in
            Task { @MainActor in await self?.refreshModules() }
        }
        async let statuses = try? context.client.listModules()
        async let models = try? context.client.listWorkModels()
        modules = ModuleSwitches(await statuses ?? [])
        workModel = await models?.current()
        let client = context.client
        let calendar = dayCalendar
        let todayStore = TodayStore(client: client, calendar: calendar)
        let timeListStore = TimeListStore(client: client, calendar: calendar)
        todayStore.onOutcome = { [weak self] in self?.forwardOutcome($0) }
        timeListStore.onOutcome = { [weak self] in self?.forwardOutcome($0) }
        today = todayStore
        timeList = timeListStore
        makePlanningStores(client: client, enabled: modules.isEnabled(.planning))
        phase = .signedIn
        Task { await today?.load() }
    }

    public func refreshModules() async {
        guard let context, let statuses = try? await context.client.listModules() else { return }
        modules = ModuleSwitches(statuses)
        if !modules.isEnabled(.planning) {
            planning = nil
            calendar = nil
        } else if planning == nil {
            makePlanningStores(client: context.client, enabled: true)
        }
    }

    private func makePlanningStores(client: APIClient, enabled: Bool) {
        guard enabled else {
            planning = nil
            calendar = nil
            return
        }
        let planning = PlanningStore(client: client, calendar: dayCalendar)
        let calendarStore = CalendarStore(client: client, calendar: dayCalendar)
        // Both screens show the same absences: a change in one refreshes the other.
        planning.onAbsencesChanged = { [weak calendarStore] in Task { await calendarStore?.load() } }
        calendarStore.onAbsencesChanged = { [weak planning] in Task { await planning?.load() } }
        planning.onOutcome = { [weak self] in self?.forwardOutcome($0) }
        calendarStore.onOutcome = { [weak self] in self?.forwardOutcome($0) }
        self.planning = planning
        self.calendar = calendarStore
    }

    private func reset(to phase: Phase) {
        if phase == .signedOut, !lifecycle.isSignedOut { lifecycle.apply(.userSignedOut) }
        appearance.disconnect()
        context = nil
        account = nil
        today = nil
        timeList = nil
        planning = nil
        calendar = nil
        workModel = nil
        modules = ModuleSwitches()
        self.phase = phase
    }
}
