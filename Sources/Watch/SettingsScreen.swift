import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    let receiver: WatchHandoffReceiver

    var body: some View {
        List {
            Section("settings.server") {
                Text(model.serverURL?.absoluteString ?? "–").font(.footnote)
                if let account = model.account {
                    Label(account.displayName, systemImage: "person.crop.circle")
                    Label("watch.signed_in", systemImage: "checkmark.circle").foregroundStyle(.green)
                }
            }
            Section {
                Button("watch.adopt_session") {
                    Task {
                        await receiver.pullNow()
                        TTHaptics.play(model.phase == .signedIn ? .success : .warning)
                    }
                }
                    .accessibilityIdentifier("watch.adopt")
            } footer: {
                Text("watch.adopt_session.hint")
            }
            Section("settings.about") {
                LabeledContent("settings.version") { Text(verbatim: Self.versionText) }
                LabeledContent("settings.license") { Text(verbatim: "AGPL-3.0-only") }
            }
        }
        .navigationTitle("sidebar.settings")
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}
