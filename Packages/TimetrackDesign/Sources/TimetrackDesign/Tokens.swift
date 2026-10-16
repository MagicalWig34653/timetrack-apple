import SwiftUI
import TimetrackCore

// MARK: - Dynamic color helper

extension Color {
    /// A color that resolves differently in light and dark appearance (no asset catalog needed, usable from a package).
    public init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        #if os(watchOS)
        // watchOS has a single (dark) appearance.
        self.init(hex: dark, alpha: darkAlpha)
        #elseif canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return UIColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
        #endif
    }

    /// `#RRGGBB` (or `RRGGBB`); nil when the text is not a valid color.
    public init?(hex text: String) {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(hex: number)
    }

    public init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

#if canImport(UIKit) && !os(watchOS)
extension UIColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#elseif canImport(AppKit)
extension NSColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#endif

// MARK: - Semantic colors

/// Semantic color tokens (Zinc neutrals, see docs/DESIGN-NATIVE.md). Views use these, never raw colors.
public enum TT {
    /// Default accent (PWA `--ui-accent`): calm blue.
    public static let defaultAccentHex: UInt32 = 0x2563EB

    // Surfaces
    public static let background = Color(light: 0xF4F4F5, dark: 0x0C0C0E)
    public static let surface = Color(light: 0xFFFFFF, dark: 0x1A1A1E)
    public static let surfaceRaised = Color(light: 0xFAFAFA, dark: 0x232328)
    /// Solid stand-in for glass (Reduce Transparency, or where no glass is available).
    public static let glassFallback = Color(light: 0xFFFFFF, dark: 0x202025)
    public static let separator = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.10)
    public static let cardBorder = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.09)

    // Text (contrast against `background`/`surface` >= 4.5:1 in both appearances)
    public static let textPrimary = Color(light: 0x18181B, dark: 0xFAFAFA)
    public static let textSecondary = Color(light: 0x52525B, dark: 0xA1A1AA)
    public static let textTertiary = Color(light: 0x6B6B75, dark: 0x8E8E98)

    // Status (independent from the accent)
    public static let success = Color(light: 0x15803D, dark: 0x4ADE80)
    public static let warning = Color(light: 0xB45309, dark: 0xFBBF24)
    public static let danger = Color(light: 0xDC2626, dark: 0xF87171)
    /// Solid fill behind white text (same in both modes; 4.8:1 against white).
    public static let dangerFill = Color(hex: 0xDC2626)

    // Kinds: segments (PWA DayTimeline: sky / amber / violet) and absences (PWA ABSENCE_CLASSES).
    public static let kindWork = Color(light: 0x0284C7, dark: 0x38BDF8)
    public static let kindTravel = Color(light: 0xD97706, dark: 0xFBBF24)
    public static let kindSchool = Color(light: 0x7C3AED, dark: 0xA78BFA)
    public static let kindVacation = Color(light: 0x0369A1, dark: 0x7DD3FC)
    public static let kindSick = Color(light: 0xE11D48, dark: 0xFB7185)
    public static let kindExcused = Color(light: 0x0F766E, dark: 0x5EEAD4)
    public static let kindOther = Color(light: 0x6D28D9, dark: 0xC4B5FD)
    public static let kindHoliday = Color(light: 0xB45309, dark: 0xFCD34D)

    // Metrics
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        public static let chip: CGFloat = 8
        public static let control: CGFloat = 14
        public static let card: CGFloat = 22
        public static let hero: CGFloat = 28
    }

    /// Readable column width for iPad/Mac content.
    public static let contentWidth: CGFloat = 760
}

// MARK: - Accent theme (override hook)

