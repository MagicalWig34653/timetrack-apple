import XCTest

/// L2: Standortautomatik settings page, permission state, mode change, new place sheet and the shortcut guide.
/// Needs the throwaway server (TT_DEV_SERVER/TT_DEV_COOKIE) with one place "Büro Test"; TT_EXPECT_PERMISSION is the status text expected
/// for the simulator's current location permission. Screenshots go to TT_SHOT_DIR (prefix TT_SHOT_PREFIX).
final class AutomationFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "auto"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "auto"
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20))
        let tab = app.tabBars.buttons["Einstellungen"]
        if tab.exists { tab.tap() } else { el("sidebar.settings").tap() }
        XCTAssertTrue(el("settings.automation").waitForExistence(timeout: 10))
        el("settings.automation").tap()
        XCTAssertTrue(el("automation.master").waitForExistence(timeout: 10))
    }

    private func scrollTo(_ element: XCUIElement) {
        var tries = 0
        while !element.isHittable && tries < 8 { app.swipeUp(); tries += 1 }
    }

    func testSettingsPage() throws {
        try launch()
        let status = el("automation.permission.status")
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        if let expected = ProcessInfo.processInfo.environment["TT_EXPECT_PERMISSION"] {
            XCTAssertTrue(status.label.contains(expected), "permission status was: \(status.label)")
        }
        sleep(2)
        shot("page-top")
        // The seeded place is listed with its mode picker; switch to "Direkt" and back.
        let picker = el("automation.mode.Büro Test")
        scrollTo(picker)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Direkt"].tap()
        sleep(2)
        XCTAssertTrue(picker.buttons["Direkt"].isSelected)
        picker.buttons["Vorschlag"].tap()
        sleep(1)
        shot("page-places")
        // Wartezeit: a stepper step is applied and shown.
        let dwell = el("automation.dwell")
        scrollTo(dwell)
        dwell.buttons["Increment"].tap()
        sleep(1)
        shot("page-timing")
        app.swipeUp(); app.swipeUp()
        shot("page-bottom")
        // The log page opens.
        let logLink = el("automation.log.link")
        scrollTo(logLink)
        logLink.tap()
        XCTAssertTrue(app.navigationBars["Protokoll"].waitForExistence(timeout: 5))
        shot("log")
    }

    func testNewPlaceSheetAndGuide() throws {
        try launch()
        let new = el("automation.place.new")
        scrollTo(new)
        new.tap()
        XCTAssertTrue(el("automation.newplace.name").waitForExistence(timeout: 5))
        el("automation.newplace.name").tap()
        el("automation.newplace.name").typeText("Zuhause Test")
        el("automation.newplace.locate").tap()
        sleep(4) // permission is granted by the harness; the one-shot fix returns the simulated location
        shot("newplace")
        XCTAssertTrue(el("automation.newplace.save").isEnabled, "location should have been set")
        app.buttons["Abbrechen"].tap()
        // Guide
        let guide = el("automation.shortcuts.link")
        scrollTo(guide)
        guide.tap()
        XCTAssertTrue(el("automation.guide.step1").waitForExistence(timeout: 5))
        sleep(1)
        shot("guide-top")
        app.swipeUp()
        shot("guide-bottom")
        el("automation.guide.trigger").buttons["Abfahrt"].tap()
        app.swipeDown(); app.swipeDown()
        shot("guide-leave")
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }
}
