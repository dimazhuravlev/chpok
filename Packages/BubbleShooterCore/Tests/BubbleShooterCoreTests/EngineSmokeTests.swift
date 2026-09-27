import XCTest
@testable import BubbleShooterCore

/// Minimal smoke tests per spec step 6. A full test suite is a separate task.
final class EngineSmokeTests: XCTestCase {

    // (a)
    func testInitialBoardComposition() {
        let engine = GameEngine(random: SeededGameRandom(seed: 42))

        XCTAssertEqual(engine.boardBubbles.count, 149)
        XCTAssertEqual(Set(engine.boardBubbles.map { $0.boardY }), Set(0...8))
        // Wide rows use the full 0...16; narrow rows only ever use 0...15,
        // so the union across all 9 rows is still 0...16 (spec 13).
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
        // No advance() needed: snapshot() must be available immediately
        // (isIdle does not depend on the post-init cannon lockout — see
        // testIdleAndSnapshotIgnoreCannonLockout).
        guard let snapshot = engine.snapshot() else {
            XCTFail("expected a non-nil snapshot while idle")
            return
        }

        let restored = GameEngine(snapshot: snapshot, random: SeededGameRandom(seed: 7))
        XCTAssertEqual(restored.snapshot(), snapshot)
    }

    /// `isIdle`/`snapshot()` must not depend on the post-init/-reset 500ms
    /// `cannonEnabled` lockout — only `canFire` does. The UI saves a
    /// snapshot right after Restart, so `snapshot()` must be available
    /// immediately, not 500ms later.
    func testIdleAndSnapshotIgnoreCannonLockout() {
        let engine = GameEngine(random: SeededGameRandom(seed: 1))

        XCTAssertTrue(engine.isIdle, "isIdle must be true right after init")
        XCTAssertNotNil(engine.snapshot(), "snapshot() must be available right after init")
        XCTAssertFalse(engine.canFire, "canFire must respect the cannon lockout right after init")

        engine.resetBoard()

        XCTAssertTrue(engine.isIdle, "isIdle must be true right after resetBoard()")
        XCTAssertNotNil(engine.snapshot(), "snapshot() must be available right after resetBoard()")
        XCTAssertFalse(engine.canFire, "canFire must respect the cannon lockout right after resetBoard()")

        engine.advance(ms: 15)
        XCTAssertFalse(engine.canFire, "canFire must still be false before the 500ms lockout elapses")

        engine.advance(ms: 600)
        XCTAssertTrue(engine.canFire, "canFire must become true once the 500ms lockout elapses")
    }

    // DoD #4 — constants
    func testConstants() {
        XCTAssertEqual(GameConsts.boardWidth, 17)
        XCTAssertEqual(GameConsts.narrowBoardWidth, 16)
        XCTAssertEqual(GameConsts.bubbleSize, 32)
        XCTAssertEqual(GameConsts.launchPower, 18)
        // Retuned from 24 to 21: the original paired a 24 threshold with a
        // 32 row step (0.75 of it), but true hex packing put rows 27.71
        // apart, which left bubbles catching ~15% earlier than intended and
        // made aiming finicky. 21 restores roughly the original ratio.
        // Must stay above the 18px flight sub-step or shots tunnel.
        XCTAssertEqual(GameConsts.collisionDistance, 21)
        XCTAssertGreaterThan(GameConsts.collisionDistance, GameConsts.launchPower)
        // Spec 13: derived from boardMinX/boardMaxX, no longer independent
        // magic numbers (37/561).
        XCTAssertEqual(GameConsts.boardMinX, 24)
        XCTAssertEqual(GameConsts.boardMaxX, 568)
        XCTAssertEqual(GameConsts.boardLogicalWidth, 544)
        XCTAssertEqual(GameConsts.leftBoardBorder, 40)
        XCTAssertEqual(GameConsts.rightBoardBorder, 552)
    }

    // DoD #4 — layout
    func testLayout() {
        XCTAssertEqual(GameLayout.original.cannonPivot, Vec2(x: 296, y: 552))

        let fitting = GameLayout.fitting(canvasHeight: 1000)
        XCTAssertEqual(fitting.cannonY, 920)
        XCTAssertEqual(fitting.inputAreaMaxY, 856)
        XCTAssertEqual(fitting.gameOverRow, 29)
        XCTAssertEqual(fitting.gameOverY, 825.6715747119590, accuracy: 1e-9)

        // Spec 11: gameOverRow/gameOverY derive from GameConsts.rowHeight
        // (true hex packing) — see LayoutTests.testOriginalLayout.
        XCTAssertEqual(GameLayout.original.gameOverRow, 16)
        XCTAssertEqual(GameLayout.original.gameOverY, 465.40500673763257, accuracy: 1e-9)
    }
}
