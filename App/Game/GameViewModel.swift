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
    /// The header fades out over this long as a restart's collapse starts
    /// (spec 69)...
    static let headerFadeOutDuration: Double = 0.25
    /// ...and back in over this long once a new board has poured in.
    static let headerFadeInDuration: Double = 0.4
    /// Pause between the app's first frame and the pour of a new board at
    /// launch (spec 69), so it doesn't start on the very first frames.
    static let launchPourDelay: Double = 0.15
    /// Extra lift (points) applied to both the cannon and queue-bubble
    /// positions in `prepare(containerSize:)` (spec 31): the queue bubble
    /// used to be clipped by the bottom edge, so both move up by this same
    /// amount, keeping the `queueGap` between their centers untouched. One
    /// constant to tweak the whole block.
    static let cannonBlockLift: Double = 72
    /// Distance (points) from the cannon-bubble center down to the
    /// queue-bubble center. 96 in the Figma layout (spec 20), pushed 28pt
    /// lower by owner request.
    static let queueGap: Double = 124

    @Published var score = 0
    @Published var livesLeft = 5
    @Published var maxLives = GameConsts.initialLives
    @Published var gameOver: GameOverInfo?
    /// Opacity of the game screen's own container (spec 31): 0 while the
    /// game-over screen is showing (set the instant it appears, with no
    /// animation — see `onGameOver` below), back to 1 as it fades out, with
    /// the new board pouring in behind it (spec 69). Otherwise it stays at 1
    /// during play.
    /// Starts at 0: a resumed match fades in over `gameFadeInDuration` at
    /// launch (owner request), a new one is shown at once and poured in.
    @Published var gameOpacity: Double = 0
    /// Opacity of the header — lives and Restart (spec 69): it goes away as
    /// a restart's collapse starts and comes back once a new board has
    /// poured in, so the board arrives on an empty screen. Hidden until
    /// `prepare` knows whether the match is new (it pours in) or resumed
    /// (the header fades in with the game).
    @Published var headerOpacity: Double = 0
    /// True while the board is being animated out or in — a restart's
    /// collapse, any pour (spec 69): `RootView` blocks input on the game
    /// container meanwhile, and `restart()` ignores repeated taps.
    @Published var isChangingBoard = false
    /// How far (points) the scene is drawn on above its container, up to the
    /// top of the screen (spec 69) — fixed with the scene in `prepare`, so
    /// the view and the scene's size always agree.
    @Published private(set) var sceneTopExtension: CGFloat = 0
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
    /// plus `cannonBlockLift`), the queue-bubble center `queueGap` further
    /// down, and the input area's bottom edge 64
    /// logical units above the cannon (unchanged from `GameLayout.fitting`'s
    /// own gap).
    /// `topExtension` (points) is how far the screen goes on above the
    /// container — header, the buttons in place of the status bar: the
    /// scene is drawn up to the top of the screen so a new board can pour in
    /// from there (spec 69). `sideExtension` (points) is how far it goes on
    /// past each side, over the board's side margins, so a bubble at a wall
    /// isn't cut off (spec 72).
    func prepare(containerSize: CGSize, topExtension: CGFloat = 0, sideExtension: CGFloat = 0) {
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
        let queueY = cannonY + Self.queueGap / scale
        let cannonPivotX = GameConsts.boardMinX + GameConsts.boardLogicalWidth / 2
        let inputAreaMaxY = cannonY - 64
        let layout = GameLayout(
            canvasHeight: canvasHeight,
            cannonY: cannonY,
            inputAreaMaxY: inputAreaMaxY,
            queuePosition: Vec2(x: cannonPivotX, y: queueY)
        )
        // No saved match: a new one, which pours in (spec 69).
        let isNewMatch = store.load() == nil
        let engine = makeEngine(layout)
        let scene = GameScene(
            engine: engine, canvasHeight: canvasHeight,
            topExtension: Double(topExtension) / scale, sideExtension: Double(sideExtension) / scale
        )

        // First appearance: the view starts at `gameOpacity == 0`. A resumed
        // match fades in once the scene exists; a new one is shown at once —
        // an empty screen — and its board pours in.
        defer {
            if isNewMatch {
                gameOpacity = 1
                pourBoard(after: Self.launchPourDelay)
            } else {
                withAnimation(.easeInOut(duration: Self.gameFadeInDuration)) {
                    gameOpacity = 1
                    headerOpacity = 1
                }
            }
        }

        self.engine = engine
        self.scene = scene
        sceneTopExtension = topExtension
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

    /// Restart button (spec 69): the header fades out and the board
    /// collapses, row after row from the bottom; behind the empty screen the
    /// match is reset, the new board pours in, and the header comes back.
    /// The scene freezes the engine for all of it, so a bubble in flight
    /// can't land (or end the match) in the middle of the transition, and
    /// input is off until the header is back.
    /// Only reachable during active play — the header sits behind the
    /// game-over screen once it's showing — but `gameOver = nil` stays in the
    /// reset, as before.
    func restart() {
        guard let engine, let scene, !isChangingBoard else { return }
        isChangingBoard = true
        withAnimation(.easeOut(duration: Self.headerFadeOutDuration)) {
            headerOpacity = 0
        }
        scene.collapseBoard { [weak self] in
            guard let self else { return }
            engine.resetBoard()
            self.gameOver = nil
            scene.rebuild()
            self.pourBoard(after: 0)
        }
    }

    /// New game on the game-over screen. The match is reset at once, behind
    /// the overlay as it fades out over `gameOverFadeDuration`; then the new
    /// board pours in (`fadeGameInAfterOverlay`).
    func dismissGameOver() {
        guard let engine, let scene else { return }
        engine.resetBoard()
        scene.rebuild()
        withAnimation(.easeInOut(duration: Self.gameOverFadeDuration)) {
            gameOver = nil
        }
        fadeGameInAfterOverlay()
    }

    /// Second half of the game-over to game transition: the game screen
    /// comes back at once, empty — the board is out of sight and the header
    /// hidden, so nothing shows through the fading overlay — and the board
    /// pours in once the overlay is gone. Split out so the debug demo can run
    /// the exact same sequence a player sees.
    func fadeGameInAfterOverlay() {
        pourBoard(after: Self.gameOverFadeDuration)
        gameOpacity = 1
    }

    /// Pours the scene's board in (spec 69) with the header hidden, and
    /// brings the header back once it's in. Input is off meanwhile.
    private func pourBoard(after delay: Double) {
        guard let scene else { return }
        isChangingBoard = true
        headerOpacity = 0
        scene.pourIn(after: delay) { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: Self.headerFadeInDuration)) {
                self.headerOpacity = 1
            }
            self.isChangingBoard = false
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
