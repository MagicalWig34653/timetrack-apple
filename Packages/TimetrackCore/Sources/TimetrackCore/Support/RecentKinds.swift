import Foundation

/// M2: the kinds the user started most recently (menu bar quick start). Newest first, no duplicates, at most `limit` entries.
public struct RecentKinds: Sendable, Equatable {
    public static let limit = 3
    public private(set) var kinds: [SegmentKind]

    public init(_ kinds: [SegmentKind] = []) {
        var seen = Set<SegmentKind>()
        self.kinds = kinds.filter { SegmentKind.selectable.contains($0) && seen.insert($0).inserted }.prefix(Self.limit).map { $0 }
    }

    public init(rawValues: String) { self.init(rawValues.split(separator: ",").compactMap { SegmentKind(rawValue: String($0)) }) }

    public var rawValues: String { kinds.map(\.rawValue).joined(separator: ",") }

    public mutating func record(_ kind: SegmentKind) { self = RecentKinds([kind] + kinds) }

    /// The quick-start list: the recent kinds, filled up with the remaining kinds so it is never empty.
    public var quickStart: [SegmentKind] {
        let rest = SegmentKind.selectable.filter { !kinds.contains($0) }
        return Array((kinds + rest).prefix(Self.limit))
    }
}
