import Foundation

public enum AbsenceKind: String, Codable, Sendable, Hashable {
    case vacation, sick, excused, other, unknown

    public init(from decoder: Decoder) throws {
        self = AbsenceKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public enum AbsenceStatus: String, Codable, Sendable, Hashable {
    case planned, requested, approved, rejected, cancelled, taken, unknown

    public init(from decoder: Decoder) throws {
        self = AbsenceStatus(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public enum DocumentStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case notNeeded = "not_needed", pending, submitted, unknown

    public init(from decoder: Decoder) throws {
        self = DocumentStatus(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// `Absence` (contract v0.10.3). Counted half days are computed by the backend (work days only, no holidays).
public struct Absence: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let version: Int
    public let kind: AbsenceKind
    public let startDate: LocalDay
    public let endDate: LocalDay
    public let halfDayStart: Bool?
    public let halfDayEnd: Bool?
    public let status: AbsenceStatus
    public let note: String?
    public let countedHalfDays: Int
    public let documentStatus: DocumentStatus?
    public let documentSubmittedOn: LocalDay?
    public let documentReferenceStart: LocalDay?
    public let documentReferenceEnd: LocalDay?

    public init(id: UUID, version: Int = 1, kind: AbsenceKind, startDate: LocalDay, endDate: LocalDay, halfDayStart: Bool? = nil,
                halfDayEnd: Bool? = nil, status: AbsenceStatus, note: String? = nil, countedHalfDays: Int,
                documentStatus: DocumentStatus? = nil, documentSubmittedOn: LocalDay? = nil,
                documentReferenceStart: LocalDay? = nil, documentReferenceEnd: LocalDay? = nil) {
        self.documentStatus = documentStatus
        self.documentSubmittedOn = documentSubmittedOn
        self.documentReferenceStart = documentReferenceStart
        self.documentReferenceEnd = documentReferenceEnd
        self.id = id
        self.version = version
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.halfDayStart = halfDayStart
        self.halfDayEnd = halfDayEnd
        self.status = status
        self.note = note
        self.countedHalfDays = countedHalfDays
    }
}

/// `GET /vacation/balance`; all amounts are half days (30 days = 60).
public struct VacationBalance: Codable, Sendable, Hashable {
    public let year: Int
    public let snapshotDate: LocalDay?
    public let snapshotRemainingHalfDays: Int?
    public let entitlementHalfDays: Int
    public let carryOverHalfDays: Int
    public let adjustmentHalfDays: Int
    public let bookedHalfDays: Int
    public let plannedHalfDays: Int
    public let availableHalfDays: Int
    public let availableAfterPlannedHalfDays: Int

    public init(year: Int, snapshotDate: LocalDay? = nil, snapshotRemainingHalfDays: Int? = nil, entitlementHalfDays: Int, carryOverHalfDays: Int = 0,
                adjustmentHalfDays: Int = 0, bookedHalfDays: Int = 0, plannedHalfDays: Int = 0, availableHalfDays: Int, availableAfterPlannedHalfDays: Int) {
        self.year = year
        self.snapshotDate = snapshotDate
        self.snapshotRemainingHalfDays = snapshotRemainingHalfDays
        self.entitlementHalfDays = entitlementHalfDays
        self.carryOverHalfDays = carryOverHalfDays
        self.adjustmentHalfDays = adjustmentHalfDays
        self.bookedHalfDays = bookedHalfDays
        self.plannedHalfDays = plannedHalfDays
        self.availableHalfDays = availableHalfDays
        self.availableAfterPlannedHalfDays = availableAfterPlannedHalfDays
    }
}

public enum HalfDayFormat {
    /// Half days as days with a German decimal comma: 61 -> "30,5", 60 -> "30", -1 -> "-0,5".
    public static func days(_ halfDays: Int) -> String {
        let whole = abs(halfDays) / 2
        let text = abs(halfDays) % 2 == 0 ? "\(whole)" : "\(whole),5"
        return halfDays < 0 ? "-" + text : text
    }
}

extension HalfDayFormat {
    /// Parses user input such as "12", "12,5" or "-0.5" into half days; nil when the value is not a whole or half number.
    public static func parseHalfDays(_ text: String) -> Int? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite, abs(value) < 10_000 else { return nil }
        let doubled = value * 2
        guard doubled == doubled.rounded() else { return nil }
        return Int(doubled)
    }
}

/// Request body of `POST /absences` and `PUT /absences/{id}` (contract `AbsenceInput`). Nullable fields are sent as explicit `null`.
public struct AbsenceInput: Encodable, Sendable, Hashable {
    public var kind: AbsenceKind
    public var startDate: LocalDay
    public var endDate: LocalDay
    public var halfDayStart: Bool
    public var halfDayEnd: Bool
    public var status: AbsenceStatus
    public var note: String?
    public var documentStatus: DocumentStatus
    public var documentSubmittedOn: LocalDay?
    public var documentReferenceStart: LocalDay?
    public var documentReferenceEnd: LocalDay?

    public init(kind: AbsenceKind, startDate: LocalDay, endDate: LocalDay, halfDayStart: Bool = false, halfDayEnd: Bool = false,
                status: AbsenceStatus, note: String? = nil, documentStatus: DocumentStatus = .notNeeded, documentSubmittedOn: LocalDay? = nil,
                documentReferenceStart: LocalDay? = nil, documentReferenceEnd: LocalDay? = nil) {
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.halfDayStart = halfDayStart
        self.halfDayEnd = halfDayEnd
        self.status = status
        self.note = note
        self.documentStatus = documentStatus
        self.documentSubmittedOn = documentSubmittedOn
        self.documentReferenceStart = documentReferenceStart
        self.documentReferenceEnd = documentReferenceEnd
    }

    public init(_ absence: Absence) {
        self.init(kind: absence.kind, startDate: absence.startDate, endDate: absence.endDate, halfDayStart: absence.halfDayStart ?? false,
                  halfDayEnd: absence.halfDayEnd ?? false, status: absence.status, note: absence.note,
                  documentStatus: absence.documentStatus ?? .notNeeded, documentSubmittedOn: absence.documentSubmittedOn,
                  documentReferenceStart: absence.documentReferenceStart, documentReferenceEnd: absence.documentReferenceEnd)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, startDate, endDate, halfDayStart, halfDayEnd, status, note
        case documentStatus, documentSubmittedOn, documentReferenceStart, documentReferenceEnd
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encode(halfDayStart, forKey: .halfDayStart)
        try c.encode(halfDayEnd, forKey: .halfDayEnd)
        try c.encode(status, forKey: .status)
        try c.encode(note, forKey: .note)
        try c.encode(documentStatus, forKey: .documentStatus)
        try c.encode(documentSubmittedOn, forKey: .documentSubmittedOn)
        try c.encode(documentReferenceStart, forKey: .documentReferenceStart)
        try c.encode(documentReferenceEnd, forKey: .documentReferenceEnd)
    }
}


/// `GET/PUT /vacation/settings`. `configured` is read-only (false while the server still reports defaults).
public struct VacationSettings: Codable, Sendable, Hashable {
    public var configured: Bool?
    public var region: String
    public var annualEntitlementHalfDays: Int
    public var carryOverByYear: [String: Int]?
    /// `MM-DD` or nil.
    public var carryOverExpiry: String?

    public init(configured: Bool? = nil, region: String = "DE-ST", annualEntitlementHalfDays: Int = 60, carryOverByYear: [String: Int]? = nil, carryOverExpiry: String? = nil) {
        self.configured = configured
        self.region = region
        self.annualEntitlementHalfDays = annualEntitlementHalfDays
        self.carryOverByYear = carryOverByYear
        self.carryOverExpiry = carryOverExpiry
    }

    private enum CodingKeys: String, CodingKey { case configured, region, annualEntitlementHalfDays, carryOverByYear, carryOverExpiry }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(region, forKey: .region)
        try c.encode(annualEntitlementHalfDays, forKey: .annualEntitlementHalfDays)
        try c.encodeIfPresent(carryOverByYear, forKey: .carryOverByYear)
        try c.encode(carryOverExpiry, forKey: .carryOverExpiry)
    }
}

public struct VacationSnapshotEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let date: LocalDay
    public let remainingHalfDays: Int
}

public struct VacationAdjustmentEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let date: LocalDay
    public let halfDays: Int
    public let reason: String
}

/// `GET /vacation/entries`: manually entered cut-off balances and corrections.
public struct VacationEntries: Codable, Sendable, Hashable {
    public let snapshots: [VacationSnapshotEntry]
    public let adjustments: [VacationAdjustmentEntry]
    public init(snapshots: [VacationSnapshotEntry] = [], adjustments: [VacationAdjustmentEntry] = []) {
        self.snapshots = snapshots
        self.adjustments = adjustments
    }
}

public enum CalendarDayKind: String, Codable, Sendable, Hashable {
    case holiday, schoolHoliday = "school_holiday", unknown

    public init(from decoder: Decoder) throws {
        self = CalendarDayKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public enum CalendarDaySource: String, Codable, Sendable, Hashable {
    case builtin, custom, unknown

    public init(from decoder: Decoder) throws {
        self = CalendarDaySource(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// Holiday or school-holiday range (`GET /calendar/holidays`); `source == .custom` entries have an `id` and can be deleted.
public struct CalendarDay: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID?
    public let startDate: LocalDay
    public let endDate: LocalDay
    public let name: String
    public let kind: CalendarDayKind
    public let source: CalendarDaySource

    public var identity: String { id?.uuidString ?? "\(source.rawValue)-\(kind.rawValue)-\(startDate)-\(name)" }

    public init(id: UUID? = nil, startDate: LocalDay, endDate: LocalDay, name: String, kind: CalendarDayKind, source: CalendarDaySource) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.name = name
        self.kind = kind
        self.source = source
    }

    public func covers(_ day: LocalDay) -> Bool { startDate <= day && day <= endDate }
}

public enum PlanMode: String, Codable, Sendable, Hashable, CaseIterable {
    case office, home, customer, school, off, unknown

    public init(from decoder: Decoder) throws {
        self = PlanMode(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    public static let selectable: [PlanMode] = [.office, .home, .customer, .school, .off]
}

public struct PlanDayInput: Encodable, Sendable, Hashable {
    public var mode: PlanMode
    public var placeId: UUID?
    public var note: String?
    /// Planned local wall-clock times `HH:mm` (contract v0.17.0): both or none, start before end. `PUT` replaces the whole day,
    /// so callers that only change mode or note must pass the stored times along.
    public var plannedStart: String?
    public var plannedEnd: String?
    public var plannedBreakMinutes: Int?

    public init(mode: PlanMode, placeId: UUID? = nil, note: String? = nil, plannedStart: String? = nil, plannedEnd: String? = nil, plannedBreakMinutes: Int? = nil) {
        self.mode = mode
        self.placeId = placeId
        self.note = note
        self.plannedStart = plannedStart
        self.plannedEnd = plannedEnd
        self.plannedBreakMinutes = plannedBreakMinutes
    }

    /// Input that keeps everything of `plan` (used when only mode or note change).
    public init(keeping plan: PlanDay, mode: PlanMode? = nil, note: String?? = nil) {
        self.init(mode: mode ?? plan.mode, placeId: plan.placeId, note: note ?? plan.note, plannedStart: plan.plannedStart,
                  plannedEnd: plan.plannedEnd, plannedBreakMinutes: plan.plannedBreakMinutes)
    }

    private enum CodingKeys: String, CodingKey { case mode, placeId, note, plannedStart, plannedEnd, plannedBreakMinutes }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(placeId, forKey: .placeId)
        try c.encode(note, forKey: .note)
        try c.encode(plannedStart, forKey: .plannedStart)
        try c.encode(plannedEnd, forKey: .plannedEnd)
        try c.encode(plannedBreakMinutes, forKey: .plannedBreakMinutes)
    }
}

/// Planned way of working for one day (`GET /plan/days`). Planned is not worked: actual time is a separate object.
public struct PlanDay: Codable, Sendable, Hashable, Identifiable {
    public let date: LocalDay
    public let mode: PlanMode
    public let placeId: UUID?
    public let note: String?
    public let plannedStart: String?
    public let plannedEnd: String?
    public let plannedBreakMinutes: Int?
    /// Server-derived: end - start - break, never negative; nil without times.
    public let plannedSeconds: Int?
    public var id: LocalDay { date }

    public init(date: LocalDay, mode: PlanMode, placeId: UUID? = nil, note: String? = nil, plannedStart: String? = nil, plannedEnd: String? = nil,
                plannedBreakMinutes: Int? = nil, plannedSeconds: Int? = nil) {
        self.date = date
        self.mode = mode
        self.placeId = placeId
        self.note = note
        self.plannedStart = plannedStart
        self.plannedEnd = plannedEnd
        self.plannedBreakMinutes = plannedBreakMinutes
        self.plannedSeconds = plannedSeconds
    }
}

/// `POST /calendar/custom-days` body.
public struct CustomDayInput: Encodable, Sendable, Hashable {
    public var kind: CalendarDayKind
    public var startDate: LocalDay
    public var endDate: LocalDay
    public var name: String

    public init(kind: CalendarDayKind, startDate: LocalDay, endDate: LocalDay, name: String) {
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.name = name
    }
}
