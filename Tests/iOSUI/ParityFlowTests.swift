import XCTest

/// N1b: accent grid (22 ids) and glow, work-model correction with preview and confirmation, balance card (R3: tiles removed), entitlement edited in the vacation settings sheet,
/// about section. Needs the throwaway server environment (TT_DEV_SERVER, TT_DEV_COOKIE; the account must be allowed to edit work models
/// and vacation settings); optional TT_SHOT_DIR, TT_SHOT_PREFIX, TT_SHOT_SCHEME (system|light|dark), TT_SHOT_GLOW, TT_SHOT_ACCENT.
final class ParityFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "n1b"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func open(_ title: String, _ id: String) {
        let tab = app.tabBars.buttons[title]
        if tab.exists { tab.tap() } else { el("sidebar.\(id)").tap() }
    }

    /// S2: the vacation settings sheet is reached from Einstellungen › Urlaubsanspruch.
    private func openVacationSettings() {
        app.openSettings()
        scrollTo(el("settings.vacation"))
        el("settings.vacation").tap()
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes { app.swipeUp(); swipes += 1 }
    }

    func testParityFlow() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "n1b"
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        // Launch arguments of UserDefaults keys act as a read-only override, so accent and glow are only forced on request (the flow changes them).
        var arguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-appearance.scheme", env["TT_SHOT_SCHEME"] ?? "system"]
        if let accent = env["TT_SHOT_ACCENT"] { arguments += ["-appearance.accent", accent] }
        if let glow = env["TT_SHOT_GLOW"] { arguments += ["-appearance.glow", glow] }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
        shot("today")

        // Vacation: tiles and the entitlement edit.
        open("Urlaub", "vacation")
        XCTAssertTrue(el("vacation.available.value").waitForExistence(timeout: 10))
        XCTAssertFalse(el("vacation.tile.entitlement").exists, "the five tiles are removed (R3)")
        shot("vacation")
        // R3: the entitlement is edited in the settings sheet (top right), not by a button in the tab.
        XCTAssertFalse(el("vacation.edit_entitlement").exists)
        openVacationSettings()
        let field = el("settings.entitlement")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Alles auswählen"].waitForExistence(timeout: 1) { app.menuItems["Alles auswählen"].tap() }
        field.typeText("28")
        shot("vacation-edit")
        el("settings.save").tap()
        el("settings.done").tap()
        open("Urlaub", "vacation")
        // The tiles are gone (R3); the balance card stays, and the saved entitlement is in the settings sheet.
        XCTAssertTrue(el("vacation.available.value").waitForExistence(timeout: 10))
        XCTAssertFalse(el("vacation.tile.entitlement").exists)
        openVacationSettings()
        let again = el("settings.entitlement")
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertTrue((again.value as? String ?? "").contains("28"), "saved entitlement, got \(String(describing: again.value))")
        el("settings.done").tap()
        open("Urlaub", "vacation")
        shot("vacation-after")

        // Settings: work models.
        app.openSettings()
        let row = el("settings.workmodel")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        shot("settings")
        row.tap()
        let editButton = el("workmodel.edit")
        XCTAssertTrue(editButton.waitForExistence(timeout: 10))
        shot("workmodel-list")
        editButton.tap()
        XCTAssertTrue(el("workmodel.warning").waitForExistence(timeout: 15))
        let weekly = el("workmodel.field.weekly")
        weekly.tap()
        weekly.press(forDuration: 1.0)
        if app.menuItems["Alles auswählen"].waitForExistence(timeout: 1) { app.menuItems["Alles auswählen"].tap() }
        weekly.typeText("34:00")
        let line = el("workmodel.preview.line")
        XCTAssertTrue(line.waitForExistence(timeout: 10), "preview must appear")
        let save = el("workmodel.save")
        XCTAssertFalse(save.isEnabled, "saving needs the confirmation")
        shot("workmodel-edit")
        let confirm = app.switches["workmodel.confirm"]
        scrollTo(confirm, maxSwipes: 2)
        if confirm.exists { confirm.switches.firstMatch.exists ? confirm.switches.firstMatch.tap() : confirm.tap() }
        scrollTo(save)
        XCTAssertTrue(save.isEnabled, "confirmed and previewed: saving is possible")
        shot("workmodel-confirmed")
        save.tap()
        XCTAssertTrue(app.staticTexts["workmodel.warning"].waitForNonExistence(timeout: 10) || !el("workmodel.warning").exists)
        sleep(1)
        shot("workmodel-saved")

        // Back to settings: about, haptics.
        app.navigationBars.buttons.firstMatch.tap()
        // S2: the about page is one level down ("Über Timetrack"); the haptic level lives on the appearance page.
        let aboutRow = el("settings.about")
        scrollTo(aboutRow)
        aboutRow.tap()
        let copy = el("about.copy")
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        XCTAssertTrue(el("about.backend.version").waitForExistence(timeout: 10) || el("about.unavailable").exists)
        shot("about")
        app.navigationBars.buttons.firstMatch.tap()

        // Appearance: grid with the new ids, glow.
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        let appearance = el("settings.appearance")
        scrollTo(appearance)
        appearance.tap()
        XCTAssertTrue(el("appearance.accent.navy").waitForExistence(timeout: 5))
        shot("appearance")
        
        el("appearance.accent.navy").tap()
        sleep(1)
        XCTAssertTrue(app.buttons["appearance.accent.navy"].isSelected)
        shot("appearance-ink")
        let glow = el("appearance.glow")
        scrollTo(glow)
        app.segmentedControls["appearance.glow"].buttons["Stark"].tap()
        sleep(1)
        shot("appearance-glow-strong")
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }
}
