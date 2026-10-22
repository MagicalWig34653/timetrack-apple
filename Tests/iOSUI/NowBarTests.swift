import XCTest

/// UX3: the "Jetzt" bar above the tab bar (start/stop on every tab) and the "Mehr" tab. Needs a THROWAWAY backend
/// (TT_DEV_SERVER / TT_DEV_COOKIE as in SmokeTests); skipped otherwise. iPhone only: on iPad the sidebar footer takes this role.
final class NowBarTests: XCTestCase {
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
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20) || app.buttons["today.stop"].exists)
        try XCTSkipIf(app.tabBars.buttons["Mehr"].exists == false, "compact layout only")
    }

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testStartAndStopFromAnotherTab() throws {
        app.tabBars.buttons["Zeit"].tap()
        if el("nowbar.stop").waitForExistence(timeout: 3) { el("nowbar.stop").tap() } // a timer left over from an earlier run
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 10), "idle bar with start on the Zeit tab")
        shot("ux3-nowbar-idle")
        el("nowbar.start").tap()
        // The throwaway seed has entries for today until 16:00; a start inside them is refused by the server (overlap), not by the bar.
        if !el("nowbar.stop").waitForExistence(timeout: 8), app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'überschneidet'")).firstMatch.exists {
            throw XCTSkip("seed data overlaps the current time")
        }
        XCTAssertTrue(el("nowbar.stop").exists, "running bar with stop")
        XCTAssertGreaterThanOrEqual(el("nowbar.stop").frame.height, 44, "hit target of at least 44 pt")
        XCTAssertGreaterThanOrEqual(el("nowbar.stop").frame.width, 44)
        shot("ux3-nowbar-running")
        // The bar follows to other tabs.
        app.tabBars.buttons["Mehr"].tap()
        XCTAssertTrue(el("nowbar.stop").exists)
        // Tapping the clock side opens "Heute". H1: there the timer card is the only start/stop control, the bar is gone.
        el("nowbar.open").tap()
        XCTAssertTrue(app.buttons["today.stop"].waitForExistence(timeout: 10))
        XCTAssertFalse(el("nowbar.stop").exists, "no second stop control on Heute")
        XCTAssertGreaterThanOrEqual(app.buttons["today.stop"].frame.height, 44)
        shot("h1-today-running")
        app.buttons["today.stop"].tap()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 10))
        XCTAssertFalse(el("nowbar.start").exists, "no second start control on Heute")
        XCTAssertGreaterThanOrEqual(app.buttons["today.start"].frame.height, 44)
        shot("h1-today-idle")
        // Back on another tab the bar is there again.
        app.tabBars.buttons["Zeit"].tap()
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 10))
    }

    func testMoreCollectsSettingsAutomationAndReminders() {
        app.openMore()
        XCTAssertTrue(el("more.settings").waitForExistence(timeout: 10))
        XCTAssertTrue(el("settings.overwork").exists, "reminders group")
        XCTAssertTrue(el("settings.calendar").exists, "automation and calendar group")
        shot("ux3-more")
        el("more.settings").tap()
        XCTAssertTrue(el("settings.sign_out").waitForExistence(timeout: 10))
        XCTAssertTrue(el("settings.appearance").exists, "S2 structure intact")
        XCTAssertFalse(el("settings.automation").exists, "automation moved to Mehr")
    }

    func testDayCardExplainsTermsAndShowsNoFalseDeficit() {
        // Morning without an entry: neither a difference nor a percentage; the ring is only a picture.
        XCTAssertTrue(el("today.standing").waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Differenz"].exists)
        el("today.terms").tap()
        XCTAssertTrue(app.staticTexts["Zeitkonto"].waitForExistence(timeout: 5))
        shot("ux3-today-terms")
    }
}
