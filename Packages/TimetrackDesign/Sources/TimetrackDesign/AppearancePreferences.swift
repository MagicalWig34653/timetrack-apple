import SwiftUI
import TimetrackCore

/// In-app accent choices: the six hues of the app icon (`IconAccent`), a neutral graphite and a custom colour.
/// The choice is independent from the app icon (changing one never changes the other).
public enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case blue, teal, violet, green, orange, pink, graphite, custom

    public var id: String { rawValue }

    /// Fixed colour of a preset; nil for `.custom`. Hues equal `IconAccent.strongHex` in the iOS target.
    public var presetHex: UInt32? {
        switch self {
        case .blue: 0x2563EB
        case .teal: 0x0EA5A4
        case .violet: 0x7C3AED
        case .green: 0x16A34A
        case .orange: 0xF97316
        case .pink: 0xEC4899
        case .graphite: 0x52525B
        case .custom: nil
        }
    }

    /// Keys live in each app's string catalog.
    public var titleKey: LocalizedStringKey {
        switch self {
        case .blue: "appearance.accent.blue"
        case .teal: "appearance.accent.teal"
        case .violet: "appearance.accent.violet"
        case .green: "appearance.accent.green"
        case .orange: "appearance.accent.orange"
        case .pink: "appearance.accent.pink"
        case .graphite: "appearance.accent.graphite"
        case .custom: "appearance.accent.custom"
        }
    }

    /// Resolves the stored choice to the base hex ("#RRGGBB"); invalid custom values fall back to the default accent.
    public static func resolvedHex(choice: String, custom: String) -> String {
        let selected = AccentChoice(rawValue: choice) ?? .blue
        if selected == .custom {
            return AccentDerivation.parse(custom).map(AccentDerivation.string) ?? AccentDerivation.string(TT.defaultAccentHex)
        }
        return AccentDerivation.string(selected.presetHex ?? TT.defaultAccentHex)
    }
}

/// Appearance mode of the app (`preferredColorScheme`).
public enum SchemeChoice: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public var titleKey: LocalizedStringKey {
        switch self {
        case .system: "appearance.scheme.system"
        case .light: "appearance.scheme.light"
        case .dark: "appearance.scheme.dark"
        }
    }
}

/// UserDefaults keys of the local appearance cache. Since A8 the values are account settings (`AppearanceSync` reconciles
/// them with the account); the cache stays the instant source for the views and the offline fallback.
public enum AppearanceKeys {
    public static let accent = AppearanceStorageKeys.accent
    public static let customHex = AppearanceStorageKeys.customHex
    public static let scheme = AppearanceStorageKeys.scheme

    /// Base accent `#RRGGBB` of a stored choice (preset hues are the native tokens, see `AccentChoice.presetHex`).
    public static func effectiveHex(_ local: LocalAppearance) -> String {
        AccentChoice.resolvedHex(choice: local.accent, custom: local.customHex)
    }
}

/// Applies the stored accent and appearance mode to a subtree. Use once at every app root (also the macOS Settings scene).
struct AppearanceModifier: ViewModifier {
    @AppStorage(AppearanceKeys.accent) private var accent = AccentChoice.blue.rawValue
    @AppStorage(AppearanceKeys.customHex) private var customHex = "#2563EB"
    @AppStorage(AppearanceKeys.scheme) private var scheme = SchemeChoice.system.rawValue

    func body(content: Content) -> some View {
        content
            .ttTheme(accentHex: AccentChoice.resolvedHex(choice: accent, custom: customHex))
            .preferredColorScheme((SchemeChoice(rawValue: scheme) ?? .system).colorScheme)
    }
}

extension View {
    /// Accent (`ttTheme`) and light/dark preference from the local appearance settings.
    public func ttAppearance() -> some View { modifier(AppearanceModifier()) }
}

extension Color {
    /// `#RRGGBB` of this colour in sRGB (used for the custom colour picker).
    public func ttHexString() -> String {
        let resolved = resolve(in: EnvironmentValues())
        func byte(_ v: Float) -> Double { Double(max(0, min(1, v))) * 255 }
        return AccentDerivation.string(AccentDerivation.hex(r: byte(resolved.red), g: byte(resolved.green), b: byte(resolved.blue)))
    }
}
