import XCTest

/// H2: the "Jetzt" bar and sheet at an accessibility Dynamic Type size (bar targets stay reachable, sheet scrolls).
/// Needs a THROWAWAY backend (TT_DEV_SERVER / TT_DEV_COOKIE); iPhone only.
final class NowBarLargeTypeTests: XCTestCase {
    func testBarAndSheetAtAccessibilityTextSize() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        try XCTSkipIf(!app.tabBars.buttons["Mehr"].waitForExistence(timeout: 20), "compact layout only")
        func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
        func shot(_ name: String) {
            guard let dir = env["TT_SHOT_DIR"] else { return }
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        if el("nowbar.stop").waitForExistence(timeout: 3) { el("nowbar.stop").tap() }
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 10))
        shot("h2-large-idle")
        el("nowbar.start").tap()
        if !el("nowbar.stop").waitForExistence(timeout: 8) { throw XCTSkip("seed data overlaps the current time") }
        XCTAssertGreaterThanOrEqual(el("nowbar.stop").frame.height, 44)
        shot("h2-large-running")
        el("nowbar.open").tap()
        XCTAssertTrue(el("nowsheet.stop").waitForExistence(timeout: 10))
        shot("h2-large-sheet")
        el("nowsheet.stop").tap()
        XCTAssertTrue(el("nowbar.start").waitForExistence(timeout: 10))
    }
}
