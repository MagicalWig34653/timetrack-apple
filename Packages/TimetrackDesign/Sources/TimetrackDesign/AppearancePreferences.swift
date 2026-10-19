import SwiftUI
import TimetrackCore

/// In-app accent choices: every id of the contract (v0.21.0), in the display order of the PWA picker. The hue of a preset is
/// `AccentPreset.nativeHex`; the choice is independent from the app icon (changing one never changes the other).
public typealias AccentChoice = AccentPreset

extension AccentPreset: @retroactive Identifiable {
    public var id: String { rawValue }

    /// Fixed colour of a preset; nil for `.custom`.
    public var presetHex: UInt32? { nativeHex }

    /// German names as in the PWA picker; keys live in each app's string catalog.
    public var titleKey: LocalizedStringKey { LocalizedStringKey("appearance.accent.\(rawValue)") }

    /// Resolves the stored choice to the base hex ("#RRGGBB"); an unknown id falls back to the default accent,
    /// an invalid custom value too.
    public static func resolvedHex(choice: String, custom: String) -> String {
        let selected = AccentPreset(rawValue: choice) ?? .blue
        if selected == .custom {
            return AccentDerivation.parse(custom).map(AccentDerivation.string) ?? AccentDerivation.string(TT.defaultAccentHex)
        }
        return AccentDerivation.string(selected.nativeHex ?? TT.defaultAccentHex)
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
    public static let glow = AppearanceStorageKeys.glow

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
    @AppStorage(AppearanceKeys.glow) private var glow = Preferences.defaultGlow

    func body(content: Content) -> some View {
        content
            .environment(\.ttGlow, GlowPreference(rawValue: glow) ?? .subtle)
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
