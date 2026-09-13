import XCTest
import Foundation

final class GameplayUITests: XCTestCase {
    func testTapFiresAndRestartResets() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetSave"]
        app.launch()

        var scene = app.otherElements["gameScene"]
        if !scene.waitForExistence(timeout: 15) {
            scene = app.descendants(matching: .any)["gameScene"]
            XCTAssertTrue(scene.waitForExistence(timeout: 15), "gameScene element never appeared")
        }

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

        var latestValue = initialValue
        var changed = false
        let firstShotDeadline = Date().addingTimeInterval(5.0)
        while Date() < firstShotDeadline {
            if let value = scene.value as? String, value != initialValue {
                latestValue = value
                changed = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(changed, "gameScene value did not change within 5s after the first tap")
        XCTAssertTrue(latestValue.contains("bubbles:"), "unexpected value after tap: \(latestValue)")

        let offsets: [CGVector] = [
            CGVector(dx: 0.3, dy: 0.3),
            CGVector(dx: 0.7, dy: 0.3),
            CGVector(dx: 0.5, dy: 0.35)
        ]
        for offset in offsets {
            scene.coordinate(withNormalizedOffset: offset).tap()
            Thread.sleep(forTimeInterval: 1.5)
        }

        // Save a gameplay screenshot (board with landed/popped bubbles and a
        // non-zero score) for the repo. A failure to write it must not fail
        // the test — it's a documentation artifact, not a test assertion.
        let screenshotDir = "/Users/dimazhuravlev/Repos/bubble-shooter/build/screenshots"
        let screenshotPath = screenshotDir + "/gameplay.png"
        do {
            try FileManager.default.createDirectory(atPath: screenshotDir, withIntermediateDirectories: true)
            let pngData = XCUIScreen.main.screenshot().pngRepresentation
            try pngData.write(to: URL(fileURLWithPath: screenshotPath))
        } catch {
            print("GameplayUITests: failed to write gameplay screenshot to \(screenshotPath): \(error)")
        }

        XCTAssertEqual(app.state, .runningForeground, "app is no longer in the foreground")

        app.buttons["restartButton"].tap()

        var resetOK = false
        let resetDeadline = Date().addingTimeInterval(3.0)
        while Date() < resetDeadline {
            if let value = scene.value as? String, value.hasPrefix("bubbles:153 score:0") {
                resetOK = true
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(resetOK, "board did not reset to bubbles:153 score:0 within 3s after Restart")
    }
}
