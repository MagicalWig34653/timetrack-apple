import CoreLocation
import Foundation
import os
import TimetrackCore
import TimetrackStores

/// Thin CoreLocation layer. It owns the only `CLLocationManager` and never asks for continuous updates:
///
/// - region monitoring via `CLMonitor` (the system watches the geofences and wakes the app on enter/exit, also after termination),
/// - significant location changes and visits as low-power wake-ups (re-plan the nearest 20 regions, check a pending arrival),
/// - `requestLocation()` as a single, 100 m accurate fix when a pending arrival is checked.
///
/// `startUpdatingLocation` is never called and the `location` background mode is not enabled.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate, LocationFixProviding {
    /// Region identifier prefix, so foreign regions of this app (none today) are never touched.
    private nonisolated static let prefix = "tt.place."

    /// Counts and states only, never coordinates or place names (readable in Console.app during the on-device test).
    private nonisolated static let logger = Logger(subsystem: "de.linolaske.timetrack", category: "location")
    private let manager = CLLocationManager()
    private var oneShotWaiters: [CheckedContinuation<LocationFix?, Never>] = []
    private var oneShotTimeout: Task<Void, Never>?

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

    /// Applies a plan: exactly the planned places are monitored (`CLMonitor` circular conditions, iOS 17+), everything else stops.
    /// Without "Always" nothing is monitored. Call at every launch: the monitor must exist again to receive events after a relaunch.
    func apply(plan: MonitorPlan, enabled: Bool) {
        let allowed = enabled && manager.authorizationStatus == .authorizedAlways
        let wanted: [String: AutomationPlace] = allowed ? Dictionary(plan.monitored.map { (Self.prefix + $0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first }) : [:]
        Self.logger.info("apply: enabled=\(enabled) allowed=\(allowed) auth=\(self.manager.authorizationStatus.rawValue) planned=\(wanted.count)")
        pendingPlan = wanted
        if allowed {
            manager.startMonitoringSignificantLocationChanges()
            manager.startMonitoringVisits()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
            manager.stopMonitoringVisits()
        }
        if applyTask == nil {
            // Serialised: a second apply while one runs is picked up by the loop below.
            applyTask = Task { [weak self] in
                while let self, let target = self.takePendingPlan() { await self.sync(to: target) }
                self?.applyTask = nil
            }
        }
    }

    private var pendingPlan: [String: AutomationPlace]?
    private var applyTask: Task<Void, Never>?
    private var monitor: CLMonitor?
    private var eventTask: Task<Void, Never>?
    private var applied: [String: String] = [:]

    private func takePendingPlan() -> [String: AutomationPlace]? {
        defer { pendingPlan = nil }
        return pendingPlan
    }

    private func sync(to wanted: [String: AutomationPlace]) async {
        if monitor == nil {
            guard !wanted.isEmpty else { return }
            let created = await CLMonitor("TimetrackPlaces") // names must be alphanumeric: a dot crashes with "Monitor name is not valid"
            monitor = created
            eventTask = Task { [weak self] in
                do {
                    for try await event in await created.events { self?.handle(event) }
                } catch {
                    Self.logger.error("monitor events ended")
                }
            }
        }
        guard let monitor else { return }
        for identifier in await monitor.identifiers where identifier.hasPrefix(Self.prefix) {
            if let place = wanted[identifier], applied[identifier] == Self.geometryKey(place) { continue }
            await monitor.remove(identifier)
            applied[identifier] = nil
        }
        for (identifier, place) in wanted where applied[identifier] == nil {
            guard let point = place.center else { continue }
            let center = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            let radius = min(CLLocationDistance(place.monitoringRadius), 5000)
            await monitor.add(CLMonitor.CircularGeographicCondition(center: center, radius: radius), identifier: identifier, assuming: .unsatisfied)
            applied[identifier] = Self.geometryKey(place)
        }
        // Which regions contain the device now (used to end visits whose exit event was missed).
        var inside = Set<UUID>()
        var known = 0
        for identifier in wanted.keys {
            guard let record = await monitor.record(for: identifier), let id = Self.placeID(identifier) else { continue }
            known += 1
            if record.lastEvent.state == .satisfied { inside.insert(id) }
        }
        if known == wanted.count, known > 0 { onWake?(.inside(inside)) }
    }

    private static func geometryKey(_ place: AutomationPlace) -> String {
        "\(place.center?.latitude ?? 0),\(place.center?.longitude ?? 0),\(place.monitoringRadius)"
    }

    private func handle(_ event: CLMonitor.Event) {
        guard let id = Self.placeID(event.identifier) else { return }
        switch event.state {
        case .satisfied:
            Self.logger.info("region enter")
            onWake?(.enter(id, event.date))
        case .unsatisfied:
            Self.logger.info("region exit")
            onWake?(.exit(id, event.date))
        default: break
        }
        if event.conditionLimitExceeded { Self.logger.error("condition limit exceeded") }
    }

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




    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Self.logger.info("didUpdateLocations accuracy=\(last.horizontalAccuracy)")
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


    private nonisolated static func placeID(_ identifier: String) -> UUID? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
    }
}
