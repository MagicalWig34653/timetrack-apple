import XCTest

/// H4: a running timer must survive every way of leaving "Heute" and coming back (other tabs, pushed screens, the "Jetzt" sheet,
/// the Zeit day details, background/foreground). Needs a THROWAWAY backend (TT_DEV_SERVER / TT_DEV_COOKIE); skipped otherwise.
/// iPhone only (tab bar).
final class RunningTimerSurvivesNavigationTests: XCTestCase {
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

    private func tab(_ title: String) { app.tabBars.buttons[title].tap() }

    /// Starts a timer (stopping a leftover first) and skips if the seed data overlaps the current time.
    private func startTimer() throws {
        if el("nowbar.stop").waitForExistence(timeout: 3) { el("nowbar.stop").tap() }
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 10))
        el("nowbar.start").tap()
        if !el("nowbar.stop").waitForExistence(timeout: 8), app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'überschneidet'")).firstMatch.exists {
            throw XCTSkip("seed data overlaps the current time")
        }
        XCTAssertTrue(el("nowbar.stop").exists)
    }

    /// Back on "Heute": the timer still runs, immediately and after the screen's own reload had time to finish.
    private func assertStillRunning(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
        tab("Heute")
        XCTAssertTrue(el("nowbar.stop").waitForExistence(timeout: 10), "\(step): bar shows a running timer", file: file, line: line)
        XCTAssertTrue(el("today.clock").exists, step, file: file, line: line)
        sleep(3) // the reload started by returning to the screen completes
        XCTAssertTrue(el("nowbar.stop").exists, "\(step): still running after the reload", file: file, line: line)
        XCTAssertFalse(el("nowbar.start").exists, "\(step): no start control while running", file: file, line: line)
    }

    func testRunningTimerSurvivesLeavingAndReturning() throws {
        try startTimer()

        // 1. Other tabs and back (several round trips; each one reloads Heute).
        for name in ["Zeit", "Urlaub", "Mehr", "Zeit"] where app.tabBars.buttons[name].exists {
            tab(name)
            assertStillRunning("tab \(name)")
        }

        // 2. Jetzt sheet from Heute and from another tab, closed with "Fertig" and by swiping down.
        tab("Heute")
        el("today.clock").tap()
        XCTAssertTrue(el("nowsheet.stop").waitForExistence(timeout: 10))
        el("nowsheet.done").tap()
        assertStillRunning("sheet from the clock card")
        tab("Zeit")
        el("nowbar.open").tap()
        XCTAssertTrue(el("nowsheet.stop").waitForExistence(timeout: 10))
        app.swipeDown(velocity: .fast)
        assertStillRunning("sheet swiped away on Zeit")

        // 3. Zeit tab: day details, then back to Heute.
        tab("Zeit")
        _ = el("day.actions").waitForExistence(timeout: 5)
        assertStillRunning("Zeit day details")

        // 4. Pushed screens: Mehr > Einstellungen, then back.
        app.openSettings()
        XCTAssertTrue(el("nowbar.stop").exists)
        if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        assertStillRunning("settings pushed and popped")

        // 5. Background and foreground.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        assertStillRunning("background and foreground")

        // 6. Pull to refresh on Heute.
        app.swipeDown(velocity: .slow)
        assertStillRunning("pull to refresh")

        el("nowbar.stop").tap()
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 10))
    }
}
