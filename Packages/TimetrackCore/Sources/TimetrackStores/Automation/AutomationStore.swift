import Foundation
import Observation
import TimetrackCore

/// Location permission as the settings page needs it (mapped from CoreLocation by the iOS layer).
public enum LocationPermission: String, Sendable, Hashable {
    case notDetermined, denied, restricted, whenInUse, always

    /// Region monitoring in the background needs "always".
    public var allowsBackgroundMonitoring: Bool { self == .always }
}

public struct LocationStatus: Sendable, Hashable {
    public var permission: LocationPermission = .notDetermined
    /// iOS "precise location" is off: region events become unreliable.
    public var reducedAccuracy = false
    public var servicesEnabled = true

    public init(permission: LocationPermission = .notDetermined, reducedAccuracy: Bool = false, servicesEnabled: Bool = true) {
        self.permission = permission
        self.reducedAccuracy = reducedAccuracy
        self.servicesEnabled = servicesEnabled
    }

    public var isReady: Bool { servicesEnabled && permission.allowsBackgroundMonitoring && !reducedAccuracy }
}

public enum AutomationSecretKey {
    public static let deviceToken = "automation-device-token"
    public static let deviceTokenId = "automation-device-token-id"
    public static let deviceId = "automation-device-id"
}

/// State of the "Standortautomatik" page: places and their modes (server), device token, settings and log (device).
@MainActor
@Observable
public final class AutomationStore {
    public private(set) var places: [Place] = []
    public private(set) var state = AutomationState()
    public private(set) var queuedCount = 0
    public private(set) var plan = MonitorPlan(monitored: [], omitted: [], smallRadius: [])
    public private(set) var tokenInfo: DeviceToken?
    public private(set) var hasLocalToken = false
    public private(set) var isLoading = false
    public private(set) var isBusy = false
    public var error: TimetrackError?
    public var status = LocationStatus()
    /// Reports user-initiated results (saved/failed) like the other stores.
    public var onOutcome: StoreOutcomeHandler?
    /// Fired after places, settings or the token changed: the platform layer re-plans the monitored regions.
    public var onConfigurationChanged: (() -> Void)?

    private let client: APIClient
    private let engine: AutomationEngine
    private let secrets: SecretStore
    private let deviceName: String

    public init(client: APIClient, engine: AutomationEngine, secrets: SecretStore, deviceName: String) {
        self.client = client
        self.engine = engine
        self.secrets = secrets
        self.deviceName = deviceName
        hasLocalToken = secrets.read(AutomationSecretKey.deviceToken) != nil
    }

    public var config: AutomationConfig { state.config }
    public var log: [AutomationLogEntry] { Array(state.log.suffix(20).reversed()) }
    public var activePlaceCount: Int { places.filter { AutomationMode(raw: $0.automationMode) != .off && !$0.archived }.count }

    public func place(id: UUID) -> Place? { places.first { $0.id == id } }

    public func mode(of place: Place) -> AutomationMode { AutomationMode(raw: place.automationMode) }

    /// Whether the place has coordinates (needed for any automation).
    public func canAutomate(_ place: Place) -> Bool { place.latitude != nil && place.longitude != nil }

