import XCTest
@testable import BubbleShooterCore

/// Hanging-cluster tests (game-logic.md §9, plus §13's win poll): removing
/// the bridge bubble in a match can strand a same-color-irrelevant group,
/// which is then swept as "hanging" for a flat 100pt bonus each; emptying
/// the board this way still reaches the win screen.
final class HangingTests: XCTestCase {

    func testHangingClusterThenWin() {
        // (8,0) red, (8,1) red, (9,1) blue — (9,1) is connected to the rest
        // of the board only via (8,1).
        let board: [GameSnapshot.BubbleRecord] = [
            .init(boardX: 8, boardY: 0, color: .red),
            .init(boardX: 8, boardY: 1, color: .red),
            .init(boardX: 9, boardY: 1, color: .blue),
        ]
        let engine = GameEngine(board: board, readyColor: .red, queueColor: .blue, random: SeededGameRandom(seed: 1))
        engine.advance(ms: 600)

        XCTAssertTrue(engine.fire(angleDegrees: 0))

        // Run past both the removal cascade and at least one 1000ms
        // win-check tick without stopping at isIdle in between (runUntilIdle
        // alone would stop once removals finish, before the next win-check
        // boundary) — manually tick until game-over or a generous cap.
        var ticks = 0
        while !engine.isGameOver, ticks < 5000 {
            engine.tick()
            ticks += 1
        }
        XCTAssertTrue(engine.isGameOver, "expected the win to be detected within \(ticks) ticks")

        let elapsed = engine.matchElapsedMs
        let events = engine.drainEvents()

        let removedEvents = events.filter { if case .removed = $0 { return true }; return false }
        XCTAssertEqual(removedEvents.count, 4, "3 matched red + 1 hanging blue")

        let matchEvents = removedEvents.filter { if case .removed(_, _, _, _, .match) = $0 { return true }; return false }
        let hangingEvents = removedEvents.filter { if case .removed(_, _, _, _, .hanging) = $0 { return true }; return false }
        XCTAssertEqual(matchEvents.count, 3)
        let matchColors: [BubbleColor] = matchEvents.compactMap {
            if case let .removed(_, color, _, _, _) = $0 { return color }
            return nil
        }
        XCTAssertEqual(matchColors, [.red, .red, .red])
        let matchPoints: [Int] = matchEvents.compactMap {
            if case let .removed(_, _, _, points, _) = $0 { return points }
            return nil
        }
        XCTAssertEqual(matchPoints.reduce(0, +), 30)

        XCTAssertEqual(hangingEvents.count, 1)
        if case let .removed(_, color, _, points, _)? = hangingEvents.first {
            XCTAssertEqual(color, .blue)
            XCTAssertEqual(points, 100)
        }

        XCTAssertEqual(engine.score, 130)
        XCTAssertEqual(engine.boardBubbles.count, 0, "the board should be empty")

        guard let gameOverIndex = events.firstIndex(where: { if case .gameOver = $0 { return true }; return false }) else {
            XCTFail("expected a .gameOver event")
            return
        }
        XCTAssertEqual(events[gameOverIndex], .gameOver(won: true, score: 130, bonus: 130, elapsedMs: elapsed))

        // All .removed events must precede .gameOver (game-logic.md §13: the
        // board empties out synchronously inside the last remove() call,
        // well before the polled win-check notices).
        for (i, e) in events.enumerated() where i != gameOverIndex {
            if case .removed = e {
                XCTAssertLessThan(i, gameOverIndex, "a .removed event must come before .gameOver")
            }
        }
    }
}
