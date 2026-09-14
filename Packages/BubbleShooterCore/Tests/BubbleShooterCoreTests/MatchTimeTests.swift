import XCTest
@testable import BubbleShooterCore

/// Match-clock tests (spec 22): `GameEngine.matchElapsedMs` tracks only
/// active (ticked) time, restarts at zero on `resetBoard()`, round-trips
/// through `GameSnapshot`, and is carried by `.gameOver`.
final class MatchTimeTests: XCTestCase {

    func testMatchElapsedGrowsWithTicks() {
        let engine = GameEngine(random: SeededGameRandom(seed: 1))
        XCTAssertEqual(engine.matchElapsedMs, 0)

        engine.advance(ms: 600)

        XCTAssertEqual(engine.matchElapsedMs, 600)
    }

    func testResetBoardRestartsMatchClock() {
        let engine = GameEngine(random: SeededGameRandom(seed: 1))
        engine.advance(ms: 600)
        XCTAssertEqual(engine.matchElapsedMs, 600)

        engine.resetBoard()

        XCTAssertEqual(engine.matchElapsedMs, 0)
    }

    func testSnapshotPreservesElapsed() {
        let engine = GameEngine(random: SeededGameRandom(seed: 42))
        engine.advance(ms: 600)
        guard let snapshot = engine.snapshot() else {
            XCTFail("expected a snapshot while idle")
            return
        }
        XCTAssertEqual(snapshot.elapsedMs, 600)

        let restored = GameEngine(snapshot: snapshot, random: SeededGameRandom(seed: 1))
        XCTAssertEqual(restored.matchElapsedMs, 600, "elapsed time must resume from the snapshot")

        restored.advance(ms: 300)
        XCTAssertEqual(restored.matchElapsedMs, 900, "elapsed time must keep growing after resume")
    }

    func testGameOverEventCarriesElapsed() {
        var board = (0...16).map { GameSnapshot.BubbleRecord(boardX: $0, boardY: 0, color: .blue) }
        board.append(.init(boardX: 8, boardY: 17, color: .red))
        let engine = GameEngine(board: board, readyColor: .blue, queueColor: .red, random: SeededGameRandom(seed: 1))

        // Mirrors GameOverTests.testBubblePastThresholdTriggersLoss: the
        // out-of-bounds bubble triggers a loss on the very first tick, so
        // matchElapsedMs must be captured right there — `tick()` keeps
        // incrementing `timeMs` on every subsequent tick regardless of
        // `isGameOver`, so capturing it any later would no longer match the
        // value the (already-drained) event carries.
        engine.tick()
        XCTAssertTrue(engine.isGameOver)

        let expectedElapsed = engine.matchElapsedMs
        XCTAssertGreaterThan(expectedElapsed, 0)
        let events = engine.drainEvents()
        guard case let .gameOver(_, _, _, elapsedMs)? = events.first(where: {
            if case .gameOver = $0 { return true }
            return false
        }) else {
            XCTFail("expected a .gameOver event, got \(events)")
            return
        }
        XCTAssertEqual(elapsedMs, expectedElapsed)
    }
}
