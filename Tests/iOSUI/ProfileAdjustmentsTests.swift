import XCTest

/// P15: legal profile choice in the work model editor and the list of time account adjustments (book, delete) against a throwaway backend
/// (contract 0.29.0+). TT_SHOT_DIR/TT_SHOT_PREFIX write screenshots; TT_DARK=1 forces dark mode.
final class ProfileAdjustmentsTests: XCTestCase {
    private var app: XCUIApplication!

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch() throws {
        let env = ProcessInfo.processInfo.environment
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        app.launchEnvironment["TT_DEV_COOKIE"] = try XCTUnwrap(env["TT_DEV_COOKIE"])
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        if env["TT_DARK"] == "1" { app.launchArguments += ["-AppleInterfaceStyle", "Dark"] }
        app.launch()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
    }

    private func shot(_ name: String) {
        let env = ProcessInfo.processInfo.environment
        let dir = env["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(env["TT_SHOT_PREFIX"] ?? "p15")-\(name).png"))
    }

    private func scrollTo(_ element: XCUIElement, max: Int = 10) {
        for _ in 0..<max where !element.isHittable { app.swipeUp() }
    }

    /// The editor offers both profiles with the standing notice; choosing the minor profile shows the school explanation.
    func testProfileChoice() throws {
        try launch()
        app.openSettings()
        let row = el("settings.workmodel")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let edit = el("workmodel.edit")
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let minor = el("workmodel.profile.jarbschg-minor-de")
        scrollTo(minor)
        XCTAssertTrue(minor.waitForExistence(timeout: 10))
        XCTAssertTrue(el("workmodel.profile.arbzg-adult-de").exists)
        minor.tap()
        XCTAssertTrue(minor.isSelected)
        app.swipeUp()
        shot("profile")
    }

    /// Books a correction, sees it in the list, deletes it after the confirmation; the balance returns to its old value.
    func testBookAndDeleteAdjustment() throws {
        try launch()
        app.openSettings()
        let row = el("settings.timeaccount")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(el("account.balance").waitForExistence(timeout: 10))
        let before = el("account.balance").label

        let value = el("account.correction.value")
        scrollTo(value)
        value.tap(); value.typeText("1:00")
        let reason = el("account.correction.reason")
        reason.tap(); reason.typeText("Zeitausgleich P15")
        let save = el("account.correction.save")
        scrollTo(save)
        save.tap()
        let book = app.buttons["Buchen"]
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        book.tap()
        XCTAssertTrue(el("account.correction.saved").waitForExistence(timeout: 10))
        let delete = el("account.adjustment.delete")
        scrollTo(delete)
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        shot("list")
        let booked = el("account.balance").label
        XCTAssertNotEqual(booked, before)

        delete.tap()
        let confirm = app.buttons["Löschen"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot("delete-confirm")
        confirm.tap()
        XCTAssertTrue(el("account.adjustments.empty").waitForExistence(timeout: 10))
        XCTAssertEqual(el("account.balance").label, before, "the server recomputed the balance")
        shot("list-empty")
    }
}
