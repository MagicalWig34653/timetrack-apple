import XCTest

/// Visual review helper for the Darstellung page and Heute with a given accent/scheme.
/// Env: TT_DEV_SERVER, TT_DEV_COOKIE (throwaway server), TT_SHOT_DIR, TT_SHOT_PREFIX, TT_SHOT_ACCENT (blue|orange|...), TT_SHOT_SCHEME (system|light|dark).
final class AppearanceShotTests: XCTestCase {
    func testAppearanceWalkthrough() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        let prefix = env["TT_SHOT_PREFIX"] ?? "appearance"
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE",
                               "-appearance.accent", env["TT_SHOT_ACCENT"] ?? "blue", "-appearance.scheme", env["TT_SHOT_SCHEME"] ?? "system"]
        app.launch()

        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20))
        sleep(1)
        shot("\(prefix)-today")
        app.buttons["today.start"].tap()
        XCTAssertTrue(app.buttons["today.stop"].waitForExistence(timeout: 10))
        sleep(2)
        shot("\(prefix)-today-running")
        app.buttons["today.stop"].tap()

        let tab = app.tabBars.buttons["Einstellungen"]
        if tab.exists { tab.tap() } else { app.descendants(matching: .any)["sidebar.settings"].firstMatch.tap() }
        let row = app.buttons["settings.appearance"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        sleep(1)
        shot("\(prefix)-settings")
        row.tap()
        XCTAssertTrue(app.buttons["appearance.accent.orange"].waitForExistence(timeout: 5))
        sleep(1)
        shot("\(prefix)-appearance")
        app.swipeUp()
        sleep(1)
        shot("\(prefix)-appearance-scrolled")
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
