import SpriteKit
import BubbleShooterCore

/// Renders one `GameEngine` and forwards its events as callbacks. Owns no
/// game logic itself — every frame it ticks the engine at a fixed 15ms step,
/// mirrors `engine.bubbles` into `SKNode`s, and animates removals.
final class GameScene: SKScene {
    private let engine: GameEngine
    private let geometry: SceneGeometry
    private let haptics = Haptics.shared

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

    // MARK: - Bridge merge state (spec 38)

    /// Ids of bubbles whose nodes were handed to a `BridgeMergeNode`. The
    /// engine drops a cluster's bubbles one at a time, ~70 ms apart, so for
    /// a while these ids are still in `engine.bubbles` with no node in
    /// `nodes`: `sync()` must skip them (it would otherwise create a fresh
    /// node for each, on top of the effect). An id leaves the set when its
    /// own `.removed` arrives — not when the layer finishes, because a big
    /// cluster's removals can outlast the effect itself.
    private var mergeIds: Set<Int> = []
    /// Merge layers currently animating, so a board reset can tear them down
    /// mid-effect.
    private var mergeLayers: [BridgeMergeNode] = []
    /// Id of the bubble that landed most recently — the one the player fired,
    /// and so where a match's bridge wave starts.
    private var lastLandedId: Int?
    /// How long after the scene appears the blur warm-up runs (spec 39): the
    /// game's launch fade-in, plus a little margin, so the stall of the first
    /// CI blur never lands on the fade or on the first frames of play.
    private let bridgeWarmUpDelay: TimeInterval = GameViewModel.gameFadeInDuration + 0.4

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

