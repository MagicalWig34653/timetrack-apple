import XCTest

/// BH1: Berichtsheft smoke flow against a throwaway backend seeded with learning fields and entries (see docs/handoffs/BH1.md).
/// TT_SHOT_DIR/TT_SHOT_PREFIX write screenshots; without them the shots go to the temporary directory.
final class ReportsTests: XCTestCase {
    private var app: XCUIApplication!

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch() throws {
        let env = ProcessInfo.processInfo.environment
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        app.launchEnvironment["TT_DEV_COOKIE"] = try XCTUnwrap(env["TT_DEV_COOKIE"])
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        if let size = env["TT_TEXT_SIZE"] { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
    }

    private func shot(_ name: String) {
        let env = ProcessInfo.processInfo.environment
        let dir = env["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(env["TT_SHOT_PREFIX"] ?? "bh1")-\(name).png"))
    }

    private func openReports() {
        app.openMore()
        let row = el("more.reports")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(el("reports.title").waitForExistence(timeout: 15))
    }

    func testWeekEditorCopyAndFields() throws {
        try launch()
        openReports()
        XCTAssertTrue(app.staticTexts["Rechner installiert und Benutzerkonten angelegt."].waitForExistence(timeout: 10))
        shot("week")

        // New entry: autosave creates it without a save button.
        el("reports.new").tap()
        let field = el("reports.entry.field")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Eigenes Thema")
        let duration = el("reports.entry.duration")
        duration.tap(); duration.typeText("1,5")
        let saved = el("reports.entry.state")
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'Gesichert'").evaluate(with: saved) || saved.waitForExistence(timeout: 5))
        sleep(3)
        shot("editor")
        el("reports.entry.done").tap()
        XCTAssertTrue(app.staticTexts["Eigenes Thema"].waitForExistence(timeout: 10))

        // Copy for the IHK portal.
        el("reports.copy").tap()
        XCTAssertTrue(el("reports.copy.text").waitForExistence(timeout: 10))
        shot("copy")
        XCTAssertTrue(el("reports.copy.action").exists && el("reports.copy.share").exists)
        el("reports.copy.done").tap()

        // Learning fields.
        el("reports.fields").tap()
        XCTAssertTrue(app.staticTexts["Netzwerke planen"].waitForExistence(timeout: 10))
        shot("fields")
    }
}
