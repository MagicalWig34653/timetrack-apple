import Foundation

// LA4: the animated work icon of the Live Activity. Pure selection and frame logic; the drawing lives in the frame fonts
// (`scripts/make-frame-fonts.py`) and the views in `Sources/WidgetShared`.
//
// What is technically possible (see docs/handoffs/LA4.md): a Live Activity does not run SwiftUI animations; the only content that
// changes by itself is `Text(timerInterval:)`. The icon is therefore a one-glyph timer text in a font whose digits 0-9 are ten poses:
// the seconds digit of the work clock picks the pose, one pose per second, without any activity update.

/// Which icon the Live Activity shows while work runs. `off` keeps the static kind symbol.
public enum LiveActivityIconStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    case briefcase
    case shovel

    public var id: String { rawValue }

    /// Conservative default: no animation until the user turns it on (the real-device rendering is still to be confirmed).
    public static let `default` = LiveActivityIconStyle.off

    public var isAnimated: Bool { self != .off }

    /// PostScript name of the frame font; nil for `off`.
    public var fontName: String? {
        switch self {
        case .off: nil
        case .briefcase: "TTFramesBriefcase"
        case .shovel: "TTFramesShovel"
        }
    }

    public static let frameCount = 10

    /// Pose shown with Reduce Motion, while paused and in the Always-On display: an upright shovel / the case at rest size.
    public var restingFrame: Int {
        switch self {
        case .off, .briefcase: 0
        case .shovel: 4
        }
    }

    /// The pose for a whole number of elapsed seconds (the seconds digit of the clock).
    public static func frame(atElapsed seconds: Int) -> Int { ((seconds % frameCount) + frameCount) % frameCount }
}

/// The choice, stored in the App Group so the app, its intents and the Live Activity share it. Local to this device.
public struct LiveActivityIconStore: Sendable {
    public static let key = "liveactivity.icon.v1"
    private let suiteName: String?

    public init(suiteName: String? = WidgetSnapshot.appGroup) { self.suiteName = suiteName }

    private var defaults: UserDefaults? { suiteName.flatMap { UserDefaults(suiteName: $0) } }

    public func read() -> LiveActivityIconStyle {
        defaults?.string(forKey: Self.key).flatMap(LiveActivityIconStyle.init(rawValue:)) ?? .default
    }

    public func write(_ style: LiveActivityIconStyle) { defaults?.set(style.rawValue, forKey: Self.key) }
}

extension LiveActivityTarget {
    /// The style that really applies: only a running work segment animates (a pause and the other kinds keep their symbol).
    public var activeIconStyle: LiveActivityIconStyle {
        guard kind == .work, !isPaused, let iconStyle else { return .off }
        return iconStyle
    }

    /// Pose index the clock's seconds digit selects at `date`.
    public func iconFrame(at date: Date) -> Int { LiveActivityIconStyle.frame(atElapsed: workedSeconds(at: date)) }
}
