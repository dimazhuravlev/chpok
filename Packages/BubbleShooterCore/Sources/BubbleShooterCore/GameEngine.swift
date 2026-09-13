import Foundation

/// Deterministic port of the original's game logic (`BoardManager`,
/// `Bubble`, `Cannon`, `LivesUI`, `MainUI`, `SimpleGame`'s game-over/win
/// handling — see game-logic.md and "Решённые развилки"). No UI/rendering:
/// callers drive time via `tick()`/`advance(ms:)`, read state from
/// `bubbles`/the published properties, and observe transitions via
/// `drainEvents()`.
///
/// See `GameEngine+Rules.swift` for the internal port of the original's
/// individual functions (flight, snap, matching, hanging clusters, lives,
/// rows, game over/win, random color).
public final class GameEngine {
    /// Delay before `cannonEnabled` flips true after `initBoard`/`resetBoard`
    /// (game-logic.md §2/§15: `Cannon.cannonEnabled = false`, then a 500ms
    /// one-shot timer sets it true). Not part of `GameConsts` because it is
    /// not listed in the reference's §0 constants table (it is narrative in
    /// §2/§15), matching the spec's "only what's in §0" scope for
    /// `GameConsts`.
    static let cannonEnableDelayMs = 500

    /// All positions that depend on screen/canvas height (cannon pivot,
    /// ready/queue position, input-area bottom, game-over threshold).
    public let layout: GameLayout

    /// Mirrors `Bubble.bubbleArr`: every live bubble regardless of state
    /// (board + ready + queue + launched), in creation order (see
    /// game-logic.md §1). Removal happens exactly when a bubble is spliced
    /// from this array, matching the original's `Bubble.remove`/
    /// `removeImmediately`.
    public internal(set) var bubbles: [Bubble] = []

    public var boardBubbles: [Bubble] {
        bubbles.filter { $0.state == .onBoard && !$0.isBeingRemoved }
    }

    public internal(set) var readyBubble: Bubble?
    public internal(set) var queueBubble: Bubble?
    public internal(set) var launchedBubble: Bubble?
    public internal(set) var score: Int = 0
    public internal(set) var livesLeft: Int = GameConsts.initialLives
    public internal(set) var maxLives: Int = GameConsts.initialLives
    public internal(set) var totalColors: Int = GameConsts.totalColors
    public internal(set) var isGameOver: Bool = false
    /// Mirrors `Cannon.addNewRowInProgress`.
    public internal(set) var isAddingRow: Bool = false
    public internal(set) var timeMs: Int = 0
    /// Original convention: 0 = up, positive = right, range [-75, 75].
    public internal(set) var aimAngleDegrees: Double = 0

    public var isIdle: Bool {
        launchedBubble == nil
            && !bubbles.contains(where: { $0.isBeingRemoved })
            && !timerQueue.hasPending
            && !isAddingRow
    }

    /// Mirrors `cannonFired`'s guard chain: `!addNewRowInProgress &&
    /// !promptActive && cannonEnabled`, plus the implicit requirement that a
    /// ready bubble exists (game-logic.md §4).
    public var canFire: Bool {
        !isAddingRow && !isGameOver && cannonEnabled && readyBubble != nil
    }

    // MARK: - Internal simulation state (shared with GameEngine+Rules.swift)

    var random: any GameRandom
    var events: [GameEvent] = []
    let timerQueue = TimerQueue()
    var nextBubbleId: Int = 0
    /// True from a successful `fire` until the engine next becomes idle;
    /// drives the one-shot `.turnResolved` event.
    var turnInProgress: Bool = false
    var cannonEnabled: Bool = false
    /// Next absolute `timeMs` at which the win-check runs. Deliberately not
    /// routed through `TimerQueue` — see its doc comment.
    var nextWinCheckAtMs: Int = GameConsts.winCheckIntervalMs
    /// Mirrors `BoardManager.timeToNewBubble`.
    var timeToNewBubble: Int = 0
    /// Mirrors `BoardManager.markHangedTime`.
    var markHangedTime: Int = 0

    // MARK: - Init

    /// Mirrors `BoardManager.initBoard()` (fully-random 17x9 board).
    public init(layout: GameLayout = .original, random: any GameRandom = SystemGameRandom()) {
        self.layout = layout
        self.random = random
        buildFullRandomBoardAndQueue()
        armCannonEnableLockout()
    }

    /// Restores a previously captured `GameSnapshot`.
    public init(snapshot: GameSnapshot, layout: GameLayout = .original, random: any GameRandom = SystemGameRandom()) {
        self.layout = layout
        self.random = random
        self.score = snapshot.score
        self.livesLeft = snapshot.livesLeft
        self.maxLives = snapshot.maxLives
        self.totalColors = snapshot.totalColors
        loadBoard(snapshot.bubbles, readyColor: snapshot.readyColor, queueColor: snapshot.queueColor)
        armCannonEnableLockout()
    }

