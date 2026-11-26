import XCTest

/// B33A8F6A: the error of the fresh sign-in ("Passkey eines anderen Kontos") has to disappear again, after a cancelled and after
/// a successful retry. Needs a THROWAWAY backend whose session is older than ten minutes (the server then answers "add passkey"
/// with 403 `reauth_required`); skipped without one. `TT_DARK=1` runs in dark mode, `TT_SHOT_DIR` writes screenshots.
final class ReauthNoticeTests: XCTestCase {
    private var app: XCUIApplication!
    private var dark: Bool { ProcessInfo.processInfo.environment["TT_DARK"] == "1" }

    private func launch(script: String) throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["TT_DEV_REAUTH_BACKEND"] == "1", "needs a throwaway backend with an old session")
        XCUIDevice.shared.appearance = dark ? .dark : .light
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = try XCTUnwrap(env["TT_DEV_SERVER"])
        app.launchEnvironment["TT_DEV_COOKIE"] = try XCTUnwrap(env["TT_DEV_COOKIE"])
        app.launchEnvironment["TT_DEV_REAUTH"] = script
        // The app applies its own appearance setting; the argument domain overrides the stored value.
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-appearance.scheme", dark ? "dark" : "light"]
        app.launch()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
    }

    override func tearDown() {
        XCUIDevice.shared.appearance = .light
    }

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private var signInAgain: XCUIElement { app.buttons["Mit Passkey erneut anmelden"] }
    private func text(containing part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    private var otherAccountMessage: XCUIElement { text(containing: "Passkey eines anderen Kontos") }
    private var anyPasskeyError: XCUIElement { text(containing: "Passkey-Anmeldung ist fehlgeschlagen") }

    private func scrollToBottom() {
        for _ in 0..<3 { app.swipeUp() }
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] else { return }
        sleep(1) // let scrolling and press highlights settle
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(dark ? "dunkel" : "hell")-\(name).png"))
    }

    /// Settings > Passkeys > "Passkey hinzufügen" until the server asks for a fresh sign-in.
    private func openFreshLoginNotice() {
        app.openSettings()
        let row = el("settings.passkeys")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        let add = el("passkeys.add")
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        add.tap()
        XCTAssertTrue(signInAgain.waitForExistence(timeout: 10), "the server did not ask for a fresh sign-in")
        scrollToBottom()
    }

    private func signInWithOtherAccount() {
        signInAgain.tap()
        XCTAssertTrue(otherAccountMessage.waitForExistence(timeout: 10))
        scrollToBottom()
    }

    func testOtherAccountMessageDisappearsAfterCancel() throws {
        try launch(script: "other,cancel")
        openFreshLoginNotice()
        XCTAssertFalse(otherAccountMessage.exists)
        shot("abbruch-1-vorher")
        signInWithOtherAccount()
        shot("abbruch-2-waehrend")
        signInAgain.tap()
        XCTAssertTrue(otherAccountMessage.waitForNonExistence(timeout: 10))
        sleep(1)
        scrollToBottom()
        shot("abbruch-3-nachher")
        XCTAssertFalse(anyPasskeyError.exists, "a cancelled prompt must not leave an error")
        XCTAssertTrue(signInAgain.isEnabled)
    }

    func testOtherAccountMessageDisappearsAfterSuccessfulRetry() throws {
        try launch(script: "other,success")
        openFreshLoginNotice()
        XCTAssertFalse(otherAccountMessage.exists)
        shot("erfolg-1-vorher")
        signInWithOtherAccount()
        shot("erfolg-2-waehrend")
        signInAgain.tap()
        XCTAssertTrue(text(containing: "Angemeldet. Du kannst es jetzt noch einmal versuchen.").waitForExistence(timeout: 10))
        scrollToBottom()
        shot("erfolg-3-nachher")
        XCTAssertFalse(otherAccountMessage.exists)
        XCTAssertFalse(anyPasskeyError.exists)
    }
}
