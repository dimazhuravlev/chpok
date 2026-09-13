import XCTest

final class SmokeUITests: XCTestCase {
    func testAppLaunchesAndShowsTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetSave"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scoreLabel"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["restartButton"].exists)
    }
}
