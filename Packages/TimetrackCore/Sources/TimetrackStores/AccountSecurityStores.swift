import Foundation
import Observation
import TimetrackCore

// AUD3-A: stores of "Konto und Sicherheit": passkeys, recovery methods, linked identities, sessions.
// All of them follow the profile store: a 403 `reauth_required` sets `needsFreshLogin` instead of a plain error, and secrets
// (recovery codes) stay in memory only.

/// Shared handling of failures: fresh-login requests are separated from real errors.
@MainActor
protocol FreshLoginReporting: AnyObject {
    var needsFreshLogin: Bool { get set }
    var error: TimetrackError? { get set }
}

extension FreshLoginReporting {
    func report(_ failure: TimetrackError) {
        if failure.knownCode == .reauthRequired { needsFreshLogin = true } else if failure != .cancelled { error = failure }
    }
}

// MARK: - Passkeys

@MainActor
@Observable
public final class PasskeysStore: FreshLoginReporting {
    public enum Notice: Equatable, Sendable { case added, renamed, revoked }

    public private(set) var passkeys: [Passkey] = []
    public private(set) var hasLoaded = false
    public private(set) var isWorking = false
    public private(set) var notice: Notice?
    public var needsFreshLogin = false
    public var error: TimetrackError?

    private let client: APIClient
    /// Runs the system passkey prompt and the server calls (`AppModel.registerAdditionalPasskey`).
    private let register: @MainActor (String?) async -> TimetrackError?

    public init(client: APIClient, register: @escaping @MainActor (String?) async -> TimetrackError?) {
        self.client = client
        self.register = register
    }

    /// The server refuses to remove the last passkey when no recovery method is active; the screen warns before that.
    public var isLast: Bool { passkeys.count == 1 }

    public func load() async {
        do {
            passkeys = try await client.listPasskeys().sorted { $0.createdAt < $1.createdAt }
            hasLoaded = true
            error = nil
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {}
    }

    private func begin() -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        error = nil
        notice = nil
        needsFreshLogin = false
        return true
    }

    /// `name` is optional (the apps pass the device name); the system prompt follows.
    @discardableResult
    public func add(name: String?) async -> Bool {
        guard begin() else { return false }
        defer { isWorking = false }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let failure = await register(trimmed.flatMap { $0.isEmpty ? nil : String($0.prefix(80)) }) {
            report(failure)
            return false
        }
        notice = .added
        await load()
        return true
    }

    @discardableResult
    public func rename(_ passkey: Passkey, to input: String) async -> Bool {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(name.count), begin() else { return false }
        defer { isWorking = false }
        do {
            let updated = try await client.renamePasskey(id: passkey.id, name: name)
            if let index = passkeys.firstIndex(where: { $0.id == passkey.id }) { passkeys[index] = updated }
            notice = .renamed
            return true
        } catch let failure as TimetrackError { report(failure) } catch {}
        return false
    }

    @discardableResult
    public func revoke(_ passkey: Passkey) async -> Bool {
        guard begin() else { return false }
        defer { isWorking = false }
        do {
            try await client.revokePasskey(id: passkey.id)
            passkeys.removeAll { $0.id == passkey.id }
            notice = .revoked
            return true
        } catch let failure as TimetrackError {
            if failure.status == 404 { passkeys.removeAll { $0.id == passkey.id }; return true } // already gone
            report(failure)
        } catch {}
        return false
    }
}

// MARK: - Recovery

@MainActor
@Observable
public final class RecoveryStore: FreshLoginReporting {
    public enum Notice: Equatable, Sendable {
        case codesDisabled, passwordSaved, passwordRemoved, emailCodeSent, emailActive, emailDisabled
    }

    public private(set) var status: RecoveryStatus?
    public private(set) var isWorking = false
    public private(set) var notice: Notice?
    /// The plain recovery codes, shown once after generating; never persisted.
    public private(set) var freshCodes: [String]?
    /// A code was sent to the account e-mail and waits for its confirmation.
    public private(set) var emailCodePending = false
    public var needsFreshLogin = false
    public var error: TimetrackError?

    private let client: APIClient

    public init(client: APIClient) { self.client = client }

    public var emailState: EmailRecoveryState? { status.map { EmailRecoveryState($0.email) } }

    public func load() async {
        do {
            status = try await client.recoveryStatus()
            error = nil
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {}
    }

    private func begin() -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        error = nil
        notice = nil
        needsFreshLogin = false
        return true
    }

    private func refreshStatus() async { if let next = try? await client.recoveryStatus() { status = next } }

    // Recovery codes

    @discardableResult
    public func generateCodes() async -> Bool {
        guard begin() else { return false }
        defer { isWorking = false }
        do {
            freshCodes = try await client.generateRecoveryCodes()
            await refreshStatus()
            return true
        } catch let failure as TimetrackError { report(failure) } catch {}
        return false
    }

    /// The person confirmed they saved the codes.
    public func dismissCodes() { freshCodes = nil }

