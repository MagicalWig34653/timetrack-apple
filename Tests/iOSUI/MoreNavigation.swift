import XCTest

extension XCUIApplication {
    /// UX3: the former "Einstellungen" tab is "Mehr" (compact: tab bar, regular: sidebar entry `sidebar.more`).
    func openMore() {
        let tab = tabBars.buttons["Mehr"]
        if tab.exists { tab.tap() } else { descendants(matching: .any)["sidebar.more"].firstMatch.tap() }
    }

    /// "Mehr" › "Einstellungen": the S2 settings pages (account, appearance, work, info, sign-out).
    func openSettings() {
        let row = descendants(matching: .any)["more.settings"].firstMatch
        openMore()
        // "Mehr" keeps its navigation stack while another tab is shown: pop back to its root when a settings page is still pushed.
        for _ in 0..<4 where !row.waitForExistence(timeout: 2) {
            guard navigationBars.buttons.firstMatch.exists else { break }
            navigationBars.buttons.firstMatch.tap()
        }
        _ = row.waitForExistence(timeout: 10)
        row.tap()
    }
}

extension XCUIApplication {
    /// H2: the one start control: the "Jetzt" bar on iPhone, the Heute card where the bar is absent (iPad).
    var startControl: XCUIElement { buttons.matching(NSPredicate(format: "identifier IN {'nowbar.start','today.start'}")).firstMatch }
    var stopControl: XCUIElement { buttons.matching(NSPredicate(format: "identifier IN {'nowbar.stop','today.stop'}")).firstMatch }
}
