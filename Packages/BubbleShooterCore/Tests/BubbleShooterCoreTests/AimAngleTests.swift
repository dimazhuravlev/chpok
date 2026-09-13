import XCTest
@testable import BubbleShooterCore

/// `GameEngine.aimAngle(from:to:)` tests (game-logic.md §4: shared formula
/// used by both aiming and firing, including the `angle < -180 -> +75`
/// copy-paste quirk, §17.3).
final class AimAngleTests: XCTestCase {
    let pivot = Vec2(x: 296, y: 552)

    func assertAngle(_ point: Vec2, _ expected: Double, accuracy: Double = 0.01, file: StaticString = #filePath, line: UInt = #line) {
        let angle = GameEngine.aimAngle(from: pivot, to: point)
        XCTAssertEqual(angle, expected, accuracy: accuracy, file: file, line: line)
    }

    func testStraightUp() {
        assertAngle(Vec2(x: 296, y: 400), 0)
    }

    func testUpRight45() {
        assertAngle(Vec2(x: 396, y: 452), 45)
    }

    func testUpLeft45() {
        assertAngle(Vec2(x: 196, y: 452), -45)
    }

    func testHorizontalRightClampsTo75() {
        assertAngle(Vec2(x: 500, y: 552), 75)
    }

    func testHorizontalLeftClampsToMinus75() {
        assertAngle(Vec2(x: 100, y: 552), -75)
    }

    /// Quirk (§4, §17.3): a point below-right of the pivot yields a raw
    /// angle < -180 before clamping, which the original's copy-paste bug
    /// clamps to +75 (not -75, as would be intuitive).
    func testDownRightClampsTo75Quirk() {
        assertAngle(Vec2(x: 396, y: 652), 75)
    }

    func testDownLeftClampsToMinus75() {
        assertAngle(Vec2(x: 196, y: 652), -75)
    }

    /// `fire(angleDegrees:)` clamps its input to `±maxAngleDegrees` via a
    /// plain `min/max` (game-logic.md's clamp range, not the quirky
    /// `aimAngle` formula, since this test-only method takes an angle
    /// directly rather than a screen point). The clamped angle actually
    /// used for the shot is observable via the `.launched` event, which is
    /// the well-specified per-shot angle (`GameEvent.launched`'s
    /// `angleDegrees`, set from the same clamped value passed into
    /// `performLaunch`).
    func testFireAngleDegreesClampsTo75() {
        let engine = GameEngine(random: SeededGameRandom(seed: 42))
        engine.advance(ms: 600) // clear the post-init cannon lockout (§2/§15)

        XCTAssertTrue(engine.fire(angleDegrees: 100))

        let events = engine.drainEvents()
        guard case let .launched(_, angleDegrees)? = events.first(where: {
            if case .launched = $0 { return true }
            return false
        }) else {
            XCTFail("expected a .launched event")
            return
        }
        XCTAssertEqual(angleDegrees, 75)
    }
}
