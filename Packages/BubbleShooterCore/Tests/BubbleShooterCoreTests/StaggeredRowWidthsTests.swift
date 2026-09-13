import XCTest
@testable import BubbleShooterCore

/// Spec 13 ("Ряды разной ширины"): the board's left/right silhouette stays
/// straight — wide rows (17 columns) and narrow rows (16 columns, inset
/// half a bubble on both sides) alternate forever, however many rows get
/// added — and the board no longer jumps sideways by half a bubble on every
/// row add. `GridTests`/`LivesTests` cover the underlying `Grid`/`GameEngine`
/// unit behaviour; these tests exercise the invariants end-to-end across a
/// realistic sequence of shots and row drops.
final class StaggeredRowWidthsTests: XCTestCase {

    /// Runs scripted misses (same decoy trick as
    /// `LivesTests.testFiveMissesThenRowAdd`: a single far-away bubble keeps
    /// the board non-empty from tick 0 and, by only ever allowing 3 colors
    /// anywhere on the board, pins `rowsToAdd` at a known constant for every
    /// row-add trigger) until at least `minDrops` `.rowsAdded` events have
    /// been observed, checking the straight-edge invariants after each one.
    func testEdgesStayStraightAcrossRowDrops() {
        // Only blue/red/yellow are ever drawn (rejection sampling in
        // getRandomColor(fullyRandom:false), §14, can only ever draw an
        // already-present color) => rowsToAdd == 1 + 3 == 4 for every single
        // trigger in this test. 3 triggers therefore add a bounded,
        // predictable 12 rows total regardless of how many of the shots
        // below happen to match instead of miss along the way (a match
        // never adds rows, only a miss with livesLeft already at 0 does) —
        // nowhere near GameLayout.original.gameOverRow (16).
        let random = ScriptedRandom(Array(repeating: [0, 1, 2, 3, 4, 5], count: 800).flatMap { $0 })
        let decoy: [GameSnapshot.BubbleRecord] = [.init(boardX: 16, boardY: 0, color: .yellow)]
        let engine = GameEngine(board: decoy, readyColor: .blue, queueColor: .red, random: random)
        engine.advance(ms: 510)

        let angles: [Double] = [-60, 60, -30, 30, -15, 15, -45, 45, 0, 70, -70]
        var rowDropCount = 0
        var shotIndex = 0

        while rowDropCount < 3 && shotIndex < 80 {
            guard engine.canFire else { break }
            let angle = angles[shotIndex % angles.count]
            XCTAssertTrue(engine.fire(angleDegrees: angle), "shot \(shotIndex)")
            engine.runUntilIdle()
            let events = engine.drainEvents()
            shotIndex += 1

            guard events.contains(where: { if case .rowsAdded = $0 { return true }; return false }) else { continue }
            rowDropCount += 1

            // (a) every board bubble sits inside its own row's valid column
            // range — the cell-validity rule replacing the old "boardX >=
            // boardWidth -> -1" hack.
            for b in engine.boardBubbles {
                let width = Grid.columns(inRow: b.boardY, rowParity: engine.rowParity)
                XCTAssertTrue(
                    (0..<width).contains(b.boardX),
                    "drop \(rowDropCount): (\(b.boardX),\(b.boardY)) outside 0..<\(width)"
                )
            }

            // (b) rows' left/right edges take exactly the two symmetric
            // values — the straight-edge silhouette itself.
            let presentRows = Set(engine.boardBubbles.map { $0.boardY })
            XCTAssertFalse(presentRows.isEmpty, "drop \(rowDropCount): board unexpectedly empty")
            let leftEdges = Set(presentRows.map {
                Grid.realCoord(boardX: 0, boardY: $0, rowParity: engine.rowParity).x - GameConsts.bubbleSize / 2
            })
            let rightEdges = Set(presentRows.map { row -> Double in
                let width = Grid.columns(inRow: row, rowParity: engine.rowParity)
                return Grid.realCoord(boardX: width - 1, boardY: row, rowParity: engine.rowParity).x + GameConsts.bubbleSize / 2
            })
            XCTAssertEqual(leftEdges, [GameConsts.boardMinX, GameConsts.leftBoardBorder],
                            "drop \(rowDropCount): left edges \(leftEdges)")
            XCTAssertEqual(rightEdges, [GameConsts.boardMaxX, GameConsts.rightBoardBorder],
                            "drop \(rowDropCount): right edges \(rightEdges)")

            // (c) no two bubbles ever share a cell.
            var seen = Set<[Int]>()
            for b in engine.boardBubbles {
                let key = [b.boardX, b.boardY]
                XCTAssertFalse(seen.contains(key), "drop \(rowDropCount): duplicate cell \(key)")
                seen.insert(key)
            }
        }

        XCTAssertGreaterThanOrEqual(rowDropCount, 3, "expected at least 3 row-drops within \(shotIndex) shots")
    }

