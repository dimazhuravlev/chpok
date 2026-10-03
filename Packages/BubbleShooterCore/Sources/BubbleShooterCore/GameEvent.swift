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
    /// Fired once per confirmed match (a same-color cluster of three or
    /// more), at the moment the per-bubble removals are scheduled — i.e.
    /// before the first of the matching `.removed(reason: .match)` events.
    /// `ids` lists every bubble of the cluster, including the one just fired,
    /// in the order they will be removed; `color` is the cluster's color
    /// (a cluster is always a single color). The removals themselves are
    /// staggered over time (`GameConsts.removalStaggerMs` apart), so this is
    /// the only point where a consumer learns about the whole cluster at once.
    /// Purely informational: it changes no rules, timing or scoring.
    case clusterMatched(ids: [Int], color: BubbleColor)
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
    /// `GameOver` popup. `elapsedMs` is `GameEngine.matchElapsedMs` at the
    /// moment the match ended (spec 22) — fixed here rather than read later
    /// so it doesn't keep growing while the game-over popup is open.
    case gameOver(won: Bool, score: Int, bonus: Int, elapsedMs: Int)
    case boardReset
}
