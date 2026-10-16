import Foundation

/// Pure accent maths (no UI types, fully testable). Mirrors the PWA's `accent.ts`: from one chosen colour it derives, per appearance,
/// a fill (buttons, rings, selection), the text colour on that fill and an "ink" (the accent used as text/icon colour on the app
/// surfaces) that always reaches `minTextContrast`.
public enum AccentDerivation {
    /// WCAG AA for normal text.
    public static let minTextContrast = 4.5
    /// WCAG for graphical objects (fills against their surroundings).
    public static let minFillContrast = 3.0

    /// The surfaces accent text and fills sit on (see `TT` tokens).
    public struct Surfaces: Sendable {
        public let backgrounds: [UInt32]
        /// Share (0...1) of the accent used for tinted chip/button backgrounds (`accent.opacity(...)`).
        public let tintShare: Double
    }

    public static let lightSurfaces = Surfaces(backgrounds: [0xF4F4F5, 0xFFFFFF, 0xFAFAFA], tintShare: 0.12)
    public static let darkSurfaces = Surfaces(backgrounds: [0x0C0C0E, 0x1A1A1E, 0x232328, 0x202025], tintShare: 0.20)

    /// Derived colours for both appearances.
    public struct Tokens: Sendable, Equatable {
        public let fillLight: UInt32
        public let fillDark: UInt32
        public let onFillLight: UInt32
        public let onFillDark: UInt32
        public let inkLight: UInt32
        public let inkDark: UInt32
    }

    // MARK: Colour maths

    public static func components(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
    }

    public static func hex(r: Double, g: Double, b: Double) -> UInt32 {
        func clamp(_ v: Double) -> UInt32 { UInt32(max(0, min(255, v.rounded()))) }
        return clamp(r) << 16 | clamp(g) << 8 | clamp(b)
    }

    /// WCAG relative luminance.
    public static func luminance(_ hex: UInt32) -> Double {
        let c = components(hex)
        func linear(_ v: Double) -> Double {
            let x = v / 255
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// WCAG contrast ratio (1...21).
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// sRGB mix: `share` (0...1) of `color` over `base`.
    public static func mix(_ color: UInt32, share: Double, over base: UInt32) -> UInt32 {
        let a = components(color), b = components(base)
        return hex(r: a.r * share + b.r * (1 - share), g: a.g * share + b.g * (1 - share), b: a.b * share + b.b * (1 - share))
    }

    /// White or black, whichever reads better on `fill` (always >= 4.5:1).
    public static func foreground(on fill: UInt32) -> UInt32 {
        contrast(fill, 0xFFFFFF) >= contrast(fill, 0x000000) ? 0xFFFFFF : 0x000000
    }

    /// Parses `#RRGGBB`, `RRGGBB` or `#RGB`; nil when invalid.
    public static func parse(_ text: String) -> UInt32? {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        return number
    }

    public static func string(_ hex: UInt32) -> String { String(format: "#%06X", hex) }

    // MARK: Derivation

    /// Text-grade colour: moves `hex` towards `target` in 5 % steps until it reaches 4.5:1 on every surface and on the tinted backgrounds.
    static func ink(_ hex: UInt32, surfaces: Surfaces, target: UInt32) -> UInt32 {
        func passes(_ color: UInt32) -> Bool {
            // Chip/button tints are made of the original hue (`hex`), so the candidate must also read on those tinted backgrounds.
            surfaces.backgrounds.allSatisfy { contrast(color, $0) >= minTextContrast }
                && surfaces.backgrounds.allSatisfy { contrast(color, mix(hex, share: surfaces.tintShare, over: $0)) >= minTextContrast }
        }
        var candidate = hex
        var step = 0
        while !passes(candidate) && step < 20 {
            step += 1
            candidate = mix(target, share: Double(step) * 0.05, over: hex)
        }
        return candidate
    }

    /// Fill colour: the accent itself unless it vanishes against the surfaces (< 3:1, e.g. graphite in dark mode); then lightened.
    /// Only applied to dark mode: in light mode the chosen hue stays exactly as picked (text on it uses `foreground(on:)`).
    static func fill(_ hex: UInt32, surfaces: Surfaces, target: UInt32) -> UInt32 {
        var candidate = hex
        var step = 0
        while !surfaces.backgrounds.allSatisfy({ contrast(candidate, $0) >= minFillContrast }) && step < 20 {
            step += 1
            candidate = mix(target, share: Double(step) * 0.05, over: hex)
        }
        return candidate
    }

    public static func tokens(for hex: UInt32) -> Tokens {
        let fillLight = hex
        let fillDark = fill(hex, surfaces: darkSurfaces, target: 0xFFFFFF)
        return Tokens(
            fillLight: fillLight, fillDark: fillDark,
            onFillLight: foreground(on: fillLight), onFillDark: foreground(on: fillDark),
            inkLight: ink(hex, surfaces: lightSurfaces, target: 0x000000),
            inkDark: ink(hex, surfaces: darkSurfaces, target: 0xFFFFFF)
        )
    }
}
