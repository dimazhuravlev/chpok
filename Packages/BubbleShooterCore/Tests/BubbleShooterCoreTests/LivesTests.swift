import XCTest
@testable import BubbleShooterCore

/// Lives / row-add tests (game-logic.md §10/§11).
final class LivesTests: XCTestCase {

    // (a) 5 consecutive misses drain lives to 0 (one `.lifeLost` each,
    // `livesLeft == 5-k`); the 6th miss adds rows instead, with
    // `count == 1 + (colors completely absent from every bubble)`.
    //
    // A single decoy bubble (far from where any scripted shot lands) keeps
    // the board non-empty from tick 0: with a truly empty board, the poll
    // in checkWin() (game-logic.md §13) can fire while the very first shot
    // is still mid-flight (no bubble has ever been `.onBoard` yet) and
    // declare an immediate, spurious win — a real consequence of
    // `checkIfGameWon`'s formula on a board that starts with zero bubbles,
    // not a scenario the original ever hits (`initBoard` always seeds 153).
    // Rejection-sampling in `getRandomColor(fullyRandom:false)` (§14) can
    // only ever draw a color that is already present somewhere in
    // `bubbles`; seeding exactly 3 distinct colors up front (ready, queue,
    // decoy) therefore *guarantees*, for the rest of this test, that the
    // other 3 colors can never appear — making "colors completely absent"
    // a fixed, known quantity (3) rather than something to sample at
    // runtime.
    func testFiveMissesThenRowAdd() {
        let random = ScriptedRandom(Array(repeating: [0, 1, 2, 3, 4, 5], count: 40).flatMap { $0 })
        let decoy: [GameSnapshot.BubbleRecord] = [.init(boardX: 16, boardY: 0, color: .yellow)]
        let engine = GameEngine(board: decoy, readyColor: .blue, queueColor: .red, random: random)
        // Minimal advance: clears the 500ms cannon lockout (§2/§15) while
        // leaving enough headroom before the first 1000ms win-check poll for
        // the first shot to land (see the false-win note above).
        engine.advance(ms: 510)

        // Angles chosen to spread landings across different columns so
        // consecutive misses don't happen to end up adjacent to each other.
        let angles: [Double] = [-60, 60, -30, 30, -15]

        for (k, angle) in angles.enumerated() {
            XCTAssertTrue(engine.fire(angleDegrees: angle), "miss #\(k + 1)")
            engine.runUntilIdle()
            let events = engine.drainEvents()
            XCTAssertTrue(events.contains(.lifeLost(livesLeft: 5 - (k + 1))), "miss #\(k + 1): \(events)")
            XCTAssertEqual(engine.livesLeft, 5 - (k + 1))
        }
        XCTAssertEqual(engine.livesLeft, 0)

        // 6th miss: lives are already at 0, so this goes through the
        // add-a-row path instead of another decrement.
        XCTAssertTrue(engine.fire(angleDegrees: 15))
        engine.runUntilIdle()
        let events = engine.drainEvents()

        XCTAssertFalse(events.contains { if case .lifeLost = $0 { return true }; return false },
                        "the 6th miss must not emit .lifeLost")

        // 3 colors were ever seeded (blue, red, yellow) => 3 are completely
        // absent (green, purple, lightblue) => count = 1 + 3 = 4.
        guard let rowsAddedIndex = events.firstIndex(where: { if case .rowsAdded = $0 { return true }; return false }),
              let livesResetIndex = events.firstIndex(where: { if case .livesReset = $0 { return true }; return false }) else {
            XCTFail("expected both .livesReset and .rowsAdded: \(events)")
            return
        }
        XCTAssertEqual(events[rowsAddedIndex], .rowsAdded(count: 4))
        XCTAssertLessThan(livesResetIndex, rowsAddedIndex, ".livesReset must precede .rowsAdded (§11)")

        // §10's resetLives/resetMaxLives, applied after totalColors is
        // updated to 6 - 4 + 1 = 3: maxLives 5-1=4, clamped down to
        // resetMaxLivesValue() = totalColors-1 = 2; livesLeft = maxLives.
        XCTAssertEqual(events[livesResetIndex], .livesReset(livesLeft: 2, maxLives: 2))
        XCTAssertEqual(engine.totalColors, 3)
        XCTAssertEqual(engine.livesLeft, 2)
        XCTAssertEqual(engine.maxLives, 2)
    }

