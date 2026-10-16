import Foundation

public struct FixedBreak: Codable, Sendable, Hashable {
    /// `HH:mm` in the model's time zone.
    public let start: String
    public let end: String
}

public struct WorkModel: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let createdAt: Date?
    public let validFrom: LocalDay
    public let validTo: LocalDay?
    public let timezone: String?
    public let weeklyTargetSeconds: Int
    /// 1 = Monday ... 7 = Sunday.
    public let workdays: [Int]
    public let dailyTargetSeconds: [String: Int]?
    public let travelCountsAsWork: Bool?
    public let roundingEnabled: Bool?
    public let roundingMinutes: Int?
    public let fixedBreaks: [FixedBreak]?

    /// Zone used for local days; falls back to the contract default `Europe/Berlin`.
    public var timeZone: TimeZone {
        timezone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "Europe/Berlin") ?? .current
    }
}

extension Array where Element == WorkModel {
    /// The version in force today: the open-ended one, otherwise the latest.
    public func current() -> WorkModel? {
        sorted { $0.validFrom < $1.validFrom }.last { $0.validTo == nil } ?? sorted { $0.validFrom < $1.validFrom }.last
    }
}
