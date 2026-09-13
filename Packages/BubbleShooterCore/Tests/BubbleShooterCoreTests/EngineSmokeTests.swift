import XCTest
@testable import BubbleShooterCore

/// Minimal smoke tests per spec step 6. A full test suite is a separate task.
final class EngineSmokeTests: XCTestCase {

    // (a)
    func testInitialBoardComposition() {
        let engine = GameEngine(random: SeededGameRandom(seed: 42))

        XCTAssertEqual(engine.boardBubbles.count, 153)
        XCTAssertEqual(Set(engine.boardBubbles.map { $0.boardY }), Set(0...8))
        XCTAssertEqual(Set(engine.boardBubbles.map { $0.boardX }), Set(0...16))
        XCTAssertNotNil(engine.readyBubble)
        XCTAssertNotNil(engine.queueBubble)
        XCTAssertEqual(engine.livesLeft, 5)
        XCTAssertEqual(engine.score, 0)
    }

    // (b)
    func testFireAndLand() {
        let engine = GameEngine(random: SeededGameRandom(seed: 42))
        // Clear the original's 500ms post-init cannon lockout (§2/§15)
        // before attempting to fire. 510, not 500: ticks are 15ms, so
        // advancing exactly 500ms would only reach timeMs=495 (33 ticks)
        // and the lockout would not have fired yet.
        engine.advance(ms: 510)

        XCTAssertTrue(engine.fire(angleDegrees: 0))
        let ticks = engine.runUntilIdle()
        XCTAssertLessThan(ticks, 2000)

        let events = engine.drainEvents()
        XCTAssertTrue(events.contains {
            if case .landed = $0 { return true }
            return false
        })

        var seenPositions = Set<[Int]>()
        for b in engine.boardBubbles {
            let key = [b.boardX, b.boardY]
            XCTAssertFalse(seenPositions.contains(key), "duplicate board position \(key)")
            seenPositions.insert(key)
        }
    }

    // (c)
    func testSnapshotRoundTrip() {
        let engine = GameEngine(random: SeededGameRandom(seed: 7))
        engine.advance(ms: 510)

        guard let snapshot = engine.snapshot() else {
            XCTFail("expected a non-nil snapshot while idle")
            return
        }

        let restored = GameEngine(snapshot: snapshot, random: SeededGameRandom(seed: 7))
        // A freshly constructed engine also arms the 500ms cannon lockout
        // (mirrors initBoard, see armCannonEnableLockout), which keeps it
        // non-idle until cleared.
        restored.advance(ms: 510)
        XCTAssertEqual(restored.snapshot(), snapshot)
    }

    // DoD #4 — constants
    func testConstants() {
        XCTAssertEqual(GameConsts.boardWidth, 17)
        XCTAssertEqual(GameConsts.bubbleSize, 32)
        XCTAssertEqual(GameConsts.launchPower, 18)
        XCTAssertEqual(GameConsts.collisionDistance, 24)
        XCTAssertEqual(GameConsts.leftBoardBorder, 37)
        XCTAssertEqual(GameConsts.rightBoardBorder, 561)
    }

    // DoD #4 — layout
    func testLayout() {
        XCTAssertEqual(GameLayout.original.cannonPivot, Vec2(x: 296, y: 552))

        let fitting = GameLayout.fitting(canvasHeight: 1000)
        XCTAssertEqual(fitting.cannonY, 952)
        XCTAssertEqual(fitting.inputAreaMaxY, 888)
        XCTAssertEqual(fitting.gameOverRow, 26)
        XCTAssertEqual(fitting.gameOverY, 854)

        XCTAssertEqual(GameLayout.original.gameOverRow, 14)
        XCTAssertEqual(GameLayout.original.gameOverY, 470)
    }
}
