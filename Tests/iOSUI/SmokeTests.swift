import XCTest

/// Smoke test against a THROWAWAY backend. Needs TT_DEV_SERVER and TT_DEV_COOKIE in the test runner's environment
/// (xcodebuild passes `TEST_RUNNER_TT_DEV_SERVER` / `TEST_RUNNER_TT_DEV_COOKIE`); skipped otherwise.
/// Use seed-throwaway.py --no-today so the timer can start at any time of day.
final class SmokeTests: XCTestCase {
    func testTimerAndTabs() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-time.zoom", "month"]
        app.launch()

        let start = app.startControl
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        XCTAssertTrue(app.stopControl.waitForExistence(timeout: 10))
        shot("running")
        app.stopControl.tap()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 10))

        open(app, "Zeit", "time")
        XCTAssertTrue(app.buttons["time.new"].waitForExistence(timeout: 10))
        shot("time")
        app.buttons["time.new"].tap()
        XCTAssertTrue(app.buttons["Sichern"].waitForExistence(timeout: 5))
        shot("editor")
        app.buttons["Abbrechen"].tap()

        open(app, "Urlaub", "vacation")
        XCTAssertTrue(app.staticTexts["Urlaubskonto"].waitForExistence(timeout: 10))
        shot("vacation")

        app.openSettings()
        XCTAssertTrue(app.buttons["settings.sign_out"].waitForExistence(timeout: 5))
        shot("settings")
    }

    /// iPhone: tab bar button; iPad (regular width): sidebar row.
    private func open(_ app: XCUIApplication, _ title: String, _ id: String) {
        let tab = app.tabBars.buttons[title]
        if tab.exists { tab.tap() } else { app.descendants(matching: .any)["sidebar.\(id)"].firstMatch.tap() }
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
