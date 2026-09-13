import Foundation

/// Pure board-grid math, ported from `BoardManager.boardCoordToRealCoord`
/// and `BoardManager.areNeighbours` (game-logic.md §3), extended by spec 13
/// ("Ряды разной ширины") with a `rowParity` parameter so the board's
/// left/right edges stay straight forever instead of the original's single
/// fixed-width, jagged-edge grid.
///
/// `rowParity` (0 or 1) is `GameEngine.rowParity`: state that flips every
/// time a row is added (see `GameEngine.addOneRow`). A row is *wide*
/// (`GameConsts.boardWidth` columns, no X offset) when
/// `((rowParity + boardY) % 2 + 2) % 2 == 0`, otherwise *narrow*
/// (`GameConsts.narrowBoardWidth` columns, `+bubbleSize/2` X offset). At the
/// default `rowParity == 0`, this reduces exactly to the original's
/// `boardY % 2` branch (even -> no offset, odd -> offset) — the original's
/// only-ever-live branch `totalRowsAdded % 2 == 0` (commented-out
/// increment, so always 0 — see §17.1) is the `rowParity == 0` case; spec 13
/// deliberately revives the other branch by actually incrementing (well,
/// toggling) that counter on every row add, both to keep the board's edges
/// straight and to stop the whole board from jumping sideways by half a
/// bubble on every row add (see `GameEngine.addOneRow`'s doc comment).
///
/// These functions take/return plain coordinates, not `Bubble` objects: the
/// original's `b1 === b2` self-exclusion in `areNeighbours` is object
/// identity, which has no meaning here — callers that iterate live bubbles
/// must additionally exclude the bubble itself (see
/// `GameEngine.neighbours(of:)`).
public enum Grid {
    /// Whether row `boardY` is wide (`GameConsts.boardWidth` columns) under
    /// the given `rowParity`, otherwise it is narrow
    /// (`GameConsts.narrowBoardWidth` columns). Uses a "safe" double-mod
    /// (`(x % 2 + 2) % 2`) so this is well-defined for negative `boardY`
    /// too, always returning the true 0/1 parity class rather than Swift's
    /// `%`, which can yield `-1` for a negative dividend.
    public static func isWideRow(_ boardY: Int, rowParity: Int = 0) -> Bool {
        ((rowParity + boardY) % 2 + 2) % 2 == 0
    }

    /// Number of columns in row `boardY`: `GameConsts.boardWidth` (17) for a
    /// wide row, `GameConsts.narrowBoardWidth` (16) for a narrow one.
    public static func columns(inRow boardY: Int, rowParity: Int = 0) -> Int {
        isWideRow(boardY, rowParity: rowParity) ? GameConsts.boardWidth : GameConsts.narrowBoardWidth
    }

    /// Ported from `boardCoordToRealCoord(x, y)`. Narrow rows are shifted
    /// `+BUBBLE_SIZE*0.5` right of wide rows (at `rowParity == 0` this is
    /// exactly the original's odd-row shift — see the type doc). `boardY`
    /// itself is never clamped: for a negative `boardY`, `isWideRow` still
    /// reports a well-defined class (see its doc), and the Y coordinate
    /// extrapolates linearly exactly as the original would — the original
    /// has no protection against negative `boardCoordY` (§6, §17.9) and
    /// this is not the place to add one.
    ///
    /// Deviation from the original (no longer a 1:1 mirror, by decision —
    /// see `GameConsts.rowHeight`): the row step is `GameConsts.rowHeight`,
    /// not `GameConsts.bubbleSize`, so this is a true hexagonal packing —
    /// all six neighbours of a cell sit exactly `bubbleSize` from its
    /// center. The X formula is unchanged apart from the wide/narrow switch.
    public static func realCoord(boardX: Int, boardY: Int, rowParity: Int = 0) -> Vec2 {
        let xOffset = isWideRow(boardY, rowParity: rowParity) ? 0.0 : GameConsts.bubbleSize * 0.5
        let x = GameConsts.initialX + Double(boardX) * GameConsts.bubbleSize + xOffset
        let y = GameConsts.initialY + Double(boardY) * GameConsts.rowHeight
        return Vec2(x: x, y: y)
    }

    /// Mirrors `areNeighbours(b1, b2)`, minus the `b1 === b2` identity check
    /// (see type doc). Passing identical coordinates therefore reports
    /// `true` for the same-row branch (`abs(0) <= 1`), exactly as the raw
    /// formula in the original would if not for that separate check.
    ///
    /// The adjacent-row branch used to be picked by `ay % 2`; it is now
    /// picked by whether row `ay` is wide or narrow, which is exactly the
    /// same branch at `rowParity == 0` (wide === even, narrow === odd) — see
    /// the type doc. A wide row's neighbours one row up/down are at columns
    /// `c-1` and `c` (the row above/below is narrower and inset right by
    /// half a bubble); a narrow row's are at `c` and `c+1`.
    public static func areNeighbours(ax: Int, ay: Int, bx: Int, by: Int, rowParity: Int = 0) -> Bool {
        if ay == by {
            return abs(ax - bx) <= 1
        }
        if abs(ay - by) > 1 { return false }
        if isWideRow(ay, rowParity: rowParity) {
            return ax == bx || ax - 1 == bx
        } else {
            return ax == bx || ax + 1 == bx
        }
    }

    /// The 6 neighbour offsets for a hex grid row, even/odd per
    /// game-logic.md §3's table, picked by wide/narrow instead of `y % 2`
    /// (see `areNeighbours`). Not used by `areNeighbours` itself (which
    /// ports the original's direct formula) but offered as the equivalent
    /// tabulated form.
    public static func neighbourOffsets(forRow y: Int, rowParity: Int = 0) -> [(dx: Int, dy: Int)] {
        if isWideRow(y, rowParity: rowParity) {
            return [(-1, 0), (1, 0), (-1, -1), (0, -1), (-1, 1), (0, 1)]
        } else {
            return [(-1, 0), (1, 0), (0, -1), (1, -1), (0, 1), (1, 1)]
        }
    }
}