    // (b) only 3 colors present on a full row 0; a scripted miss adds
    // rows(count 4), shifts every existing bubble down by the same amount,
    // and fills the new rows with colors drawn only from what was already
    // present.
    func testRowAddShiftsBoardAndFillsFromPresentColors() {
        // col -> color, chosen so (8,0) lands on blue and the row still
        // cycles through all of {blue,red,green} — matches the spec's
        // "row 0: blue, red, green по кругу".
        func colorFor(_ col: Int) -> BubbleColor {
            [.blue, .red, .green][(col + 1) % 3]
        }
        var board: [GameSnapshot.BubbleRecord] = []
        for col in 0...16 {
            board.append(.init(boardX: col, boardY: 0, color: colorFor(col)))
        }
        XCTAssertEqual(colorFor(8), .blue) // sanity: matches the spec's example layout

        let engine = GameEngine(
            board: board, readyColor: .red, queueColor: .green,
            livesLeft: 0, maxLives: 5, totalColors: 6,
            random: ScriptedRandom(Array(repeating: [0, 1, 2, 3, 4, 5], count: 200).flatMap { $0 })
        )
        engine.advance(ms: 510)

        // Vertical shot collides with (8,0) and lands in row 1; a same-row
        // board (no row 1 pre-populated) can chain at most 2 same-colored
        // bubbles here, never reaching the >=3 needed for a match (verified
        // below via the absence of any .removed event) regardless of the
        // exact (7,1)/(8,1) landing column.
        XCTAssertTrue(engine.fire(angleDegrees: 0))
        engine.runUntilIdle()
        let events = engine.drainEvents()

        XCTAssertFalse(events.contains { if case .removed = $0 { return true }; return false },
                        "expected a clean miss, not a match: \(events)")
        XCTAssertTrue(events.contains(.rowsAdded(count: 4)), "\(events)")
        XCTAssertEqual(engine.totalColors, 3)

        // Old row-0 bubbles shifted down by rowsToAdd (4): boardY 0 -> 4,
        // and (8,0)'s real position recomputes for the new (still-even) row
        // rather than just carrying the old pixel position forward.
        let shifted = engine.boardBubbles.filter { $0.boardY == 4 }
        XCTAssertEqual(shifted.count, 17, "all 17 original row-0 bubbles should have shifted to row 4")
        guard let col8 = shifted.first(where: { $0.boardX == 8 }) else {
            XCTFail("expected (8,0) to have become (8,4)")
            return
        }
        XCTAssertEqual(col8.color, .blue)
        XCTAssertEqual(col8.position, Vec2(x: 296, y: Grid.realCoord(boardX: 8, boardY: 4).y))
        XCTAssertEqual(col8.position.x, 296)

        // 4 new rows of 17 columns each; every new bubble's color was
        // already present before the row-add (blue/red/green).
        let newRows = engine.boardBubbles.filter { $0.boardY < 4 }
        XCTAssertEqual(newRows.count, 17 * 4)
        XCTAssertTrue(newRows.allSatisfy { [.blue, .red, .green].contains($0.color) },
                       "new row bubbles must only use colors that were already present")
    }

    // (c) parity shift: a single row-add flips (8,0)'s row from even to
    // odd, so its recomputed x picks up the +16 odd-row offset even though
    // the column index (8) didn't change.
    func testRowAddRecomputesParityOffset() {
        // All 6 colors present in row 0 (17 columns, col -> (col+4)%6 so
        // that column 8 specifically lands on blue) => 0 absent => count=1.
        func colorFor(_ col: Int) -> BubbleColor {
            BubbleColor(rawValue: (col + 4) % 6)!
        }
        var board: [GameSnapshot.BubbleRecord] = []
        for col in 0...16 {
            board.append(.init(boardX: col, boardY: 0, color: colorFor(col)))
        }
        XCTAssertEqual(colorFor(8), .blue) // sanity
        XCTAssertEqual(Set((0...16).map(colorFor)), Set(BubbleColor.allCases), "all 6 colors present")

        let engine = GameEngine(
            board: board, readyColor: .green, queueColor: .green,
            livesLeft: 0, maxLives: 5, totalColors: 6,
            random: ScriptedRandom(Array(repeating: [0, 1, 2, 3, 4, 5], count: 40).flatMap { $0 })
        )
        engine.advance(ms: 510)

        // green (the ready color) doesn't match (8,0)=blue or either of its
        // row-0 neighbours, so this is a guaranteed miss.
        XCTAssertTrue(engine.fire(angleDegrees: 0))
        engine.runUntilIdle()
        let events = engine.drainEvents()

        XCTAssertFalse(events.contains { if case .removed = $0 { return true }; return false })
        XCTAssertTrue(events.contains(.rowsAdded(count: 1)), "\(events)")

        guard let shiftedCol8 = engine.boardBubbles.first(where: { $0.boardX == 8 && $0.boardY == 1 }) else {
            XCTFail("expected (8,0) to have become (8,1)")
            return
        }
        XCTAssertEqual(shiftedCol8.color, .blue)
        XCTAssertEqual(shiftedCol8.position.x, 312, "odd row 1 adds the +16 parity offset: 40 + 8*32 + 16")
    }
}
