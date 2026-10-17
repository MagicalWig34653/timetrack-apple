import CoreLocation
import Foundation
import TimetrackCore
import TimetrackStores

/// Thin CoreLocation layer. It owns the only `CLLocationManager` and never asks for continuous updates:
///
/// - region monitoring (the system watches the geofences and wakes the app on enter/exit, also after termination),
/// - significant location changes and visits as low-power wake-ups (re-plan the nearest 20 regions, check a pending arrival),
/// - `requestLocation()` as a single, 100 m accurate fix when a pending arrival is checked.
///
/// `startUpdatingLocation` is never called and the `location` background mode is not enabled.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate, LocationFixProviding {
    /// Region identifier prefix, so foreign regions of this app (none today) are never touched.
    private nonisolated static let prefix = "tt.place."

    private let manager = CLLocationManager()
    private var oneShotWaiters: [CheckedContinuation<LocationFix?, Never>] = []
    private var oneShotTimeout: Task<Void, Never>?
    private var stateReports: [UUID: Bool] = [:]
    private var reconcileTask: Task<Void, Never>?

    /// Authorization or accuracy changed.
    var onStatusChange: ((LocationStatus) -> Void)?
    /// A wake-up the engine should evaluate (region callback, significant change, visit).
    var onWake: ((Wake) -> Void)?

    enum Wake {
        case enter(UUID, Date)
        case exit(UUID, Date)
        case moved(GeoPoint)
        case visit
        /// Which monitored regions contain the device right now (answer to `requestState`).
        case inside(Set<UUID>)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
    }

    // MARK: - Status and permission

    var status: LocationStatus {
        let permission: LocationPermission
        switch manager.authorizationStatus {
        case .notDetermined: permission = .notDetermined
        case .restricted: permission = .restricted
        case .denied: permission = .denied
        case .authorizedWhenInUse: permission = .whenInUse
        case .authorizedAlways: permission = .always
        @unknown default: permission = .denied
        }
        return LocationStatus(permission: permission, reducedAccuracy: manager.accuracyAuthorization == .reducedAccuracy,
                              servicesEnabled: true)
    }

    /// Step 1: "While using". iOS only offers the "Always" upgrade afterwards.
    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    /// Step 2: the upgrade to "Always" (the system asks once; later the user has to change it in Settings).
    func requestAlways() { manager.requestAlwaysAuthorization() }

    /// One-time precise location for this purpose; the reason text is `NSLocationTemporaryUsageDescriptionDictionary["AutomationVerification"]`.
    func requestPreciseOnce() async {
        try? await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "AutomationVerification")
        onStatusChange?(status)
    }

    // MARK: - Monitoring

    /// Applies a plan: exactly the planned places are monitored, everything else stops. Without "Always" nothing is monitored.
    func apply(plan: MonitorPlan, enabled: Bool) {
        let allowed = enabled && manager.authorizationStatus == .authorizedAlways && CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        let wanted: [String: AutomationPlace] = allowed ? Dictionary(plan.monitored.map { (Self.prefix + $0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first }) : [:]
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.prefix) && wanted[region.identifier] == nil {
            manager.stopMonitoring(for: region)
        }
        let current = Dictionary(manager.monitoredRegions.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for (identifier, place) in wanted {
            guard let point = place.center else { continue }
            let center = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            if let existing = current[identifier] as? CLCircularRegion,
               existing.radius == CLLocationDistance(place.monitoringRadius), existing.center.latitude == center.latitude, existing.center.longitude == center.longitude {
                continue
            }
            let region = CLCircularRegion(center: center, radius: min(CLLocationDistance(place.monitoringRadius), manager.maximumRegionMonitoringDistance), identifier: identifier)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
        if allowed {
            manager.startMonitoringSignificantLocationChanges()
            manager.startMonitoringVisits()
            // Initial state of every region (also tells which ones contain the device after a restart).
            stateReports = [:]
            for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.prefix) { manager.requestState(for: region) }
        } else {
            manager.stopMonitoringSignificantLocationChanges()
            manager.stopMonitoringVisits()
        }
    }

    var monitoredCount: Int { manager.monitoredRegions.filter { $0.identifier.hasPrefix(Self.prefix) }.count }

    // MARK: - One-shot fix

    nonisolated func currentFix() async -> LocationFix? { await oneShot() }

    private func oneShot() async -> LocationFix? {
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else { return nil }
        return await withCheckedContinuation { continuation in
            oneShotWaiters.append(continuation)
            if oneShotWaiters.count == 1 {
                manager.requestLocation()
                oneShotTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(25))
                    if !Task.isCancelled { self?.finishOneShot(nil) }
                }
            }
        }
    }

    private func finishOneShot(_ fix: LocationFix?) {
        oneShotTimeout?.cancel()
        let waiters = oneShotWaiters
        oneShotWaiters = []
        for waiter in waiters { waiter.resume(returning: fix) }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.onStatusChange?(self.status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let id = Self.placeID(region) else { return }
        let now = Date()
        Task { @MainActor in self.onWake?(.enter(id, now)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let id = Self.placeID(region) else { return }
        let now = Date()
        Task { @MainActor in self.onWake?(.exit(id, now)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard let id = Self.placeID(region) else { return }
        Task { @MainActor in self.collect(id, inside: state == .inside) }
    }

    /// Waits briefly for all `requestState` answers, then reports which places contain the device.
    private func collect(_ id: UUID, inside: Bool) {
        stateReports[id] = inside
        reconcileTask?.cancel()
        reconcileTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let insideIDs = Set(self.stateReports.filter(\.value).keys)
            // Only report once every monitored region answered; a partial answer would end visits wrongly.
            if self.stateReports.count >= self.monitoredCount { self.onWake?(.inside(insideIDs)) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let fix = LocationFix(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude, horizontalAccuracy: last.horizontalAccuracy,
                              speed: last.speed >= 0 ? last.speed : nil, timestamp: last.timestamp)
        Task { @MainActor in
            // The answer to our own one-shot request must not trigger another evaluation (that would request again).
            if !self.oneShotWaiters.isEmpty { self.finishOneShot(fix); return }
            self.onWake?(.moved(GeoPoint(latitude: fix.latitude, longitude: fix.longitude)))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // requestLocation answers failures here; the pending check then proceeds without a fix.
        Task { @MainActor in self.finishOneShot(nil) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in self.onWake?(.visit) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // Typically the 20-region limit or missing authorization; the settings page shows the plan and the permission state.
    }

    private nonisolated static func placeID(_ region: CLRegion) -> UUID? {
        guard region.identifier.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(region.identifier.dropFirst(prefix.count)))
    }
}