    override func didMove(to view: SKView) {
        // Spec 39: pay the dissolve blur's one-time setup cost while the
        // player is looking at the board, not in the middle of the first pop.
        // Deferred, never synchronous: a synchronous warm-up here holds the
        // first frame back by ~0.6 s (see `BridgeMergeNode.warmUp`).
        run(SKAction.sequence([
            SKAction.wait(forDuration: bridgeWarmUpDelay),
            SKAction.run { [weak self] in
                guard let self, let view = self.view else { return }
                BridgeMergeNode.warmUp(in: view, pixelsPerUnit: self.pixelsPerUnit)
            }
        ]), withKey: "bridgeWarmUp")
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
            // Spec 38: a bubble inside a bridge merge layer belongs to that
            // layer until the engine finishes removing it — neither move it
            // nor create a second node for it.
            if mergeIds.contains(bubble.id) { continue }
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
        let events = engine.drainEvents()
        // Where the engine put every bubble it already removed within this
        // very batch — see `startBridgeMerge`.
        var removedPositions: [Int: Vec2] = [:]
        for case let .removed(id, _, position, _, _) in events {
            removedPositions[id] = position
        }

        for event in events {
            haptics.handle(event)
            switch event {
            case let .landed(id, _, _):
                lastLandedId = id
            case let .clusterMatched(ids, color):
                startBridgeMerge(ids: ids, color: color, removedPositions: removedPositions)
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

    /// Device pixels per logical scene unit: how many pixels one scene unit
    /// takes on screen — the `.aspectFit` scale of the scene inside its view,
    /// times the view's pixel density — or 1 before the scene is presented.
    /// The merge layer renders at this density (see `BridgeMergeNode`).
    private var pixelsPerUnit: CGFloat {
        guard let view, size.width > 0, size.height > 0 else { return 1 }
        let fit = min(view.bounds.width / size.width, view.bounds.height / size.height)
        return max(1, fit * view.contentScaleFactor)
    }

    /// Spec 38: hands a freshly matched cluster over to a `BridgeMergeNode`.
    /// The nodes of every listed bubble move into the effect layer (keeping
    /// their positions), lose their pending move/fade actions and stored
    /// targets, and from then on are only the layer's business: `sync()`
    /// skips their ids (`mergeIds`) until the engine's per-bubble `.removed`
    /// events arrive, which `animateRemoval` merely checks off.
    private func startBridgeMerge(ids: [Int], color: BubbleColor, removedPositions: [Int: Vec2]) {
        let livePositions = Dictionary(uniqueKeysWithValues: engine.bubbles.map { ($0.id, $0.position) })

        // The bridge wave starts at the bubble the player just fired, when it
        // is part of the cluster; otherwise at the cluster's first bubble.
        let startId = lastLandedId.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first

        var members: [BubbleNode] = []
        var startIndex = 0
        for id in ids {
            guard let node = nodes[id] as? BubbleNode else { continue }
            nodes.removeValue(forKey: id)

            // This frame's `sync()` has not run yet, so the node may be
            // stale. The fired bubble is still where the previous frame left
            // it in flight, and since it sits at the bottom of the cluster it
            // is usually the first one removed — in this very batch, which
            // leaves the engine no longer listing it (its `.removed` carries
            // the final position instead). A bubble caught mid row-slide is
            // not at its cell yet either. Pin every member to the engine's
            // position: `sync()` won't touch it again.
            if let position = livePositions[id] ?? removedPositions[id] {
                node.position = geometry.scenePoint(position)
            }
            node.removeAction(forKey: moveActionKey)
            node.removeAction(forKey: fadeActionKey)
            node.alpha = 1
            targets.removeValue(forKey: id)

            mergeIds.insert(id)
            if id == startId { startIndex = members.count }
            members.append(node)
        }
        guard !members.isEmpty else { return }

        let layer = BridgeMergeNode(
            bubbles: members, startIndex: startIndex, color: Palette.color(for: color), pixelsPerUnit: pixelsPerUnit
        )
        addChild(layer)
        mergeLayers.append(layer)
        layer.play { [weak self, weak layer] in
            guard let layer else { return }
            layer.removeFromParent()
            self?.mergeLayers.removeAll { $0 === layer }
        }
    }

    private func animateRemoval(id: Int, reason: RemovalReason) {
        // Spec 38: a match removal has no animation of its own any more. A
        // bubble that went into a bridge merge layer is animated by that
        // layer, so its `.removed` only checks it off — which is also what
        // lets `sync()` trust `engine.bubbles` for this id again. (Any other
        // match-removed node — in practice there is none, the engine
        // announces the whole cluster before its first removal — is simply
        // dropped by `sync()`, as its id is gone from `engine.bubbles`.)
        if mergeIds.remove(id) != nil || reason == .match { return }

        guard let node = nodes.removeValue(forKey: id) else { return }
        dying.insert(id)
        // Spec 21 step 1/5: drop any stored target along with the node so a
        // removed bubble's id can't leave a stale entry behind (it never
        // will be looked up again, but nothing should linger either), and
        // cancel any in-flight move/fade action first so it can't fight the
        // removal animation below (e.g. a hanging bubble that starts
        // falling mid row-drop-slide).
        targets.removeValue(forKey: id)
        node.removeAction(forKey: moveActionKey)
        node.removeAction(forKey: fadeActionKey)

        let cleanup = SKAction.run { [weak self] in
            node.removeFromParent()
            self?.dying.remove(id)
        }

        let fall = SKAction.group([
            SKAction.moveBy(x: 0, y: -300, duration: 0.45),
            SKAction.fadeOut(withDuration: 0.45)
        ])
        node.run(SKAction.sequence([fall, cleanup]))
    }

    private func performBoardReset() {
        for node in children where node is BubbleNode {
            node.removeAllActions()
            node.removeFromParent()
        }
        // Spec 38: active merge layers go too, taking the bubble nodes
        // they hold along with them.
        for layer in mergeLayers {
            layer.removeAllActions()
            layer.removeFromParent()
        }
        mergeLayers.removeAll()
        mergeIds.removeAll()
        lastLandedId = nil
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

    /// Re-applies the current palette to every live bubble node — the
    /// cannon-loaded ("ready"), queued, on-board, and any in-flight
    /// ("launched") bubble alike (spec 32). `sync()` would eventually repaint
    /// everything on its own next pass too (it calls `apply(color:)`
    /// unconditionally every frame), but calling this explicitly when the
    /// palette changes makes the repaint immediate and the dependency
    /// intentional rather than incidental.
    func repaintBubbles() {
        let colorsById = Dictionary(uniqueKeysWithValues: engine.bubbles.map { ($0.id, $0.color) })
        for (id, node) in nodes {
            guard let bubbleNode = node as? BubbleNode, let color = colorsById[id] else { continue }
            bubbleNode.apply(color: color)
        }
    }
}
