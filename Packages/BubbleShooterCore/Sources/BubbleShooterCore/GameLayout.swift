import Foundation

/// Screen-size-dependent positions the engine needs: the cannon pivot (also
/// the ready/queue bubble position, see game-logic.md §0) and the bottom
/// edge of the clickable input rectangle. In the original these are fixed
/// (`WIDTH*0.37, HEIGHT*0.92`) because the canvas is a fixed 800x600; the
/// app stretches the board to fill the screen under a header, so the cannon
/// sits at the bottom of the *real* canvas, not at a hardcoded y=552.
///
/// `GameLayout.original` reproduces the original 1:1 and is the default used
/// everywhere (including tests). Game logic itself never depends on layout
/// except through the handful of points/thresholds exposed here.
public struct GameLayout: Equatable {
    /// Logical canvas height, px. Original: 600.
    public var canvasHeight: Double
    /// Y of the cannon pivot and of the ready/queue bubble centers.
    /// Original: 552 (= 600 * 0.92).
    public var cannonY: Double
    /// Bottom edge of the clickable input rectangle. Original: 505 (= 25 + 480).
    public var inputAreaMaxY: Double

    public init(canvasHeight: Double, cannonY: Double, inputAreaMaxY: Double) {
        self.canvasHeight = canvasHeight
        self.cannonY = cannonY
        self.inputAreaMaxY = inputAreaMaxY
    }

    /// Reproduces the original's fixed 800x600 canvas exactly.
    public static let original = GameLayout(canvasHeight: 600, cannonY: 552, inputAreaMaxY: 505)

    /// Derives a layout for an arbitrary canvas height, keeping the cannon a
    /// fixed distance from the bottom edge and the input area a fixed
    /// distance above the cannon.
    public static func fitting(canvasHeight: Double) -> GameLayout {
        let cannonY = canvasHeight - 48
        let inputAreaMaxY = cannonY - 64
        return GameLayout(canvasHeight: canvasHeight, cannonY: cannonY, inputAreaMaxY: inputAreaMaxY)
    }

    /// `Cannon` pivot, originally `(WIDTH*0.37, cannonY)`; X is now derived
    /// as the center of the board's logical span (spec 13), which happens
    /// to equal the original's fixed 296 exactly. Only Y follows the layout.
    public var cannonPivot: Vec2 { Vec2(x: GameConsts.boardMinX + GameConsts.boardLogicalWidth / 2, y: cannonY) }

    /// Ready-bubble position — same point as the cannon pivot (see
    /// game-logic.md §0: the ready bubble converges to the cannon's own
    /// position every tick via `setToMyRealCoord`).
    public var readyPosition: Vec2 { Vec2(x: GameConsts.boardMinX + GameConsts.boardLogicalWidth / 2, y: cannonY) }

    /// Queue-bubble position, `(GameConsts.initialX, cannonY)` — originally
    /// `WIDTH*0.05`, which is the same 40px value as the board's own X
    /// origin.
    public var queuePosition: Vec2 { Vec2(x: GameConsts.initialX, y: cannonY) }

    /// Whether `p` falls inside the cannon's clickable rectangle
    /// (`onInputDown` only fires for pointer-downs inside it).
    public func containsInputPoint(_ p: Vec2) -> Bool {
        p.x >= GameConsts.inputAreaMinX && p.x <= GameConsts.inputAreaMaxX &&
        p.y >= GameConsts.inputAreaMinY && p.y <= inputAreaMaxY
    }

    /// Row threshold for the loss condition (`boardCoordY > gameOverRow`).
    /// Uses `GameConsts.rowHeight`, not `bubbleSize`, so the threshold
    /// tracks the true hex-packing row pitch (see `GameConsts.rowHeight`):
    /// `GameLayout.original.gameOverRow == 16` (more rows now fit in the
    /// same pixel span than the original's hardcoded `boardCoordY > 14`,
    /// since rows are packed tighter).
    public var gameOverRow: Int {
        Int(floor((cannonY - 104) / GameConsts.rowHeight))
    }

    /// Pixel-Y threshold for the loss condition (`imgSprite.y > gameOverY`).
    /// Uses `GameConsts.rowHeight` so this stays approximately the original
    /// pixel height (`GameLayout.original.gameOverY ≈ 465.4`, close to the
    /// original's hardcoded `imgSprite.y > 470`) even though `gameOverRow`
    /// itself grew.
    public var gameOverY: Double {
        GameConsts.initialY + GameConsts.rowHeight * Double(gameOverRow) - 18
    }
}
