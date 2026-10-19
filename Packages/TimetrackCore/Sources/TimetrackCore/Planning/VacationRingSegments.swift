import Foundation

/// Shares of the vacation ring (V3): booked (approved or taken), planned (planned or requested) and free.
/// The capacity is what could be used in the year: booked days plus the days still available, so snapshots and expired carry-over stay consistent.
public struct VacationRingSegments: Sendable, Hashable {
    public let bookedHalfDays: Int
    public let plannedHalfDays: Int
    /// Free after planned days; negative when more is planned than available.
    public let freeAfterPlannedHalfDays: Int
    public let capacityHalfDays: Int

    public init(_ balance: VacationBalance) {
        bookedHalfDays = max(balance.bookedHalfDays, 0)
        plannedHalfDays = max(balance.plannedHalfDays, 0)
        freeAfterPlannedHalfDays = balance.availableAfterPlannedHalfDays
        capacityHalfDays = bookedHalfDays + max(balance.availableHalfDays, 0)
    }

    /// More days are planned than the capacity leaves free.
    public var isOverPlanned: Bool { freeAfterPlannedHalfDays < 0 }

    /// Booked share of the capacity, 0...1.
    public var bookedFraction: Double {
        guard capacityHalfDays > 0 else { return 0 }
        return min(Double(bookedHalfDays) / Double(capacityHalfDays), 1)
    }

    /// Planned share, clipped so booked and planned never exceed the full ring.
    public var plannedFraction: Double {
        guard capacityHalfDays > 0 else { return 0 }
        return min(Double(plannedHalfDays) / Double(capacityHalfDays), 1 - bookedFraction)
    }

    public var freeFraction: Double { max(1 - bookedFraction - plannedFraction, 0) }
}
