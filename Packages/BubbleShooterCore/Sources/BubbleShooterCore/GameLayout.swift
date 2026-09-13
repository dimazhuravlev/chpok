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

    /// `Cannon` pivot, `(WIDTH*0.37, cannonY)`. X is fixed as in the
    /// original (see game-logic.md §0/§4); only Y follows the layout.
    public var cannonPivot: Vec2 { Vec2(x: 296, y: cannonY) }

    /// Ready-bubble position, `(WIDTH*0.37, cannonY)` — same point as the
    /// cannon pivot (see game-logic.md §0: the ready bubble converges to the
    /// cannon's own position every tick via `setToMyRealCoord`).
    public var readyPosition: Vec2 { Vec2(x: 296, y: cannonY) }

    /// Queue-bubble position, `(WIDTH*0.05, cannonY)`.
    public var queuePosition: Vec2 { Vec2(x: 40, y: cannonY) }

    /// Whether `p` falls inside the cannon's clickable rectangle
    /// (`onInputDown` only fires for pointer-downs inside it).
    public func containsInputPoint(_ p: Vec2) -> Bool {
        p.x >= GameConsts.inputAreaMinX && p.x <= GameConsts.inputAreaMaxX &&
        p.y >= GameConsts.inputAreaMinY && p.y <= inputAreaMaxY
    }

    /// Row threshold for the loss condition (`boardCoordY > gameOverRow`).
    /// Derived so that `GameLayout.original.gameOverRow == 14`, matching the
    /// original's hardcoded `boardCoordY > 14`.
    public var gameOverRow: Int {
        Int(floor((cannonY - 104) / GameConsts.bubbleSize))
    }

    /// Pixel-Y threshold for the loss condition (`imgSprite.y > gameOverY`).
    /// Derived so that `GameLayout.original.gameOverY == 470`, matching the
    /// original's hardcoded `imgSprite.y > 470`.
    public var gameOverY: Double {
        GameConsts.initialY + GameConsts.bubbleSize * Double(gameOverRow) - 18
    }
}
