import XCTest

/// S2: screenshots of the settings screen (top, scrolled pages and, when present, the sub pages) for the before/after comparison.
/// Needs the throwaway server environment (TT_DEV_SERVER, TT_DEV_COOKIE); optional TT_SHOT_DIR, TT_SHOT_PREFIX, TT_SHOT_SCHEME (system|light|dark).
final class SettingsShotTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "s2"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testSettingsScreens() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "s2"
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-appearance.scheme", env["TT_SHOT_SCHEME"] ?? "system"]
        app.launch()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
        app.openSettings()
        XCTAssertTrue(el("settings.sign_out").waitForExistence(timeout: 10))
        sleep(2) // lets the about section load the server info
        shot("settings-0")
        for page in 1...4 {
            app.swipeUp()
            shot("settings-\(page)")
        }
        // Sub pages (only the ones the new structure has).
        for (id, name) in [("settings.server", "server"), ("settings.about", "about"), ("settings.vacation", "vacation"), ("settings.appearance", "appearance")] {
            for _ in 0..<6 where !el(id).isHittable { app.swipeUp() }
            if !el(id).isHittable { for _ in 0..<6 where !el(id).isHittable { app.swipeDown() } }
            guard el(id).isHittable else { continue }
            el(id).tap()
            sleep(2)
            shot("sub-\(name)")
            app.swipeUp()
            shot("sub-\(name)-2")
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
            sleep(1)
        }
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }
}
