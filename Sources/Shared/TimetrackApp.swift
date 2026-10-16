import SwiftUI
import TimetrackCore

/// iOS/iPadOS placeholder: A1 only proves that the shared core links on iOS. The real UI follows in a later package.
@main
struct TimetrackApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentUnavailableView {
                    Label("Timetrack", systemImage: "clock")
                } description: {
                    Text("placeholder.description \(DurationFormat.hoursMinutes(27720))")
                }
                .navigationTitle("Timetrack")
            }
        }
    }
}
