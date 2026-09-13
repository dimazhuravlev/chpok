import Foundation

/// Pure board-grid math, ported from `BoardManager.boardCoordToRealCoord`
/// and `BoardManager.areNeighbours` (game-logic.md §3) under the original's
/// only-ever-live branch `totalRowsAdded % 2 == 0` (the original increments
/// `totalRowsAdded` in a commented-out line, so it is always 0 — see §17.1).
/// These functions take/return plain coordinates, not `Bubble` objects: the
/// original's `b1 === b2` self-exclusion in `areNeighbours` is object
/// identity, which has no meaning here — callers that iterate live bubbles
/// must additionally exclude the bubble itself (see
/// `GameEngine.neighbours(of:)`).
public enum Grid {
    /// Mirrors `boardCoordToRealCoord(x, y)`. Odd rows are shifted
    /// `+BUBBLE_SIZE*0.5` right of even rows. `boardY % 2` is used as-is
    /// (matching the original's `Math.floor(y % 2)`, a no-op for integer
    /// `y`): for a negative `boardY`, this yields a negative offset exactly
    /// as the original would, rather than a "corrected" 0/1 parity — the
    /// original has no protection against negative `boardCoordY` (§6, §17.9)
    /// and this is not the place to add one.
    public static func realCoord(boardX: Int, boardY: Int) -> Vec2 {
        let x = GameConsts.initialX
            + Double(boardX) * GameConsts.bubbleSize
            + Double(boardY % 2) * GameConsts.bubbleSize * 0.5
        let y = GameConsts.initialY + Double(boardY) * GameConsts.bubbleSize
        return Vec2(x: x, y: y)
    }

    /// Mirrors `areNeighbours(b1, b2)`, minus the `b1 === b2` identity check
    /// (see type doc). Passing identical coordinates therefore reports
    /// `true` for the same-row branch (`abs(0) <= 1`), exactly as the raw
    /// formula in the original would if not for that separate check.
    public static func areNeighbours(ax: Int, ay: Int, bx: Int, by: Int) -> Bool {
        if ay == by {
            return abs(ax - bx) <= 1
        }
        if abs(ay - by) > 1 { return false }
        if ay % 2 == 0 {
            return ax == bx || ax - 1 == bx
        } else {
            return ax == bx || ax + 1 == bx
        }
    }

    /// The 6 neighbour offsets for a hex grid row, even/odd per
    /// game-logic.md §3's table. Not used by `areNeighbours` itself (which
    /// ports the original's direct formula) but offered as the equivalent
    /// tabulated form.
    public static func neighbourOffsets(forRow y: Int) -> [(dx: Int, dy: Int)] {
        if y % 2 == 0 {
            return [(-1, 0), (1, 0), (-1, -1), (0, -1), (-1, 1), (0, 1)]
        } else {
            return [(-1, 0), (1, 0), (0, -1), (1, -1), (0, 1), (1, 1)]
        }
    }
}
