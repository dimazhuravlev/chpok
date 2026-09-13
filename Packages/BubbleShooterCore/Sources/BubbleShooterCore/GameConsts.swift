import Foundation

/// Logical, screen-size-independent constants from the original's `GameConsts`
/// (game-logic.md §0) plus a few directly-derived values used by the port.
/// Positions that depend on the on-screen canvas height (cannon/ready/queue
/// pivot, bottom of the input area, game-over threshold) live in
/// `GameLayout` instead, so there is a single source of truth for them.
public enum GameConsts {
    /// `BOARD_WIDTH` — columns in a *wide* row. Rows alternate wide/narrow
    /// (spec 13, "Ряды разной ширины"): a narrow row has one fewer column
    /// (`narrowBoardWidth`), inset by half a bubble on both sides so the
    /// board's left/right silhouette stays straight forever, however many
    /// rows have been dropped. Which physical rows are wide vs. narrow is
    /// not fixed to `boardY`'s own parity — it also depends on
    /// `GameEngine.rowParity`, which flips every time a row is added (see
    /// `Grid.isWideRow`).
    public static let boardWidth = 17
    /// Columns in a *narrow* row (`boardWidth - 1`).
    public static let narrowBoardWidth = boardWidth - 1
    /// `BOARD_HEIGHT` — starting rows filled by `initBoard`.
    public static let boardHeight = 9
    /// `BUBBLE_SIZE` — px, bubble diameter / grid step.
    public static let bubbleSize: Double = 32
    /// Vertical distance between adjacent rows for a true hexagonal
    /// (close) packing: `bubbleSize * sqrt(3) / 2`. Combined with the
    /// unchanged horizontal step (`bubbleSize`) and odd-row half-step
    /// offset, this places all six neighbours of any cell at exactly
    /// `bubbleSize` from its center — including the four diagonal
    /// neighbours, which a naive `rowHeight == bubbleSize` grid would push
    /// out to `sqrt((bubbleSize/2)^2 + bubbleSize^2) ≈ 35.78`, leaving
    /// visible gaps between rows.
    public static let rowHeight: Double = bubbleSize * (3.0.squareRoot() / 2)
    /// `INITIAL_X_COORD` — px, grid origin X: center-x of column 0 of a
    /// wide row.
    public static let initialX: Double = 40
    /// `INITIAL_Y_COORD` — px, grid origin Y.
    public static let initialY: Double = 40

    /// Left edge of the logical board span: half a bubble left of the
    /// center of column 0 of a wide row. A narrow row's column 0 sits at
    /// `boardMinX + bubbleSize` (inset by half a bubble from this edge).
    public static let boardMinX: Double = initialX - bubbleSize / 2
    /// Right edge of the logical board span: half a bubble right of the
    /// center of the last column of a wide row. A narrow row's last column
    /// sits at `boardMaxX - bubbleSize` (inset by half a bubble from this
    /// edge).
    public static let boardMaxX: Double = initialX + bubbleSize * Double(boardWidth - 1) + bubbleSize / 2
    /// Width of the logical board span, `boardMaxX - boardMinX`.
    public static let boardLogicalWidth: Double = boardMaxX - boardMinX

    /// `LEFT_BOARD_BORDER` — px, left bounce wall: the center-x of column 0
    /// of a wide row, i.e. half a bubble in from `boardMinX`. Derived, not
    /// a magic number, so it stays symmetric with `rightBoardBorder` about
    /// the wide row.
    public static let leftBoardBorder: Double = boardMinX + bubbleSize / 2
    /// `RIGHT_BOARD_BORDER` — px, right bounce wall: the center-x of the
    /// last column of a wide row, i.e. half a bubble in from `boardMaxX`.
    public static let rightBoardBorder: Double = boardMaxX - bubbleSize / 2
    /// `TOTAL_COLORS` — total bubble colors in the game.
    public static let totalColors = 6
    /// `LAUNCH_POWER` — px/tick, magnitude of the launch velocity.
    public static let launchPower: Double = 18
    /// Flight sub-steps per tick (spec 18, "faster bubble flight"). Not part
    /// of the original — `GameEngine.tick()` runs the launched bubble's
    /// single-step update this many times per tick on average (via an
    /// accumulator, see `GameEngine.flightAccumulator`), so the flight covers
    /// more ground per tick without the step itself ever changing size: each
    /// sub-step is still exactly one `launchPower`-sized move with its own
    /// full collision/bounce check. The step must stay `launchPower` and
    /// must not grow — a bigger single step risks skipping straight past a
    /// neighbour before `collisionDistance` can register a hit (tunnelling).
    public static let flightStepsPerTick: Double = 1.5
    /// Fixed simulation tick, ms (see "Решённые развилки").
    public static let tickMs = 15
    /// `WIDTH` — logical canvas width, px (canvas height is layout-dependent,
    /// see `GameLayout.canvasHeight`).
    public static let canvasWidth: Double = 800

    /// `Util.CircleCollision` threshold: `BUBBLE_SIZE * 0.75`.
    public static let collisionDistance: Double = 24
    /// Clamp range for the aiming/launch angle, degrees.
    public static let maxAngleDegrees: Double = 75
    /// Per-bubble removal stagger, ms (`70 * i` in `removeSameColorCluster`
    /// and `markHangingClusters`).
    public static let removalStaggerMs = 70
    /// Delay before `addNewRow()` once lives are exhausted, ms.
    public static let addRowDelayMs = 100
    /// Win-check poll interval, ms (`MainUI`'s `gameWonCheck` loop).
    public static let winCheckIntervalMs = 1000
    /// Starting/reset lives and max lives.
    public static let initialLives = 5

    /// Cannon clickable rectangle (`Cannon.clickableArea`). Only the X
    /// bounds and the top Y bound are screen-size independent; the bottom Y
    /// bound is `GameLayout.inputAreaMaxY`. X bounds now track the board
    /// span exactly (`boardMinX`/`boardMaxX`), not the original's
    /// independent `(25, 585)` magic numbers.
    public static let inputAreaMinX: Double = boardMinX
    public static let inputAreaMinY: Double = 25
    public static let inputAreaMaxX: Double = boardMaxX

    /// Ceiling snap value used by `checkIfArrivedToPosition` when
    /// `y < BUBBLE_SIZE`: `y = 0.01 + BUBBLE_SIZE`.
    public static let ceilingSnapY: Double = 32.01
}
