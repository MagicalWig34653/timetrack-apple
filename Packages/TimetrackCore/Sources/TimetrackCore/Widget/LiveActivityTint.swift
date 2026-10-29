import Foundation

// Q1: how strongly the Live Activity card (Smart Stack on the watch, Lock Screen on the iPhone) is tinted with the kind colour.
// Pure colour maths (no UIKit) so it is testable; `LiveActivityTarget.backgroundTint` turns it into a dynamic colour.

/// The user's choice. `subtle` is the default: dark, low-saturation graphite with only a hint of the account colour.
public enum LiveActivityTintStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case subtle
    case colorful
    case neutral

    public var id: String { rawValue }
    public static let `default` = LiveActivityTintStyle.subtle
}

/// A colour in HSB plus alpha (0...1 each).
public struct LiveActivityTintColor: Sendable, Equatable {
    public var hue: Double
    public var saturation: Double
    public var brightness: Double
    public var alpha: Double

    /// Contrast ratio of white text on this colour when composited over a grey backdrop (0...1).
    public func whiteTextContrast(overGrey backdrop: Double = 0.34) -> Double {
        let (r, g, b) = Self.rgb(hue: hue, saturation: saturation, brightness: brightness)
        func mix(_ c: Double) -> Double { c * alpha + backdrop * (1 - alpha) }
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * lin(mix(r)) + 0.7152 * lin(mix(g)) + 0.0722 * lin(mix(b))
        return 1.05 / (luminance + 0.05)
    }

    static func rgb(hue: Double, saturation s: Double, brightness v: Double) -> (Double, Double, Double) {
        let h = (hue - hue.rounded(.down)) * 6
        let c = v * s, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double)
        switch Int(h) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}

public enum LiveActivityTint {
    /// The card background for an accent colour (given in HSB) in the dark or light appearance.
    /// - subtle: N2: very dark (brightness 0.10) and only half opaque, so the card is a dark glass pane (the watch Smart Stack and the
    ///   Lock Screen material shine through) with a hint of the accent hue. The earlier opaque graphite (0.19 at 94 %) looked far too bright on the watch.
    /// - colorful: the stronger LA3 tint.
    /// - neutral: no hue at all, plain graphite.
    public static func color(style: LiveActivityTintStyle, hue: Double, saturation: Double, brightness: Double, dark: Bool) -> LiveActivityTintColor {
        switch style {
        case .colorful:
            return dark
                ? LiveActivityTintColor(hue: hue, saturation: saturation, brightness: brightness * 0.38, alpha: 0.9)
                : LiveActivityTintColor(hue: hue, saturation: saturation * 0.45, brightness: min(1, brightness + 0.1), alpha: 0.78)
        case .subtle:
            return dark
                ? LiveActivityTintColor(hue: hue, saturation: min(0.5, saturation * 0.4), brightness: 0.10, alpha: 0.5)
                : LiveActivityTintColor(hue: hue, saturation: saturation * 0.10, brightness: 0.96, alpha: 0.82)
        case .neutral:
            return dark
                ? LiveActivityTintColor(hue: 0, saturation: 0, brightness: 0.08, alpha: 0.5)
                : LiveActivityTintColor(hue: 0, saturation: 0, brightness: 0.95, alpha: 0.82)
        }
    }
}

extension LiveActivityTint {
    /// LA7: the watch Smart Stack card. Static (never a dynamic colour: the card is drawn by the system with a trait collection that
    /// need not match the iPhone, which resolved the light variant) and fully opaque (a translucent tint over the system card material
    /// rendered as bright grey-green). Always dark, with a hint of the accent hue unless neutral.
    public static func watchCard(style: LiveActivityTintStyle, hue: Double, saturation: Double, brightness: Double) -> LiveActivityTintColor {
        switch style {
        case .colorful: LiveActivityTintColor(hue: hue, saturation: min(0.75, saturation), brightness: max(0.14, min(0.22, brightness * 0.26)), alpha: 1)
        case .subtle: LiveActivityTintColor(hue: hue, saturation: min(0.5, saturation * 0.4), brightness: 0.11, alpha: 1)
        case .neutral: LiveActivityTintColor(hue: 0, saturation: 0, brightness: 0.10, alpha: 1)
        }
    }
}

/// The choice, stored in the App Group like the icon style. Local to this device.
public struct LiveActivityTintStore: Sendable {
    public static let key = "liveactivity.tint.v1"
    private let suiteName: String?

    public init(suiteName: String? = WidgetSnapshot.appGroup) { self.suiteName = suiteName }

    private var defaults: UserDefaults? { suiteName.flatMap { UserDefaults(suiteName: $0) } }

    public func read() -> LiveActivityTintStyle {
        defaults?.string(forKey: Self.key).flatMap(LiveActivityTintStyle.init(rawValue:)) ?? .default
    }

    public func write(_ style: LiveActivityTintStyle) { defaults?.set(style.rawValue, forKey: Self.key) }
}

extension LiveActivityTarget {
    /// The tint that applies; older states without the field get the new subtle default.
    public var activeTintStyle: LiveActivityTintStyle { tintStyle ?? .default }
}
