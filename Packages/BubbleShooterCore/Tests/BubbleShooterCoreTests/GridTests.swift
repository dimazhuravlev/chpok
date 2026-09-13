import XCTest
@testable import BubbleShooterCore

/// Pure grid-math tests for `Grid` (game-logic.md §3): `realCoord` against
/// `boardCoordToRealCoord` and `areNeighbours`/`neighbourOffsets` against the
/// even/odd-row neighbour table.
final class GridTests: XCTestCase {

    // MARK: - realCoord

    func testRealCoordKnownPoints() {
        XCTAssertEqual(Grid.realCoord(boardX: 0, boardY: 0), Vec2(x: 40, y: 40))
        XCTAssertEqual(Grid.realCoord(boardX: 1, boardY: 0), Vec2(x: 72, y: 40))
        XCTAssertEqual(Grid.realCoord(boardX: 0, boardY: 1), Vec2(x: 56, y: 72))
        XCTAssertEqual(Grid.realCoord(boardX: 16, boardY: 8), Vec2(x: 552, y: 296))
        XCTAssertEqual(Grid.realCoord(boardX: 16, boardY: 9), Vec2(x: 568, y: 328))
    }

    // MARK: - neighbourOffsets: full even/odd table (§3)

    func testNeighbourOffsetsEvenRow() {
        let expected: Set<[Int]> = [[-1, 0], [1, 0], [-1, -1], [0, -1], [-1, 1], [0, 1]]
        let actual = Set(Grid.neighbourOffsets(forRow: 0).map { [$0.dx, $0.dy] })
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.count, 6)
    }

    func testNeighbourOffsetsOddRow() {
        let expected: Set<[Int]> = [[-1, 0], [1, 0], [0, -1], [1, -1], [0, 1], [1, 1]]
        let actual = Set(Grid.neighbourOffsets(forRow: 1).map { [$0.dx, $0.dy] })
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.count, 6)
    }

    /// A bubble's own cell is never one of its 6 offsets, for either parity
    /// (the reference's "a bubble is not its own neighbour" — see the
    /// interpretation note in the task report about where self-exclusion
    /// actually lives in this port).
    func testNeighbourOffsetsNeverIncludeSelf() {
        XCTAssertFalse(Grid.neighbourOffsets(forRow: 0).contains { $0.dx == 0 && $0.dy == 0 })
        XCTAssertFalse(Grid.neighbourOffsets(forRow: 1).contains { $0.dx == 0 && $0.dy == 0 })
    }

    /// Every tabulated offset round-trips through `areNeighbours`, for both
    /// row parities, at several sample origins.
    func testOffsetsAgreeWithAreNeighbours() {
        for originY in [0, 2, 4, 1, 3, 5] {
            let offsets = Grid.neighbourOffsets(forRow: originY)
            for originX in [0, 5, 8, 16] {
                for offset in offsets {
                    let bx = originX + offset.dx
                    let by = originY + offset.dy
                    XCTAssertTrue(
                        Grid.areNeighbours(ax: originX, ay: originY, bx: bx, by: by),
                        "(\(originX),\(originY)) should be neighbours with (\(bx),\(by)) via offset \(offset)"
                    )
                }
            }
        }
    }

    // MARK: - areNeighbours: symmetry + known non-neighbours

    func testAreNeighboursSymmetric() {
        for ay in -2...10 {
            for ax in -2...18 {
                for by in -2...10 {
                    for bx in -2...18 where !(ax == bx && ay == by) {
                        let forward = Grid.areNeighbours(ax: ax, ay: ay, bx: bx, by: by)
                        let backward = Grid.areNeighbours(ax: bx, ay: by, bx: ax, by: ay)
                        if forward != backward {
                            XCTFail("asymmetric: (\(ax),\(ay)) vs (\(bx),\(by)): \(forward) != \(backward)")
                            return
                        }
                    }
                }
            }
        }
    }

    func testKnownNonNeighbours() {
        // Same row, two cells apart.
        XCTAssertFalse(Grid.areNeighbours(ax: 0, ay: 0, bx: 2, by: 0))
        XCTAssertFalse(Grid.areNeighbours(ax: 2, ay: 0, bx: 0, by: 0))
    }

    func testKnownNeighboursEvenRow() {
        // (5,4) even row: neighbours are (4,4),(6,4),(4,3),(5,3),(4,5),(5,5).
        let neighbours: [(Int, Int)] = [(4, 4), (6, 4), (4, 3), (5, 3), (4, 5), (5, 5)]
        for (bx, by) in neighbours {
            XCTAssertTrue(Grid.areNeighbours(ax: 5, ay: 4, bx: bx, by: by), "(5,4) vs (\(bx),\(by))")
        }
        XCTAssertFalse(Grid.areNeighbours(ax: 5, ay: 4, bx: 6, by: 3))
        XCTAssertFalse(Grid.areNeighbours(ax: 5, ay: 4, bx: 4, by: 6))
    }

    func testKnownNeighboursOddRow() {
        // (5,3) odd row: neighbours are (4,3),(6,3),(5,2),(6,2),(5,4),(6,4).
        let neighbours: [(Int, Int)] = [(4, 3), (6, 3), (5, 2), (6, 2), (5, 4), (6, 4)]
        for (bx, by) in neighbours {
            XCTAssertTrue(Grid.areNeighbours(ax: 5, ay: 3, bx: bx, by: by), "(5,3) vs (\(bx),\(by))")
        }
        XCTAssertFalse(Grid.areNeighbours(ax: 5, ay: 3, bx: 4, by: 2))
        XCTAssertFalse(Grid.areNeighbours(ax: 5, ay: 3, bx: 4, by: 4))
    }

    /// Documents the actual, intentional behaviour: `Grid.areNeighbours`
    /// mirrors the original's raw formula only — the original's separate
    /// `b1 === b2` identity guard is deliberately implemented one layer up,
    /// at `GameEngine.neighbours(of:)` (object identity has no meaning for
    /// a pure coordinate function). Passing identical coordinates therefore
    /// hits the same-row branch (`abs(0) <= 1`) and reports `true`. See the
    /// task report for why this is not treated as a core deviation.
    func testAreNeighboursSelfCoordinateIsRawFormulaTrue() {
        XCTAssertTrue(Grid.areNeighbours(ax: 3, ay: 3, bx: 3, by: 3))
    }
}
