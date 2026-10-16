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
