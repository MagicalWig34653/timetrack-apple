import Foundation

/// What a plan share lets the recipient see (contract: `ShareScopes`). Nothing is shared unless a scope is on.
public struct ShareScopes: Codable, Sendable, Hashable {
    public var plan: Bool
    public var actual: Bool
    public var vacation: Bool

    public init(plan: Bool = false, actual: Bool = false, vacation: Bool = false) {
        self.plan = plan
        self.actual = actual
        self.vacation = vacation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decodeIfPresent(Bool.self, forKey: .plan) ?? false
        actual = try c.decodeIfPresent(Bool.self, forKey: .actual) ?? false
        vacation = try c.decodeIfPresent(Bool.self, forKey: .vacation) ?? false
    }

    public var isEmpty: Bool { !plan && !actual && !vacation }

    public enum Scope: String, CaseIterable, Sendable, Hashable { case plan, actual, vacation }

    public subscript(scope: Scope) -> Bool {
        get {
            switch scope {
            case .plan: plan
            case .actual: actual
            case .vacation: vacation
            }
        }
        set {
            switch scope {
            case .plan: plan = newValue
            case .actual: actual = newValue
            case .vacation: vacation = newValue
            }
        }
    }

    /// The enabled scopes in the fixed order plan, actual, vacation.
    public var enabled: [Scope] { Scope.allCases.filter { self[$0] } }
}

/// An outgoing share (`GET /shares`).
public struct Share: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let recipientHandle: String
    public var scopes: ShareScopes
    public let createdAt: Date
}

/// A share another account gave to this one (`GET /shares/incoming`).
public struct IncomingShare: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let ownerDisplayName: String
    public let scopes: ShareScopes
}

public struct ShareCreateInput: Encodable, Sendable, Hashable {
    public var recipientHandle: String
    public var scopes: ShareScopes

    public init(recipientHandle: String, scopes: ShareScopes) {
        self.recipientHandle = recipientHandle
        self.scopes = scopes
    }
}

struct ShareScopesInput: Encodable { let scopes: ShareScopes }

/// What the server releases to the recipient for a range (`GET /shares/incoming/{id}/view`). Scopes that are not shared are `nil`.
public struct SharedView: Codable, Sendable, Hashable {
    public struct PlanDay: Codable, Sendable, Hashable, Identifiable {
        public let date: LocalDay
        public let mode: PlanMode
        public let plannedStart: String?
        public let plannedEnd: String?
        public let plannedBreakMinutes: Int?
        public let plannedSeconds: Int?
        public var id: LocalDay { date }
    }

    public struct ActualDay: Codable, Sendable, Hashable, Identifiable {
        public let date: LocalDay
        public let evaluatedStart: Date?
        public let evaluatedEnd: Date?
        public let evaluatedWorkSeconds: Int
        public var id: LocalDay { date }
    }

    public struct VacationPeriod: Codable, Sendable, Hashable, Identifiable {
        public let startDate: LocalDay
        public let endDate: LocalDay
        public var id: String { startDate + "/" + endDate }
    }

    public let plan: [PlanDay]?
    public let actual: [ActualDay]?
    public let vacation: [VacationPeriod]?

    /// No scope is shared (or the range holds no scope at all).
    public var isEmpty: Bool { plan == nil && actual == nil && vacation == nil }
}
