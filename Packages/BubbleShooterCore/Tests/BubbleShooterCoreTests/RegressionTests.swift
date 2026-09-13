import XCTest
@testable import BubbleShooterCore

/// One test per logic defect found and fixed during the 08 final-review
/// pass (see the review report for the full "axis -> verdict" table). Each
/// test documents the defect it guards against in its doc comment.
final class RegressionTests: XCTestCase {

    /// Fix: `fire(toward:)`/`fire(angleDegrees:)` must update
    /// `aimAngleDegrees`, the published property `GameScene` reads right
    /// after a successful fire to rotate the cannon sprite
    /// (`updateCannonRotation`, game-logic.md §4 / 05-game-scene-ui.md
    /// "Пушка поворачивается на угол выстрела").
    ///
    /// Before the fix, `performLaunch` computed the launch velocity from the
    /// correct angle but left `aimAngleDegrees` frozen at its initial `0`
    /// forever — only `aim(toward:)` wrote to it, and the app never calls
    /// `aim(toward:)` (no drag-aiming; tap fires immediately). The bubble
    /// always flew in the right direction, but the cannon sprite never
    /// visibly turned to face any shot.
    func testFireTowardUpdatesAimAngleDegrees() {
        let engine = GameEngine(board: [], readyColor: .red, queueColor: .blue, random: SeededGameRandom(seed: 1))
        engine.advance(ms: 600)
        XCTAssertEqual(engine.aimAngleDegrees, 0)

        let point = Vec2(x: engine.layout.cannonPivot.x + 100, y: engine.layout.cannonPivot.y - 100)
        let expected = GameEngine.aimAngle(from: engine.layout.cannonPivot, to: point)
        XCTAssertGreaterThan(expected, 0, "sanity: an up-and-right point should aim right (positive)")

        XCTAssertTrue(engine.fire(toward: point))
        XCTAssertEqual(engine.aimAngleDegrees, expected, accuracy: 0.0001)
    }

    /// Same fix, via the direct-angle firing entry point: the clamped angle
    /// actually used for the shot must also end up in `aimAngleDegrees`.
    func testFireAngleDegreesUpdatesAimAngleDegrees() {
        let engine = GameEngine(board: [], readyColor: .red, queueColor: .blue, random: SeededGameRandom(seed: 1))
        engine.advance(ms: 600)

        XCTAssertTrue(engine.fire(angleDegrees: -45))
        XCTAssertEqual(engine.aimAngleDegrees, -45, accuracy: 0.0001)

        // Second shot, different (clamped) angle: must update again, not
        // stick to the first shot's value.
        engine.runUntilIdle()
        guard engine.canFire else { return }
        XCTAssertTrue(engine.fire(angleDegrees: 200))
        XCTAssertEqual(engine.aimAngleDegrees, GameConsts.maxAngleDegrees, accuracy: 0.0001)
    }
}
