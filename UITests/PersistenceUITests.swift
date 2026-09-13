import XCTest

final class PersistenceUITests: XCTestCase {
    private func findScene(_ app: XCUIApplication) -> XCUIElement {
        var scene = app.otherElements["gameScene"]
        if !scene.waitForExistence(timeout: 15) {
            scene = app.descendants(matching: .any)["gameScene"]
            XCTAssertTrue(scene.waitForExistence(timeout: 15), "gameScene element never appeared")
        }
        return scene
    }

    /// Plays one shot, relaunches the app, and checks the exact same match
    /// (score, bubble count, lives) comes back — then Restart + relaunch
    /// proves a fresh match is what gets saved going forward.
    func testGameResumesAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetSave"]
        app.launch()

        var scene = findScene(app)
        guard let initialValue = scene.value as? String else {
            XCTFail("gameScene has no string accessibility value")
            return
        }
        XCTAssertTrue(
            initialValue.hasPrefix("bubbles:153 score:0"),
            "unexpected initial value: \(initialValue)"
        )

        // Cannon is locked for ~500ms after init; wait it out before firing.
        Thread.sleep(forTimeInterval: 1.0)

        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()

        var sawChange = false
        let firstShotDeadline = Date().addingTimeInterval(5.0)
        while Date() < firstShotDeadline {
            if let value = scene.value as? String, !value.hasPrefix("bubbles:153 score:0") {
                sawChange = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(sawChange, "gameScene value still starts with bubbles:153 score:0 after 5s")

        // Let the turn fully resolve (engine back to idle -> .turnResolved ->
        // save-to-disk) and any cascading removals settle before treating the
        // value as the state that should survive a relaunch.
        Thread.sleep(forTimeInterval: 1.5)
        guard let rememberedValue = scene.value as? String else {
            XCTFail("gameScene has no string accessibility value after settling")
            return
        }

        app.terminate()
        app.launchArguments = []
        app.launch()

        scene = findScene(app)
        let resumedValue = scene.value as? String
        XCTAssertEqual(
            resumedValue, rememberedValue,
            "resumed game did not match the saved state (same score/bubbles/lives expected)"
        )

        app.buttons["restartButton"].tap()

        var resetOK = false
        let resetDeadline = Date().addingTimeInterval(5.0)
        while Date() < resetDeadline {
            if let value = scene.value as? String, value.hasPrefix("bubbles:153 score:0") {
                resetOK = true
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(resetOK, "board did not reset to bubbles:153 score:0 within 5s after Restart")

        // Restart's own save should stick: relaunching (still no -resetSave)
        // must resume the fresh post-restart match, not the old in-flight one.
        app.terminate()
        app.launch()

        scene = findScene(app)
        guard let freshValue = scene.value as? String else {
            XCTFail("gameScene has no string accessibility value after restart+relaunch")
            return
        }
        XCTAssertTrue(
            freshValue.hasPrefix("bubbles:153 score:0"),
            "unexpected value after restart+relaunch: \(freshValue)"
        )
    }
}
