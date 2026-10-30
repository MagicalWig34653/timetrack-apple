import Foundation

/// Filter and sort selection of the absence list (V3). Codable so the selection can be remembered between launches.
public struct AbsenceListOptions: Codable, Sendable, Hashable {
    public enum Sort: String, Codable, Sendable, CaseIterable, Hashable { case date, kind, status }

    public enum Attachment: String, Codable, Sendable, CaseIterable, Hashable { case any, with, without }

    public enum Period: Codable, Sendable, Hashable {
        case all
        /// Ends today or later.
        case upcoming
        /// Ended before today.
        case past
        /// Overlaps the range; a missing bound is open.
        case custom(from: LocalDay?, to: LocalDay?)
    }

    /// Empty = every kind.
    public var kinds: Set<AbsenceKind> = []
    /// Empty = every status.
    public var statuses: Set<AbsenceStatus> = []
    public var period: Period = .all
    public var attachment: Attachment = .any
    public var sort: Sort = .date
    public var ascending = true

    public init() {}

    /// Kinds the user can pick (the unknown value is never a filter choice).
    public static let kindChoices: [AbsenceKind] = [.vacation, .sick, .excused, .other]
    /// Statuses shown in the list (rejected and cancelled are hidden by the store).
    public static let statusChoices: [AbsenceStatus] = [.planned, .requested, .approved, .taken, .recorded]

    /// Number of active filters (sorting does not count).
    public var activeFilterCount: Int {
        (kinds.isEmpty ? 0 : 1) + (statuses.isEmpty ? 0 : 1) + (period == .all ? 0 : 1) + (attachment == .any ? 0 : 1)
    }

    public var hasFilters: Bool { activeFilterCount > 0 }

    /// Default order (by date, ascending); only then the list keeps its grouping into planned and booked.
    public var isDefaultSort: Bool { sort == .date && ascending }

    public var isDefault: Bool { self == AbsenceListOptions() }

    public func resettingFilters() -> AbsenceListOptions {
        var copy = AbsenceListOptions()
        copy.sort = sort
        copy.ascending = ascending
        return copy
    }

    public func matches(_ absence: Absence, today: LocalDay) -> Bool {
        if !kinds.isEmpty {
            let kind = absence.kind == .unknown ? AbsenceKind.other : absence.kind
            if !kinds.contains(kind) { return false }
        }
        if !statuses.isEmpty, !statuses.contains(absence.status) { return false }
        switch attachment {
        case .any: break
        case .with: if absence.attachmentCount == 0 { return false }
        case .without: if absence.attachmentCount > 0 { return false }
        }
        switch period {
        case .all: break
        case .upcoming: if absence.endDate < today { return false }
        case .past: if absence.endDate >= today { return false }
        case .custom(let from, let to):
            if let from, !from.isEmpty, absence.endDate < from { return false }
            if let to, !to.isEmpty, absence.startDate > to { return false }
        }
        return true
    }

    /// Filters and sorts; ties fall back to the start date and then the id so the order is stable.
    public func apply(to absences: [Absence], today: LocalDay) -> [Absence] {
        let filtered = absences.filter { matches($0, today: today) }
        return filtered.sorted { lhs, rhs in
            let order = compare(lhs, rhs)
            if order != .orderedSame { return ascending ? order == .orderedAscending : order == .orderedDescending }
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func compare(_ lhs: Absence, _ rhs: Absence) -> ComparisonResult {
        switch sort {
        case .date:
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate ? .orderedAscending : .orderedDescending }
            return .orderedSame
        case .kind: return Self.compare(Self.rank(lhs.kind), Self.rank(rhs.kind))
        case .status: return Self.compare(Self.rank(lhs.status), Self.rank(rhs.status))
        }
    }

    private static func compare(_ lhs: Int, _ rhs: Int) -> ComparisonResult {
        lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
    }

    private static func rank(_ kind: AbsenceKind) -> Int {
        switch kind {
        case .vacation: 0
        case .sick: 1
        case .excused: 2
        case .other, .unknown: 3
        }
    }

    /// Workflow order, not alphabetical: planned, requested, approved, taken.
    private static func rank(_ status: AbsenceStatus) -> Int {
        switch status {
        case .planned: 0
        case .requested: 1
        case .approved: 2
        case .taken: 3
        case .recorded: 3
        case .rejected: 4
        case .cancelled: 5
        case .unknown: 6
        }
    }

    // MARK: - Persistence

    public static let storageKey = "vacation.absenceListOptions.v1"

    public static func load(from defaults: UserDefaults, key: String = storageKey) -> AbsenceListOptions {
        guard let data = defaults.data(forKey: key), let options = try? JSONDecoder().decode(AbsenceListOptions.self, from: data) else { return AbsenceListOptions() }
        return options
    }

    public func save(to defaults: UserDefaults, key: String = Self.storageKey) {
        if isDefault {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: key)
        }
    }
}
