import XCTest
@testable import BubbleShooterCore

/// Game-over tests (game-logic.md §12): the per-tick, per-board-bubble
/// threshold check, `GameLayout`-derived thresholds, and `resetBoard()`
/// recovering from a finished game.
final class GameOverTests: XCTestCase {

    private func rowZero(colors: (Int) -> BubbleColor = { _ in .blue }) -> [GameSnapshot.BubbleRecord] {
        (0...16).map { .init(boardX: $0, boardY: 0, color: colors($0)) }
    }

    // (a) a bubble past the original layout's threshold (row 16 / y ≈465.4,
    // per GameConsts.rowHeight — see LayoutTests.testOriginalLayout)
    // triggers a loss on the very next tick, no shot required, and locks
    // out every player action.
    func testBubblePastThresholdTriggersLoss() {
        var board = rowZero()
        board.append(.init(boardX: 8, boardY: 17, color: .red))
        let engine = GameEngine(board: board, readyColor: .blue, queueColor: .red, random: SeededGameRandom(seed: 1))

        XCTAssertFalse(engine.isGameOver)
        engine.tick()

        XCTAssertTrue(engine.isGameOver)
        let elapsed = engine.matchElapsedMs
        let events = engine.drainEvents()
        XCTAssertTrue(events.contains(.gameOver(won: false, score: 0, bonus: 0, elapsedMs: elapsed)), "\(events)")

        XCTAssertFalse(engine.canFire)
        XCTAssertNil(engine.snapshot())
        XCTAssertFalse(engine.fire(angleDegrees: 0))
    }

    // (b) GameLayout.fitting(canvasHeight: 1000): gameOverRow=29/gameOverY≈825.67
    // (LayoutTests, per GameConsts.rowHeight). Row 29 itself is still in play
    // (boardY > 29 is the condition, not >=); row 30 is past it.
    func testFittingLayoutThreshold() {
        let layout = GameLayout.fitting(canvasHeight: 1000)

        var boardAtRow29 = rowZero()
        boardAtRow29.append(.init(boardX: 8, boardY: 29, color: .red))
        let stillPlaying = GameEngine(board: boardAtRow29, readyColor: .blue, queueColor: .red, layout: layout, random: SeededGameRandom(seed: 1))
        stillPlaying.tick()
        XCTAssertFalse(stillPlaying.isGameOver, "row 29 must still be in play")

        var boardAtRow30 = rowZero()
        boardAtRow30.append(.init(boardX: 8, boardY: 30, color: .red))
        let over = GameEngine(board: boardAtRow30, readyColor: .blue, queueColor: .red, layout: layout, random: SeededGameRandom(seed: 1))
        over.tick()
        XCTAssertTrue(over.isGameOver, "row 30 must be past the threshold")
        let elapsed = over.matchElapsedMs
        XCTAssertTrue(over.drainEvents().contains(.gameOver(won: false, score: 0, bonus: 0, elapsedMs: elapsed)))
    }

    // (c) resetBoard() after a loss fully restores a fresh game.
    func testResetBoardAfterGameOver() {
        var board = rowZero()
        board.append(.init(boardX: 8, boardY: 17, color: .red))
        let engine = GameEngine(board: board, readyColor: .blue, queueColor: .red, score: 42, random: SeededGameRandom(seed: 1))
        engine.tick()
        XCTAssertTrue(engine.isGameOver)
        _ = engine.drainEvents()

        engine.resetBoard()

        XCTAssertFalse(engine.isGameOver)
        XCTAssertEqual(engine.score, 0)
        XCTAssertEqual(engine.boardBubbles.count, 149)
        XCTAssertEqual(engine.livesLeft, 5)
        XCTAssertEqual(engine.maxLives, 5)
        XCTAssertTrue(engine.drainEvents().contains(.boardReset))
    }
}
