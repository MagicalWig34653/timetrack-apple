import SwiftUI

/// Plain on/off switch for haptic feedback (the fine grading Aus/Dezent/Normal stays on the appearance page of iOS).
/// Off stores `off`; on restores `normal` unless a finer level (`subtle`) is already chosen.
public struct HapticsToggle: View {
    @AppStorage(HapticLevel.storageKey) private var level = HapticLevel.default.rawValue
    private let title: LocalizedStringKey

    public init(_ title: LocalizedStringKey = "haptics.title") { self.title = title }

    public var body: some View {
        Toggle(title, isOn: Binding(get: { Self.isOn(level) }, set: { level = Self.level(isOn: $0, current: level) }))
            .accessibilityIdentifier("haptics.toggle")
    }

    /// Pure mapping, unit-tested.
    public static func isOn(_ stored: String) -> Bool { (HapticLevel(rawValue: stored) ?? .default) != .off }

    public static func level(isOn: Bool, current: String) -> String {
        guard isOn else { return HapticLevel.off.rawValue }
        let known = HapticLevel(rawValue: current) ?? .default
        return (known == .off ? HapticLevel.normal : known).rawValue
    }
}
