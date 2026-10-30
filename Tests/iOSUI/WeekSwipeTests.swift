import XCTest

/// V5: swiping the week header / day strip changes the week (skipped without TT_DEV_SERVER).
final class WeekSwipeTests: XCTestCase {
    private var app: XCUIApplication!

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-time.zoom", "week"]
        app.launch()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
        let tab = app.tabBars.buttons["Zeit"]
        if tab.exists { tab.tap() } else { el("sidebar.time").tap() }
    }

    private func shot(_ name: String) {
        let env = ProcessInfo.processInfo.environment
        let dir = env["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(env["TT_SHOT_PREFIX"] ?? "v5")-\(name).png"))
    }

    private func title() -> String { el("calendar.title").label }

    func testSwipeOnStripSwitchesWeeks() throws {
        try launch()
        XCTAssertTrue(el("calendar.title").waitForExistence(timeout: 20))
        let start = title()
        sleep(2)
        shot("week-before")
        // Swipe left on the strip = next week.
        el("week.pages").swipeLeft()
        XCTAssertTrue(waitForTitle(notEqualTo: start), "swipe left did not change the week")
        let next = title()
        sleep(1)
        shot("week-next")
        // Swipe right = back.
        el("week.pages").swipeRight()
        XCTAssertTrue(waitForTitle(equalTo: start), "swipe right did not return to the first week")
        XCTAssertNotEqual(next, start)
        // The buttons keep working.
        el("calendar.next").tap()
        XCTAssertTrue(waitForTitle(notEqualTo: start))
        el("time.today").tap()
        XCTAssertTrue(waitForTitle(equalTo: start))
    }

    /// A day of the strip (the ids are the ISO dates of the shown week).
    private func stripElement() -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'strip.'")
        let first = app.descendants(matching: .any).matching(predicate).element(boundBy: 3)
        _ = first.waitForExistence(timeout: 10)
        return first
    }

    private func waitForTitle(notEqualTo old: String) -> Bool {
        let end = Date().addingTimeInterval(8)
        while Date() < end { if title() != old { return true }; usleep(200_000) }
        return false
    }

    private func waitForTitle(equalTo value: String) -> Bool {
        let end = Date().addingTimeInterval(8)
        while Date() < end { if title() == value { return true }; usleep(200_000) }
        return false
    }
}
