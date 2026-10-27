import Foundation
import Observation
import TimetrackCore

/// P14: where this device stands with APNs push, in terms the settings row explains in German.
public enum PushRegistrationState: Equatable, Sendable {
    /// Nothing attempted yet (no token, user has not enabled push).
    case idle
    /// The server is being asked.
    case registering
    case registered(PushDeviceInfo)
    /// 501 `push_unavailable`: this server has no APNs configuration. Not an error, nothing else is attempted.
    case unavailable
    /// 409 `too_many_push_devices`.
    case limitReached
    /// iOS/macOS refused to hand out a token (missing entitlement, no network to Apple, free developer team).
    case systemFailure(String)
    case failed(TimetrackError)
}

public enum PushTestState: Equatable, Sendable {
    case idle, sending, sent
    case failed(TimetrackError)
}

/// What survives a restart: which server-side device row belongs to which token and account, so a changed token or a
/// sign-out can replace or delete exactly that row.
struct PushRegistrationRecord: Codable, Equatable {
    var accountId: UUID
    var serverURL: String
    var token: String
    var device: PushDeviceInfo
    var registeredAt: Date
}

/// Registers the APNs device token of this app with the signed-in account (`/me/push-devices`) and keeps it registered:
/// token change, app start and login all call `setToken`/`register`; the same token for the same account is not sent again
/// within `minimumInterval` (the server limits registrations to 30 per hour). Deleted on sign-out.
@MainActor
@Observable
public final class PushRegistrationStore {
    public private(set) var state: PushRegistrationState = .idle
    public private(set) var testState: PushTestState = .idle
    public private(set) var token: String?

    public static let recordKey = "de.linolaske.timetrack.push.registration"
    /// Same token and account: re-send at most this often (app start / foreground).
    public static let minimumInterval: TimeInterval = 6 * 3600

    private let client: APIClient
    private let accountId: UUID
    private let identity: PushIdentity
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private var inFlight: Task<Void, Never>?

    public init(client: APIClient, accountId: UUID, identity: PushIdentity, defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { .now }) {
        self.client = client
        self.accountId = accountId
        self.identity = identity
        self.defaults = defaults
        self.now = now
        if let record = loadRecord(), record.accountId == accountId, record.serverURL == client.baseURL.absoluteString {
            state = .registered(record.device)
            token = record.token
        }
    }

    public var isRegistered: Bool {
        if case .registered = state { return true }
        return false
    }

    /// The device row, if registered.
    public var device: PushDeviceInfo? {
        if case .registered(let info) = state { return info }
        return nil
    }

    // MARK: - Registration

    /// A (possibly new) device token arrived from the system.
    public func setToken(_ hex: String) async {
        let normalized = hex.lowercased()
        let changed = normalized != token
        token = normalized
        await register(force: changed)
    }

    /// The system could not create a token.
    public func tokenRequestFailed(_ message: String) {
        if case .registered = state { return } // an earlier registration still stands; the failure may be transient
        state = .systemFailure(message)
    }

    /// Sends the token unless the same registration is recent. `force` ignores the throttle (token change, "Erneut registrieren").
    public func register(force: Bool = false) async {
        guard let token else { return }
        if let record = loadRecord(), !force, record.accountId == accountId, record.token == token,
           record.serverURL == client.baseURL.absoluteString, now().timeIntervalSince(record.registeredAt) < Self.minimumInterval {
            state = .registered(record.device)
            return
        }
        // Calls overlap (app start, login and the token callback arrive together): the later one waits for the earlier one.
        let previous = inFlight
        let task = Task { [weak self] in
            await previous?.value
            await self?.performRegistration(token: token)
        }
        inFlight = task
        await task.value
    }

    private func performRegistration(token: String) async {
        if let record = loadRecord(), record.accountId == accountId, record.token == token, record.serverURL == client.baseURL.absoluteString,
           now().timeIntervalSince(record.registeredAt) < 5 { // a parallel call just did it
            state = .registered(record.device)
            return
        }
        state = .registering
        do {
            let device = try await client.registerPushDevice(PushDeviceRegistration(
                token: token, platform: identity.platform, environment: identity.environment,
                appBundleId: identity.appBundleId, label: identity.label))
            saveRecord(PushRegistrationRecord(accountId: accountId, serverURL: client.baseURL.absoluteString, token: token, device: device, registeredAt: now()))
            state = .registered(device)
        } catch let failure as TimetrackError {
            if failure == .cancelled { state = .idle; return }
            switch (failure.status, failure.knownCode) {
            case (501?, _), (_, .pushUnavailable?): state = .unavailable
            case (409?, .tooManyPushDevices?): state = .limitReached
            default: state = .failed(failure)
            }
        } catch {
            state = .failed(.cancelled)
        }
    }

    /// Deletes this device's row (sign-out, switching accounts). A row that is already gone (404) counts as done.
    /// Returns false when the server could not be reached; the local record is dropped either way (the session ends right after).
    @discardableResult
    public func unregister() async -> Bool {
        await inFlight?.value
        guard let record = loadRecord(), record.accountId == accountId else {
            state = .idle
            return true
        }
        defer { clearRecord(); state = .idle; testState = .idle }
        do {
            try await client.deletePushDevice(id: record.device.id)
            return true
        } catch let failure as TimetrackError {
            return failure.status == 404
        } catch {
            return false
        }
    }

    // MARK: - Test

    /// `POST /me/push-devices/{id}/test`: one generic notification to this device.
    public func sendTest() async {
        guard let device, testState != .sending else { return }
        testState = .sending
        do {
            try await client.sendTestPush(deviceId: device.id)
            testState = .sent
        } catch let failure as TimetrackError {
            switch (failure.status, failure.knownCode) {
            case (404?, _): // the server dropped the device (410 from APNs): register again next time
                clearRecord()
                state = .idle
                testState = .failed(failure)
                await register(force: true)
            case (501?, _), (_, .pushUnavailable?):
                state = .unavailable
                testState = .idle
            default:
                testState = .failed(failure)
            }
        } catch {
            testState = .failed(.cancelled)
        }
    }

    public func clearTestResult() { testState = .idle }

    // MARK: - Persistence

    private func loadRecord() -> PushRegistrationRecord? {
        guard let data = defaults.data(forKey: Self.recordKey) else { return nil }
        return try? JSONCoding.makeDecoder().decode(PushRegistrationRecord.self, from: data)
    }

    private func saveRecord(_ record: PushRegistrationRecord) {
        if let data = try? JSONCoding.makeEncoder().encode(record) { defaults.set(data, forKey: Self.recordKey) }
    }

    private func clearRecord() { defaults.removeObject(forKey: Self.recordKey) }
}
