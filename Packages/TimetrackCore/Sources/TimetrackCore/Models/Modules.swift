import Foundation

/// Switchable module key (ADR-0012). A struct instead of an enum so unknown future keys still decode.
public struct ModuleKey: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let reports: ModuleKey = "reports"
    public static let planning: ModuleKey = "planning"
    public static let transfer: ModuleKey = "transfer"
    public static let automation: ModuleKey = "automation"
    public static let mcp: ModuleKey = "mcp"
    public static let all: [ModuleKey] = [.reports, .planning, .transfer, .automation, .mcp]
}

public struct ModuleStatus: Codable, Sendable, Hashable, Identifiable {
    public let key: ModuleKey
    public let serverEnabled: Bool
    public let accountEnabled: Bool
    public let effective: Bool
    public let lockedByOperator: Bool
    public var id: String { key.rawValue }

    public init(key: ModuleKey, serverEnabled: Bool = true, accountEnabled: Bool = true, effective: Bool = true, lockedByOperator: Bool = false) {
        self.key = key
        self.serverEnabled = serverEnabled
        self.accountEnabled = accountEnabled
        self.effective = effective
        self.lockedByOperator = lockedByOperator
    }
}

/// Which features are visible. Core features (time tracking, account) are always on; modules default to on until
/// the server says otherwise, because a failed module request must not hide the whole app.
public struct ModuleSwitches: Sendable, Hashable {
    private let effective: [ModuleKey: Bool]

    public init(_ statuses: [ModuleStatus] = []) {
        effective = Dictionary(statuses.map { ($0.key, $0.effective) }, uniquingKeysWith: { _, last in last })
    }

    public func isEnabled(_ key: ModuleKey) -> Bool { effective[key] ?? true }

    /// Unknown until loaded; used by UIs to avoid flashing features that are off.
    public var isEmpty: Bool { effective.isEmpty }
}
