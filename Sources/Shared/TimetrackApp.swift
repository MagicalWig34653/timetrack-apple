import SwiftUI

@main
struct TimetrackApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentUnavailableView {
                    Label("Timetrack", systemImage: "clock")
                } description: {
                    Text("Das Projekt ist eingerichtet. Zeiterfassung und Anmeldung folgen nach der PWA.")
                }
                .navigationTitle("Timetrack")
            }
        }
    }
}
