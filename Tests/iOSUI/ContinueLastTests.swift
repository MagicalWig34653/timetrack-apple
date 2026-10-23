import XCTest

/// H4: "Fortführen" of the last finished entry of today (Heute, Jetzt-Sheet, bar context menu). Needs a THROWAWAY backend; skipped otherwise.
/// The backend may or may not support reopening: either outcome (reopened / new entry from now) must end with a running timer and an honest notice.
final class ContinueLastTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20) || app.stopControl.exists)
        try XCTSkipIf(app.tabBars.buttons["Mehr"].exists == false, "compact layout only")
    }

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// Runs a short entry (start, stop) so that something is left to continue.
    private func recordShortEntry() throws {
        if el("nowbar.stop").waitForExistence(timeout: 3) { el("nowbar.stop").tap() }
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 10))
        el("nowbar.start").tap()
        if !el("nowbar.stop").waitForExistence(timeout: 8) { throw XCTSkip("seed data overlaps the current time") }
        sleep(2)
        el("nowbar.stop").tap()
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 10))
    }

    func testContinueFromHeuteAndFromTheSheet() throws {
        try recordShortEntry()
        app.tabBars.buttons["Heute"].tap()
        let button = el("continue.last")
        XCTAssertTrue(button.waitForExistence(timeout: 10), "idle Heute offers to continue")
        XCTAssertTrue(button.label.contains("Fortführen"), button.label)
        XCTAssertTrue(button.label.contains("zuletzt bis"), button.label)
        shot("h4-continue-idle")
        button.tap()
        XCTAssertTrue(el("nowbar.stop").waitForExistence(timeout: 10), "timer runs after continuing")
        XCTAssertTrue(el("continue.notice").waitForExistence(timeout: 5), "the outcome is stated")
        shot("h4-continue-notice")
        XCTAssertFalse(el("continue.last").exists, "no continue offer while a timer runs")

        // Stop again and continue from the Jetzt sheet.
        el("nowbar.stop").tap()
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 10))
        el("nowbar.open").tap()
        XCTAssertTrue(el("nowsheet.start").waitForExistence(timeout: 10))
        XCTAssertTrue(el("continue.last").waitForExistence(timeout: 5), "the sheet offers it as well")
        shot("h4-continue-sheet")
        el("continue.last").tap()
        XCTAssertTrue(el("nowsheet.stop").waitForExistence(timeout: 10))
        el("nowsheet.stop").tap()
    }
}
