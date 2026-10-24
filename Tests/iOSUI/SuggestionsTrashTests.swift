import XCTest

/// SG1: automation suggestions (Mehr › Zu prüfen) and the bin of cancelled entries (Mehr › Storniert). Needs a THROWAWAY backend seeded
/// with `scripts/seed-sg1.py` (two open start suggestions, three cancelled entries of which one overlaps a live entry).
/// Screenshots go to TT_SHOT_DIR when set. iPhone layout (tab bar).
final class SuggestionsTrashTests: XCTestCase {
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func launch() throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        try XCTSkipIf(!app.tabBars.buttons.element(boundBy: 0).waitForExistence(timeout: 20), "compact layout only")
        return app
    }

    private func count(_ app: XCUIApplication, _ id: String) -> Int { app.descendants(matching: .any).matching(identifier: id).count }

    private func waitUntil(_ timeout: TimeInterval = 15, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { Thread.sleep(forTimeInterval: 0.3) }
        return condition()
    }

    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        var tries = 0
        while !element.isHittable, tries < 6 { app.swipeUp(); tries += 1 }
    }

    func testSuggestionsAdjustAndAccept() throws {
        continueAfterFailure = false
        let app = try launch()
        app.openMore()
        let row = el(app, "more.review")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil { row.value as? String == "2 zu prüfen" } || row.exists)
        shot("sg1-more")
        row.tap()
        XCTAssertTrue(el(app, "review.sheet").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "suggestion.item").waitForExistence(timeout: 10))
        XCTAssertEqual(count(app, "suggestion.item"), 2)
        XCTAssertTrue(app.staticTexts["Du bist bei „Kunde Nord“ angekommen."].exists)
        shot("sg1-suggestions")

        // Adjust the first (earliest) suggestion: add an end, so it becomes a finished entry instead of a running timer.
        el(app, "suggestion.adjust").tap()
        XCTAssertTrue(el(app, "suggestion.adjust.sheet").waitForExistence(timeout: 10))
        app.switches.firstMatch.tap()
        shot("sg1-adjust")
        el(app, "suggestion.adjust.accept").tap()
        XCTAssertTrue(waitUntil { self.count(app, "suggestion.item") == 1 }, "the adjusted suggestion leaves the list")

        // The other one would start a timer on 4 October that runs into the seeded entries of later days: the server refuses (409),
        // the suggestion stays and the error is explained. Rejecting it then books nothing.
        el(app, "suggestion.accept").tap()
        XCTAssertTrue(app.staticTexts["Der Eintrag überschneidet sich mit einem anderen."].waitForExistence(timeout: 10))
        XCTAssertEqual(count(app, "suggestion.item"), 1)
        shot("sg1-accept-refused")
        el(app, "suggestion.reject").tap()
        XCTAssertTrue(waitUntil { self.count(app, "suggestion.item") == 0 }, "the rejected suggestion leaves the list")
        XCTAssertTrue(app.staticTexts["Nichts zu prüfen"].waitForExistence(timeout: 10))
        shot("sg1-suggestions-empty")
    }

    func testCancelledBinRestoreConflictAndPurge() throws {
        continueAfterFailure = false
        let app = try launch()
        app.openMore()
        let row = el(app, "more.cancelled")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(el(app, "cancelled.screen").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "cancelled.item").waitForExistence(timeout: 10))
        XCTAssertEqual(count(app, "cancelled.item"), 3)
        shot("sg1-cancelled")

        // The oldest entry overlaps a live one: restoring is refused with an explanation, the entry stays.
        let restores = app.buttons.matching(identifier: "cancelled.restore")
        let overlapping = restores.element(boundBy: 2)
        scrollTo(app, overlapping)
        overlapping.tap()
        XCTAssertTrue(el(app, "cancelled.restore_failure").waitForExistence(timeout: 10))
        XCTAssertEqual(count(app, "cancelled.item"), 3)
        shot("sg1-restore-conflict")

        // The newest one restores cleanly.
        app.swipeDown(); app.swipeDown()
        restores.element(boundBy: 0).tap()
        XCTAssertTrue(waitUntil { self.count(app, "cancelled.item") == 2 }, "the restored entry leaves the bin")
        XCTAssertTrue(el(app, "cancelled.note").exists)

        // Permanent deletion: dry-run numbers first, the typed word unlocks the button.
        scrollTo(app, app.buttons.matching(identifier: "cancelled.purge").element(boundBy: 0))
        app.buttons.matching(identifier: "cancelled.purge").element(boundBy: 0).tap()
        XCTAssertTrue(el(app, "purge.sheet").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "purge.summary").waitForExistence(timeout: 10))
        let confirm = el(app, "purge.confirm")
        XCTAssertFalse(confirm.isEnabled)
        shot("sg1-purge")
        let field = app.textFields["purge.word"].exists ? app.textFields["purge.word"] : el(app, "purge.word")
        field.tap()
        field.typeText("löschen")
        XCTAssertTrue(waitUntil { confirm.isEnabled })
        shot("sg1-purge-typed")
        confirm.tap()
        XCTAssertTrue(waitUntil { self.count(app, "cancelled.item") == 1 }, "the deleted entry is gone")
        shot("sg1-cancelled-after")
    }
}
