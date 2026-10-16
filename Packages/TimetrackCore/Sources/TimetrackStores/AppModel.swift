import Foundation
import Observation
import TimetrackCore

/// Session and environment for all screens. One instance per app; platform views read it from the environment.
@MainActor
@Observable
public final class AppModel {
    public enum Phase: Equatable {
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
    public private(set) var isBusy = false
    public var lastError: TimetrackError?

    private let auth: AuthService
    private var context: AuthContext?

    public init(auth: AuthService) {
        self.auth = auth
    }

    public var dayCalendar: DayCalendar {
        DayCalendar(timeZone: workModel?.timeZone ?? TimeZone(identifier: "Europe/Berlin") ?? .current)
    }

    public func isEnabled(_ module: ModuleKey) -> Bool { modules.isEnabled(module) }

    // MARK: - Lifecycle

    public func restore() async {
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

    private func adopt(_ context: AuthContext) async {
        self.context = context
        account = context.session.account
        serverURL = context.client.baseURL
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
        today = TodayStore(client: client, calendar: calendar)
        timeList = TimeListStore(client: client, calendar: calendar)
        phase = .signedIn
        Task { await today?.load() }
    }

    public func refreshModules() async {
        guard let context, let statuses = try? await context.client.listModules() else { return }
        modules = ModuleSwitches(statuses)
    }

    private func reset(to phase: Phase) {
        context = nil
        account = nil
        today = nil
        timeList = nil
        workModel = nil
        modules = ModuleSwitches()
        self.phase = phase
    }
}
