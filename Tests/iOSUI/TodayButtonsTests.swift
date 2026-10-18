import XCTest

/// T2: the action buttons on "Heute" keep single-line labels and a tap height of at least 44 pt, at the default and a large text size.
/// Also stores screenshots in TT_SHOT_DIR (prefix TT_SHOT_PREFIX). Needs the throwaway server environment; skipped otherwise.
/// TT_TEXT_SIZE (e.g. UICTContentSizeCategoryXXXL) overrides the app text size for the run.
final class TodayButtonsTests: XCTestCase {
    func testTodayButtonsAreSingleLineAndTappable() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        let prefix = env["TT_SHOT_PREFIX"] ?? "t2"
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        if let size = env["TT_TEXT_SIZE"] { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()

        let start = app.buttons["today.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        sleep(1)
        shot("\(prefix)-today-top")
        XCTAssertGreaterThanOrEqual(start.frame.height, 43.9)

        let sick = app.buttons["today.quick.sick"]
        let tabTop = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
        for _ in 0..<5 where !sick.exists || sick.frame.maxY > tabTop - 8 { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(sick.exists)
        sleep(1)
        shot("\(prefix)-today-quick")
        let accessibilitySize = (env["TT_TEXT_SIZE"] ?? "").contains("Accessibility")
        for id in ["today.quick.sick", "today.quick.vacation", "today.quick.more"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.exists, id)
            XCTAssertGreaterThanOrEqual(button.frame.height, 43.9, "\(id) tap height")
            // Padding sits inside the minimum height: one text line stays at ~44-50 pt up to the largest non-accessibility size,
            // a wrapped label would add a second line (>= 20 pt) on top.
            if !accessibilitySize, id != "today.quick.more" { XCTAssertLessThan(button.frame.height, 58, "\(id) label wraps") }
        }
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
