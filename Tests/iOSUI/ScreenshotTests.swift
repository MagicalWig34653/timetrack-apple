import XCTest

/// Visual review helper: walks the main screens and stores PNGs in TT_SHOT_DIR (prefix TT_SHOT_PREFIX).
/// Needs the same throwaway-server environment as the smoke test; skipped otherwise.
final class ScreenshotTests: XCTestCase {
    func testWalkthrough() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        let prefix = env["TT_SHOT_PREFIX"] ?? "shot"
        let wide = env["TT_SHOT_LANDSCAPE"] != nil
        if wide { XCUIDevice.shared.orientation = .landscapeLeft }
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()

        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20))
        sleep(1)
        shot("\(prefix)-today-idle")
        app.swipeUp()
        shot("\(prefix)-today-scrolled")
        app.swipeDown()
        app.buttons["today.start"].tap()
        XCTAssertTrue(app.buttons["today.stop"].waitForExistence(timeout: 10))
        sleep(2)
        shot("\(prefix)-today-running")

        open(app, "Zeit", "time")
        XCTAssertTrue(app.buttons["time.new"].waitForExistence(timeout: 10))
        sleep(1)
        shot("\(prefix)-time")
        app.swipeUp()
        shot("\(prefix)-time-scrolled")
        app.swipeDown()
        app.buttons["time.new"].tap()
        XCTAssertTrue(app.buttons["Sichern"].waitForExistence(timeout: 5))
        sleep(1)
        shot("\(prefix)-editor")
        app.buttons["Abbrechen"].tap()

        open(app, "Urlaub", "vacation")
        XCTAssertTrue(app.staticTexts["Urlaubskonto"].waitForExistence(timeout: 10))
        sleep(1)
        shot("\(prefix)-vacation")
        app.swipeUp()
        shot("\(prefix)-vacation-scrolled")

        open(app, "Einstellungen", "settings")
        XCTAssertTrue(app.buttons["settings.sign_out"].waitForExistence(timeout: 5))
        sleep(1)
        shot("\(prefix)-settings")
        app.swipeUp()
        shot("\(prefix)-settings-scrolled")

        // leave the throwaway server without a running timer
        open(app, "Heute", "today")
        if app.buttons["today.stop"].waitForExistence(timeout: 5) { app.buttons["today.stop"].tap() }
    }

    private func open(_ app: XCUIApplication, _ title: String, _ id: String) {
        let tab = app.tabBars.buttons[title]
        if tab.exists { tab.tap() } else { app.descendants(matching: .any)["sidebar.\(id)"].firstMatch.tap() }
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
