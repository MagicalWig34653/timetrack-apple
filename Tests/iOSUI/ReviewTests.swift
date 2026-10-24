import XCTest

/// Q1: "n zu prüfen" is tappable and opens the review list with reasons and fix actions. Needs a THROWAWAY backend (TT_DEV_SERVER /
/// TT_DEV_COOKIE) with one open automation entry flagged `needs_review` plus an end suggestion, and one ended flagged entry.
/// Screenshots go to TT_SHOT_DIR when set. iPhone only.
final class ReviewTests: XCTestCase {
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testReviewListFromTodayAndTimeTab() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        try XCTSkipIf(!app.tabBars.buttons["Mehr"].waitForExistence(timeout: 20), "compact layout only")

        // Chip on "Heute" is a button and opens the list.
        let chip = el(app, "today.review")
        try XCTSkipUnless(chip.waitForExistence(timeout: 15), "seed has no flagged entry")
        shot("q1-review-today")
        chip.tap()
        XCTAssertTrue(el(app, "review.sheet").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Ende fehlt – Vorschlag der Automatik"].waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "review.accept").exists)
        XCTAssertTrue(el(app, "review.adjust").exists)
        XCTAssertTrue(el(app, "review.delete").exists)
        shot("q1-review-sheet")
        app.swipeUp()
        shot("q1-review-sheet-2")
        app.buttons["Fertig"].tap()

        // Banner at the top of "Zeit".
        app.tabBars.buttons["Zeit"].tap()
        XCTAssertTrue(el(app, "time.review").waitForExistence(timeout: 10))
        shot("q1-review-time")
        el(app, "time.review").tap()
        XCTAssertTrue(el(app, "review.accept").waitForExistence(timeout: 10))

        // Adjust opens the editor with a prefilled end and reason; cancel keeps the item.
        el(app, "review.adjust").tap()
        XCTAssertTrue(app.buttons["Abbrechen"].waitForExistence(timeout: 10))
        shot("q1-review-editor")
        app.buttons["Abbrechen"].tap()
        XCTAssertTrue(el(app, "review.accept").waitForExistence(timeout: 10))

        // Accepting the proposal ends the entry; it leaves the list.
        el(app, "review.accept").tap()
        let deadline = Date().addingTimeInterval(15)
        while el(app, "review.accept").exists, Date() < deadline { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertFalse(el(app, "review.accept").exists, "the accepted entry leaves the list")
        shot("q1-review-after-accept")
    }
}
