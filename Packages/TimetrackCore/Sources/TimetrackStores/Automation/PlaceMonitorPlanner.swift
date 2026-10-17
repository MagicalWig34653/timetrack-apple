import Foundation
import TimetrackCore

public struct GeoPoint: Codable, Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres (haversine); precise enough for geofences.
    public func distance(to other: GeoPoint) -> Double {
        let radius = 6_371_000.0
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// A place with usable geofence data, as cached for background launches (no network needed to know the places).
public struct AutomationPlace: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var center: GeoPoint
    /// Radius as saved on the server.
    public var savedRadius: Int
    public var mode: AutomationMode
    public var confirmAfterSeconds: Int

    public init(id: UUID, name: String, center: GeoPoint, savedRadius: Int, mode: AutomationMode, confirmAfterSeconds: Int = 300) {
        self.id = id
        self.name = name
        self.center = center
        self.savedRadius = savedRadius
        self.mode = mode
        self.confirmAfterSeconds = confirmAfterSeconds
    }

    /// iOS cannot reliably detect geofences smaller than about 100 m, so the monitored radius is never below that.
    public var monitoringRadius: Int { max(savedRadius, PlaceMonitorPlanner.minimumRadius) }
    public var hasTooSmallRadius: Bool { savedRadius < PlaceMonitorPlanner.minimumRadius }

    /// Places without coordinates are skipped. Archived places are dropped; a missing radius counts as the minimum.
    public init?(_ place: Place) {
        guard !place.archived, let latitude = place.latitude, let longitude = place.longitude,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.init(id: place.id, name: place.name, center: GeoPoint(latitude: latitude, longitude: longitude),
                  savedRadius: place.radiusMeters ?? PlaceMonitorPlanner.minimumRadius, mode: AutomationMode(raw: place.automationMode),
                  confirmAfterSeconds: place.confirmAfterSeconds ?? 300)
    }
}

public struct MonitorPlan: Sendable, Equatable {
    /// At most `limit` places, nearest first. Only places whose automation is on.
    public var monitored: [AutomationPlace]
    /// Active places that did not fit under the system limit (monitored again after the device moved).
    public var omitted: [AutomationPlace]
    /// Monitored places whose saved radius is below the minimum (monitored with the minimum).
    public var smallRadius: [AutomationPlace]
}

/// Chooses which places the system geofences watch. iOS allows 20 regions per app; with more active places the nearest 20
/// are monitored and the choice is renewed when a significant location change reports that the device moved.
public enum PlaceMonitorPlanner {
    public static let regionLimit = 20
    public static let minimumRadius = 100

    public static func plan(places: [AutomationPlace], near location: GeoPoint?, limit: Int = regionLimit) -> MonitorPlan {
        let active = places.filter { $0.mode != .off }
        let ordered: [AutomationPlace]
        if let location {
            ordered = active.sorted { lhs, rhs in
                let (l, r) = (lhs.center.distance(to: location), rhs.center.distance(to: location))
                return l == r ? lhs.name < rhs.name : l < r
            }
        } else {
            // Without a position: direct places first (a missed booking matters more than a missed suggestion), then by name.
            ordered = active.sorted { lhs, rhs in
                let (l, r) = (lhs.mode == .direct ? 0 : 1, rhs.mode == .direct ? 0 : 1)
                return l == r ? lhs.name < rhs.name : l < r
            }
        }
        let monitored = Array(ordered.prefix(max(0, limit)))
        return MonitorPlan(monitored: monitored, omitted: Array(ordered.dropFirst(max(0, limit))), smallRadius: monitored.filter(\.hasTooSmallRadius))
    }
}
