import SpriteKit
import BubbleShooterCore

/// Renders one `GameEngine` and forwards its events as callbacks. Owns no
/// game logic itself — every frame it ticks the engine at a fixed 15ms step,
/// mirrors `engine.bubbles` into `SKNode`s, and animates removals.
final class GameScene: SKScene {
    private let engine: GameEngine
    private let geometry: SceneGeometry
    private let haptics = Haptics()

    /// Live bubble nodes keyed by `Bubble.id`.
    private var nodes: [Int: SKNode] = [:]
    /// Ids currently mid removal-animation: excluded from `sync()`'s node
    /// housekeeping (their `removeFromParent` happens when the animation
    /// completes, not immediately).
    private var dying: Set<Int> = []

    private var lastUpdateTime: TimeInterval?
    private var accumulator: TimeInterval = 0

    /// Last engine-reported target position for each ready/queue bubble
    /// (`.readyToLaunch`/`.inQueue`), keyed by `Bubble.id`. Lets `sync()`
    /// tell "target actually changed" (queue bubble promoted to ready after
    /// a shot — animate the move) apart from "target unchanged, this is
    /// just another frame" (leave any in-flight animation alone; see
    /// `updateQueueSlotPosition`).
    private var queueTargets: [Int: Vec2] = [:]
    private let queueMoveActionKey = "queueMove"
    /// Duration/easing for the queue-bubble-to-cannon slide (spec 20).
    private let queueMoveDuration: TimeInterval = 0.18
    /// Below this (logical units), a target "change" is just float noise
    /// from re-deriving the same position — snap instead of animating.
    private let queueMoveThreshold: Double = 1.0

    var onScoreChanged: ((Int) -> Void)?
    var onGameOver: ((Bool, Int, Int) -> Void)?
    var onTurnResolved: (() -> Void)?
    var onBoardReset: (() -> Void)?
    var onLivesChanged: ((Int, Int) -> Void)?

    init(engine: GameEngine, canvasHeight: Double) {
        self.engine = engine
        self.geometry = SceneGeometry(canvasHeight: canvasHeight)
        super.init(size: CGSize(width: GameConsts.boardLogicalWidth, height: canvasHeight))
        scaleMode = .aspectFit
        backgroundColor = Palette.background
        sync()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let corePoint = geometry.corePoint(point)
        if engine.fire(toward: corePoint) {
            haptics.prepareForShot()
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

    /// Creates missing bubble nodes, updates position/color of existing
    /// ones, and removes nodes for ids no longer in `engine.bubbles` (unless
    /// animating out). Ready/queue bubbles whose target actually moved
    /// slide to the new spot instead of snapping (see
    /// `updateQueueSlotPosition`); everything else is repositioned directly,
    /// same as before.
    private func sync() {
        var seenIds = Set<Int>()
        for bubble in engine.bubbles {
            seenIds.insert(bubble.id)
            let isQueueSlot = bubble.state == .readyToLaunch || bubble.state == .inQueue
            let scenePos = geometry.scenePoint(bubble.position)
            if let node = nodes[bubble.id] as? BubbleNode {
                node.apply(color: bubble.color)
                if isQueueSlot {
                    updateQueueSlotPosition(node: node, bubble: bubble, scenePos: scenePos)
                } else {
                    queueTargets.removeValue(forKey: bubble.id)
                    node.position = scenePos
                }
            } else {
                let node = BubbleNode(color: bubble.color)
                node.position = scenePos
                addChild(node)
                nodes[bubble.id] = node
                if isQueueSlot {
                    queueTargets[bubble.id] = bubble.position
                }
            }
        }

        let staleIds = nodes.keys.filter { !seenIds.contains($0) && !dying.contains($0) }
        for id in staleIds {
            nodes[id]?.removeFromParent()
            nodes.removeValue(forKey: id)
            queueTargets.removeValue(forKey: id)
        }
    }

    /// Spec 20: when a queue bubble is promoted to ready-to-launch right
    /// after a shot, its engine position jumps instantly from the queue spot
    /// to the cannon pivot. Rather than snapping the node there like every
    /// other frame, run it over as a `0.18`s ease-out slide — but only the
    /// one frame the target actually moved by more than `queueMoveThreshold`
    /// logical units; every later frame (target unchanged) must leave the
    /// node/animation alone, or the slide would restart every tick.
    private func updateQueueSlotPosition(node: SKNode, bubble: Bubble, scenePos: CGPoint) {
        let previousTarget = queueTargets[bubble.id]
        queueTargets[bubble.id] = bubble.position
        guard let previousTarget else {
            node.position = scenePos
            return
        }
        guard previousTarget.distance(to: bubble.position) > queueMoveThreshold else { return }
        node.removeAction(forKey: queueMoveActionKey)
        let move = SKAction.move(to: scenePos, duration: queueMoveDuration)
        move.timingMode = .easeOut
        node.run(move, withKey: queueMoveActionKey)
    }

    // MARK: - Events

    private func handleEvents() {
        for event in engine.drainEvents() {
            haptics.handle(event)
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
                onLivesChanged?(livesLeft, engine.maxLives)
            case let .livesReset(livesLeft, maxLives):
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
        queueTargets.removeAll()
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
