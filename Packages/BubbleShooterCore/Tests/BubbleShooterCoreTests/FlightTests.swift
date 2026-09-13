import XCTest
@testable import BubbleShooterCore

/// Flight tests (game-logic.md §5): straight shot to the ceiling, wall
/// bounce, re-fire guard while flying, and `fire(toward:)`'s input-area
/// gate.
final class FlightTests: XCTestCase {

    private func emptyBoardEngine(ready: BubbleColor = .red, queue: BubbleColor = .blue) -> GameEngine {
        let engine = GameEngine(board: [], readyColor: ready, queueColor: queue, random: SeededGameRandom(seed: 1))
        engine.advance(ms: 600) // clear the post-init cannon lockout (§2/§15)
        return engine
    }

    // (a) empty board, straight-up shot: y decreases exactly 18px/tick,
    // x stays 296, lands at the ceiling in (8,0), a miss loses a life.
    func testVerticalShotLandsAtCeilingColumn8() {
        let engine = emptyBoardEngine()
        XCTAssertTrue(engine.fire(angleDegrees: 0))
        guard let firedId = engine.launchedBubble?.id else {
            XCTFail("expected a launched bubble right after firing")
            return
        }

        var ticks = 0
        while let flying = engine.launchedBubble, ticks < 2000 {
            XCTAssertEqual(flying.position.x, 296, accuracy: 0.0001)
            let yBefore = flying.position.y
            engine.tick()
            ticks += 1
            if let stillFlying = engine.launchedBubble, stillFlying === flying {
                XCTAssertEqual(stillFlying.position.y, yBefore - 18, accuracy: 0.0001,
                                "y must decrease by exactly 18px on every tick before landing")
            }
        }
        XCTAssertLessThan(ticks, 2000, "bubble should have landed by now")

        engine.runUntilIdle()
        let events = engine.drainEvents()
        XCTAssertTrue(events.contains(.landed(id: firedId, boardX: 8, boardY: 0)), "\(events)")
        XCTAssertTrue(events.contains(.lifeLost(livesLeft: 4)), "\(events)")

        let landed = engine.boardBubbles.first { $0.id == firedId }
        XCTAssertEqual(landed?.boardX, 8)
        XCTAssertEqual(landed?.boardY, 0)
    }

    // (b) empty board, angle 75: bounces off the right wall (x clamps to
    // 561, vx flips sign), eventually lands in row 0 within the board's
    // horizontal bounds.
    func testAngledShotBouncesOffRightWall() {
        let engine = emptyBoardEngine()
        XCTAssertTrue(engine.fire(angleDegrees: 75))
        guard let firedId = engine.launchedBubble?.id else {
            XCTFail("expected a launched bubble right after firing")
            return
        }

        var foundBounce = false
        var ticks = 0
        while let flying = engine.launchedBubble, ticks < 2000 {
            let prevX = flying.position.x
            let prevVx = flying.velocity.x
            let predictedX = prevX + prevVx
            engine.tick()
            ticks += 1
            if !foundBounce, predictedX > GameConsts.rightBoardBorder,
               let stillFlying = engine.launchedBubble, stillFlying === flying {
                XCTAssertEqual(stillFlying.position.x, GameConsts.rightBoardBorder, accuracy: 0.0001)
                XCTAssertEqual(stillFlying.velocity.x, -prevVx, accuracy: 0.0001)
                foundBounce = true
            }
        }
        XCTAssertLessThan(ticks, 2000, "bubble should have landed by now")
        XCTAssertTrue(foundBounce, "expected the flight to bounce off the right wall at least once")

        engine.runUntilIdle()
        let landed = engine.boardBubbles.first { $0.id == firedId }
        XCTAssertNotNil(landed)
        XCTAssertEqual(landed?.boardY, 0)
        // Row 0 is wide at the default rowParity 0, so a landed bubble's X
        // must fall exactly within the wide row's span (spec 13 tightens
        // this from the old, looser 37...585 bounds — see GameConsts).
        if let x = landed?.position.x {
            XCTAssertGreaterThanOrEqual(x, GameConsts.leftBoardBorder)
            XCTAssertLessThanOrEqual(x, GameConsts.rightBoardBorder)
        }
    }

    // (c) firing while a bubble is already in flight is a no-op.
    func testFireWhileFlyingReturnsFalse() {
        let engine = emptyBoardEngine()
        XCTAssertTrue(engine.fire(angleDegrees: 0))
        let firstId = engine.launchedBubble?.id

        XCTAssertFalse(engine.fire(angleDegrees: 30))
        XCTAssertEqual(engine.launchedBubble?.id, firstId, "a second fire() must not replace the flying bubble")

        let launchedEvents = engine.drainEvents().filter {
            if case .launched = $0 { return true }
            return false
        }
        XCTAssertEqual(launchedEvents.count, 1)
    }

    // (d) fire(toward:) is gated by the input-area rectangle (original
    // layout: y must be <= inputAreaMaxY = 505).
    func testFireTowardRespectsInputArea() {
        let engine = emptyBoardEngine()
        XCTAssertFalse(engine.fire(toward: Vec2(x: 300, y: 540)))
        XCTAssertNil(engine.launchedBubble)

        XCTAssertTrue(engine.fire(toward: Vec2(x: 296, y: 300)))
        XCTAssertNotNil(engine.launchedBubble)
    }
}