    /// One line per code, for copying and sharing.
    public var codesText: String { freshCodes?.joined(separator: "\n") ?? "" }

    @discardableResult
    public func disableCodes() async -> Bool {
        guard begin() else { return false }
        defer { isWorking = false }
        do {
            try await client.disableRecoveryCodes()
            freshCodes = nil
            await refreshStatus()
            notice = .codesDisabled
            return true
        } catch let failure as TimetrackError { report(failure) } catch {}
        return false
    }

    // Fallback password

    @discardableResult
    public func setPassword(_ password: String, repeated: String) async -> Bool {
        guard RecoveryValidation.passwordProblem(password, repeated: repeated) == nil, begin() else { return false }
        defer { isWorking = false }
        do {
            try await client.setFallbackPassword(password)
            await refreshStatus()
            notice = .passwordSaved
            return true
        } catch let failure as TimetrackError { report(failure) } catch {}
        return false
    }

    @discardableResult
    public func removePassword() async -> Bool {
        guard begin() else { return false }
        defer { isWorking = false }
        do {
            try await client.removeFallbackPassword()
            await refreshStatus()
            notice = .passwordRemoved
            return true
        } catch let failure as TimetrackError { report(failure) } catch {}
        return false
    }

    // E-mail

    /// 204 turns it on at once; 202 sends a code to the account e-mail (then `emailCodePending`).
    @discardableResult
    public func enableEmail() async -> Bool {
        guard begin() else { return false }
        defer { isWorking = false }
        do {
            switch try await client.enableEmailRecovery() {
            case .active:
                emailCodePending = false
                await refreshStatus()
                notice = .emailActive
            case .codeSent:
                emailCodePending = true
                notice = .emailCodeSent
            }
            return true
        } catch let failure as TimetrackError {
            report(failure)
            // 501: the server cannot send mail; show the method as unavailable.
            if failure.status == 501, status != nil { status?.email.available = false }
        } catch {}
        return false
    }

    @discardableResult
    public func verifyEmail(code input: String) async -> Bool {
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, begin() else { return false }
        defer { isWorking = false }
        do {
            try await client.verifyRecoveryEmail(code: code)
            emailCodePending = false
            await refreshStatus()
            notice = .emailActive
            return true
        } catch let failure as TimetrackError { report(failure) } catch {}
        return false
    }

    public func cancelEmailCode() { emailCodePending = false }

    @discardableResult
    public func disableEmail() async -> Bool {
        guard begin() else { return false }
        defer { isWorking = false }
        do {
            try await client.disableEmailRecovery()
            emailCodePending = false
            await refreshStatus()
            notice = .emailDisabled
            return true
        } catch let failure as TimetrackError { report(failure) } catch {}
        return false
    }
}

// MARK: - Linked identities (OIDC)

/// Shows and unlinks identities. Linking a new one needs the provider's browser sign-in and is not offered in the apps.
@MainActor
@Observable
public final class IdentitiesStore: FreshLoginReporting {
    public private(set) var identities: [ExternalIdentity] = []
    public private(set) var hasLoaded = false
    public private(set) var isWorking = false
    public private(set) var unlinkedNotice = false
    public var needsFreshLogin = false
    public var error: TimetrackError?

    private let client: APIClient

    public init(client: APIClient) { self.client = client }

    public func load() async {
        do {
            identities = try await client.listIdentities().sorted { $0.linkedAt < $1.linkedAt }
            hasLoaded = true
            error = nil
        } catch let failure as TimetrackError {
            // 404/501: a server without external sign-in shows the empty state, not an error.
            if failure.status == 404 || failure.status == 501 { identities = []; hasLoaded = true; error = nil } else if failure != .cancelled { error = failure }
        } catch {}
    }

    @discardableResult
    public func unlink(_ identity: ExternalIdentity) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        error = nil
        unlinkedNotice = false
        needsFreshLogin = false
        defer { isWorking = false }
        do {
            try await client.unlinkIdentity(id: identity.id)
            identities.removeAll { $0.id == identity.id }
            unlinkedNotice = true
            return true
        } catch let failure as TimetrackError {
            if failure.status == 404 { identities.removeAll { $0.id == identity.id }; return true }
            report(failure)
        } catch {}
        return false
    }
}

// MARK: - Sessions

/// The contract has no session list, only "end all other sessions" (same as the web app).
@MainActor
@Observable
public final class SessionsStore: FreshLoginReporting {
    public private(set) var isWorking = false
    public private(set) var revokedNotice = false
    public var needsFreshLogin = false
    public var error: TimetrackError?

    private let client: APIClient

    public init(client: APIClient) { self.client = client }

    @discardableResult
    public func revokeOthers() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        error = nil
        revokedNotice = false
        needsFreshLogin = false
        defer { isWorking = false }
        do {
            try await client.revokeOtherSessions()
            revokedNotice = true
            return true
        } catch let failure as TimetrackError { report(failure) } catch {}
        return false
    }
}
