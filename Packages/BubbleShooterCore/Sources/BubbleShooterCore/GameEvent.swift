import Foundation

/// Why a bubble was removed: a same-color cluster match, or a hanging
/// (disconnected-from-ceiling) sweep.
public enum RemovalReason: Equatable {
    case match, hanging
}

/// Discrete events the engine emits while simulating, drained via
/// `GameEngine.drainEvents()`. The UI is expected to animate off of these;
/// current state (positions etc.) is read directly from `bubbles`.
public enum GameEvent: Equatable {
    case launched(id: Int, angleDegrees: Double)
    case landed(id: Int, boardX: Int, boardY: Int)
    /// Fired at the moment of actual removal (mirrors `Bubble.remove`), not
    /// at the moment a bubble is merely marked for removal.
    case removed(id: Int, color: BubbleColor, position: Vec2, points: Int, reason: RemovalReason)
    case scoreChanged(score: Int)
    case lifeLost(livesLeft: Int)
    case livesReset(livesLeft: Int, maxLives: Int)
    /// Fired after `addNewRow` fully completes (all rows added, positions
    /// recomputed).
    case rowsAdded(count: Int)
    case readyBubbleChanged(id: Int, color: BubbleColor)
    case queueBubbleChanged(id: Int, color: BubbleColor)
    /// Fired the moment the engine first becomes idle after a shot (see
    /// `GameEngine.isIdle`).
    case turnResolved
    /// `bonus == score` on a win, `0` on a loss, mirroring the original's
    /// `GameOver` popup.
    case gameOver(won: Bool, score: Int, bonus: Int)
    case boardReset
}
