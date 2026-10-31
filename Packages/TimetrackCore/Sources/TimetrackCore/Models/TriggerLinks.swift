import Foundation

// AUD3-A (contract 0.26.0, ADR-0027): trigger links (`/me/trigger-links`, public `GET /t/<token>/<action>`).

public enum TriggerAction: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case start, stop, toggle
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .start: "Start"
        case .stop: "Stopp"
        case .toggle: "Umschalten"
        }
    }

    public var detail: String {
        switch self {
        case .start: "Startet einen Abschnitt, wenn keiner läuft."
        case .stop: "Beendet den laufenden Abschnitt."
        case .toggle: "Startet oder beendet je nach Zustand. Ein zweiter Aufruf innerhalb von 10 Sekunden gilt als Wiederholung."
        }
    }
}

public struct TriggerLink: Decodable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let label: String
    /// Raw strings so a newer server's additional actions survive decoding.
    public let actionNames: [String]
    public let placeId: UUID?
    public let kind: SegmentKind
    public let createdAt: Date
    public let expiresAt: Date?
    public let lastUsedAt: Date?
    public let lastAction: String?
    /// Only in the answer of the creating POST: the secret (never listed again).
    public let token: String?
    /// Only in the answer of the creating POST: `/t/<token>`.
    public let path: String?

    enum CodingKeys: String, CodingKey {
        case id, label, placeId, kind, createdAt, expiresAt, lastUsedAt, lastAction, token, path
        case actionNames = "actions"
    }

    public init(id: UUID, label: String, actionNames: [String], placeId: UUID? = nil, kind: SegmentKind = .work, createdAt: Date,
                expiresAt: Date? = nil, lastUsedAt: Date? = nil, lastAction: String? = nil, token: String? = nil, path: String? = nil) {
        self.id = id
        self.label = label
        self.actionNames = actionNames
        self.placeId = placeId
        self.kind = kind
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.lastUsedAt = lastUsedAt
        self.lastAction = lastAction
        self.token = token
        self.path = path
    }

    public var actions: [TriggerAction] { actionNames.compactMap(TriggerAction.init(rawValue:)) }

    /// "Start, Stopp" for the list row.
    public var actionSummary: String { actions.map(\.title).joined(separator: ", ") }

    /// German name of the last action, or nil when unknown.
    public var lastActionTitle: String? { lastAction.flatMap(TriggerAction.init(rawValue:))?.title }
}

/// Body of `POST /me/trigger-links`.
public struct TriggerLinkInput: Encodable, Sendable, Equatable {
    public let label: String
    public let actions: [TriggerAction]
    public let placeId: UUID?
    public let kind: SegmentKind
    public let expiresInDays: Int?

    /// Allowed range of `expiresInDays` in the contract.
    public static let expiryRange = 1...730

    public init(label: String, actions: [TriggerAction], placeId: UUID? = nil, kind: SegmentKind = .work, expiresInDays: Int? = nil) {
        self.label = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        // Contract order, no duplicates.
        self.actions = TriggerAction.allCases.filter(actions.contains)
        self.placeId = placeId
        self.kind = SegmentKind.selectable.contains(kind) ? kind : .work
        self.expiresInDays = expiresInDays
    }

    enum CodingKeys: String, CodingKey { case label, actions, placeId, kind, expiresInDays }

    /// Omits `placeId` and `expiresInDays` instead of sending null.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(actions, forKey: .actions)
        try container.encodeIfPresent(placeId, forKey: .placeId)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(expiresInDays, forKey: .expiresInDays)
    }
}

/// The one-time addresses of a freshly created trigger link (one per allowed action).
public struct TriggerLinkAddresses: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Identifiable {
        public let action: TriggerAction
        public let url: URL
        public var id: String { action.rawValue }
    }

    public let entries: [Entry]

    /// `path` is `/t/<token>` (relative to the server root); a server installed below a path prefix keeps it.
    public init?(baseURL: URL, path: String, actions: [TriggerAction]) {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false), path.hasPrefix("/t/"), !actions.isEmpty else { return nil }
        let prefix = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.query = nil
        components.fragment = nil
        var built: [Entry] = []
        for action in actions {
            components.path = prefix + path + "/" + action.rawValue
            guard let url = components.url else { return nil }
            built.append(Entry(action: action, url: url))
        }
        entries = built
    }
}
