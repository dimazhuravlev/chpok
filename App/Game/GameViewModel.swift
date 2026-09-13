import SwiftUI
import BubbleShooterCore

/// Snapshot shown by the game-over popup.
struct GameOverInfo: Equatable {
    let won: Bool
    let score: Int
    let bonus: Int

    var total: Int { score + bonus }
    var title: String { won ? "You Win!" : "Game Over" }
}

/// Owns the `GameEngine`/`GameScene` pair and republishes their state for
/// SwiftUI. `makeEngine` is a seam so a future task can hand in an engine
/// restored from a save without touching `GameScene`.
@MainActor
final class GameViewModel: ObservableObject {
    @Published var score = 0
    @Published var livesLeft = 5
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
    /// Later calls (e.g. from further size changes) are ignored.
    func prepare(containerSize: CGSize) {
        guard engine == nil, containerSize.width > 0, containerSize.height > 0 else { return }

        if CommandLine.arguments.contains("-resetSave") {
            store.clear()
        }

        let canvasHeight = 560 * Double(containerSize.height) / Double(containerSize.width)
        let layout = GameLayout.fitting(canvasHeight: canvasHeight)
        let engine = makeEngine(layout)
        let scene = GameScene(engine: engine, canvasHeight: canvasHeight)

        self.engine = engine
        self.scene = scene
        score = engine.score
        livesLeft = engine.livesLeft

        wireCallbacks(scene: scene)
        updateStatus()
    }

    private func wireCallbacks(scene: GameScene) {
        scene.onScoreChanged = { [weak self] score in
            self?.score = score
            self?.updateStatus()
        }
        scene.onGameOver = { [weak self] won, score, bonus in
            guard let self else { return }
            gameOver = GameOverInfo(won: won, score: score, bonus: bonus)
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
            updateStatus()
            if let snapshot = engine.snapshot() {
                store.save(snapshot)
            }
        }
        scene.onLivesChanged = { [weak self] livesLeft, _ in
            self?.livesLeft = livesLeft
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
        gameOver = nil
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
