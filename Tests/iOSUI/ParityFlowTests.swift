import XCTest

/// N1b: accent grid (22 ids) and glow, work-model correction with preview and confirmation, vacation tiles with editable entitlement,
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
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE",
                               "-appearance.accent", env["TT_SHOT_ACCENT"] ?? "wine", "-appearance.scheme", env["TT_SHOT_SCHEME"] ?? "system",
                               "-appearance.glow", env["TT_SHOT_GLOW"] ?? "medium"]
        app.launch()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20))
        shot("today")

        // Vacation: tiles and the entitlement edit.
        open("Urlaub", "vacation")
        XCTAssertTrue(el("vacation.tile.entitlement").waitForExistence(timeout: 10))
        shot("vacation")
        let edit = el("vacation.edit_entitlement")
        app.swipeUp(); app.swipeUp()
        edit.tap()
        let field = el("vacation.entitlement.field")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Alles auswählen"].waitForExistence(timeout: 1) { app.menuItems["Alles auswählen"].tap() }
        field.typeText("28")
        shot("vacation-edit")
        el("vacation.entitlement.save").tap()
        let tile = el("vacation.tile.entitlement")
        XCTAssertTrue(el("vacation.edit_entitlement").waitForExistence(timeout: 10))
        app.swipeDown(); app.swipeDown()
        var updated = false
        for _ in 0..<20 where !updated {
            updated = tile.label.contains("28")
            if !updated { usleep(500_000) }
        }
        XCTAssertTrue(updated, "the tile must show the new entitlement, got \(tile.label)")
        shot("vacation-after")

        // Settings: work models.
        open("Einstellungen", "settings")
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
        let haptics = el("haptics.toggle")
        scrollTo(haptics)
        XCTAssertTrue(haptics.exists)
        let copy = el("about.copy")
        scrollTo(copy)
        XCTAssertTrue(el("about.backend.version").exists || el("about.unavailable").exists)
        shot("about")

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
