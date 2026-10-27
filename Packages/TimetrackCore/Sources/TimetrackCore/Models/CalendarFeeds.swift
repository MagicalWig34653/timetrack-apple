import Foundation

// N2 (contract 0.31.0): ICS calendar subscription feeds (`/me/calendar-feeds`, public `/ics/<token>.ics`).

public enum CalendarFeedContent: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case absences, holidays, plan, tracked
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .absences: "Abwesenheiten"
        case .holidays: "Feiertage"
        case .plan: "Geplante Arbeitszeit"
        case .tracked: "Gebuchte Arbeitszeit"
        }
    }

    public var detail: String {
        switch self {
        case .absences: "Urlaub, Krank und weitere Abwesenheiten"
        case .holidays: "Gesetzliche Feiertage deines Bundeslands"
        case .plan: "Plantage als Termine"
        case .tracked: "Tatsächlich gebuchte Arbeitstage"
        }
    }
}

public struct CalendarFeed: Decodable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let label: String
    /// Raw strings so a newer server's additional contents survive decoding.
    public let include: [String]
    public let createdAt: Date
    public let expiresAt: Date?
    public let lastUsedAt: Date?
    /// Only in the answer of the creating POST: the secret (never listed again).
    public let token: String?
    /// Only in the answer of the creating POST: `/ics/<token>.ics`.
    public let path: String?

    public init(id: UUID, label: String, include: [String], createdAt: Date, expiresAt: Date? = nil, lastUsedAt: Date? = nil, token: String? = nil, path: String? = nil) {
        self.id = id
        self.label = label
        self.include = include
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.lastUsedAt = lastUsedAt
        self.token = token
        self.path = path
    }

    public var contents: [CalendarFeedContent] { include.compactMap(CalendarFeedContent.init(rawValue:)) }

    /// "Abwesenheiten, Feiertage" for the list row.
    public var contentSummary: String { contents.map(\.title).joined(separator: ", ") }
}

/// Body of `POST /me/calendar-feeds`.
public struct CalendarFeedInput: Encodable, Sendable, Equatable {
    public let label: String
    public let include: [CalendarFeedContent]
    public let expiresInDays: Int?

    public init(label: String, include: [CalendarFeedContent], expiresInDays: Int? = nil) {
        self.label = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        self.include = include
        self.expiresInDays = expiresInDays
    }
}

/// The one-time link of a freshly created feed.
public struct CalendarFeedLink: Sendable, Equatable {
    public let https: URL
    /// `webcal://` variant: opens the system calendar's subscribe dialog.
    public let webcal: URL

    /// `path` is `/ics/<token>.ics` (relative to the server root); a server installed below a path prefix keeps it.
    public init?(baseURL: URL, path: String) {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false), path.hasPrefix("/ics/") else { return nil }
        let prefix = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = prefix + path
        components.query = nil
        components.fragment = nil
        guard let https = components.url else { return nil }
        components.scheme = "webcal"
        guard let webcal = components.url else { return nil }
        self.https = https
        self.webcal = webcal
    }
}