    /// A single row-add (guaranteed via an all-6-colors row 0, so
    /// `rowsToAdd == 1`) must leave every surviving bubble's X exactly
    /// unchanged and shift its Y by exactly `rowHeight` — the whole point of
    /// flipping `rowParity` together with the shift (see
    /// `GameEngine.addOneRow`'s doc comment): the board no longer jumps
    /// sideways on a row add.
    func testRowDropKeepsBubblePositions() {
        func colorFor(_ col: Int) -> BubbleColor {
            BubbleColor(rawValue: (col + 4) % 6)!
        }
        var board: [GameSnapshot.BubbleRecord] = []
        for col in 0...16 {
            board.append(.init(boardX: col, boardY: 0, color: colorFor(col)))
        }
        XCTAssertEqual(Set((0...16).map(colorFor)), Set(BubbleColor.allCases), "sanity: all 6 colors present")

        let engine = GameEngine(
            board: board, readyColor: .green, queueColor: .green,
            livesLeft: 0, maxLives: 5, totalColors: 6,
            random: ScriptedRandom(Array(repeating: [0, 1, 2, 3, 4, 5], count: 40).flatMap { $0 })
        )
        engine.advance(ms: 510)

        let before: [Int: Vec2] = Dictionary(uniqueKeysWithValues: engine.boardBubbles.map { ($0.id, $0.position) })
        XCTAssertEqual(before.count, 17)

        // green (the ready color) doesn't match (8,0)=blue or either of its
        // row-0 neighbours, so this is a guaranteed miss; livesLeft is
        // already 0, so it triggers a row-add immediately.
        XCTAssertTrue(engine.fire(angleDegrees: 0))
        engine.runUntilIdle()
        let events = engine.drainEvents()
        XCTAssertTrue(events.contains(.rowsAdded(count: 1)), "\(events)")

        var checked = 0
        for b in engine.boardBubbles {
            guard let priorPosition = before[b.id] else { continue } // a newly-added row-0 bubble
            checked += 1
            XCTAssertEqual(b.position.x, priorPosition.x, accuracy: 1e-9, "id \(b.id): X must not change across a row drop")
            XCTAssertEqual(b.position.y, priorPosition.y + GameConsts.rowHeight, accuracy: 1e-9, "id \(b.id): Y must increase by exactly rowHeight")
        }
        XCTAssertEqual(checked, 17, "all 17 original bubbles should have survived the drop")
    }

    /// Regression: `resetBoard()` must reset `rowParity` to 0 along with
    /// everything else. Without that, restarting after any row-adds (which
    /// flip `rowParity`) would rebuild the "fresh" board under a stale,
    /// non-zero parity and silently produce a different (148-, not
    /// 149-bubble) wide/narrow split.
    func testResetBoardRestoresRowParityToZero() {
        let engine = GameEngine(random: SeededGameRandom(seed: 99))
        engine.advance(ms: 600)

        // A rich, fully-random starting board very likely has all 6 colors
        // present, so the first row-add trigger has rowsToAdd == 1 (a
        // single, odd flip) — but to stay robust regardless of exactly how
        // the seed plays out, just keep firing until rowParity is actually
        // nonzero (or give up after a generous cap).
        let angles: [Double] = [-60, -30, 0, 30, 60, -45, 45, -15, 15, 70, -70]
        var shotIndex = 0
        while engine.rowParity == 0 && shotIndex < 100 {
            guard engine.canFire else { break }
            XCTAssertTrue(engine.fire(angleDegrees: angles[shotIndex % angles.count]), "shot \(shotIndex)")
            engine.runUntilIdle()
            _ = engine.drainEvents()
            shotIndex += 1
        }
        XCTAssertEqual(engine.rowParity, 1, "expected a net-odd row-add within \(shotIndex) shots")

        engine.resetBoard()

        XCTAssertEqual(engine.rowParity, 0)
        XCTAssertEqual(engine.boardBubbles.count, 149)
        for row in 0...8 {
            let width = Grid.columns(inRow: row, rowParity: engine.rowParity)
            let cols = Set(engine.boardBubbles.filter { $0.boardY == row }.map { $0.boardX })
            XCTAssertEqual(cols, Set(0..<width), "row \(row) after reset")
        }
    }
}
