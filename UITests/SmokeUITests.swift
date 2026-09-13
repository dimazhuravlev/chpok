import XCTest

final class SmokeUITests: XCTestCase {
    func testAppLaunchesAndShowsTitle() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["title"].waitForExistence(timeout: 10))
    }
}