    // MARK: - Loading

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            places = try await client.listPlaces().filter { !$0.archived }
            await engine.setPlaces(places)
            tokenInfo = await currentTokenInfo()
            if activePlaceCount > 0, !hasLocalToken, await engine.snapshot.config.enabled { await ensureDeviceToken() }
            await refreshFromEngine()
            onConfigurationChanged?()
            error = nil
        } catch let failure as TimetrackError {
            error = failure
            await refreshFromEngine()
        } catch {
            self.error = .cancelled
        }
    }

    public func refreshFromEngine() async {
        state = await engine.snapshot
        queuedCount = await engine.queuedCount
        plan = PlaceMonitorPlanner.plan(places: state.places, near: state.lastKnown)
    }

    private func currentTokenInfo() async -> DeviceToken? {
        guard let idText = secrets.read(AutomationSecretKey.deviceTokenId), let id = UUID(uuidString: idText) else { return nil }
        // A revoked or expired token disappears from the list; the stored secret is then useless.
        guard let tokens = try? await client.listDeviceTokens() else { return tokenInfo }
        if let match = tokens.first(where: { $0.id == id }) { return match }
        secrets.delete(AutomationSecretKey.deviceToken)
        secrets.delete(AutomationSecretKey.deviceTokenId)
        hasLocalToken = false
        return nil
    }

    // MARK: - Settings (device only)

    public func setEnabled(_ enabled: Bool) async {
        var config = state.config
        config.enabled = enabled
        await apply(config)
        if enabled { await ensureDeviceToken() }
    }

    public func setDwellMinutes(_ minutes: Int) async {
        var config = state.config
        config.dwellMinutes = minutes
        await apply(config)
    }

    public func setCooldownMinutes(_ minutes: Int) async {
        var config = state.config
        config.cooldownMinutes = minutes
        await apply(config)
    }

    private func apply(_ config: AutomationConfig) async {
        await engine.setConfig(config)
        await refreshFromEngine()
        onConfigurationChanged?()
    }

    // MARK: - Places (server)

    public func setMode(_ mode: AutomationMode, for place: Place) async {
        guard canAutomate(place) || mode == .off else {
            error = .api(status: 400, code: "bad_request", message: "Der Ort hat keine Koordinaten.")
            onOutcome?(.failed)
            return
        }
        await save { [client] in try await client.updatePlace(id: place.id, PlaceInput(place, mode: mode)) }
        if mode != .off { await ensureDeviceToken() }
    }

    public func createPlace(name: String, coordinate: GeoPoint, radius: Int, mode: AutomationMode, kind: String = "other") async {
        let input = PlaceInput(name: name, kind: kind, automationMode: mode, latitude: coordinate.latitude, longitude: coordinate.longitude,
                               radiusMeters: max(radius, 20), confirmAfterSeconds: 300)
        await save { [client] in try await client.createPlace(input) }
        if mode != .off { await ensureDeviceToken() }
    }

    private func save(_ operation: @Sendable () async throws -> Place) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let saved = try await operation()
            if let index = places.firstIndex(where: { $0.id == saved.id }) { places[index] = saved } else { places.append(saved) }
            await engine.setPlaces(places)
            await refreshFromEngine()
            onConfigurationChanged?()
            error = nil
            onOutcome?(.saved)
        } catch let failure as TimetrackError {
            error = failure
            onOutcome?(.failed)
        } catch {
            self.error = .cancelled
        }
    }

    // MARK: - Device token

    /// Creates the automation token once. The clear text goes straight into the Keychain and is never shown again.
    public func ensureDeviceToken() async {
        guard secrets.read(AutomationSecretKey.deviceToken) == nil else { return }
        await createToken()
    }

    public func recreateDeviceToken() async {
        if let idText = secrets.read(AutomationSecretKey.deviceTokenId), let id = UUID(uuidString: idText) { try? await client.revokeDeviceToken(id: id) }
        secrets.delete(AutomationSecretKey.deviceToken)
        secrets.delete(AutomationSecretKey.deviceTokenId)
        await createToken()
    }

    public func revokeDeviceToken() async {
        isBusy = true
        defer { isBusy = false }
        if let idText = secrets.read(AutomationSecretKey.deviceTokenId), let id = UUID(uuidString: idText) {
            do { try await client.revokeDeviceToken(id: id) } catch let failure as TimetrackError {
                if failure.status != 404 { error = failure; onOutcome?(.failed); return } // 404: already gone
            } catch { return }
        }
        secrets.delete(AutomationSecretKey.deviceToken)
        secrets.delete(AutomationSecretKey.deviceTokenId)
        hasLocalToken = false
        tokenInfo = nil
        onOutcome?(.saved)
    }

    private func createToken() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let created = try await client.createDeviceToken(name: "Timetrack App (\(deviceName))")
            guard let token = created.token else { throw TimetrackError.decoding("DeviceToken.token") }
            secrets.write(token, for: AutomationSecretKey.deviceToken)
            secrets.write(created.id.uuidString.lowercased(), for: AutomationSecretKey.deviceTokenId)
            hasLocalToken = true
            tokenInfo = created
            error = nil
            await engine.flush() // events queued while the token was missing
            await refreshFromEngine()
        } catch let failure as TimetrackError {
            error = failure
            onOutcome?(.failed)
        } catch {
            self.error = .cancelled
        }
    }

    public func syncNow() async {
        await engine.flush()
        await refreshFromEngine()
    }
}
