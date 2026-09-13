import SpriteKit
import BubbleShooterCore

/// Renders one `GameEngine` and forwards its events as callbacks. Owns no
/// game logic itself — every frame it ticks the engine at a fixed 15ms step,
/// mirrors `engine.bubbles` into `SKNode`s, and animates removals.
final class GameScene: SKScene {
    private let engine: GameEngine
    private let geometry: SceneGeometry

    /// Live bubble nodes keyed by `Bubble.id`.
    private var nodes: [Int: SKNode] = [:]
    /// Ids currently mid removal-animation: excluded from `sync()`'s node
    /// housekeeping (their `removeFromParent` happens when the animation
    /// completes, not immediately).
    private var dying: Set<Int> = []

    private var lastUpdateTime: TimeInterval?
    private var accumulator: TimeInterval = 0

    private let cannonNode = SKNode()
    private let livesNode = SKNode()

    var onScoreChanged: ((Int) -> Void)?
    var onGameOver: ((Bool, Int, Int) -> Void)?
    var onTurnResolved: (() -> Void)?
    var onBoardReset: (() -> Void)?
    var onLivesChanged: ((Int, Int) -> Void)?

    init(engine: GameEngine, canvasHeight: Double) {
        self.engine = engine
        self.geometry = SceneGeometry(canvasHeight: canvasHeight)
        super.init(size: CGSize(width: 560, height: canvasHeight))
        scaleMode = .aspectFit
        backgroundColor = Palette.background
        setUpCannon()
        addChild(livesNode)
        sync()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpCannon() {
        let barrel = SKShapeNode(rect: CGRect(x: -7, y: 0, width: 14, height: 44), cornerRadius: 5)
        barrel.fillColor = Palette.cannon
        barrel.strokeColor = .clear

        let base = SKShapeNode(circleOfRadius: 10)
        base.fillColor = Palette.cannon
        base.strokeColor = .clear

        cannonNode.addChild(barrel)
        cannonNode.addChild(base)
        cannonNode.position = geometry.scenePoint(engine.layout.cannonPivot)
        cannonNode.zPosition = 5
        addChild(cannonNode)
        updateCannonRotation()
    }

    private func updateCannonRotation() {
        cannonNode.zRotation = -engine.aimAngleDegrees * .pi / 180
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let corePoint = geometry.corePoint(point)
        if engine.fire(toward: corePoint) {
            updateCannonRotation()
        }
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval
        if let last = lastUpdateTime, currentTime - last <= 0.5 {
            dt = currentTime - last
        } else {
            dt = 0
        }
        lastUpdateTime = currentTime

        accumulator += dt
        var ticks = 0
        while accumulator >= 0.015 && ticks < 8 {
            engine.tick()
            accumulator -= 0.015
            ticks += 1
        }
        if ticks >= 8 {
            accumulator = 0
        }

        // NOTE: spec ("Решённые развилки") describes the per-frame order as
        // sync() then handleEvents(). Doing it in that order makes `.removed`
        // animations unreachable: `engine.bubbles` already drops a bubble the
        // instant it is removed (see GameEngine+Rules.swift `remove(_:reason:)`),
        // so by the time sync() runs it would delete that bubble's node on the
        // spot (id not in `engine.bubbles`, not yet in `dying` because
        // handleEvents() hasn't drained the `.removed` event yet) — the
        // animation code in handleEvents() would then find no node left to
        // animate. Running handleEvents() first lets it move the node into
        // `dying` and start the animation before sync()'s housekeeping ever
        // looks at it; every individual event's described behavior (including
        // `.boardReset`'s own explicit `sync()` call) is unchanged. See report
        // for this deviation.
        handleEvents()
        sync()
    }

    /// Creates missing bubble nodes, updates position/color of existing ones,
    /// removes nodes for ids no longer in `engine.bubbles` (unless animating
    /// out), and redraws the lives row from current values.
    private func sync() {
        var seenIds = Set<Int>()
        for bubble in engine.bubbles {
            seenIds.insert(bubble.id)
            if let node = nodes[bubble.id] as? BubbleNode {
                node.position = geometry.scenePoint(bubble.position)
                node.apply(color: bubble.color)
            } else {
                let node = BubbleNode(color: bubble.color)
                node.position = geometry.scenePoint(bubble.position)
                addChild(node)
                nodes[bubble.id] = node
            }
        }

        let staleIds = nodes.keys.filter { !seenIds.contains($0) && !dying.contains($0) }
        for id in staleIds {
            nodes[id]?.removeFromParent()
            nodes.removeValue(forKey: id)
        }

        syncLivesIndicator()
    }

    private func syncLivesIndicator() {
        livesNode.removeAllChildren()
        let baseX = 70.0
        let y = engine.layout.cannonY
        for i in 0..<engine.maxLives {
            let dot = SKShapeNode(circleOfRadius: 6)
            dot.fillColor = Palette.lifeIcon
            dot.strokeColor = .clear
            dot.alpha = i < engine.livesLeft ? 1.0 : 0.25
            dot.position = geometry.scenePoint(Vec2(x: baseX + Double(i) * 16, y: y))
            livesNode.addChild(dot)
        }
    }

    // MARK: - Events

    private func handleEvents() {
        for event in engine.drainEvents() {
            switch event {
            case let .removed(id, _, _, _, reason):
                animateRemoval(id: id, reason: reason)
            case let .scoreChanged(score):
                onScoreChanged?(score)
            case let .gameOver(won, score, bonus):
                onGameOver?(won, score, bonus)
            case .boardReset:
                performBoardReset()
            case let .lifeLost(livesLeft):
                syncLivesIndicator()
                onLivesChanged?(livesLeft, engine.maxLives)
            case let .livesReset(livesLeft, maxLives):
                syncLivesIndicator()
                onLivesChanged?(livesLeft, maxLives)
            case .turnResolved:
                onTurnResolved?()
            default:
                break
            }
        }
    }

    private func animateRemoval(id: Int, reason: RemovalReason) {
        guard let node = nodes.removeValue(forKey: id) else { return }
        dying.insert(id)

        let cleanup = SKAction.run { [weak self] in
            node.removeFromParent()
            self?.dying.remove(id)
        }

        let action: SKAction
        switch reason {
        case .match:
            let grow = SKAction.scale(to: 1.25, duration: 0.06)
            let shrinkAndFade = SKAction.group([
                SKAction.scale(to: 0, duration: 0.12),
                SKAction.fadeOut(withDuration: 0.12)
            ])
            action = SKAction.sequence([grow, shrinkAndFade, cleanup])
        case .hanging:
            let fall = SKAction.group([
                SKAction.moveBy(x: 0, y: -300, duration: 0.45),
                SKAction.fadeOut(withDuration: 0.45)
            ])
            action = SKAction.sequence([fall, cleanup])
        }
        node.run(action)
    }

    private func performBoardReset() {
        for node in children where node is BubbleNode {
            node.removeAllActions()
            node.removeFromParent()
        }
        nodes.removeAll()
        dying.removeAll()
        sync()
        onBoardReset?()
    }

    /// Public entry point for Restart from the UI: resets the visual state
    /// the same way the `.boardReset` event does (the engine's board itself
    /// must already have been reset by the caller before calling this).
    func rebuild() {
        performBoardReset()
    }
}
