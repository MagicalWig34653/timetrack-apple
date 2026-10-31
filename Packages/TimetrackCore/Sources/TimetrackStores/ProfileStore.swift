import Foundation
import Observation
import TimetrackCore

/// AUD3-A: profile of the signed-in account (display name, e-mail with confirmation code). Mirrors the web app's profile page.
/// Changing or removing the e-mail needs a fresh session; the store then sets `needsFreshLogin` instead of a plain error.
@MainActor
@Observable
public final class ProfileStore {
    public enum Notice: Equatable, Sendable {
        case nameSaved, codeSent, emailConfirmed, emailRemoved
    }

    public private(set) var profile: Profile?
    public private(set) var hasLoaded = false
    public private(set) var isWorking = false
    public private(set) var notice: Notice?
    /// The server wants a session younger than ten minutes (403 `reauth_required`).
    public private(set) var needsFreshLogin = false
    public var error: TimetrackError?

    /// Called with the new display name after it was saved, so the app's account card follows.
    public var onDisplayNameChanged: (@MainActor (String) -> Void)?

    private let client: APIClient

    public init(client: APIClient) { self.client = client }

    private func adopt(_ next: Profile) {
        let nameChanged = profile?.displayName != next.displayName
        profile = next
        if nameChanged { onDisplayNameChanged?(next.displayName) }
    }

    private func begin() -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        error = nil
        notice = nil
        needsFreshLogin = false
        return true
    }

    private func fail(_ failure: TimetrackError) {
        if failure.knownCode == .reauthRequired { needsFreshLogin = true } else if failure != .cancelled { error = failure }
    }

    public func load() async {
        do {
            adopt(try await client.getProfile())
            hasLoaded = true
            error = nil
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {
            // not a TimetrackError: ignore
        }
    }

    @discardableResult
    public func saveDisplayName(_ input: String) async -> Bool {
        guard let name = ProfileValidation.displayName(input) else { error = .api(status: 400, code: "bad_request", message: "name"); return false }
        guard begin() else { return false }
        defer { isWorking = false }
        do {
            adopt(try await client.updateProfileName(name))
            notice = .nameSaved
            return true
        } catch let failure as TimetrackError { fail(failure) } catch {}
        return false
    }

    /// Sends the code. On success the server holds a `pendingEmail`, which the reload shows.
    @discardableResult
    public func requestEmailChange(_ input: String) async -> Bool {
        guard let email = ProfileValidation.email(input) else { error = .api(status: 400, code: "bad_request", message: "email"); return false }
        guard begin() else { return false }
        defer { isWorking = false }
        do {
            try await client.requestProfileEmailChange(email: email)
            await reloadKeepingState()
            notice = .codeSent
            return true
        } catch let failure as TimetrackError { fail(failure) } catch {}
        return false
    }

    @discardableResult
    public func confirmEmail(code input: String) async -> Bool {
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, begin() else { return false }
        defer { isWorking = false }
        do {
            adopt(try await client.verifyProfileEmail(code: code))
            notice = .emailConfirmed
            return true
        } catch let failure as TimetrackError {
            fail(failure)
            // A consumed request (409 email_taken) no longer waits for a code.
            if failure.status == 409 { await reloadKeepingState() }
        } catch {}
        return false
    }

    @discardableResult
    public func removeEmail() async -> Bool {
        guard begin() else { return false }
        defer { isWorking = false }
        do {
            try await client.removeProfileEmail()
            await reloadKeepingState()
            notice = .emailRemoved
            return true
        } catch let failure as TimetrackError { fail(failure) } catch {}
        return false
    }

    /// Reload after a write without touching `error`/`notice` of the call in progress.
    private func reloadKeepingState() async {
        if let next = try? await client.getProfile() { adopt(next) }
    }
}
