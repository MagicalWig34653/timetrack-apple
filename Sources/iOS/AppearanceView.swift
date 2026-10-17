import SwiftUI
import TimetrackDesign
import TimetrackStores

/// "Darstellung": in-app accent colour, light/dark and the app icon (chosen separately from the accent).
struct AppearanceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            AppearanceSettingsPage(sync: model.appearance) {
                FormSection("appearance.icon", footer: "appearance.icon.footer") {
                    AppIconPickerSection()
                }
                HapticsSection()
            }
            .padding(.horizontal, TT.Space.l)
            .padding(.vertical, TT.Space.s)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("settings.appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "Haptisches Feedback": local to this device (not part of the account), applies to every haptic in the app.
private struct HapticsSection: View {
    @AppStorage(HapticLevel.storageKey) private var level = HapticLevel.default.rawValue

    var body: some View {
        FormSection("haptics.title", footer: "haptics.footer") {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                Picker("haptics.title", selection: $level) {
                    ForEach(HapticLevel.allCases) { Text($0.titleKey).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("appearance.haptics")
                Button("haptics.try") { TTHaptics.play(.success) }
                    .buttonStyle(.ttSecondary)
                    .accessibilityIdentifier("appearance.haptics.try")
            }
            .padding(TT.Space.m)
        }
    }
}
