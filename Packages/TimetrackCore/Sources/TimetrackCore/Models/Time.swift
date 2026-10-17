import Foundation

/// Decodes enums leniently: an unknown server value becomes `.unknown` instead of failing the whole payload.
public enum SegmentKind: String, Codable, Sendable, CaseIterable, Hashable {
    case work, travel, school, unknown

    public init(from decoder: Decoder) throws {
        self = SegmentKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    public static let selectable: [SegmentKind] = [.work, .travel, .school]
}

public enum SegmentSource: String, Codable, Sendable, Hashable {
    case timer, manual, automation, suggestion, `import`, unknown

    public init(from decoder: Decoder) throws {
        self = SegmentSource(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public enum DayMarkKind: String, Codable, Sendable, Hashable {
    case unmarked = "none", holiday, vacation, sick, excused
    case schoolCredit = "school_credit"
    case unknown

    public init(from decoder: Decoder) throws {
        self = DayMarkKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public struct Segment: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let kind: SegmentKind
    public let placeId: UUID?
    public let startedAt: Date
    public let endedAt: Date?
    public let rawStartedAt: Date
    public let rawEndedAt: Date?
    public let source: SegmentSource
    public let note: String?
    public let version: Int
    public let voided: Bool
    public let needsReview: Bool
    public let revisions: Int?

    public var isRunning: Bool { endedAt == nil && !voided }

    public init(id: UUID, kind: SegmentKind, placeId: UUID? = nil, startedAt: Date, endedAt: Date? = nil, rawStartedAt: Date? = nil,
                rawEndedAt: Date? = nil, source: SegmentSource = .manual, note: String? = nil, version: Int = 1,
                voided: Bool = false, needsReview: Bool = false, revisions: Int? = nil) {
        self.id = id
        self.kind = kind
        self.placeId = placeId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.rawStartedAt = rawStartedAt ?? startedAt
        self.rawEndedAt = rawEndedAt ?? endedAt
        self.source = source
        self.note = note
        self.version = version
        self.voided = voided
        self.needsReview = needsReview
        self.revisions = revisions
    }
}

public struct SegmentInput: Codable, Sendable, Hashable {
    public var kind: SegmentKind
    public var placeId: UUID?
    public var startedAt: Date
    public var endedAt: Date?
    public var note: String?

    public init(kind: SegmentKind, placeId: UUID? = nil, startedAt: Date, endedAt: Date? = nil, note: String? = nil) {
        self.kind = kind
        self.placeId = placeId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
    }
}

/// Correction with a mandatory reason; only fields that changed are sent. `If-Match` carries the segment version.
public struct SegmentCorrection: Codable, Sendable, Hashable {
    public var startedAt: Date?
    public var endedAt: Date?
    public var kind: SegmentKind?
    public var note: String?
    public var reason: String

    public init(startedAt: Date? = nil, endedAt: Date? = nil, kind: SegmentKind? = nil, note: String? = nil, reason: String) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.kind = kind
        self.note = note
        self.reason = reason
    }
}

public struct BreakHint: Codable, Sendable, Hashable {
    /// Contract codes: `break_missing_30`, `break_missing_45`, `break_part_too_short`, `work_over_6h_without_break`.
    public let code: String
}

/// Server-side evaluation of one local day. The client only displays it; rounding and break rules live in the backend.
public struct DayEvaluation: Codable, Sendable, Hashable, Identifiable {
    public let date: LocalDay
    public let modelId: UUID?
    public let mark: DayMarkKind?
    public let skipFixedBreaks: Bool?
    public let targetSeconds: Int
    public let rawWorkSeconds: Int
    public let breakDeductionSeconds: Int
    public let startAdjustSeconds: Int
    public let endAdjustSeconds: Int
    public let evaluatedWorkSeconds: Int
    public let creditSeconds: Int
    public let deltaSeconds: Int
    public let evaluatedStart: Date?
    public let evaluatedEnd: Date?
    public let provisional: Bool
    public let segmentIds: [UUID]
    public let segments: [Segment]?
    public let note: String?
    public let breakHints: [BreakHint]
    public var id: LocalDay { date }

    public init(date: LocalDay, targetSeconds: Int = 0, rawWorkSeconds: Int = 0, evaluatedWorkSeconds: Int = 0, creditSeconds: Int = 0,
                deltaSeconds: Int = 0, provisional: Bool = false, mark: DayMarkKind? = nil, segments: [Segment]? = nil,
                breakHints: [BreakHint] = []) {
        self.date = date
        self.modelId = nil
        self.mark = mark
        self.skipFixedBreaks = nil
        self.targetSeconds = targetSeconds
        self.rawWorkSeconds = rawWorkSeconds
        self.breakDeductionSeconds = 0
        self.startAdjustSeconds = 0
        self.endAdjustSeconds = 0
        self.evaluatedWorkSeconds = evaluatedWorkSeconds
        self.creditSeconds = creditSeconds
        self.deltaSeconds = deltaSeconds
        self.evaluatedStart = nil
        self.evaluatedEnd = nil
        self.provisional = provisional
        self.segmentIds = segments?.map(\.id) ?? []
        self.segments = segments
        self.note = nil
        self.breakHints = breakHints
    }

    /// Copy of `other` with a different segment list (used for optimistic local changes).
    public init(copying other: DayEvaluation, segments: [Segment]?) {
        self = other.replacingSegments(segments)
    }

    private func replacingSegments(_ segments: [Segment]?) -> DayEvaluation {
        DayEvaluation(date: date, modelId: modelId, mark: mark, skipFixedBreaks: skipFixedBreaks, targetSeconds: targetSeconds,
                      rawWorkSeconds: rawWorkSeconds, breakDeductionSeconds: breakDeductionSeconds, startAdjustSeconds: startAdjustSeconds,
                      endAdjustSeconds: endAdjustSeconds, evaluatedWorkSeconds: evaluatedWorkSeconds, creditSeconds: creditSeconds,
                      deltaSeconds: deltaSeconds, evaluatedStart: evaluatedStart, evaluatedEnd: evaluatedEnd, provisional: provisional,
                      segmentIds: segments?.map(\.id) ?? segmentIds, segments: segments, note: note, breakHints: breakHints)
    }

    private init(date: LocalDay, modelId: UUID?, mark: DayMarkKind?, skipFixedBreaks: Bool?, targetSeconds: Int, rawWorkSeconds: Int,
                 breakDeductionSeconds: Int, startAdjustSeconds: Int, endAdjustSeconds: Int, evaluatedWorkSeconds: Int, creditSeconds: Int,
                 deltaSeconds: Int, evaluatedStart: Date?, evaluatedEnd: Date?, provisional: Bool, segmentIds: [UUID], segments: [Segment]?,
                 note: String?, breakHints: [BreakHint]) {
        self.date = date; self.modelId = modelId; self.mark = mark; self.skipFixedBreaks = skipFixedBreaks; self.targetSeconds = targetSeconds
        self.rawWorkSeconds = rawWorkSeconds; self.breakDeductionSeconds = breakDeductionSeconds; self.startAdjustSeconds = startAdjustSeconds
        self.endAdjustSeconds = endAdjustSeconds; self.evaluatedWorkSeconds = evaluatedWorkSeconds; self.creditSeconds = creditSeconds
        self.deltaSeconds = deltaSeconds; self.evaluatedStart = evaluatedStart; self.evaluatedEnd = evaluatedEnd; self.provisional = provisional
        self.segmentIds = segmentIds; self.segments = segments; self.note = note; self.breakHints = breakHints
    }
}

public struct TimeAccount: Codable, Sendable, Hashable {
    public let asOf: LocalDay
    public let accountStart: LocalDay?
    public let balanceSeconds: Int
    public let openingSeconds: Int
    public let adjustmentSeconds: Int
    public let provisional: Bool

    public init(asOf: LocalDay, accountStart: LocalDay? = nil, balanceSeconds: Int, openingSeconds: Int = 0, adjustmentSeconds: Int = 0, provisional: Bool = false) {
        self.asOf = asOf
        self.accountStart = accountStart
        self.balanceSeconds = balanceSeconds
        self.openingSeconds = openingSeconds
        self.adjustmentSeconds = adjustmentSeconds
        self.provisional = provisional
    }
}

public struct Place: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let kind: String
    public let automationMode: String
    public let archived: Bool
    public let defaultSegmentKind: SegmentKind?
    /// L2: geofence data (all optional; a place without coordinates cannot be monitored).
    public let latitude: Double?
    public let longitude: Double?
    public let radiusMeters: Int?
    public let confirmAfterSeconds: Int?

    public init(id: UUID, name: String, kind: String = "other", automationMode: String = "off", archived: Bool = false,
                defaultSegmentKind: SegmentKind? = nil, latitude: Double? = nil, longitude: Double? = nil,
                radiusMeters: Int? = nil, confirmAfterSeconds: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.automationMode = automationMode
        self.archived = archived
        self.defaultSegmentKind = defaultSegmentKind
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.confirmAfterSeconds = confirmAfterSeconds
    }
}
