import XCTest

/// A8: the accent is an account setting. Two phases against a THROWAWAY backend (env TT_DEV_SERVER, TT_DEV_COOKIE, TT_SHOT_DIR, TT_SHOT_PREFIX):
/// - TT_A8_PHASE=change: pick Orange and Dunkel on the Darstellung page and wait until the sync line says "synced".
/// - TT_A8_PHASE=verify: (run after uninstalling the app, i.e. empty UserDefaults) the account's Orange must be selected after sign-in.
final class AccountAccentTests: XCTestCase {
    func testAccountAccent() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        let phase = env["TT_A8_PHASE"] ?? "change"
        let prefix = env["TT_SHOT_PREFIX"] ?? "a8"
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()

        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
        sleep(2)
        shot("\(prefix)-today")

        app.openSettings()
        let row = app.buttons["settings.appearance"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let orange = app.buttons["appearance.accent.orange"]
        XCTAssertTrue(orange.waitForExistence(timeout: 5))
        sleep(2)

        if phase == "change" {
            orange.tap()
            let dark = app.segmentedControls.buttons["Dunkel"]
            if dark.exists { dark.tap() }
            let line = app.descendants(matching: .any)["appearance.sync"].firstMatch
            XCTAssertTrue(line.waitForExistence(timeout: 5))
            var state = ""
            for _ in 0..<30 where state != "synced" {
                state = (line.value as? String) ?? ""
                if state != "synced" { usleep(500_000) }
            }
            XCTAssertEqual(state, "synced")
        } else {
            XCTAssertTrue(orange.isSelected, "the account's Orange must be applied on a fresh install")
        }
        sleep(1)
        shot("\(prefix)-appearance")
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