    /// Builds an arbitrary board — for tests.
    public init(board: [GameSnapshot.BubbleRecord],
        readyColor: BubbleColor,
        queueColor: BubbleColor,
        score: Int = 0,
        livesLeft: Int = 5,
        maxLives: Int = 5,
        totalColors: Int = 6,
        layout: GameLayout = .original,
        random: any GameRandom = SeededGameRandom(seed: 1)
    ) {
        self.layout = layout
        self.random = random
        self.score = score
        self.livesLeft = livesLeft
        self.maxLives = maxLives
        self.totalColors = totalColors
        loadBoard(board, readyColor: readyColor, queueColor: queueColor)
        armCannonEnableLockout()
    }

    // MARK: - Aiming / firing

    /// Mirrors the shared angle formula used by both `Cannon.onUpdate`
    /// (aiming) and `Cannon.cannonFired` (firing), including the
    /// `angle < -180 -> 75` quirk (game-logic.md §4, §17.3).
    public static func aimAngle(from pivot: Vec2, to point: Vec2) -> Double {
        let dx = pivot.x - point.x
        let dy = pivot.y - point.y
        var angle = 180.0 / Double.pi * atan2(dy, dx) - 90.0
        if angle < -180 || angle > 75 {
            angle = 75
        } else if angle < -75 {
            angle = -75
        }
        return angle
    }

    /// Mirrors `Cannon.onUpdate` (rotation only, no physics effect).
    @discardableResult
    public func aim(toward point: Vec2) -> Double {
        aimAngleDegrees = GameEngine.aimAngle(from: layout.cannonPivot, to: point)
        return aimAngleDegrees
    }

    /// Mirrors `Cannon.cannonFired` driven by a pointer-down point.
    @discardableResult
    public func fire(toward point: Vec2) -> Bool {
        guard canFire, let ready = readyBubble else { return false }
        guard layout.containsInputPoint(point) else { return false }
        let angle = GameEngine.aimAngle(from: layout.cannonPivot, to: point)
        performLaunch(ready, angleDegrees: angle)
        return true
    }

    /// Direct-angle firing (clamped to `±maxAngleDegrees`). Not present in
    /// the original (which only ever fires from a screen point) — added per
    /// spec for deterministic tests.
    @discardableResult
    public func fire(angleDegrees: Double) -> Bool {
        guard canFire, let ready = readyBubble else { return false }
        let clamped = min(GameConsts.maxAngleDegrees, max(-GameConsts.maxAngleDegrees, angleDegrees))
        performLaunch(ready, angleDegrees: clamped)
        return true
    }

    // MARK: - Simulation

    /// Advances exactly one 15ms tick. Order: advance time -> update the
    /// launched bubble (flight/bounce/collision/snap/landing) -> game-over
    /// check for every board bubble -> run all now-eligible `TimerQueue`
    /// actions -> win-check (own interval) -> `.turnResolved` if the engine
    /// just became idle after a shot.
    public func tick() {
        timeMs += GameConsts.tickMs

        updateLaunchedBubble()

        for b in bubbles where b.state == .onBoard {
            checkGameOver(for: b)
        }

        timerQueue.fire(upToMs: timeMs)

        if timeMs >= nextWinCheckAtMs {
            checkWin()
            nextWinCheckAtMs += GameConsts.winCheckIntervalMs
        }

        if turnInProgress && isIdle {
            turnInProgress = false
            events.append(.turnResolved)
        }
    }

    /// Runs `ms / 15` ticks (integer division, rounded down).
    public func advance(ms: Int) {
        let ticks = ms / GameConsts.tickMs
        guard ticks > 0 else { return }
        for _ in 0..<ticks {
            tick()
        }
    }

    @discardableResult
    public func runUntilIdle(maxTicks: Int = 20_000) -> Int {
        var count = 0
        while count < maxTicks && !isIdle && !isGameOver {
            tick()
            count += 1
        }
        return count
    }

    public func drainEvents() -> [GameEvent] {
        let result = events
        events.removeAll()
        return result
    }

    /// Mirrors `resetBoard()` as invoked by the GameOver "OK" button / the
    /// Restart button (`MainUI.reset()` + `BoardManager.resetBoard()`
    /// folded together, since this port has no separate score-reset call).
    public func resetBoard() {
        timerQueue.cancelAll()
        bubbles.removeAll()
        readyBubble = nil
        queueBubble = nil
        launchedBubble = nil
        turnInProgress = false
        score = 0
        livesLeft = GameConsts.initialLives
        maxLives = GameConsts.initialLives
        totalColors = GameConsts.totalColors
        isGameOver = false
        isAddingRow = false

        buildFullRandomBoardAndQueue()
        armCannonEnableLockout()
        events.append(.boardReset)
    }

    public func snapshot() -> GameSnapshot? {
        guard isIdle, !isGameOver, let ready = readyBubble, let queue = queueBubble else { return nil }
        let records = boardBubbles.map {
            GameSnapshot.BubbleRecord(boardX: $0.boardX, boardY: $0.boardY, color: $0.color)
        }
        return GameSnapshot(
            bubbles: records,
            readyColor: ready.color,
            queueColor: queue.color,
            score: score,
            livesLeft: livesLeft,
            maxLives: maxLives,
            totalColors: totalColors
        )
    }
}
