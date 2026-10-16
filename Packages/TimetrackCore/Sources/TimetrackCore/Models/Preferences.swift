import Foundation

/// Accent preset ids of the contract (`GET /me/preferences`). The ids are names; every platform picks its own hues.
public enum AccentPreset: String, CaseIterable, Sendable, Codable {
    case blue, teal, violet, green, orange, pink, graphite, custom
}

/// Colour scheme ids of the contract.
public enum ColorSchemePreference: String, CaseIterable, Sendable, Codable {
    case system, light, dark
}

/// Account-level appearance (contract v0.14.0, ADR-0020). Unknown future fields are ignored; unknown future ids are kept
/// as raw strings and shown as the default (`blue` / `system`), but never written back by this client.
public struct Preferences: Codable, Sendable, Hashable {
    public var accent: String
    /// `#RRGGBB`, non-nil exactly when `accent == "custom"`.
    public var accentCustomHex: String?
    public var colorScheme: String
    /// Nil as long as the account never saved anything (the server then answers the defaults).
    public var updatedAt: Date?

    public static let defaultAccent = AccentPreset.blue.rawValue
    public static let defaultColorScheme = ColorSchemePreference.system.rawValue

    public init(accent: String = Preferences.defaultAccent, accentCustomHex: String? = nil,
                colorScheme: String = Preferences.defaultColorScheme, updatedAt: Date? = nil) {
        self.accent = accent
        self.accentCustomHex = accentCustomHex
        self.colorScheme = colorScheme
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case accent, accentCustomHex, colorScheme, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? Self.defaultAccent
        accentCustomHex = try c.decodeIfPresent(String.self, forKey: .accentCustomHex)
        colorScheme = try c.decodeIfPresent(String.self, forKey: .colorScheme) ?? Self.defaultColorScheme
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// Known preset, or `blue` for an unknown future id.
    public var accentPreset: AccentPreset { AccentPreset(rawValue: accent) ?? .blue }
    public var hasUnknownAccent: Bool { AccentPreset(rawValue: accent) == nil }
    public var scheme: ColorSchemePreference { ColorSchemePreference(rawValue: colorScheme) ?? .system }
    public var hasUnknownScheme: Bool { ColorSchemePreference(rawValue: colorScheme) == nil }

    /// Valid `#RRGGBB` custom colour in upper case, else nil.
    public var customHex: String? { accentCustomHex.flatMap(Preferences.normalizedHex) }

    /// Account that never saved anything.
    public var isUnset: Bool { updatedAt == nil }

    /// `#RRGGBB` (any case, optional missing `#` rejected) normalised to upper case; nil when malformed.
    public static func normalizedHex(_ text: String) -> String? {
        guard text.count == 7, text.hasPrefix("#") else { return nil }
        let digits = text.dropFirst()
        guard digits.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        return "#" + digits.uppercased()
    }
}

/// Merge-patch body for `PATCH /me/preferences`: only set keys are sent. The contract recommends always sending
/// `accent` and `colorScheme`, and `accentCustomHex` only together with `custom`.
public struct PreferencesPatch: Encodable, Sendable, Equatable {
    public enum CustomHex: Sendable, Equatable {
        case unchanged
        /// Sent as JSON `null`.
        case clear
        case set(String)
    }

    public var accent: String?
    public var colorScheme: String?
    public var customHex: CustomHex

    public init(accent: String? = nil, colorScheme: String? = nil, customHex: CustomHex = .unchanged) {
        self.accent = accent
        self.colorScheme = colorScheme
        self.customHex = customHex
    }

    private enum CodingKeys: String, CodingKey { case accent, accentCustomHex, colorScheme }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(accent, forKey: .accent)
        try c.encodeIfPresent(colorScheme, forKey: .colorScheme)
        switch customHex {
        case .unchanged: break
        case .clear: try c.encodeNil(forKey: .accentCustomHex)
        case .set(let hex): try c.encode(hex, forKey: .accentCustomHex)
        }
    }
}

/// What `AppearanceSync` needs from the API; `APIClient` conforms, tests use a fake.
public protocol PreferencesService: Sendable {
    func getPreferences() async throws -> Preferences
    func updatePreferences(_ patch: PreferencesPatch) async throws -> Preferences
}
