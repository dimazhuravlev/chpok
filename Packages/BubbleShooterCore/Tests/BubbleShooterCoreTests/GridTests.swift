import XCTest
@testable import BubbleShooterCore

/// Pure grid-math tests for `Grid` (game-logic.md §3): `realCoord` against
/// `boardCoordToRealCoord` and `areNeighbours`/`neighbourOffsets` against the
/// even/odd-row neighbour table.
final class GridTests: XCTestCase {

    // MARK: - realCoord

    /// Row step is `GameConsts.rowHeight` (16√3 ≈ 27.712812921102035), not
    /// `bubbleSize` (32) — true hex packing, see `GameConsts.rowHeight`.
    /// Y values are irrational, so these compare with a tight `accuracy`
    /// rather than exact `Vec2` equality.
    ///
    /// Spec 13: at the default `rowParity == 0`, row 0 is wide (columns
    /// 0...16, x 40...552) and row 1 is narrow (columns 0...15, x 56...536)
    /// — inset exactly `bubbleSize/2` (16px) from row 0's span on *both*
    /// edges, the symmetric straight-edge silhouette spec 13 introduces.
    func testRealCoordKnownPoints() {
        let p00 = Grid.realCoord(boardX: 0, boardY: 0)
        XCTAssertEqual(p00.x, 40, accuracy: 1e-9)
        XCTAssertEqual(p00.y, 40, accuracy: 1e-9)

        let p16_0 = Grid.realCoord(boardX: 16, boardY: 0)
        XCTAssertEqual(p16_0.x, 552, accuracy: 1e-9)
        XCTAssertEqual(p16_0.y, 40, accuracy: 1e-9)

        let p0_1 = Grid.realCoord(boardX: 0, boardY: 1)
        XCTAssertEqual(p0_1.x, 56, accuracy: 1e-9)
        XCTAssertEqual(p0_1.y, 67.712812921102035, accuracy: 1e-9)

        let p15_1 = Grid.realCoord(boardX: 15, boardY: 1)
        XCTAssertEqual(p15_1.x, 536, accuracy: 1e-9)
        XCTAssertEqual(p15_1.y, 67.712812921102035, accuracy: 1e-9)

        // Deeper-row sanity, same wide/narrow rule: row 8 is wide (even),
        // row 9 is narrow (odd).
        let p16_8 = Grid.realCoord(boardX: 16, boardY: 8)
        XCTAssertEqual(p16_8.x, 552, accuracy: 1e-9)
        XCTAssertEqual(p16_8.y, 261.70250336881628, accuracy: 1e-9)

        let p15_9 = Grid.realCoord(boardX: 15, boardY: 9)
        XCTAssertEqual(p15_9.x, 536, accuracy: 1e-9)
        XCTAssertEqual(p15_9.y, 289.41531628991831, accuracy: 1e-9)
    }

    /// Spec 13: `Grid.columns(inRow:)` returns 17 for a wide row and 16 for
    /// a narrow one, and the two flip with `rowParity`.
    func testColumnsInRow() {
        XCTAssertEqual(Grid.columns(inRow: 0), 17)
        XCTAssertEqual(Grid.columns(inRow: 1), 16)
        XCTAssertEqual(Grid.columns(inRow: 0, rowParity: 1), 16)
        XCTAssertEqual(Grid.columns(inRow: 1, rowParity: 1), 17)
    }

    /// Spec 11: every one of a cell's six tabulated neighbours (both row
    /// parities) sits exactly `bubbleSize` away in real coordinates — the
    /// defining property of a true hexagonal (close) packing. Sampled at a
    /// few interior rows/columns so both even and odd row parity are
    /// covered. Spec 13 extends this across both `GameEngine.rowParity`
    /// values (0 and 1) too — the hex-packing property must hold no matter
    /// how many rows have been dropped.
    func testAllSixNeighboursAreExactlyOneDiameterApart() {
        for rowParity in [0, 1] {
            for row in [4, 5] {
                for col in 3...6 {
                    let origin = Grid.realCoord(boardX: col, boardY: row, rowParity: rowParity)
                    for offset in Grid.neighbourOffsets(forRow: row, rowParity: rowParity) {
                        let neighbour = Grid.realCoord(boardX: col + offset.dx, boardY: row + offset.dy, rowParity: rowParity)
                        XCTAssertEqual(
                            origin.distance(to: neighbour), GameConsts.bubbleSize, accuracy: 1e-9,
                            "rowParity \(rowParity): (\(col),\(row)) + offset (\(offset.dx),\(offset.dy)) should be exactly bubbleSize apart"
                        )
                    }
                }
            }
        }
    }

    /// Spec 11: `rowHeight` is the height of a row of a true hexagonal
    /// packing (`bubbleSize * sqrt(3)/2`) and, being the short leg of that
    /// packing, is strictly less than the bubble diameter itself.
    func testRowHeightIsHexPacking() {
        XCTAssertEqual(GameConsts.rowHeight, 32 * (3.0.squareRoot() / 2), accuracy: 1e-12)
        XCTAssertLessThan(GameConsts.rowHeight, GameConsts.bubbleSize)
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
