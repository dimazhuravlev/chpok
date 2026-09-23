import SwiftUI
import BubbleShooterCore

/// Snapshot shown by the game-over screen.
struct GameOverInfo: Equatable {
    let won: Bool
    let score: Int
    let bonus: Int
    /// `GameEngine.matchElapsedMs` fixed at the moment the match ended (spec
    /// 22) — active (foreground-only) time, carried on `GameEvent.gameOver`
    /// so it doesn't keep growing while the popup is open.
    let elapsedMs: Int

    var total: Int { score + bonus }
    /// Lowercase with an exclamation mark, matching the rest of the
    /// fullscreen game-over screen's typography (spec 26).
    var title: String { won ? "you win!" : "you lose!" }

    /// `m:ss`, or `h:mm:ss` once the match runs an hour or more (spec 22).
    /// Seconds (and minutes, once hours are shown) are always two digits.
    var timeText: String {
        let totalSeconds = elapsedMs / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Owns the `GameEngine`/`GameScene` pair and republishes their state for
/// SwiftUI. `makeEngine` is a seam so a future task can hand in an engine
/// restored from a save without touching `GameScene`.
@MainActor
final class GameViewModel: ObservableObject {
    /// Fade duration for the game-over screen's `.transition(.opacity)`,
    /// shared by every `gameOver`/`showGameOverDemo` mutation so the
    /// appear/disappear fades stay symmetric (spec 27).
    static let gameOverFadeDuration: Double = 0.25

    @Published var score = 0
    @Published var livesLeft = 5
    @Published var maxLives = GameConsts.initialLives
    @Published var gameOver: GameOverInfo?
    /// Exact format `bubbles:<N> score:<S> lives:<L>`, N = `engine.boardBubbles.count`.
    @Published var status: String = "bubbles:0 score:0 lives:5"

    private(set) var engine: GameEngine?
    private(set) var scene: GameScene?

    /// Persists/restores the in-progress match; see `GameSaveStore`.
    let store: GameSaveStore

    var makeEngine: (GameLayout) -> GameEngine
    var onTurnResolved: ((GameEngine) -> Void)?
    var onGameOverHook: ((GameEngine) -> Void)?

    init(store: GameSaveStore = GameSaveStore()) {
        self.store = store
        makeEngine = { layout in
            if let snapshot = store.load() {
                return GameEngine(snapshot: snapshot, layout: layout)
            }
            return GameEngine(layout: layout)
        }
        // Default seam behavior: save after every resolved turn, clear once
        // the match ends. `wireCallbacks` invokes these with the live engine.
        onTurnResolved = { engine in
            if let snapshot = engine.snapshot() {
                store.save(snapshot)
            }
        }
        onGameOverHook = { _ in
            store.clear()
        }
    }

    /// Creates the engine/scene once a non-zero container size is known.
    /// `containerSize` is the scene's own on-screen rectangle — side-inset by
    /// 10pt and starting right below the header, already reduced by
    /// `sceneTopInset(areaWidth:)` (see `RootView`) so it matches exactly
    /// what SpriteKit renders. Later calls (e.g. from further size changes)
    /// are ignored.
    ///
    /// Geometry per the Figma layout (spec 20): the cannon-bubble center
    /// sits 103pt above the scene's bottom edge, the queue-bubble center
    /// 96pt further down, and the input area's bottom edge 64 logical units
    /// above the cannon (unchanged from `GameLayout.fitting`'s own gap).
    func prepare(containerSize: CGSize) {
        guard engine == nil, containerSize.width > 0, containerSize.height > 0 else { return }

        if CommandLine.arguments.contains("-resetSave") {
            store.clear()
        }

        let areaWidth = Double(containerSize.width)
        let areaHeight = Double(containerSize.height)
        let scale = areaWidth / GameConsts.boardLogicalWidth
        let canvasHeight = GameConsts.boardLogicalWidth * areaHeight / areaWidth
        let cannonY = canvasHeight - 103 / scale
        let queueY = cannonY + 96 / scale
        let cannonPivotX = GameConsts.boardMinX + GameConsts.boardLogicalWidth / 2
        let inputAreaMaxY = cannonY - 64
        let layout = GameLayout(
            canvasHeight: canvasHeight,
            cannonY: cannonY,
            inputAreaMaxY: inputAreaMaxY,
            queuePosition: Vec2(x: cannonPivotX, y: queueY)
        )
        let engine = makeEngine(layout)
        let scene = GameScene(engine: engine, canvasHeight: canvasHeight)

        self.engine = engine
        self.scene = scene
        score = engine.score
        livesLeft = engine.livesLeft
        maxLives = engine.maxLives

        wireCallbacks(scene: scene)
        updateStatus()
    }

    /// Extra top gap (points) `RootView` must add above the scene's own
    /// GeometryReader frame so the first bubble row lands 42.5pt below the
    /// header — the Figma target. Row 0 sits `GameConsts.initialY` logical
    /// units below the scene's own top edge; converted to points via the
    /// same width-based `scale` `prepare(containerSize:)` uses, that is
    /// normally less than 42.5pt, so this makes up the difference. The
    /// caller then shrinks the container height it passes to
    /// `prepare(containerSize:)` by this same amount, which keeps the
    /// cannon/queue bubbles' *absolute* on-screen position unaffected: the
    /// scene starts `inset` points lower but is also `inset` points
    /// "shorter" in logical terms, and the two cancel out (see the spec's
    /// worked derivation). Clamped to zero so a container that's already
    /// tall enough never pushes the scene up into the header.
    static func sceneTopInset(areaWidth: Double) -> Double {
        guard areaWidth > 0 else { return 0 }
        let scale = areaWidth / GameConsts.boardLogicalWidth
        return max(0, 42.5 - GameConsts.initialY * scale)
    }

    private func wireCallbacks(scene: GameScene) {
        scene.onScoreChanged = { [weak self] score in
            self?.score = score
            self?.updateStatus()
        }
        scene.onGameOver = { [weak self] won, score, bonus, elapsedMs in
            guard let self else { return }
            withAnimation(.easeInOut(duration: Self.gameOverFadeDuration)) {
                self.gameOver = GameOverInfo(won: won, score: score, bonus: bonus, elapsedMs: elapsedMs)
            }
            updateStatus()
            if let engine {
                onGameOverHook?(engine)
            }
        }
        scene.onTurnResolved = { [weak self] in
            guard let self else { return }
            updateStatus()
            if let engine {
                onTurnResolved?(engine)
            }
        }
        scene.onBoardReset = { [weak self] in
            guard let self, let engine = self.engine else { return }
            score = engine.score
            livesLeft = engine.livesLeft
            maxLives = engine.maxLives
            updateStatus()
            if let snapshot = engine.snapshot() {
                store.save(snapshot)
            }
        }
        scene.onLivesChanged = { [weak self] livesLeft, maxLives in
            self?.livesLeft = livesLeft
            self?.maxLives = maxLives
            self?.updateStatus()
        }
    }

    private func updateStatus() {
        guard let engine else { return }
        status = "bubbles:\(engine.boardBubbles.count) score:\(engine.score) lives:\(engine.livesLeft)"
    }

    /// Restart button: reset the engine's board, dismiss any game-over
    /// popup, and rebuild the scene's visuals to match.
    func restart() {
        guard let engine, let scene else { return }
        engine.resetBoard()
        withAnimation(.easeInOut(duration: Self.gameOverFadeDuration)) {
            gameOver = nil
        }
        scene.rebuild()
    }

    /// OK button on the game-over popup: same effect as Restart.
    func dismissGameOver() {
        restart()
    }

    /// Called by `RootView` when `scenePhase` leaves `.active`. Saves only if
    /// the engine is currently idle (`snapshot()` non-nil); if a bubble is
    /// mid-flight, the previous on-disk save is left untouched.
    func persistIfPossible() {
        guard let engine, let snapshot = engine.snapshot() else { return }
        store.save(snapshot)
    }
}
