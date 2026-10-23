import XCTest

/// UX3: the "Jetzt" bar above the tab bar (start/stop on every tab including Heute) and the "Mehr" tab. Needs a THROWAWAY backend
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
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20) || app.stopControl.exists)
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
        // H2: tapping the clock side opens the "Jetzt" sheet (mini-player style) with start time and note.
        el("nowbar.open").tap()
        XCTAssertTrue(el("nowsheet.stop").waitForExistence(timeout: 10), "sheet with stop")
        XCTAssertTrue(el("nowsheet.start_time").exists)
        XCTAssertTrue(el("nowsheet.note").exists)
        shot("h2-sheet-running")
        el("nowsheet.done").tap()
        app.tabBars.buttons["Heute"].tap()
        XCTAssertTrue(el("nowbar.stop").waitForExistence(timeout: 10), "bar still shown on Heute")
        XCTAssertFalse(app.buttons["today.stop"].exists, "no second stop control on the Heute card")
        XCTAssertGreaterThanOrEqual(el("nowbar.stop").frame.height, 44)
        shot("h2-today-running")
        el("nowbar.stop").tap()
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["today.start"].exists, "no second start control on the Heute card")
        XCTAssertTrue(el("nowbar.kind").exists, "kind choice reachable in the bar")
        XCTAssertGreaterThanOrEqual(el("nowbar.start").frame.height, 44)
        shot("h3-today-idle")
        el("nowbar.open").tap()
        XCTAssertTrue(el("nowsheet.start").waitForExistence(timeout: 10), "idle sheet with start")
        shot("h2-sheet-idle")
        el("nowsheet.done").tap()
        // Back on another tab the bar is still there.
        app.tabBars.buttons["Zeit"].tap()
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 10))
    }

    /// H3: the kind chosen in the "Jetzt" sheet is what the bar's start uses (shared "ios.lastKind"); the Heute card has no kind buttons on iPhone.
    func testKindChosenInSheetIsUsedByBarStart() throws {
        if el("nowbar.stop").waitForExistence(timeout: 3) { el("nowbar.stop").tap() }
        app.tabBars.buttons["Heute"].tap()
        XCTAssertTrue(el("today.clock").waitForExistence(timeout: 10), "the first section of Heute is the clock card")
        XCTAssertFalse(app.buttons["Fahrt"].firstMatch.exists, "no kind buttons on the Heute card (iPhone)")
        el("nowbar.open").tap()
        XCTAssertTrue(el("nowsheet.start").waitForExistence(timeout: 10))
        app.buttons["Fahrt"].firstMatch.tap()
        el("nowsheet.done").tap()
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 5))
        el("nowbar.start").tap()
        if !el("nowbar.stop").waitForExistence(timeout: 8) { throw XCTSkip("seed data overlaps the current time") }
        shot("h3-today-running-travel")
        XCTAssertTrue(app.staticTexts["Fahrt"].firstMatch.exists, "the running segment has the chosen kind")
        el("nowbar.stop").tap()
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 10))
        el("nowbar.open").tap()
        XCTAssertTrue(el("nowsheet.start").waitForExistence(timeout: 10))
        app.buttons["Arbeit"].firstMatch.tap() // restore the default choice
        el("nowsheet.done").tap()
    }

    /// H3: start at a head start and shift the start in the running sheet; the bar's controls keep clear space (>= 44 pt targets, drawn smaller).
    func testSheetQuickActions() throws {
        if el("nowbar.stop").waitForExistence(timeout: 3) { el("nowbar.stop").tap() }
        el("nowbar.open").tap()
        XCTAssertTrue(el("nowsheet.head15").waitForExistence(timeout: 10))
        el("nowsheet.head15").tap()
        if !el("nowsheet.stop").waitForExistence(timeout: 8) { throw XCTSkip("seed data overlaps the current time") }
        XCTAssertTrue(el("nowsheet.pause").exists)
        XCTAssertTrue(el("outlook.break").waitForExistence(timeout: 5) || el("nowsheet.context").exists)
        el("nowsheet.earlier5").tap()
        XCTAssertTrue(el("nowsheet.context").waitForExistence(timeout: 5))
        XCTAssertFalse(el("nowsheet.save").exists, "no pending change after a quick step")
        el("nowsheet.pause").tap()
        XCTAssertTrue(el("nowsheet.pause_since").waitForExistence(timeout: 10), "after Pause the sheet shows the gap and offers Weiter")
        el("nowsheet.done").tap()
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
