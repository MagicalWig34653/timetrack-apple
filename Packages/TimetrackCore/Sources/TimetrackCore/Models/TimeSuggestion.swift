import Foundation

/// An open time suggestion of the backend (`GET /time/suggestions`, contract `Suggestion`): "start" proposes an entry,
/// "end" proposes the missing end of a segment the automation started (Q1: the reason behind "n zu prüfen").
public struct TimeSuggestion: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case start, end, unknown

        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public let id: UUID
    public let type: Kind
    public let placeId: UUID?
    public let proposedStartedAt: Date?
    public let proposedEndedAt: Date?
    public let segmentId: UUID?
    public let createdAt: Date

    public init(id: UUID, type: Kind, placeId: UUID? = nil, proposedStartedAt: Date? = nil, proposedEndedAt: Date? = nil,
                segmentId: UUID? = nil, createdAt: Date = .now) {
        self.id = id
        self.type = type
        self.placeId = placeId
        self.proposedStartedAt = proposedStartedAt
        self.proposedEndedAt = proposedEndedAt
        self.segmentId = segmentId
        self.createdAt = createdAt
    }
}
