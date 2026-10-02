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
    /// The personal best winning time (spec 36) exactly as it stood *before*
    /// this match — `nil` when there was no record yet. Never the time of the
    /// match being shown: a win that sets a new record must still show the old
    /// one, otherwise the line would just repeat `timeText`.
    let previousBestMs: Int?

    var total: Int { score + bonus }
    /// Lowercase and without an exclamation mark, matching the rest of the
    /// fullscreen game-over screen's typography (spec 26; the "!" went away
    /// with the spec 36 mockups).
    var title: String { won ? "you win!" : "you lose!" }

    /// Whether this match set a new personal best: a win that is strictly
    /// faster than the previous best, or any win when there was none yet (the
    /// very first win is itself the record). A tie is not a new best — the
    /// same rule `BestTimeStore.submit(_:)` applies when it decides to write.
    /// A loss never is.
    var isNewBest: Bool {
        guard won else { return false }
        guard let previousBestMs else { return true }
        return elapsedMs < previousBestMs
    }

    /// Label of the time line (spec 36): `new best time` when this match set
    /// the record, plain `time` otherwise.
    var timeLabel: String { isNewBest ? "new best time" : "time" }

    /// `MM:SS` (minutes always two digits), or `H:MM:SS` once the match runs
    /// an hour or more (spec 22, minutes zero-padded since spec 36). Seconds
    /// (and minutes, once hours are shown) are always two digits.
    var timeText: String { Self.formatTime(elapsedMs) }

    /// The previous personal best in the same format as `timeText`; `nil` when
    /// there is none, in which case the screen omits the line entirely.
    var bestText: String? { previousBestMs.map(Self.formatTime) }

    /// Shared by `timeText` and `bestText` so the two lines can't drift apart.
    private static func formatTime(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
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
    static let gameOverFadeDuration: Double = 0.5
    /// How long the game scene fades back in once the game-over screen has
    /// fully finished fading out (spec 31) — see `dismissGameOver()`, which
    /// starts this only after `gameOverFadeDuration` has elapsed so the two
    /// screens never cross-fade over each other.
    static let gameFadeInDuration: Double = 0.8
    /// Extra lift (points) applied to both the cannon and queue-bubble
    /// positions in `prepare(containerSize:)` (spec 31): the queue bubble
    /// used to be clipped by the bottom edge, so both move up by this same
    /// amount, keeping the 96pt gap between their centers untouched. One
    /// constant to tweak the whole block.
    static let cannonBlockLift: Double = 72

    @Published var score = 0
    @Published var livesLeft = 5
    @Published var maxLives = GameConsts.initialLives
    @Published var gameOver: GameOverInfo?
    /// Opacity of the game screen's own container (spec 31): 0 while the
    /// game-over screen is showing (set the instant it appears, with no
    /// animation — see `onGameOver` below), animated back to 1 by
    /// `dismissGameOver()` only after the game-over screen has fully faded
    /// out. `restart()` never touches it, so it stays at 1 during normal
    /// play.
    /// Starts at 0 so the very first appearance of the game — app launch —
    /// fades in over `gameFadeInDuration` exactly like the one after the
    /// game-over screen, rather than snapping in (owner request).
    @Published var gameOpacity: Double = 0
    /// Exact format `bubbles:<N> score:<S> lives:<L>`, N = `engine.boardBubbles.count`.
    @Published var status: String = "bubbles:0 score:0 lives:5"

    private(set) var engine: GameEngine?
    private(set) var scene: GameScene?

    /// Persists/restores the in-progress match; see `GameSaveStore`.
    let store: GameSaveStore
    /// The personal best winning time (spec 36); see `BestTimeStore`. Kept
    /// apart from `store` on purpose — the match save is cleared at the end of
    /// every match, the record must survive that.
    let bestTimeStore: BestTimeStore

    var makeEngine: (GameLayout) -> GameEngine
    var onTurnResolved: ((GameEngine) -> Void)?
    var onGameOverHook: ((GameEngine) -> Void)?

    init(store: GameSaveStore = GameSaveStore(), bestTimeStore: BestTimeStore = BestTimeStore()) {
        self.store = store
        self.bestTimeStore = bestTimeStore
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
    /// Geometry per the Figma layout (spec 20), raised per spec 31: the
    /// cannon-bubble center sits 127pt above the scene's bottom edge (103pt
    /// plus `cannonBlockLift`), the queue-bubble center 96pt further down
    /// (31pt above the bottom edge), and the input area's bottom edge 64
    /// logical units above the cannon (unchanged from `GameLayout.fitting`'s
    /// own gap).
    func prepare(containerSize: CGSize) {
        guard engine == nil, containerSize.width > 0, containerSize.height > 0 else { return }

        if CommandLine.arguments.contains("-resetSave") {
            store.clear()
            bestTimeStore.clear()
        }

        let areaWidth = Double(containerSize.width)
        let areaHeight = Double(containerSize.height)
        let scale = areaWidth / GameConsts.boardLogicalWidth
        let canvasHeight = GameConsts.boardLogicalWidth * areaHeight / areaWidth
        let cannonY = canvasHeight - (103 + Self.cannonBlockLift) / scale
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

        // First appearance: the view starts at `gameOpacity == 0`, so fade
        // the whole screen in once the scene actually exists.
        defer {
            withAnimation(.easeInOut(duration: Self.gameFadeInDuration)) {
                gameOpacity = 1
            }
        }

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
            // Order matters (spec 36): read the record into the info FIRST,
            // and only then offer this match's time to the store. The screen
            // shows the best as it was before this match; swap the two steps
            // and a win would show its own, just-stored time as the "best".
            // Only wins can set a record — see `BestTimeStore`.
            let info = GameOverInfo(
                won: won, score: score, bonus: bonus, elapsedMs: elapsedMs,
                previousBestMs: bestTimeStore.load()
            )
            if won {
                bestTimeStore.submit(elapsedMs)
            }
            // Snap the game screen to invisible immediately (no animation)
            // so it can't show through the game-over screen's own fade-in;
            // `dismissGameOver()` is what animates it back (spec 31).
            gameOpacity = 0
            withAnimation(.easeInOut(duration: Self.gameOverFadeDuration)) {
                self.gameOver = info
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
    /// popup, and rebuild the scene's visuals to match. Only reachable
    /// during active play — the header sits behind the game-over screen
    /// once it's showing — so there's no game-over screen to fade out here,
    /// and `gameOpacity` is simply left at 1 (spec 31).
    func restart() {
        guard let engine, let scene else { return }
        engine.resetBoard()
        withAnimation(.easeInOut(duration: Self.gameOverFadeDuration)) {
            gameOver = nil
        }
        scene.rebuild()
    }

    /// OK button on the game-over popup. Unlike `restart()`, this sequences
    /// the two screens explicitly (spec 31) instead of relying on the
    /// freshly reset game scene showing through the game-over screen's own
    /// fade-out: the game-over screen fades out over `gameOverFadeDuration`,
    /// and only once that has fully elapsed does the game scene — already
    /// reset, still sitting at `gameOpacity == 0` since `onGameOver` fired —
    /// fade in over `gameFadeInDuration`.
    func dismissGameOver() {
        guard let engine, let scene else { return }
        engine.resetBoard()
        scene.rebuild()
        withAnimation(.easeInOut(duration: Self.gameOverFadeDuration)) {
            gameOver = nil
        }
        fadeGameInAfterOverlay()
    }

    /// Second half of the game-over to game transition: wait out the
    /// overlay's own fade, then bring the game screen back. Split out so the
    /// debug demo can run the exact same sequence a player sees — dismissing
    /// the demo used to only hide the overlay, leaving the game fully opaque
    /// underneath, which made the transition look like it wasn't there.
    func fadeGameInAfterOverlay() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.gameOverFadeDuration * 1_000_000_000))
            guard let self else { return }
            withAnimation(.easeIn(duration: Self.gameFadeInDuration)) {
                self.gameOpacity = 1
            }
        }
    }

    /// Called by `RootView` when `scenePhase` leaves `.active`. Saves only if
    /// the engine is currently idle (`snapshot()` non-nil); if a bubble is
    /// mid-flight, the previous on-disk save is left untouched.
    func persistIfPossible() {
        guard let engine, let snapshot = engine.snapshot() else { return }
        store.save(snapshot)
    }
}
