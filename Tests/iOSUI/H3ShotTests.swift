import XCTest

/// H3: gallery of the redesigned bar, "Jetzt" sheet and "Heute" top (light, dark, large Dynamic Type) plus the behaviour of the sheet's
/// quick actions. Needs a THROWAWAY backend (TT_DEV_SERVER / TT_DEV_COOKIE); screenshots go to TT_SHOT_DIR when set. iPhone only.
final class H3ShotTests: XCTestCase {
    private func launch(_ extra: [String] = []) throws -> XCUIApplication {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"] + extra
        app.launch()
        try XCTSkipIf(!app.tabBars.buttons["Mehr"].waitForExistence(timeout: 20), "compact layout only")
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func expandSheet(_ app: XCUIApplication) {
        let bar = app.navigationBars["Jetzt"]
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)))
    }

    private func tour(_ app: XCUIApplication, prefix: String) throws {
        if el(app, "nowbar.stop").waitForExistence(timeout: 3) { el(app, "nowbar.stop").tap() }
        XCTAssertTrue(el(app, "nowbar.start").waitForExistence(timeout: 10))
        shot("\(prefix)-today-idle")
        el(app, "nowbar.open").tap()
        XCTAssertTrue(el(app, "nowsheet.start").waitForExistence(timeout: 10))
        shot("\(prefix)-sheet-idle")
        expandSheet(app)
        shot("\(prefix)-sheet-idle-large")
        // Start with a 15 minute head start: the running entry begins 15 minutes ago.
        el(app, "nowsheet.head15").tap()
        guard el(app, "nowsheet.stop").waitForExistence(timeout: 10) else { throw XCTSkip("seed data overlaps the current time") }
        XCTAssertTrue(el(app, "nowsheet.pause").exists, "work entries offer a pause")
        XCTAssertTrue(el(app, "nowsheet.earlier5").exists)
        shot("\(prefix)-sheet-running")
        el(app, "nowsheet.earlier5").tap()
        XCTAssertTrue(el(app, "nowsheet.context").exists)
        expandSheet(app)
        shot("\(prefix)-sheet-running-large")
        el(app, "nowsheet.done").tap()
        XCTAssertTrue(el(app, "today.clock").waitForExistence(timeout: 5), "Heute starts with the clock card")
        XCTAssertFalse(app.buttons["today.start"].exists || app.buttons["today.stop"].exists, "no start/stop on the card on iPhone")
        shot("\(prefix)-today-running")
        el(app, "nowbar.stop").tap()
        XCTAssertTrue(el(app, "toast.stopped").waitForExistence(timeout: 5), "banner with Weiter after a stop")
        shot("\(prefix)-toast")
        XCTAssertTrue(el(app, "nowbar.start").waitForExistence(timeout: 10))
        shot("\(prefix)-today-after-stop")
    }

    func testLight() throws { try tour(try launch(), prefix: "h3-light") }
    func testDark() throws { try tour(try launch(), prefix: "h3-dark") }
    func testLargeType() throws {
        try tour(try launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]), prefix: "h3-large")
    }
}
