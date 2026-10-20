import XCTest

extension XCUIApplication {
    /// UX3: the former "Einstellungen" tab is "Mehr" (compact: tab bar, regular: sidebar entry `sidebar.more`).
    func openMore() {
        let tab = tabBars.buttons["Mehr"]
        if tab.exists { tab.tap() } else { descendants(matching: .any)["sidebar.more"].firstMatch.tap() }
    }

    /// "Mehr" › "Einstellungen": the S2 settings pages (account, appearance, work, info, sign-out).
    func openSettings() {
        openMore()
        let row = descendants(matching: .any)["more.settings"].firstMatch
        _ = row.waitForExistence(timeout: 10)
        row.tap()
    }
}
