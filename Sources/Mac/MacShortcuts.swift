import AppIntents

/// H5: Shortcuts/Siri on the Mac. Only "Letzten Timer fortführen" for now; Start/Stopp as App Intents exist on iOS only so far.
struct TimetrackMacShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ContinueTimerIntent(), phrases: ["Führe den Timer in \(.applicationName) fort", "Letzten Timer fortführen in \(.applicationName)"],
                    shortTitle: "Timer fortführen", systemImageName: "arrow.uturn.forward")
    }
}
