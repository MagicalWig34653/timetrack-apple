import SwiftUI
import TimetrackCore
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
                LiveActivityIconSection()
                LiveActivityTintSection()
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

/// LA4 "Live Activity": the animated work icon. Local to this device (App Group, read by the Live Activity too).
struct LiveActivityIconSection: View {
    @State private var style = LiveActivityIconStore().read()

    var body: some View {
        FormSection("la.icon.title", footer: "la.icon.footer") {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                Picker("la.icon.title", selection: $style) {
                    Text("la.icon.off").tag(LiveActivityIconStyle.off)
                    Text("la.icon.briefcase").tag(LiveActivityIconStyle.briefcase)
                    Text("la.icon.shovel").tag(LiveActivityIconStyle.shovel)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("appearance.la.icon")
                .onChange(of: style) {
                    LiveActivityIconStore().write(style)
                    Task { await TimerLiveActivity.reconcileFromSnapshot(source: "settings") } // an open activity switches at once
                }
                LiveIconPreview(style: style)
            }
            .padding(TT.Space.m)
        }
    }
}

/// Q1 "Live Activity: Hintergrund": how strongly the card (Lock Screen and Apple Watch Smart Stack) is tinted. Local to this device.
struct LiveActivityTintSection: View {
    @State private var style = LiveActivityTintStore().read()

    var body: some View {
        FormSection("la.tint.title", footer: "la.tint.footer") {
            Picker("la.tint.title", selection: $style) {
                Text("la.tint.subtle").tag(LiveActivityTintStyle.subtle)
                Text("la.tint.colorful").tag(LiveActivityTintStyle.colorful)
                Text("la.tint.neutral").tag(LiveActivityTintStyle.neutral)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(TT.Space.m)
            .accessibilityIdentifier("appearance.la.tint")
            .onChange(of: style) {
                LiveActivityTintStore().write(style)
                Task { await TimerLiveActivity.reconcileFromSnapshot(source: "settings") } // an open activity switches at once
            }
        }
    }
}
