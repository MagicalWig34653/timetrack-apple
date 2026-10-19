import Foundation

/// Accent preset ids of the contract (`GET /me/preferences`, v0.21.0). The ids are names; every platform picks its own hues.
/// The order is the display order of the picker (as in the PWA), `custom` comes last.
public enum AccentPreset: String, CaseIterable, Sendable, Codable {
    case blue, teal, violet, green, orange, pink, graphite
    /// Contract v0.15.0.
    case indigo, navy, purple, magenta, crimson, forest, petrol, bronze
    /// Contract v0.21.0.
    case wine, slate, cocoa, olive, ocean, ink
    case custom

    /// Native hue of a preset (nil for `custom`). The six hues of the app icon keep their native values (teal, orange and pink differ
    /// slightly from the PWA, see docs/DESIGN-NATIVE.md); all later ids use the PWA values from the contract handoffs.
    public var nativeHex: UInt32? {
        switch self {
        case .blue: 0x2563EB
        case .teal: 0x0EA5A4
        case .violet: 0x7C3AED
        case .green: 0x16A34A
        case .orange: 0xF97316
        case .pink: 0xEC4899
        case .graphite: 0x52525B
        case .indigo: 0x4338CA
        case .navy: 0x1E3A8A
        case .purple: 0x7E22CE
        case .magenta: 0xA21CAF
        case .crimson: 0xB91C1C
        case .forest: 0x166534
        case .petrol: 0x0F766E
        case .bronze: 0x92400E
        case .wine: 0x7F1D3F
        case .slate: 0x475A8C
        case .cocoa: 0x5C4033
        case .olive: 0x4D6B1F
        case .ocean: 0x0E7490
        case .ink: 0x334155
        case .custom: nil
        }
    }

    /// Ids a server before contract v0.15.0 knows (`custom` included).
    public var isLegacy: Bool {
        switch self {
        case .blue, .teal, .violet, .green, .orange, .pink, .graphite, .custom: true
        default: false
        }
    }

    /// Ids a server before contract v0.21.0 rejects (the v0.15.0 and the v0.21.0 additions).
    public var needsV021: Bool {
        switch self {
        case .wine, .slate, .cocoa, .olive, .ocean, .ink: true
        default: false
        }
    }
}

/// Glow levels of the contract (`glow`, v0.15.0, ADR-0020): "Leuchteffekt".
public enum GlowPreference: String, CaseIterable, Sendable, Codable {
    case off, subtle, medium, strong
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
    /// Nil when the server predates contract v0.15.0 (no glow field); clients then keep their local value.
    public var glow: String?
    /// Nil as long as the account never saved anything (the server then answers the defaults).
    public var updatedAt: Date?

    public static let defaultAccent = AccentPreset.blue.rawValue
    public static let defaultColorScheme = ColorSchemePreference.system.rawValue
    public static let defaultGlow = GlowPreference.subtle.rawValue

    public init(accent: String = Preferences.defaultAccent, accentCustomHex: String? = nil,
                colorScheme: String = Preferences.defaultColorScheme, glow: String? = nil, updatedAt: Date? = nil) {
        self.accent = accent
        self.accentCustomHex = accentCustomHex
        self.colorScheme = colorScheme
        self.glow = glow
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case accent, accentCustomHex, colorScheme, glow, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? Self.defaultAccent
        accentCustomHex = try c.decodeIfPresent(String.self, forKey: .accentCustomHex)
        colorScheme = try c.decodeIfPresent(String.self, forKey: .colorScheme) ?? Self.defaultColorScheme
        glow = try? c.decodeIfPresent(String.self, forKey: .glow)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// Known preset, or `blue` for an unknown future id.
    public var accentPreset: AccentPreset { AccentPreset(rawValue: accent) ?? .blue }
    public var hasUnknownAccent: Bool { AccentPreset(rawValue: accent) == nil }
    public var scheme: ColorSchemePreference { ColorSchemePreference(rawValue: colorScheme) ?? .system }
    public var hasUnknownScheme: Bool { ColorSchemePreference(rawValue: colorScheme) == nil }
    /// Known glow level; unknown future ids and a missing field show as `subtle` (use `hasGlow` to tell the server's silence apart).
    public var glowLevel: GlowPreference { glow.flatMap(GlowPreference.init(rawValue:)) ?? .subtle }
    public var hasGlow: Bool { glow != nil }

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
    public var glow: String?
    public var customHex: CustomHex

    public init(accent: String? = nil, colorScheme: String? = nil, glow: String? = nil, customHex: CustomHex = .unchanged) {
        self.accent = accent
        self.colorScheme = colorScheme
        self.glow = glow
        self.customHex = customHex
    }

    private enum CodingKeys: String, CodingKey { case accent, accentCustomHex, colorScheme, glow }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(accent, forKey: .accent)
        try c.encodeIfPresent(colorScheme, forKey: .colorScheme)
        try c.encodeIfPresent(glow, forKey: .glow)
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
