import Foundation
import SwiftUI
import TimetrackCore
#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif canImport(WatchKit)
import WatchKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Meaning of a haptic, not its mechanics: every platform maps these to its closest native feedback.
/// Haptics belong to explicit user actions only; passive updates (timer ticks, refreshes, widgets) never use them.
public enum TTHaptic: String, CaseIterable, Sendable {
    /// A choice changed: tab, segmented control, calendar day, accent colour.
    case selection
    /// A light mark of a gesture's beginning (range start).
    case tap
    /// A very soft tap for navigation (week/month arrows, "Heute").
    case softTap
    /// An action succeeded (saved, confirmed, range complete).
    case success
    /// Something needs attention (validation error).
    case warning
    /// A request failed.
    case error
    /// The timer started.
    case start
    /// The timer stopped.
    case stop
    /// A destructive confirmation appeared (warning style).
    case confirmDestructive
}

/// User choice "Haptisches Feedback". Local to the device (UserDefaults `appearance.haptics`), never part of the account.
public enum HapticLevel: String, CaseIterable, Identifiable, Sendable {
    case off, subtle, normal

    public var id: String { rawValue }
    public static let storageKey = "appearance.haptics"
    public static let `default` = HapticLevel.normal

    public var titleKey: LocalizedStringKey {
        switch self {
        case .off: "haptics.off"
        case .subtle: "haptics.subtle"
        case .normal: "haptics.normal"
        }
    }

    /// Stored level; unknown or missing values mean the default.
    public static func stored(in defaults: UserDefaults = .standard) -> HapticLevel {
        defaults.string(forKey: storageKey).flatMap(HapticLevel.init(rawValue:)) ?? .default
    }
}

/// What plays at which level, and which store result maps to which haptic. Pure, hence unit-tested.
public enum HapticPolicy {
    /// Kinds that "Dezent" still plays: outcomes of explicit actions. Pure navigation and selection ticks are dropped.
    public static let subtleKinds: Set<TTHaptic> = [.start, .stop, .success, .warning, .error, .confirmDestructive]

    public static func resolve(_ kind: TTHaptic, level: HapticLevel) -> TTHaptic? {
        switch level {
        case .off: nil
        case .subtle: subtleKinds.contains(kind) ? kind : nil
        case .normal: kind
        }
    }

    /// Haptic of a user-initiated store result (see `StoreOutcome`).
    public static func haptic(for outcome: StoreOutcome) -> TTHaptic {
        switch outcome {
        case .timerStarted: .start
        case .timerStopped: .stop
        case .saved, .deleted: .success
        case .failed: .error
        }
    }
}

/// Plays one haptic on the device. Injected into `TTHapticEngine` so tests can record events.
@MainActor
public protocol HapticPerforming {
    func perform(_ kind: TTHaptic)
}

/// Policy, debounce and delivery in one place. Views and non-view code share one instance (`TTHaptics.engine`).
@MainActor
public final class TTHapticEngine {
    /// Minimum gap between two haptics; a second one inside it is dropped (e.g. tab change plus selection in the same tap).
    public static let minimumInterval: TimeInterval = 0.08

    private let performer: any HapticPerforming
    private let level: () -> HapticLevel
    private let now: () -> TimeInterval
    private var lastPlayed: TimeInterval?

    public init(performer: any HapticPerforming, level: @escaping () -> HapticLevel = { HapticLevel.stored() },
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.performer = performer
        self.level = level
        self.now = now
    }

    /// Applies level and debounce and records the slot; true when the haptic may play now.
    public func admit(_ kind: TTHaptic) -> TTHaptic? {
        guard let resolved = HapticPolicy.resolve(kind, level: level()) else { return nil }
        let time = now()
        if let lastPlayed, time - lastPlayed < Self.minimumInterval { return nil }
        lastPlayed = time
        return resolved
    }

    public func play(_ kind: TTHaptic) {
        guard let resolved = admit(kind) else { return }
        performer.perform(resolved)
    }

    public func handle(_ outcome: StoreOutcome) { play(HapticPolicy.haptic(for: outcome)) }
}

/// Entry points for app code. `TTHaptics.play(.success)` from stores' callbacks, button actions and other non-view code;
/// `View.ttHaptic(_:trigger:)` for state-driven feedback. Never call from App Intents, widgets or background tasks.
public enum TTHaptics {
    @MainActor public static var engine = TTHapticEngine(performer: SystemHapticPerformer())

    @MainActor public static func play(_ kind: TTHaptic) { engine.play(kind) }
    @MainActor public static func handle(_ outcome: StoreOutcome) { engine.handle(outcome) }
}

/// Real device feedback. Plays only while the app is active (intents, background refreshes and widgets never reach it).
@MainActor
public struct SystemHapticPerformer: HapticPerforming {
    public init() {}

    #if os(watchOS)
    public func perform(_ kind: TTHaptic) {
        guard WKApplication.shared().applicationState == .active else { return }
        let device = WKInterfaceDevice.current()
        switch kind {
        case .selection, .tap, .softTap: device.play(.click)
        case .success: device.play(.success)
        case .warning, .confirmDestructive: device.play(.retry)
        case .error: device.play(.failure)
        case .start: device.play(.start)
        case .stop: device.play(.stop)
        }
    }
    #elseif canImport(UIKit)
    public func perform(_ kind: TTHaptic) {
        guard UIApplication.shared.applicationState == .active else { return }
        switch kind {
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .tap: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .softTap: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning, .confirmDestructive: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .start: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .stop: UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
        }
    }
    #elseif canImport(AppKit)
    public func perform(_ kind: TTHaptic) {
        guard NSApp?.isActive == true else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch kind {
        case .selection: pattern = .alignment
        case .tap, .softTap, .warning, .error, .confirmDestructive: pattern = .generic
        case .success, .start, .stop: pattern = .levelChange
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
    #else
    public func perform(_ kind: TTHaptic) {}
    #endif
}

extension TTHaptic {
    /// SwiftUI feedback of this kind. `.start`/`.stop` only play on Apple Watch, so iPhone/iPad use impacts instead.
    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .selection: .selection
        case .tap: .impact(weight: .light)
        case .softTap: .impact(flexibility: .soft, intensity: 0.6)
        case .success: .success
        case .warning, .confirmDestructive: .warning
        case .error: .error
        #if os(watchOS)
        case .start: .start
        case .stop: .stop
        #elseif os(macOS)
        case .start, .stop: .levelChange
        #else
        case .start: .impact(weight: .medium)
        case .stop: .impact(flexibility: .rigid, intensity: 0.9)
        #endif
        }
    }
}

extension View {
    /// Plays `kind` when `trigger` changes (policy and debounce from `TTHaptics.engine`). One line per interaction; the
    /// trigger must change only through explicit user actions, never through loads or timers.
    public func ttHaptic<T: Equatable>(_ kind: TTHaptic, trigger: T) -> some View {
        sensoryFeedback(trigger: trigger) { _, _ in
            MainActor.assumeIsolated { TTHaptics.engine.admit(kind) }?.sensoryFeedback
        }
    }

    /// Plays `kind` only when `flag` turns true (a confirmation dialog or sheet appearing), not when it turns false again.
    public func ttHaptic(_ kind: TTHaptic, whenBecomesTrue flag: Bool) -> some View {
        sensoryFeedback(trigger: flag) { old, new in
            guard new, !old else { return nil }
            return MainActor.assumeIsolated { TTHaptics.engine.admit(kind) }?.sensoryFeedback
        }
    }
}
