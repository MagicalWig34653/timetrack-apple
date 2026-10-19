import SwiftUI
import TimetrackCore

/// Strengths derived from the glow level ("Leuchteffekt", account preference `glow`). Pure, hence unit-tested.
/// Reduce Transparency and Increase Contrast switch every soft halo off (borders and text stay as they are); the level itself is kept.
public struct GlowStyle: Sendable, Equatable {
    public let level: GlowPreference
    public let reduceTransparency: Bool
    public let increasedContrast: Bool

    public init(level: GlowPreference, reduceTransparency: Bool = false, increasedContrast: Bool = false) {
        self.level = level
        self.reduceTransparency = reduceTransparency
        self.increasedContrast = increasedContrast
    }

    /// 0 = off ... 3 = strong, after the accessibility settings.
    public var effectiveLevel: Int {
        guard !reduceTransparency, !increasedContrast else { return 0 }
        switch level {
        case .off: return 0
        case .subtle: return 1
        case .medium: return 2
        case .strong: return 3
        }
    }

    public var isOn: Bool { effectiveLevel > 0 }

    /// Opacity of the halo under primary buttons and active elements.
    public var haloOpacity: Double { [0, 0.22, 0.38, 0.52][effectiveLevel] }
    public var haloRadius: CGFloat { [0, 8, 14, 20][effectiveLevel] }
    /// Opacity of the halo around progress rings.
    public var ringOpacity: Double { [0, 0.22, 0.38, 0.55][effectiveLevel] }
    public var ringRadius: CGFloat { [0, 4, 8, 12][effectiveLevel] }
    /// Accent share of card borders (medium and strong tint the edge).
    public var cardEdgeOpacity: Double { [0, 0, 0.22, 0.38][effectiveLevel] }
    /// Multiplier of the two soft accent lights behind the page (the baseline of the design is `subtle` = 1).
    public var backdropFactor: Double { [0, 1, 1.5, 2.2][effectiveLevel] }
}

extension EnvironmentValues {
    /// The chosen glow level; set once at the app root by `.ttAppearance()`.
    @Entry public var ttGlow: GlowPreference = .subtle
}

extension GlowPreference: @retroactive Identifiable {
    public var id: String { rawValue }

    public var titleKey: LocalizedStringKey {
        switch self {
        case .off: "appearance.glow.off"
        case .subtle: "appearance.glow.subtle"
        case .medium: "appearance.glow.medium"
        case .strong: "appearance.glow.strong"
        }
    }

    public var descriptionKey: LocalizedStringKey {
        switch self {
        case .off: "appearance.glow.desc.off"
        case .subtle: "appearance.glow.desc.subtle"
        case .medium: "appearance.glow.desc.medium"
        case .strong: "appearance.glow.desc.strong"
        }
    }
}

/// Soft coloured halo behind a view (buttons, rings); nothing when the glow is off or accessibility settings ask for less.
struct TTHaloModifier: ViewModifier {
    let color: Color
    let ring: Bool
    @Environment(\.ttGlow) private var level
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let style = GlowStyle(level: level, reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased)
        content.shadow(color: color.opacity(ring ? style.ringOpacity : style.haloOpacity), radius: ring ? style.ringRadius : style.haloRadius, y: ring ? 0 : 3)
    }
}

extension View {
    /// Accent halo for primary actions (strength by glow level).
    public func ttHalo(_ color: Color) -> some View { modifier(TTHaloModifier(color: color, ring: false)) }
    /// Accent halo for progress rings.
    public func ttRingHalo(_ color: Color) -> some View { modifier(TTHaloModifier(color: color, ring: true)) }
}