/// Accent selection. The default is `#2563EB`; a personal choice (hex) is injected at the app root with `.ttTheme(accentHex:)`.
/// From the hex, `AccentDerivation` computes appearance-aware colours so accent text and buttons keep >= 4.5:1:
/// - `accent`: fill (buttons, rings, selection, glows)
/// - `onAccent`: text/icon colour on that fill (white or black)
/// - `ink`: the accent as text/icon colour on app surfaces (darker in light mode, lighter in dark mode)
public struct TTTheme: Sendable, Equatable {
    public var accentHex: String?

    public init(accentHex: String? = nil) { self.accentHex = accentHex }

    /// Valid override or the default. Invalid input is discarded (like the PWA).
    public var baseHex: UInt32 {
        if let accentHex, let value = AccentDerivation.parse(accentHex) { return value }
        return TT.defaultAccentHex
    }

    public var tokens: AccentDerivation.Tokens { AccentDerivation.tokens(for: baseHex) }

    public var accent: Color {
        let t = tokens
        return Color(light: t.fillLight, dark: t.fillDark)
    }

    public var onAccent: Color {
        let t = tokens
        return Color(light: t.onFillLight, dark: t.onFillDark)
    }

    public var ink: Color {
        let t = tokens
        return Color(light: t.inkLight, dark: t.inkDark)
    }
}

extension EnvironmentValues {
    @Entry public var ttTheme = TTTheme()
}

extension View {
    /// Applies the accent to the whole subtree (`tint`, text-safe ink) and exposes it to design components.
    public func ttTheme(accentHex: String? = nil) -> some View {
        let theme = TTTheme(accentHex: accentHex)
        return self.environment(\.ttTheme, theme).tint(theme.ink)
    }
}

// MARK: - Kinds

extension SegmentKind {
    public var ttTint: Color {
        switch self {
        case .work, .unknown: TT.kindWork
        case .travel: TT.kindTravel
        case .school: TT.kindSchool
        }
    }
    public var ttSymbol: String {
        switch self {
        case .work, .unknown: "briefcase.fill"
        case .travel: "car.fill"
        case .school: "graduationcap.fill"
        }
    }
    /// Keys live in each app's string catalog (`kind.work` ...).
    public var ttTitle: LocalizedStringKey {
        switch self {
        case .work, .unknown: "kind.work"
        case .travel: "kind.travel"
        case .school: "kind.school"
        }
    }
}

extension AbsenceKind {
    public var ttTint: Color {
        switch self {
        case .vacation: TT.kindVacation
        case .sick: TT.kindSick
        case .excused: TT.kindExcused
        case .other, .unknown: TT.kindOther
        }
    }
    public var ttSymbol: String {
        switch self {
        case .vacation: "beach.umbrella.fill"
        case .sick: "cross.case.fill"
        case .excused: "checkmark.seal.fill"
        case .other, .unknown: "calendar.badge.clock"
        }
    }
    public var ttTitle: LocalizedStringKey {
        switch self {
        case .vacation: "absence.vacation"
        case .sick: "absence.sick"
        case .excused: "absence.excused"
        case .other, .unknown: "absence.other"
        }
    }
}

// MARK: - Typography

/// Typography scale. Durations use rounded monospaced digits; all fonts scale with Dynamic Type.
public enum TTFont {
    public static let pageTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    public static let sectionTitle = Font.system(.title3, design: .default, weight: .semibold)
    public static let cardTitle = Font.system(.headline, design: .default, weight: .semibold)
    public static let body = Font.system(.body)
    public static let label = Font.system(.subheadline, weight: .medium)
    public static let meta = Font.system(.footnote)
    public static let eyebrow = Font.system(.caption2, weight: .semibold)
    /// Stat numerals (tiles).
    public static let stat = Font.system(.title, design: .rounded, weight: .semibold).monospacedDigit()
    public static let statSmall = Font.system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
    /// Inline durations and time ranges.
    public static let numeral = Font.system(.subheadline, design: .rounded, weight: .medium).monospacedDigit()
    public static let numeralSmall = Font.system(.footnote, design: .rounded).monospacedDigit()
}
