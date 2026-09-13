import Foundation

/// Mirrors the original's `STATE_*` constants (game-logic.md §1).
/// `onBoard` = `STATE_DEFAULT`, `readyToLaunch` = `STATE_READY_TO_LAUNCH`,
/// `inQueue` = `STATE_IN_QUEUE`, `launched` = `STATE_LAUNCHED`.
public enum BubbleState: Int, Codable {
    case onBoard, readyToLaunch, inQueue, launched
}

/// Mirrors the original's `Bubble` instance (game-logic.md §1). The engine
/// owns every mutation; the public setters are `internal(set)` so UI/test
/// code outside this module can only read.
public final class Bubble: Identifiable {
    /// Unique, monotonically increasing within the owning `GameEngine`. Not
    /// present in the original (which used object identity); added so
    /// `Bubble` can conform to `Identifiable` for SwiftUI-style consumers.
    public let id: Int
    public internal(set) var color: BubbleColor
    public internal(set) var state: BubbleState
    /// Valid when `state == .onBoard`. Mirrors `boardCoordX`.
    public internal(set) var boardX: Int
    /// Mirrors `boardCoordY`.
    public internal(set) var boardY: Int
    /// Center, logical px. Mirrors `imgSprite.x/y` (anchor 0.5,0.5).
    public internal(set) var position: Vec2
    /// px/tick. Mirrors `vx`/`vy`.
    public internal(set) var velocity: Vec2
    public internal(set) var isBeingRemoved: Bool

    // Internal-only, as in the original (`markedToBeRemoved`,
    // `markedToBeHanged`, `traversed`, `score`).
    var markedToBeRemoved: Bool = false
    var markedToBeHanged: Bool = false
    var traversed: Bool = false
    var pendingScore: Int = 0

    init(id: Int, color: BubbleColor, state: BubbleState, boardX: Int, boardY: Int, position: Vec2) {
        self.id = id
        self.color = color
        self.state = state
        self.boardX = boardX
        self.boardY = boardY
        self.position = position
        self.velocity = Vec2(x: 0, y: 0)
        self.isBeingRemoved = false
    }
}
