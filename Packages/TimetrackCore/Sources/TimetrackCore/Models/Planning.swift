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

/// Read-only view of `Absence` (contract v0.10.3). Counted half days are computed by the backend (work days only, no holidays).
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

    public init(id: UUID, version: Int = 1, kind: AbsenceKind, startDate: LocalDay, endDate: LocalDay, halfDayStart: Bool? = nil,
                halfDayEnd: Bool? = nil, status: AbsenceStatus, note: String? = nil, countedHalfDays: Int) {
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
