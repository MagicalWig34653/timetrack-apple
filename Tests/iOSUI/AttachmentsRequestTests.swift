import XCTest

/// AB1: add and delete an absence attachment, 413 error with retry state, fill the vacation request PDF and save it as an attachment,
/// against the throwaway backend (seed-throwaway.py + seed-vacation-v3.py + seed-ab1.py; skipped without TT_DEV_SERVER).
/// The system pickers cannot be driven, so the debug build adds `TT_DEV_ATTACH_FILE` like a pick would (TT_AB1_FILE maps to it).
/// Screenshots go to TT_SHOT_DIR (prefix TT_SHOT_PREFIX).
final class AttachmentsRequestTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "ab1"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch(attach file: String? = nil) throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "ab1"
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        if let file { app.launchEnvironment["TT_DEV_ATTACH_FILE"] = file }
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-vacation.absenceListOptions.v1", ""]
        if let scheme = env["TT_SHOT_SCHEME"] { app.launchArguments += ["-appearance.scheme", scheme] }
        app.launch()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }

    private func openVacation() {
        let tab = app.tabBars.buttons["Urlaub"]
        if tab.exists { tab.tap() } else { el("sidebar.vacation").tap() }
        XCTAssertTrue(app.staticTexts["Urlaubskonto"].waitForExistence(timeout: 10))
        XCTAssertTrue(el("absence.filter").waitForExistence(timeout: 10))
    }

    /// The absence list is long; scrolls until the row of the given kind (title text) is visible and returns its paperclip.
    private func paperclip(ofRowNamed title: String) -> XCUIElement {
        let row = app.buttons.matching(identifier: "absence.row").matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), title)
        // The paperclip is the sibling right of the row; take the one with the smallest vertical distance.
        let candidates = app.descendants(matching: .any).matching(identifier: "absence.attachments").allElementsBoundByIndex
        return candidates.min { abs($0.frame.midY - row.frame.midY) < abs($1.frame.midY - row.frame.midY) }!
    }

    func testAddAndDeleteAnAttachment() throws {
        let file = try XCTUnwrap(ProcessInfo.processInfo.environment["TT_AB1_PDF"], "no sample pdf")
        try launch(attach: file)
        openVacation()
        paperclip(ofRowNamed: "Sonstiges").tap()
        XCTAssertTrue(el("attachments.done").waitForExistence(timeout: 5))
        shot("attachments-add")
        let uploaded = app.buttons.matching(identifier: "attachment.row").firstMatch
        XCTAssertTrue(uploaded.waitForExistence(timeout: 15), "the picked file is uploaded and listed")
        XCTAssertTrue(uploaded.label.contains("krankschein.pdf"), uploaded.label)
        XCTAssertFalse(el("attachments.upload").exists, "the pending entry is gone after the upload")
        shot("attachments-uploaded")

        // opens in QuickLook
        uploaded.tap()
        XCTAssertTrue(app.staticTexts["Krankschein (synthetisch)"].waitForExistence(timeout: 10) || app.otherElements["QLPreviewControllerView"].exists || app.buttons["Done"].exists || app.buttons["Fertig"].exists)
        for name in ["Schließen", "Close", "Fertig", "Done"] where app.buttons[name].exists { app.buttons[name].tap(); break }
        XCTAssertTrue(el("attachment.delete").waitForExistence(timeout: 5), "back in the attachment list")

        // delete with confirmation (the list may hold leftovers of earlier runs, so the count must drop by one)
        let before = app.buttons.matching(identifier: "attachment.row").count
        el("attachment.delete").tap()
        let confirm = app.buttons["Löschen"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot("attachments-delete-confirm")
        confirm.tap()
        let gone = NSPredicate { _, _ in self.app.buttons.matching(identifier: "attachment.row").count == before - 1 }
        wait(for: [XCTNSPredicateExpectation(predicate: gone, object: nil)], timeout: 10)
        XCTAssertEqual(app.buttons.matching(identifier: "attachment.row").count, before - 1, "the attachment is gone")
    }

    func testServerLimitShowsAFailedEntry() throws {
        let file = try XCTUnwrap(ProcessInfo.processInfo.environment["TT_AB1_BIG"], "no big file")
        try launch(attach: file)
        openVacation()
        paperclip(ofRowNamed: "Sonstiges").tap()
        let failed = el("attachments.upload")
        XCTAssertTrue(failed.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'zu groß'")).firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(el("attachments.retry").exists, "a file the server rejects is not offered for retry")
        shot("attachments-too-large")
        el("attachments.dismiss").tap()
        XCTAssertTrue(failed.waitForNonExistence(timeout: 5))
    }

    func testFillTheVacationRequestAndSaveItAsAttachment() throws {
        try launch()
        openVacation()
        paperclip(ofRowNamed: "Urlaub").tap() // the vacation rows have a menu with attachments and request
        let action = el("absence.action.request")
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        shot("row-menu")
        action.tap()
        XCTAssertTrue(el("request.generate").waitForExistence(timeout: 15), "template, balance and calendar loaded")
        XCTAssertTrue(el("request.working_days").exists)
        el("request.substitute").tap()
        el("request.substitute").typeText("Erika Beispiel")
        shot("request-form")
        el("request.generate").tap()
        XCTAssertTrue(el("request.ready").waitForExistence(timeout: 20))
        for _ in 0..<3 where !el("request.attach").isHittable { app.swipeUp() }
        shot("request-result")
        el("request.attach").tap()
        XCTAssertTrue(el("request.attached").waitForExistence(timeout: 20), "saved as attachment")
        shot("request-attached")
    }

    func testNoTemplateIsExplained() throws {
        try launch()
        // The throwaway server has a template; this test only runs when the seed removed it (TT_AB1_NO_TEMPLATE=1).
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TT_AB1_NO_TEMPLATE"] == "1")
        openVacation()
        paperclip(ofRowNamed: "Urlaub").tap()
        el("absence.action.request").tap()
        XCTAssertTrue(el("request.no_template").waitForExistence(timeout: 15))
        shot("request-no-template")
    }
}
