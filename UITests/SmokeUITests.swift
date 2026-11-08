import XCTest

final class SmokeUITests: XCTestCase {
    func testAppLaunchesAndShowsTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetSave"]
        app.launch()
        XCTAssertTrue(app.buttons["restartButton"].waitForExistence(timeout: 15))
        let lives = app.otherElements["livesIndicator"]
        XCTAssertTrue(lives.exists)
        // `settings` and `restart` sit up in place of the status bar, above
        // the lives (spec 71).
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.exists)
        XCTAssertLessThan(settings.frame.midY, lives.frame.minY)
        XCTAssertLessThan(app.buttons["restartButton"].frame.midY, lives.frame.minY)
    }
}
