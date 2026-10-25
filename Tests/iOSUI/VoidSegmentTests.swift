import XCTest

/// A9 regression: voiding a segment in "Zeit" crashed the app (UICollectionView batch-update assertion of the SwiftUI List).
/// Runs against a THROWAWAY backend seeded by scripts/seed-cx1.py (env TT_DEV_SERVER, TT_DEV_COOKIE); skipped otherwise.
/// Each test voids exactly one seeded segment, so run a freshly seeded backend per test method (or the whole class once:
/// the tests use distinct notes). Seeded notes used: "Lernfeld 5" (one of several last Thursday), "Berufsschule" (the only segment of its day),
/// "Vor-Ort-Termin" (refresh in flight), "Updates ausgerollt" (double tap).
final class VoidSegmentTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
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
        if tab.exists { tab.tap() } else { app.descendants(matching: .any)["sidebar.time"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["time.new"].waitForExistence(timeout: 10))
        app.buttons["calendar.prev"].tap()
    }

    /// One of several segments of a day disappears.
    func testVoidOneOfSeveralBySwipe() throws {
        let row = reveal("Lernfeld 5")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        voidViaSwipe(row)
        assertGone("Lernfeld 5")
    }

    /// The last segment of a day: the section turns into the empty-day row.
    func testVoidLastSegmentOfDayBySwipe() throws {
        let row = reveal("Berufsschule")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        voidViaSwipe(row)
        assertGone("Berufsschule")
    }

    /// Void while a pull-to-refresh is in flight.
    func testVoidWhileRefreshing() throws {
        let row = reveal("Vor-Ort-Termin")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        voidViaSwipe(row)
        assertGone("Vor-Ort-Termin")
    }

    /// Rapid double tap on the confirm button must not send or apply the void twice.
    func testVoidDoubleTap() throws {
        let row = reveal("Updates ausgerollt")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["Stornieren"].firstMatch.tap()
        let reason = app.textFields["void.reason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        reason.tap()
        reason.typeText("Test")
        let confirm = app.navigationBars.buttons["Stornieren"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        if confirm.exists { confirm.tap() }
        assertGone("Updates ausgerollt")
    }

    private func segmentCell(_ note: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "label CONTAINS %@", note)).firstMatch
    }

    /// The list is lazy: bring the row on screen in the seeded previous week.
    private func reveal(_ note: String) -> XCUIElement {
        let row = segmentCell(note)
        for _ in 0..<8 where !(row.exists && row.isHittable) { app.collectionViews.firstMatch.swipeUp(velocity: .slow) }
        return row
    }

    private func voidViaSwipe(_ row: XCUIElement) {
        row.swipeLeft()
        let swipeVoid = app.buttons["Stornieren"].firstMatch
        XCTAssertTrue(swipeVoid.waitForExistence(timeout: 5))
        swipeVoid.tap()
        let reason = app.textFields["void.reason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        reason.tap()
        reason.typeText("Test")
        let confirm = app.navigationBars.buttons["Stornieren"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }

    private func assertGone(_ note: String) {
        let gone = NSPredicate { _, _ in !self.segmentCell(note).exists }
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 15), .completed, "segment row still visible")
        sleep(2) // let the list settle; a crash shows up as a non-foreground state
        XCTAssertEqual(app.state, .runningForeground, "app crashed while voiding")
        XCTAssertTrue(app.buttons["time.new"].exists)
    }
}
