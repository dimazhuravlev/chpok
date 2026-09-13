import XCTest
@testable import BubbleShooterCore

/// `GameEngine.init(random:)` / `BoardManager.initBoard` tests (game-logic.md
/// §2): fully-random 17x9 board plus ready/queue, and determinism of
/// `SeededGameRandom`.
final class InitBoardTests: XCTestCase {

    private struct BubbleKey: Equatable {
        let x: Int
        let y: Int
        let color: Int
    }

    func testInitialBoardComposition() {
        let engine = GameEngine(random: SeededGameRandom(seed: 42))

        XCTAssertEqual(engine.bubbles.count, 151)
        XCTAssertEqual(engine.boardBubbles.count, 149)
        XCTAssertEqual(engine.rowParity, 0)

        // Rows 0..8 alternate wide (17 columns)/narrow (16 columns) per
        // spec 13: 5 wide (even rows) + 4 narrow (odd rows) = 149.
        var byRow: [Int: Set<Int>] = [:]
        for b in engine.boardBubbles {
            byRow[b.boardY, default: []].insert(b.boardX)
        }
        XCTAssertEqual(Set(byRow.keys), Set(0...8))
        for row in 0...8 {
            let width = Grid.columns(inRow: row, rowParity: engine.rowParity)
            XCTAssertEqual(byRow[row], Set(0..<width), "row \(row) should have columns 0..<\(width)")
        }

        // Positions match Grid.realCoord.
        for b in engine.boardBubbles {
            XCTAssertEqual(b.position, Grid.realCoord(boardX: b.boardX, boardY: b.boardY, rowParity: engine.rowParity))
        }

        guard let ready = engine.readyBubble, let queue = engine.queueBubble else {
            XCTFail("expected ready and queue bubbles")
            return
        }
        XCTAssertEqual(ready.state, .readyToLaunch)
        XCTAssertEqual(queue.state, .inQueue)
        XCTAssertEqual(ready.position, engine.layout.readyPosition)
        XCTAssertEqual(queue.position, engine.layout.queuePosition)

        XCTAssertEqual(engine.livesLeft, 5)
        XCTAssertEqual(engine.maxLives, 5)
        XCTAssertEqual(engine.totalColors, 6)
        XCTAssertEqual(engine.score, 0)
        XCTAssertTrue(engine.isIdle)
        XCTAssertFalse(engine.isGameOver)

        // canFire respects the post-init 500ms cannon lockout (§2/§15) —
        // becomes true only after it elapses, per the spec's blanket rule.
        XCTAssertFalse(engine.canFire, "canFire must be false during the post-init lockout")
        engine.advance(ms: 600)
        XCTAssertTrue(engine.canFire)
        XCTAssertTrue(engine.isIdle, "advancing time alone must not disturb idleness")
    }

    private func boardKeys(_ engine: GameEngine) -> [BubbleKey] {
        engine.bubbles.map { BubbleKey(x: $0.boardX, y: $0.boardY, color: $0.color.rawValue) }
    }

    func testDeterminismSameSeed() {
        let a = GameEngine(random: SeededGameRandom(seed: 7))
        let b = GameEngine(random: SeededGameRandom(seed: 7))
        XCTAssertEqual(boardKeys(a), boardKeys(b))
    }

    func testDeterminismDifferentSeeds() {
        let a = GameEngine(random: SeededGameRandom(seed: 7))
        let b = GameEngine(random: SeededGameRandom(seed: 8))
        XCTAssertNotEqual(boardKeys(a), boardKeys(b))
    }
}
