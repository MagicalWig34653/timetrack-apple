import Foundation

/// Per-place automation switch (contract `PlaceInput.automationMode`).
public enum AutomationMode: String, Codable, Sendable, CaseIterable, Hashable {
    case off, suggest, direct

    public init(raw: String) { self = AutomationMode(rawValue: raw) ?? .off }
}

/// Body of `POST /places` and `PUT /places/{id}` (contract `PlaceInput`).
public struct PlaceInput: Codable, Sendable, Hashable {
    public var name: String
    public var kind: String
    public var automationMode: AutomationMode
    public var latitude: Double?
    public var longitude: Double?
    public var radiusMeters: Int?
    public var confirmAfterSeconds: Int?
    public var defaultSegmentKind: SegmentKind?

    public init(name: String, kind: String = "other", automationMode: AutomationMode = .off, latitude: Double? = nil, longitude: Double? = nil,
                radiusMeters: Int? = nil, confirmAfterSeconds: Int? = nil, defaultSegmentKind: SegmentKind? = nil) {
        self.name = name
        self.kind = kind
        self.automationMode = automationMode
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.confirmAfterSeconds = confirmAfterSeconds
        self.defaultSegmentKind = defaultSegmentKind
    }

    /// Copy of an existing place with another automation mode (PUT replaces the whole place, so every field is carried over).
    public init(_ place: Place, mode: AutomationMode) {
        self.init(name: place.name, kind: place.kind, automationMode: mode, latitude: place.latitude, longitude: place.longitude,
                  radiusMeters: place.radiusMeters, confirmAfterSeconds: place.confirmAfterSeconds, defaultSegmentKind: place.defaultSegmentKind)
    }

    // Optional fields are sent as explicit `null` only where the contract allows it; omitted keys keep the server default.
    enum CodingKeys: String, CodingKey { case name, kind, automationMode, latitude, longitude, radiusMeters, confirmAfterSeconds, defaultSegmentKind }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(automationMode, forKey: .automationMode)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(radiusMeters, forKey: .radiusMeters)
        try container.encodeIfPresent(confirmAfterSeconds, forKey: .confirmAfterSeconds)
        try container.encodeIfPresent(defaultSegmentKind, forKey: .defaultSegmentKind)
    }
}

/// `DeviceToken` (automation scope). The clear text `token` exists only in the creation answer.
public struct DeviceToken: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let expiresAt: Date?
    public let lastUsedAt: Date?
    /// Only present right after creation.
    public let token: String?

    public init(id: UUID, name: String, createdAt: Date, expiresAt: Date? = nil, lastUsedAt: Date? = nil, token: String? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.lastUsedAt = lastUsedAt
        self.token = token
    }
}

public enum AutomationEventType: String, Codable, Sendable, Hashable {
    case arrival
    case presenceConfirmed = "presence_confirmed"
    case departure
    case cancel
}

/// Body of `POST /automation/events`. Only ids and timestamps leave the device; coordinates are never sent.
public struct AutomationEventPayload: Codable, Sendable, Hashable {
    public let eventId: UUID
    public let deviceId: String
    public let placeId: UUID
    public let type: AutomationEventType
    public let occurredAt: Date

    public init(eventId: UUID, deviceId: String, placeId: UUID, type: AutomationEventType, occurredAt: Date) {
        self.eventId = eventId
        self.deviceId = deviceId
        self.placeId = placeId
        self.type = type
        self.occurredAt = occurredAt
    }
}

/// Server answer of `POST /automation/events`.
public struct AutomationEventResult: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case booked, suggested, ignored, recorded, duplicate
        case needsReview = "needs_review"
        case unknown

        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public let result: Kind
    public let segmentId: UUID?
    public let suggestionId: UUID?

    public init(result: Kind, segmentId: UUID? = nil, suggestionId: UUID? = nil) {
        self.result = result
        self.segmentId = segmentId
        self.suggestionId = suggestionId
    }
}
