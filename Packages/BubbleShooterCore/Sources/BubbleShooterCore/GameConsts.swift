import Foundation

/// Logical, screen-size-independent constants from the original's `GameConsts`
/// (game-logic.md §0) plus a few directly-derived values used by the port.
/// Positions that depend on the on-screen canvas height (cannon/ready/queue
/// pivot, bottom of the input area, game-over threshold) live in
/// `GameLayout` instead, so there is a single source of truth for them.
public enum GameConsts {
    /// `BOARD_WIDTH` — columns on the board.
    public static let boardWidth = 17
    /// `BOARD_HEIGHT` — starting rows filled by `initBoard`.
    public static let boardHeight = 9
    /// `BUBBLE_SIZE` — px, bubble diameter / grid step.
    public static let bubbleSize: Double = 32
    /// `INITIAL_X_COORD` — px, grid origin X.
    public static let initialX: Double = 40
    /// `INITIAL_Y_COORD` — px, grid origin Y.
    public static let initialY: Double = 40
    /// `LEFT_BOARD_BORDER` — px, left bounce wall.
    public static let leftBoardBorder: Double = 37
    /// `RIGHT_BOARD_BORDER` — px, right bounce wall.
    public static let rightBoardBorder: Double = 561
    /// `TOTAL_COLORS` — total bubble colors in the game.
    public static let totalColors = 6
    /// `LAUNCH_POWER` — px/tick, magnitude of the launch velocity.
    public static let launchPower: Double = 18
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

    /// Cannon clickable rectangle (`Cannon.clickableArea`): `(25,25)` sized
    /// `560x480`. Only the X bounds and the top Y bound are screen-size
    /// independent; the bottom Y bound is `GameLayout.inputAreaMaxY`.
    public static let inputAreaMinX: Double = 25
    public static let inputAreaMinY: Double = 25
    public static let inputAreaMaxX: Double = 585

    /// Ceiling snap value used by `checkIfArrivedToPosition` when
    /// `y < BUBBLE_SIZE`: `y = 0.01 + BUBBLE_SIZE`.
    public static let ceilingSnapY: Double = 32.01
}
