import XCTest
@testable import BubbleShooterCore

/// Snap invariants (game-logic.md §6/§7) across a series of shots on the
/// full starting board: no two board bubbles ever share a cell, no bubble
/// ends up above row 0, and every bubble that lands is either adjacent to an
/// existing board bubble or itself in row 0.
final class SnapTests: XCTestCase {

    func testThirtyShotsPreserveGridInvariants() {
        let engine = GameEngine(random: SeededGameRandom(seed: 3))
        engine.advance(ms: 600)

        let angles: [Double] = [-60, -30, 0, 30, 60]
        var adjacencyViolations: [(shot: Int, x: Int, y: Int)] = []

        for i in 0..<30 {
            guard engine.canFire else { break } // e.g. isGameOver from accumulated row-adds
            let angle = angles[i % angles.count]

            // Snapshot pre-shot board cells: the "neighbour" side of the
            // invariant is about the cell the bubble snapped to being
            // adjacent to a bubble that was already on the board when it
            // collided — checked via the immutable `.landed` event rather
            // than a post-hoc live-object lookup, because a same-tick match
            // can remove the just-landed bubble (delay 70*i with i=0)
            // before we get a chance to look it up (game-logic.md §8).
            let priorCoords = engine.boardBubbles.map { [$0.boardX, $0.boardY] }
            // Spec 13: `rowParity` can itself change *during* this shot's own
            // resolution (a miss that empties lives triggers a row-add,
            // which flips it) — captured here, alongside `priorCoords`,
            // because the bubble actually lands under whatever `rowParity`
            // was active at landing time, which is always this
            // *pre*-resolution value: `resolveLanding` runs before
            // `bubbleArrived` -> `loseOneLife` -> any row-add it triggers.
            let rowParityAtLanding = engine.rowParity

            XCTAssertTrue(engine.fire(angleDegrees: angle), "shot \(i) at \(angle) degrees should fire")
            engine.runUntilIdle()

            let events = engine.drainEvents()
            guard case let .landed(_, landedX, landedY)? = events.first(where: {
                if case .landed = $0 { return true }
                return false
            }) else {
                XCTFail("shot \(i) should have produced a .landed event")
                continue
            }

            let isNeighbourOfPriorBoard = priorCoords.contains {
                Grid.areNeighbours(ax: landedX, ay: landedY, bx: $0[0], by: $0[1], rowParity: rowParityAtLanding)
            }
            if !(isNeighbourOfPriorBoard || landedY == 0) {
                adjacencyViolations.append((i, landedX, landedY))
            }

            var seen = Set<[Int]>()
            for b in engine.boardBubbles {
                XCTAssertGreaterThanOrEqual(b.boardY, 0, "shot \(i): board bubble above row 0")
                let key = [b.boardX, b.boardY]
                XCTAssertFalse(seen.contains(key), "shot \(i): duplicate board position \(key)")
                seen.insert(key)
            }
        }

        // `assignStateDefaultCoords` (game-logic.md §6) snaps to the grid
        // cell nearest the bubble's post-collision *pixel* anchor — it does
        // not search for a cell actually touching the bubble it collided
        // with. Before spec 11 (true hexagonal packing, `GameConsts.rowHeight`),
        // that pixel-nearest snap and `Grid.areNeighbours`'s board-coordinate
        // adjacency check could disagree: the old grid used `rowHeight ==
        // bubbleSize`, so a diagonal step in board coordinates covered
        // ~35.78px in real pixels instead of exactly `bubbleSize` — enough
        // slack that a grazing collision (this scripted seed-3/angle-cycle
        // run's shot 10) could round to a cell that wasn't actually a
        // neighbour of anything on the board, even though a real collision
        // occurred. A ≤1-violation tolerance used to guard this exact,
        // provable (not a bug) edge case.
        //
        // Under true hex packing, pixel-nearest and board-adjacent agree —
        // every one of a cell's six board-neighbours now sits at exactly
        // `bubbleSize` in real coordinates (see
        // `GridTests.testAllSixNeighboursAreExactlyOneDiameterApart`) — and
        // this run (including former shot 10) now lands adjacent every
        // time, so the tolerance is tightened to zero. A violation here
        // would point at a real regression.
        XCTAssertEqual(
            adjacencyViolations.count, 0,
            "unexpectedly many non-adjacent, non-row-0 landings: \(adjacencyViolations)"
        )
    }
}
