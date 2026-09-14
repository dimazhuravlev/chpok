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

    /// Last engine-reported target position for every bubble node, keyed by
    /// `Bubble.id` — the fix for task 20's hang (spec 21): whether to start
    /// a new move action is decided by comparing the engine's new target to
    /// this *stored previous target*, never to the node's current (possibly
    /// still-animating) position. Comparing to the live position kept the
    /// gap "visible" for the whole slide, so every frame re-issued a fresh
    /// `move(to:duration:)` and the bubble crawled ever more slowly instead
    /// of ever finishing. Entries are dropped when their node is removed or
    /// the scene is fully rebuilt (see `sync()`/`performBoardReset()`); a
    /// `.launched` bubble is excluded from the whole mechanism (see
    /// `updatePosition`).
    private var targets: [Int: Vec2] = [:]
    private let moveActionKey = "bubbleMove"
    private let fadeActionKey = "bubbleFade"
    /// Duration/easing for the queue-bubble-to-cannon slide (spec 20) and,
    /// symmetrically, the new queue bubble sliding up from below the screen
    /// into the vacated slot (spec 21 step 3) — both ends of the same
    /// "conveyor belt" move together over the same 0.18s ease-out.
    private let queueMoveDuration: TimeInterval = 0.18
    /// Duration for a new row's appearance (spec 21 step 4): existing
    /// bubbles glide down to their post-row-add position, new top-row
    /// bubbles fade in from zero alpha, both over this same span.
    private let rowAddDuration: TimeInterval = 0.3
    /// Below this (logical units), a target "change" is just float noise
    /// from re-deriving the same position — snap instead of animating.
    private let moveThreshold: Double = 1.0
    /// Logical distance between the queue slot and the cannon pivot (spec
    /// 21 context: `layout.queuePosition.y - layout.cannonY`), i.e. how far
    /// below its slot a fresh queue bubble starts before sliding up.
    private let queueStep: Double
    /// True only for the one `sync()` call right after `.rowsAdded` fires
    /// (set in `handleEvents()`, consumed and reset at the top of `sync()`).
    private var isAddingRowThisFrame = false
    /// The very first `.inQueue` bubble ever shown (match start, or right
    /// after a board reset) should just appear in its slot, not slide in —
    /// only later replacements slide (spec 21 step 3 exception).
    private var hasQueueBubbleAppeared = false

    var onScoreChanged: ((Int) -> Void)?
    var onGameOver: ((Bool, Int, Int, Int) -> Void)?
    var onTurnResolved: (() -> Void)?
    var onBoardReset: (() -> Void)?
    var onLivesChanged: ((Int, Int) -> Void)?

    init(engine: GameEngine, canvasHeight: Double) {
        self.engine = engine
        self.geometry = SceneGeometry(canvasHeight: canvasHeight)
        self.queueStep = engine.layout.queuePosition.y - engine.layout.cannonY
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
    /// animating out). Position changes go through `updatePosition`/
    /// `placeNewNode`, which only ever animate a *change of target* (see
    /// their docs and the spec 21 hang diagnosis) — everything else is
    /// repositioned/placed directly, same as before.
    private func sync() {
        let addingRow = isAddingRowThisFrame
        isAddingRowThisFrame = false

        var seenIds = Set<Int>()
        for bubble in engine.bubbles {
            seenIds.insert(bubble.id)
            let scenePos = geometry.scenePoint(bubble.position)
            if let node = nodes[bubble.id] as? BubbleNode {
                node.apply(color: bubble.color)
                updatePosition(node: node, bubble: bubble, scenePos: scenePos, addingRow: addingRow)
            } else {
                let node = BubbleNode(color: bubble.color)
                addChild(node)
                nodes[bubble.id] = node
                placeNewNode(node: node, bubble: bubble, scenePos: scenePos, addingRow: addingRow)
            }
        }

        let staleIds = nodes.keys.filter { !seenIds.contains($0) && !dying.contains($0) }
        for id in staleIds {
            nodes[id]?.removeFromParent()
            nodes.removeValue(forKey: id)
            targets.removeValue(forKey: id)
        }
    }

    /// Spec 21 step 2: repositions a node that already exists.
    /// - `.launched`: driven directly every frame along its flight path; any
    ///   leftover move action (e.g. a queue-to-cannon slide still finishing
    ///   when the player fires again) is cancelled first so it can't fight
    ///   the direct position set, and no target is remembered — this state
    ///   is outside the target-tracking mechanism entirely.
    /// - otherwise: compare the engine's new target to the *stored* previous
    ///   target (never to `node.position`, which is what caused the task 20
    ///   hang — see the spec's diagnosis). No stored target means the node
    ///   was just created and handled by `placeNewNode` instead — but by the
    ///   time an *existing* node reaches here with no stored target (e.g. a
    ///   bubble that just landed, whose target was dropped while it was
    ///   `.launched`), it snaps into place immediately, same as a brand-new
    ///   node would. A real target change starts one move action (0.18s
    ///   ease-out for a queue/cannon slide, 0.3s linear while a row is being
    ///   added); anything smaller than `moveThreshold` is left alone so the
    ///   in-flight action isn't restarted every tick.
    private func updatePosition(node: SKNode, bubble: Bubble, scenePos: CGPoint, addingRow: Bool) {
        if bubble.state == .launched {
            node.removeAction(forKey: moveActionKey)
            targets.removeValue(forKey: bubble.id)
            node.position = scenePos
            return
        }

        guard let previousTarget = targets[bubble.id] else {
            node.position = scenePos
            targets[bubble.id] = bubble.position
            return
        }

        guard previousTarget.distance(to: bubble.position) > moveThreshold else { return }
        targets[bubble.id] = bubble.position

        node.removeAction(forKey: moveActionKey)
        let move = SKAction.move(to: scenePos, duration: addingRow ? rowAddDuration : queueMoveDuration)
        if !addingRow {
            move.timingMode = .easeOut
        }
        node.run(move, withKey: moveActionKey)
    }

    /// Spec 21 steps 3 & 4: places a node that was just created this frame.
    /// Normally that's a direct snap (no stored target yet, nothing to
    /// animate from). Two exceptions:
    /// - A fresh `.inQueue` bubble (the queue's new back-of-the-line
    ///   replacement) starts one `queueStep` below its slot — already past
    ///   the bottom edge — and slides up over the same 0.18s ease-out as the
    ///   bubble it's replacing slides into the cannon, so both moves read as
    ///   one continuous belt. The very first queue bubble ever (match start
    ///   or right after a board reset) is exempted: it just appears.
    /// - During a row-add frame, a brand-new top-row `.onBoard` bubble
    ///   starts at zero alpha and fades in over `rowAddDuration`, in place
    ///   (it's already at its final position, nothing to slide).
    private func placeNewNode(node: BubbleNode, bubble: Bubble, scenePos: CGPoint, addingRow: Bool) {
        if bubble.state == .inQueue {
            targets[bubble.id] = bubble.position
            guard hasQueueBubbleAppeared else {
                hasQueueBubbleAppeared = true
                node.position = scenePos
                return
            }
            let startPosition = Vec2(x: bubble.position.x, y: bubble.position.y + queueStep)
            node.position = geometry.scenePoint(startPosition)
            let move = SKAction.move(to: scenePos, duration: queueMoveDuration)
            move.timingMode = .easeOut
            node.run(move, withKey: moveActionKey)
            return
        }

        targets[bubble.id] = bubble.position
        node.position = scenePos
        if addingRow {
            node.alpha = 0
            node.run(SKAction.fadeAlpha(to: 1, duration: rowAddDuration), withKey: fadeActionKey)
        }
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
            case let .gameOver(won, score, bonus, elapsedMs):
                onGameOver?(won, score, bonus, elapsedMs)
            case .boardReset:
                performBoardReset()
            case let .lifeLost(livesLeft):
                onLivesChanged?(livesLeft, engine.maxLives)
            case let .livesReset(livesLeft, maxLives):
                onLivesChanged?(livesLeft, maxLives)
            case .turnResolved:
                onTurnResolved?()
            case .rowsAdded:
                // Spec 21 step 4: the engine has already fully recomputed
                // every shifted bubble's position by the time this event
                // drains (see context note), so this frame's `sync()` sees
                // the final post-row-add layout — flag it to animate rather
                // than snap.
                isAddingRowThisFrame = true
            default:
                break
            }
        }
    }

    private func animateRemoval(id: Int, reason: RemovalReason) {
        guard let node = nodes.removeValue(forKey: id) else { return }
        dying.insert(id)
        // Spec 21 step 1/5: drop any stored target along with the node so a
        // removed bubble's id can't leave a stale entry behind (it never
        // will be looked up again, but nothing should linger either), and
        // cancel any in-flight move/fade action first so it can't fight the
        // removal animation below (e.g. a hanging bubble that starts
        // falling mid row-drop-slide, or gets matched mid fade-in).
        targets.removeValue(forKey: id)
        node.removeAction(forKey: moveActionKey)
        node.removeAction(forKey: fadeActionKey)

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
        targets.removeAll()
        isAddingRowThisFrame = false
        hasQueueBubbleAppeared = false
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
