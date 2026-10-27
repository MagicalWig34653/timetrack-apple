import Foundation

// P14 (contract 0.33.0, ADR-0030): APNs device registration of the Apple apps.

public enum PushPlatform: String, Codable, Sendable, Hashable {
    case ios, macos, watchos
}

public enum PushEnvironment: String, Codable, Sendable, Hashable {
    case sandbox, production
}

/// Registered APNs device as the server lists it (the token itself is never returned).
public struct PushDeviceInfo: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let platform: String
    public let environment: String
    public let appBundleId: String
    public let label: String?
    public let createdAt: Date
    public let lastSuccessAt: Date?

    public init(id: UUID, platform: String, environment: String, appBundleId: String, label: String? = nil, createdAt: Date, lastSuccessAt: Date? = nil) {
        self.id = id
        self.platform = platform
        self.environment = environment
        self.appBundleId = appBundleId
        self.label = label
        self.createdAt = createdAt
        self.lastSuccessAt = lastSuccessAt
    }
}

/// Body of `POST /me/push-devices`.
public struct PushDeviceRegistration: Encodable, Sendable, Equatable {
    public let token: String
    public let platform: PushPlatform
    public let environment: PushEnvironment
    public let appBundleId: String
    public let label: String?

    public init(token: String, platform: PushPlatform, environment: PushEnvironment, appBundleId: String, label: String?) {
        self.token = token
        self.platform = platform
        self.environment = environment
        self.appBundleId = appBundleId
        self.label = label.map { String($0.prefix(100)) }
    }
}

/// What this build is: fixed per app target, handed to the registration store by the app.
public struct PushIdentity: Sendable, Equatable {
    public let platform: PushPlatform
    public let environment: PushEnvironment
    public let appBundleId: String
    public let label: String?

    public init(platform: PushPlatform, environment: PushEnvironment, appBundleId: String, label: String?) {
        self.platform = platform
        self.environment = environment
        self.appBundleId = appBundleId
        self.label = label
    }
}

public enum PushTokenFormat {
    /// APNs device token as lowercase hex (the server accepts 64 to 200 hex characters).
    public static func hex(_ token: Data) -> String { token.map { String(format: "%02x", $0) }.joined() }
}

/// Which APNs environment a build talks to. The signing profile decides (`aps-environment`); builds without a profile
/// (TestFlight/App Store strip it on iOS) are production, simulator and debug builds sandbox.
public enum PushEnvironmentResolver {
    /// `profile`: bytes of `embedded.mobileprovision` / `embedded.provisionprofile` (CMS-wrapped plist; the plist text is readable inside).
    public static func resolve(profile: Data?, fallbackIsSandbox: Bool) -> PushEnvironment {
        if let profile, let value = apsEnvironment(in: profile) { return value == "development" ? .sandbox : .production }
        return fallbackIsSandbox ? .sandbox : .production
    }

    static func apsEnvironment(in profile: Data) -> String? {
        let text = String(decoding: profile, as: UTF8.self)
        for key in ["aps-environment", "com.apple.developer.aps-environment"] {
            guard let range = text.range(of: "<key>\(key)</key>") else { continue }
            let rest = text[range.upperBound...].prefix(120)
            if let open = rest.range(of: "<string>"), let close = rest.range(of: "</string>"), open.upperBound <= close.lowerBound {
                let value = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if value == "development" || value == "production" { return value }
            }
        }
        return nil
    }
}
