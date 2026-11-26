import XCTest

/// Background launch (card B33A8F6A, TestFlight builds 26 and 31): BackgroundTasks calls the registered launch handlers on a
/// background queue. The app must survive that and report the task as completed. Needs no backend and no session.
final class BackgroundLaunchTests: XCTestCase {
    func testAutomationRefreshLaunchHandlerRunsOffTheMainThread() {
        runBackgroundTask("de.linolaske.timetrack.automation.refresh")
    }

    func testFocusRetryLaunchHandlerRunsOffTheMainThread() {
        runBackgroundTask("de.linolaske.timetrack.focus.retry")
    }

    private func runBackgroundTask(_ identifier: String) {
        let completed = XCTDarwinNotificationExpectation(notificationName: "de.linolaske.timetrack.dev.bgtask-completed." + identifier)
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_BG_LAUNCH"] = identifier
        app.launch()
        let result = XCTWaiter().wait(for: [completed], timeout: 30)
        XCTAssertEqual(result, .completed, "the launch handler never completed its task (app state \(app.state.rawValue))")
        XCTAssertEqual(app.state, .runningForeground, "the app crashed in the background launch handler")
        app.terminate()
    }
}
