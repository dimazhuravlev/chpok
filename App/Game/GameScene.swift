import SpriteKit
import BubbleShooterCore

/// Renders one `GameEngine` and forwards its events as callbacks. Owns no
/// game logic itself — every frame it ticks the engine at a fixed 15ms step,
/// mirrors `engine.bubbles` into `SKNode`s, and animates removals.
///
/// Spec 51: a matched cluster disappears in one of two ways, chosen once for
/// the whole scene by `matchEffect`. By default (`.pops`) every bubble of the
/// cluster flashes and pops on its own `.removed` event, one after another —
/// the engine releases them ~70 ms apart, bottom to top — as before the
/// bridges. The bridge merge effect (`.bridges`, specs 38-43) is the
/// alternative, switched on with the `-bridgeMerge` launch argument.
final class GameScene: SKScene {
    /// How a matched cluster disappears (spec 51).
    enum MatchEffect {
        /// Each bubble flashes and pops on its own `.removed`, one by one.
        case pops
        /// The cluster merges through blurred bridges (`BridgeMergeNode`).
        case bridges
    }

    /// The effect in use. `.pops` by default; the `-bridgeMerge` launch
    /// argument (scheme arguments, or `xcrun simctl launch ... -bridgeMerge`)
    /// switches to `.bridges`. For a TestFlight build, change the default
    /// here: swap the two cases of the ternary.
    static let matchEffect: MatchEffect =
        CommandLine.arguments.contains("-bridgeMerge") ? .bridges : .pops

    // MARK: - Match pop tuning (spec 51)

    /// Flash phase of a pop: the bubble swells and lightens toward white.
    private let flashDuration: TimeInterval = 0.08
    /// Collapse phase of a pop: scale and opacity run to zero together.
    private let popFadeDuration: TimeInterval = 0.12
    /// Scale reached at the flash's peak (the node's normal scale is 1).
    private let flashScale: CGFloat = 1.18
    /// How far the fill lightens toward white at the flash's peak.
    private let flashLightenFraction: CGFloat = 0.35

    // MARK: - Pop blur tuning (spec 52)

    /// Blur radius reached by the end of a pop's collapse, logical units: a
    /// bubble's own radius is about 15. The blur shrinks along with the
    /// collapsing bubble, so it takes about the bubble's own radius (16,
    /// spec 54; 8 did not show) to read as a soft pop rather than a cloud
    /// like the fall's. Drawn with the pre-blurred `FallBlurFrames`.
    private let popBlurRadius: CGFloat = 16

    private let engine: GameEngine
    private let geometry: SceneGeometry
    /// Scene height above the canvas, logical units (spec 69): the view runs
    /// on up under the header to the top of the screen, so a new board can
    /// pour in from there. Nothing of the game lives in it.
    private let topExtension: Double
    /// Scene width past each side of the board, logical units (spec 72): the
    /// view runs on out to the screen edges, over the board's side margins,
    /// so a bubble at a wall — squashed by the bounce, popping, falling — is
    /// drawn whole instead of cut off at the board's edge. The board keeps
    /// its coordinates: `anchorPoint` puts the scene's origin at the board's
    /// left edge, not the view's.
    private let sideExtension: Double
    private let haptics = Haptics.shared

    // MARK: - Board in and out (spec 69)

    /// While true the engine stands still — no ticks, no events, no `sync()`
    /// — so the board can be animated out and in without the game moving
    /// under it: from the start of a restart's collapse to the end of the
    /// new board's pour.
    private(set) var isEngineFrozen = false
    /// The collapse starts its rows this far apart, the bottom row first.
    private let collapseRowStep: TimeInterval = 0.05
    /// The pour starts its rows this far apart, the bottom row first.
    private let pourRowStep: TimeInterval = 0.06
    /// Every bubble's own random delay on top of its row's, up to this.
    private let boardJitter: TimeInterval = 0.12
    /// Gravity of the pour, logical units per second squared: a bubble
    /// falls to the top row in about 0.3 s, to the bottom one in 0.4.
    private let pourGravity: CGFloat = 6000
    /// Squash of a poured bubble as it lands.
    private let pourLandingSquash: CGFloat = 0.18
    /// The cannon and queue bubbles slide up into place and fade in once the
    /// board is in: over this long, from this far below (logical units)...
    private let pourAppearDuration: TimeInterval = 0.4
    private let pourAppearOffset: CGFloat = 30
    /// ...the queue bubble this much after the cannon's.
    private let pourAppearStagger: TimeInterval = 0.06
    /// How long a bubble falls off the board — a hanging one in play, and
    /// every one in a restart's collapse.
    private let fallDuration: TimeInterval = 0.45
    private let boardTransitionKey = "boardTransition"

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
    /// Opacity of the bubble waiting in the queue under the cannon (spec 44).
    /// It brightens to 1 over `queueMoveDuration`, in step with its slide
    /// into the cannon; anything not `.inQueue` is always fully opaque.
    private let queueBubbleAlpha: CGFloat = 0.4
    // MARK: New rows (spec 76)

    /// A new row comes in two steps: first the whole board slides down to
    /// make room, over `rowShiftDuration`; then, `rowWaveLead` into the
    /// slide — as soon as the empty row shows (spec 89) — the new bubbles
    /// start to appear in their cells one by one, left to right — a quick
    /// wave, each fading in as it drops into its cell from `rowAppearDrop`
    /// above over `rowAppearDuration` (spec 87; it grew in place before).
    /// With more than one row added, the lowest goes first and each next one
    /// up `rowWaveRowDelay` later.
    private let rowShiftDuration: TimeInterval = 0.28
    private let rowWaveLead: TimeInterval = 0.1
    private let rowAppearDuration: TimeInterval = 0.22
    /// From the first bubble of a row starting to appear to the last.
    private let rowWaveDuration: TimeInterval = 0.3
    private let rowWaveRowDelay: TimeInterval = 0.1
    /// Logical units: a third of a bubble.
    private let rowAppearDrop: CGFloat = 10
    private let rowAppearKey = "rowAppear"
    /// How many rows the last `.rowsAdded` brought: which of the new
    /// bubbles' rows is the lowest.
    private var rowsAddedThisFrame = 0
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

    // MARK: - Aim line (spec 60)

    /// Where the finger is, in scene coordinates, while it is down; `nil`
    /// otherwise.
    private var aimPoint: CGPoint?
    /// The predicted path of the shot (`GameEngine.predictedPath`), drawn
    /// while the finger is down when the setting is on. Below the bubbles,
    /// so it starts from under the ready bubble and ends under the one the
    /// shot would land next to.
    private lazy var trajectoryNode: SKShapeNode = {
        let node = SKShapeNode()
        node.zPosition = 5
        node.fillColor = .clear
        // White, so the default shading in `trajectoryShader` is just the
        // stroke's antialiasing coverage.
        node.strokeColor = .white
        node.lineCap = .round
        node.lineJoin = .round
        node.isAntialiased = true
        node.isHidden = true
        node.strokeShader = trajectoryShader
        return node
    }()
    /// Thickness of the aim line, points on screen.
    private let trajectoryWidth: CGFloat = 1
    /// How far before and after a bounce the line starts and ends its turn,
    /// points on screen (spec 93): a small round instead of a sharp corner.
    /// Set by length along the line, not by radius: a fixed radius at the
    /// sharp corner of a flat shot started the turn far short of the wall,
    /// and the zigzag looked narrower than the board.
    private let trajectoryCornerCut: CGFloat = 4
    /// Over this last stretch the line fades into the background, so it
    /// doesn't end in a cut just short of the bubbles it would hit (scene
    /// units; at most half the line).
    private let trajectoryFade: CGFloat = GameConsts.bubbleSize * 3

    /// Colors the stroke along its length: the line's color, mixed toward
    /// the background over the last `u_fade` of the path (smoothstep), at
    /// the default shading's antialiasing coverage. Both colors are opaque —
    /// the line pre-blended over the flat background — so the corners at the
    /// bounces, where the stroke overlaps itself, don't come out darker.
    private lazy var trajectoryShader: SKShader = {
        let shader = SKShader(source: """
        void main() {
            float coverage = SKDefaultShading().a;
            float fade = min(u_fade, u_path_length * 0.5);
            float t = clamp((u_path_length - v_path_distance) / max(fade, 0.0001), 0.0, 1.0);
            t = t * t * (3.0 - 2.0 * t);
            vec3 color = mix(u_background.rgb, u_line.rgb, t);
            gl_FragColor = vec4(color * coverage, coverage);
        }
        """)
        shader.uniforms = [
            SKUniform(name: "u_fade", float: Float(trajectoryFade)),
            SKUniform(name: "u_line", vectorFloat4: vector_float4(1, 1, 1, 1)),
            SKUniform(name: "u_background", vectorFloat4: vector_float4(0, 0, 0, 1))
        ]
        return shader
    }()

    // MARK: - Soft rubber (spec 47)

    /// Squash and stretch of the bubbles; stepped once per frame.
    private let jelly = BubbleJelly()
    /// Latest flight velocity of the launched bubble, in scene coordinates,
    /// keyed by `Bubble.id`: a sign change of `dx` between frames is a wall
    /// bounce (the core reports none), and the landing squashes along the
    /// last value (the engine may already have dropped the bubble by then).
    private var flightVelocities: [Int: CGVector] = [:]
    /// The launched bubble itself, keyed by `Bubble.id`. The engine keeps
    /// updating its `velocity` until it lands and never clears it, so the
    /// landing reads the final velocity from here — right even when the shot
    /// bounces off a wall and lands within the same frame, which the per-frame
    /// `flightVelocities` would miss — and still has it after a match has
    /// already dropped the bubble from `engine.bubbles`.
    private var flightBubbles: [Int: Bubble] = [:]

    var onScoreChanged: ((Int) -> Void)?
    var onGameOver: ((Bool, Int, Int, Int) -> Void)?
    var onTurnResolved: (() -> Void)?
    var onBoardReset: (() -> Void)?
    var onLivesChanged: ((Int, Int) -> Void)?

    init(engine: GameEngine, canvasHeight: Double, topExtension: Double = 0, sideExtension: Double = 0) {
        self.engine = engine
        self.geometry = SceneGeometry(canvasHeight: canvasHeight)
        self.topExtension = topExtension
        self.sideExtension = sideExtension
        self.queueStep = engine.layout.queuePosition.y - engine.layout.cannonY
        let width = GameConsts.boardLogicalWidth + 2 * sideExtension
        super.init(size: CGSize(width: width, height: canvasHeight + topExtension))
        anchorPoint = CGPoint(x: sideExtension / width, y: 0)
        scaleMode = .aspectFit
        backgroundColor = Palette.background
        sync()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        // Palette hex values are Display P3 coordinates (see `Palette`).
        // SpriteKit renders into an 8-bit sRGB Metal layer even on a P3
        // screen and has no wide-color setting, so the layer is relabelled:
        // the same 0...255 components are read as Display P3 by the
        // compositor. Neutrals don't move; saturated colors reach the P3
        // gamut edge.
        // Only where `Palette.usesDisplayP3`: iOS 18 shows the relabelled
        // layer washed out (spec 63).
        if Palette.usesDisplayP3 {
            (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        }

        if trajectoryNode.parent == nil { addChild(trajectoryNode) }

        // Spec 45: draw the pre-blurred frames of the falling bubbles in the
        // background; nothing here waits for them.
        FallBlurFrames.prepare()

        // Spec 51: the pops never touch Core Image blur, so there is nothing
        // to warm up (and no warm-up stall) unless the bridges are in use.
        guard Self.matchEffect == .bridges else { return }

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

    /// The press primes the haptics and starts the aim line; the shot waits
    /// for the lift.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        haptics.prepareForShot()
        aimPoint = touches.first?.location(in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        aimPoint = touches.first?.location(in: self)
    }

    /// A touch the system cancels (a gesture, an incoming call) doesn't fire.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        aimPoint = nil
    }

    /// The shot goes off when the finger lifts, toward where it lifted
    /// (spec 59) — a press can be slid to adjust the aim first.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        aimPoint = nil
        guard !isEngineFrozen, let touch = touches.first else { return }
        let point = touch.location(in: self)
        let corePoint = geometry.corePoint(point)
        if engine.fire(toward: corePoint) {
            haptics.prepareForShot()
        }
    }

    // MARK: - Frame loop

    private var afterNextFrame: (() -> Void)?

    /// One-shot callback fired once the scene has run a frame (spec 54): lets
    /// the restart fade-in wait until the rebuilt board is what gets drawn.
    func runAfterNextFrame(_ block: @escaping () -> Void) {
        afterNextFrame = block
    }

    override func didFinishUpdate() {
        guard let block = afterNextFrame else { return }
        afterNextFrame = nil
        block()
    }

    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval
        if let last = lastUpdateTime, currentTime - last <= 0.5 {
            dt = currentTime - last
        } else {
            dt = 0
        }
        lastUpdateTime = currentTime

        // Spec 69: the board is being animated out or in; only the jelly
        // (the landing squashes of the pour) goes on.
        guard !isEngineFrozen else {
            jelly.step(dt)
            return
        }

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
        jelly.step(dt)
        updateTrajectory()
    }

    /// Spec 60: redraws the aim line every frame while the finger is down —
    /// the board moves under it (new rows, matches) even when the finger
    /// doesn't. Always on (spec 78: no longer a setting). Hidden when nothing
    /// is ready to fire, or the finger is outside the area a shot can be
    /// aimed from — and for a straight shot (spec 65): the line is for bank shots only, a shot that
    /// doesn't bounce goes where the finger points anyway.
    private func updateTrajectory() {
        guard let aimPoint,
              let points = engine.predictedPath(toward: geometry.corePoint(aimPoint)),
              Self.bouncesOffWall(points),
              let first = points.first,
              let ready = engine.readyBubble
        else {
            trajectoryNode.isHidden = true
            return
        }
        let unitsPerPoint = (view?.contentScaleFactor ?? 1) / pixelsPerUnit
        let scenePoints = points.map { geometry.scenePoint($0) }
        let path = CGMutablePath()
        path.move(to: geometry.scenePoint(first))
        for i in scenePoints.indices.dropFirst().dropLast() {
            let corner = scenePoints[i]
            let radius = Self.cornerRadius(
                from: scenePoints[i - 1], at: corner, to: scenePoints[i + 1],
                cut: trajectoryCornerCut * unitsPerPoint
            )
            if radius > 0 {
                path.addArc(tangent1End: corner, tangent2End: scenePoints[i + 1], radius: radius)
            } else {
                path.addLine(to: corner)
            }
        }
        if let last = scenePoints.last, scenePoints.count > 1 { path.addLine(to: last) }
        trajectoryNode.path = path
        updateTrajectoryColors(for: ready)
        trajectoryNode.lineWidth = trajectoryWidth * unitsPerPoint
        trajectoryNode.isHidden = false
    }

    /// The radius that rounds the corner at `corner` starting `cut` before it
    /// on each segment (or at the segment's half, if shorter). 0 for no
    /// round — a corner that turns right back on itself.
    private static func cornerRadius(from previous: CGPoint, at corner: CGPoint, to next: CGPoint,
                                     cut: CGFloat) -> CGFloat {
        let a = CGVector(dx: previous.x - corner.x, dy: previous.y - corner.y)
        let b = CGVector(dx: next.x - corner.x, dy: next.y - corner.y)
        let la = hypot(a.dx, a.dy), lb = hypot(b.dx, b.dy)
        guard la > 0, lb > 0 else { return 0 }
        let cosine = max(-1, min(1, (a.dx * b.dx + a.dy * b.dy) / (la * lb)))
        let halfAngle = acos(cosine) / 2
        guard halfAngle > 0.01 else { return 0 }
        // The round meets each segment r / tan(half angle) from the corner.
        return min(cut, min(la, lb) / 2) * tan(halfAngle)
    }

    /// Whether a `predictedPath` meets a wall: every bounce puts its point
    /// exactly on one.
    private static func bouncesOffWall(_ points: [Vec2]) -> Bool {
        points.contains { $0.x == GameConsts.leftBoardBorder || $0.x == GameConsts.rightBoardBorder }
    }

    /// Feeds the shader the background and the line's color: the color of
    /// the bubble in the cannon, the one about to fly it, fully opaque
    /// (spec 91; a faint white or black before).
    private func updateTrajectoryColors(for ready: Bubble) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        Palette.background.getRed(&r, green: &g, blue: &b, alpha: nil)
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0
        Palette.color(for: ready.color).getRed(&lr, green: &lg, blue: &lb, alpha: nil)
        let line = vector_float4(Float(lr), Float(lg), Float(lb), 1)
        let background = vector_float4(Float(r), Float(g), Float(b), 1)
        if trajectoryShader.uniformNamed("u_line")?.vectorFloat4Value != line {
            trajectoryShader.uniformNamed("u_line")?.vectorFloat4Value = line
        }
        if trajectoryShader.uniformNamed("u_background")?.vectorFloat4Value != background {
            trajectoryShader.uniformNamed("u_background")?.vectorFloat4Value = background
        }
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
    ///   ease-out for a queue/cannon slide, `rowShiftDuration` ease-in-out
    ///   while a row is being added, spec 76); anything smaller than `moveThreshold` is left alone so the
    ///   in-flight action isn't restarted every tick.
    /// Spec 44: a launched bubble is also always fully opaque (its fade is
    /// cancelled and alpha set to 1 on the spot), and a node that left
    /// `.inQueue` (it is dimmed, no fade running) starts brightening to 1 in
    /// step with its slide into the cannon.
    private func updatePosition(node: SKNode, bubble: Bubble, scenePos: CGPoint, addingRow: Bool) {
        if bubble.state == .launched {
            node.removeAction(forKey: moveActionKey)
            node.removeAction(forKey: fadeActionKey)
            node.alpha = 1
            targets.removeValue(forKey: bubble.id)
            node.position = scenePos
            if let node = node as? BubbleNode {
                updateFlightStretch(node: node, bubble: bubble)
            }
            return
        }

        // Not a new row's bubble waiting hidden for its wave (spec 76): it
        // shows when its turn comes, not now.
        if bubble.state != .inQueue, node.alpha < 1, node.action(forKey: fadeActionKey) == nil,
           node.action(forKey: rowAppearKey) == nil {
            let brighten = SKAction.fadeAlpha(to: 1, duration: queueMoveDuration)
            brighten.timingMode = .easeOut
            node.run(brighten, withKey: fadeActionKey)
        }

        guard let previousTarget = targets[bubble.id] else {
            node.position = scenePos
            targets[bubble.id] = bubble.position
            return
        }

        guard previousTarget.distance(to: bubble.position) > moveThreshold else { return }
        targets[bubble.id] = bubble.position

        node.removeAction(forKey: moveActionKey)
        let move = SKAction.move(to: scenePos, duration: addingRow ? rowShiftDuration : queueMoveDuration)
        move.timingMode = addingRow ? .easeInEaseOut : .easeOut
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
    ///   or right after a board reset) is exempted: it just appears. Every
    ///   `.inQueue` node, slid in or not, is dimmed to `queueBubbleAlpha`
    ///   (spec 44) — a restored game or a rebuilt scene gets it too, since
    ///   those create fresh nodes through here.
    /// - During a row-add frame, a brand-new top-row `.onBoard` bubble
    ///   starts hidden in its cell and appears there in the wave once the
    ///   board has slid down (`appearInWave`, spec 76).
    private func placeNewNode(node: BubbleNode, bubble: Bubble, scenePos: CGPoint, addingRow: Bool) {
        if bubble.state == .inQueue {
            targets[bubble.id] = bubble.position
            node.alpha = queueBubbleAlpha
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
            appearInWave(node, at: bubble.position)
        }
    }

    /// Spec 76: a bubble of a new row waits, hidden, for the empty row to
    /// show and for its turn in the wave — by its row, the lowest new one
    /// first, then by how far across it is — and then fades in as it drops
    /// the last little way into its cell (spec 87). `node` is already at its
    /// cell.
    private func appearInWave(_ node: BubbleNode, at position: Vec2) {
        let row = max(0, Int(((position.y - GameConsts.initialY) / GameConsts.rowHeight).rounded()))
        let rowsBelow = max(0, rowsAddedThisFrame - 1 - row)
        let span = GameConsts.rightBoardBorder - GameConsts.leftBoardBorder
        let across = min(1, max(0, (position.x - GameConsts.leftBoardBorder) / span))
        let delay = rowWaveLead + Double(rowsBelow) * rowWaveRowDelay + across * rowWaveDuration

        let cell = node.position
        node.alpha = 0
        node.position = CGPoint(x: cell.x, y: cell.y + rowAppearDrop)
        let drop = SKAction.move(to: cell, duration: rowAppearDuration)
        drop.timingMode = .easeOut
        let fade = SKAction.fadeIn(withDuration: rowAppearDuration)
        fade.timingMode = .easeOut
        node.run(
            SKAction.sequence([SKAction.wait(forDuration: delay), SKAction.group([drop, fade])]),
            withKey: rowAppearKey
        )
    }

    /// Ends a new bubble's wave at once, fully shown, when something else
    /// takes the bubble over before it is all there (spec 76). Every caller
    /// then places the bubble itself or lets it fall from where it is — at
    /// most `rowAppearDrop` above its cell.
    private func finishRowAppear(_ node: SKNode) {
        guard node.action(forKey: rowAppearKey) != nil else { return }
        node.removeAction(forKey: rowAppearKey)
        node.alpha = 1
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
            case let .launched(id, _):
                startFlightStretch(id: id)
            case let .landed(id, _, _):
                lastLandedId = id
                squashOnLanding(id: id, removedPositions: removedPositions)
            case let .clusterMatched(ids, color):
                // Spec 51: in `.pops` the cluster's nodes stay where they are
                // and pop one by one on their own `.removed` events.
                guard Self.matchEffect == .bridges else { break }
                startBridgeMerge(ids: ids, color: color, removedPositions: removedPositions)
            case let .removed(id, _, position, _, reason):
                animateRemoval(id: id, reason: reason, position: position)
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
            case let .rowsAdded(count):
                rowsAddedThisFrame = count
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

    /// Velocity of a bubble in scene coordinates (the core's Y axis points
    /// down, the scene's up).
    private func sceneVelocity(of bubble: Bubble) -> CGVector {
        CGVector(dx: bubble.velocity.x, dy: -bubble.velocity.y)
    }

    /// Spec 47: the shot leaves the cannon — squashed by the push, then
    /// stretched along its line of flight.
    private func startFlightStretch(id: Int) {
        guard let node = nodes[id] as? BubbleNode,
              let bubble = engine.bubbles.first(where: { $0.id == id }) else { return }
        let velocity = sceneVelocity(of: bubble)
        flightVelocities[id] = velocity
        flightBubbles[id] = bubble
        jelly.launch(node, direction: velocity)
    }

    /// Spec 47, every frame of the flight: keeps the stretch along the
    /// current velocity, and answers a wall bounce — `dx` changing sign
    /// since the last frame — with a squash across the wall.
    private func updateFlightStretch(node: BubbleNode, bubble: Bubble) {
        let velocity = sceneVelocity(of: bubble)
        if let previous = flightVelocities[bubble.id], previous.dx * velocity.dx < 0 {
            jelly.impulse(node, direction: CGVector(dx: 1, dy: 0), peak: BubbleJelly.wallSquash)
            haptics.bubbleHit()
        }
        flightVelocities[bubble.id] = velocity
        jelly.setFlightTarget(node, direction: velocity)
    }

    /// Spec 47: the fired bubble hits — it squashes along its velocity and
    /// springs back to round, and the bubbles around it take the blow ring
    /// by ring, each weaker and a little later (`BubbleJelly.rings`). Those in
    /// front of the blow squash more. Only resting board bubbles with a node
    /// of their own take part (not falling ones, not those in a merge layer).
    private func squashOnLanding(id: Int, removedPositions: [Int: Vec2]) {
        let lastFrameVelocity = flightVelocities.removeValue(forKey: id)
        let finalVelocity = flightBubbles.removeValue(forKey: id).map { sceneVelocity(of: $0) }
        guard let velocity = finalVelocity ?? lastFrameVelocity else { return }
        if let node = nodes[id] as? BubbleNode {
            jelly.clearTarget(node)
            jelly.impulse(node, direction: velocity, peak: BubbleJelly.landingSquash)
        }
        haptics.bubbleHit()
        guard let corePosition = engine.bubbles.first(where: { $0.id == id })?.position ?? removedPositions[id] else { return }
        let center = geometry.scenePoint(corePosition)
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed > 0 else { return }
        let forward = CGVector(dx: velocity.dx / speed, dy: velocity.dy / speed)

        let reach = GameConsts.bubbleSize * (BubbleJelly.rings.last?.radius ?? 0)
        for other in engine.bubbles where other.id != id && other.state == .onBoard {
            guard !mergeIds.contains(other.id), !dying.contains(other.id),
                  let node = nodes[other.id] as? BubbleNode else { continue }
            let point = geometry.scenePoint(other.position)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = hypot(dx, dy)
            guard distance > 0, distance < reach,
                  let ring = BubbleJelly.rings.first(where: { distance < GameConsts.bubbleSize * $0.radius })
            else { continue }
            let toward = CGVector(dx: dx / distance, dy: dy / distance)
            let front = max(0, toward.dx * forward.dx + toward.dy * forward.dy)
            let peak = BubbleJelly.neighbourSquash * (0.35 + 0.65 * front) * ring.strength
            jelly.impulse(node, direction: toward, peak: peak, delay: ring.delay)
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
            finishRowAppear(node)
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
        // Spec 43: one pop haptic per bridge, as it appears — the match is
        // voiced by the bridges, not by the `.removed` events.
        layer.onBridgeAppeared = { [weak self] in self?.haptics.bubblePopped() }
        addChild(layer)
        mergeLayers.append(layer)
        layer.play { [weak self, weak layer] in
            guard let layer else { return }
            layer.removeFromParent()
            self?.mergeLayers.removeAll { $0 === layer }
        }
    }

    /// Removal animation of one bubble. A matched bubble pops (spec 51) — a
    /// flash, then a collapse with a light blur — in the default `.pops` mode; with `.bridges`
    /// (spec 38) a match has no animation of its own here: a bubble that went
    /// into a bridge merge layer is animated by that layer, so its `.removed`
    /// only checks it off, which is also what lets `sync()` trust
    /// `engine.bubbles` for this id again. (Any other match-removed node in
    /// that mode — in practice there is none, the engine announces the whole
    /// cluster before its first removal — is dropped by `sync()`, as its id is
    /// gone from `engine.bubbles`.) A hanging bubble falls in both modes.
    private func animateRemoval(id: Int, reason: RemovalReason, position: Vec2) {
        if mergeIds.remove(id) != nil { return }
        if reason == .match && Self.matchEffect == .bridges { return }

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
        finishRowAppear(node)

        let cleanup = SKAction.run { [weak self] in
            node.removeFromParent()
            self?.dying.remove(id)
        }

        if reason == .match, let bubble = node as? BubbleNode {
            // Spec 52: the engine removes the first matched bubble (usually
            // the shot) in the same frame as `.landed`, before `sync()` has
            // moved its node from the last flight frame, so pop it at the
            // cell the event names, fully opaque.
            bubble.position = geometry.scenePoint(position)
            bubble.alpha = 1
            haptics.bubblePopped()
            bubble.run(popAction(for: bubble, cleanup: cleanup))
            return
        }

        node.run(SKAction.sequence([fallAction(), cleanup]))
    }

    /// A bubble falling off the board: down and out over `fallDuration`.
    /// Spec 45: it blurs into a cloud as it falls, like the dissolve of a
    /// matched cluster — or falls sharp, if the pre-blurred frames are not
    /// ready yet.
    private func fallAction() -> SKAction {
        var actions = [
            SKAction.moveBy(x: 0, y: -300, duration: fallDuration),
            SKAction.fadeOut(withDuration: fallDuration)
        ]
        if let blur = FallBlurFrames.blurAction(duration: fallDuration) {
            actions.append(blur)
        }
        return SKAction.group(actions)
    }

    /// Spec 51: one bubble's pop — `flashDuration` of swelling to `flashScale`
    /// and lightening, then `popFadeDuration` of collapsing to nothing. The
    /// scale goes through `BubbleNode.baseScale`, not `setScale` or
    /// `SKAction.scale`: `BubbleJelly` writes the node's transform every
    /// frame on top of `baseScale`, so a direct scale would fight it — and
    /// this way a squash that is still settling plays on under the pop. The
    /// haptic fires as the pop starts, one per bubble.
    private func popAction(for bubble: BubbleNode, cleanup: SKAction) -> SKAction {
        let base = bubble.color
        let lit = Self.lightened(base, by: flashLightenFraction)
        var baseR: CGFloat = 0, baseG: CGFloat = 0, baseB: CGFloat = 0, baseA: CGFloat = 0
        base.getRed(&baseR, green: &baseG, blue: &baseB, alpha: &baseA)
        var litR: CGFloat = 0, litG: CGFloat = 0, litB: CGFloat = 0, litA: CGFloat = 0
        lit.getRed(&litR, green: &litG, blue: &litB, alpha: &litA)

        let flashDuration = flashDuration
        let popFadeDuration = popFadeDuration
        let peak = flashScale

        let flash = SKAction.customAction(withDuration: flashDuration) { node, elapsed in
            guard let bubble = node as? BubbleNode else { return }
            // Progress 0...1, eased out slightly so the flash settles rather
            // than arriving at a constant rate.
            let t = flashDuration > 0 ? min(1, max(0, CGFloat(elapsed) / CGFloat(flashDuration))) : 1
            let eased = t * (2 - t)
            bubble.baseScale = 1 + (peak - 1) * eased
            bubble.color = SKColor(
                red: baseR + (litR - baseR) * eased,
                green: baseG + (litG - baseG) * eased,
                blue: baseB + (litB - baseB) * eased,
                alpha: baseA + (litA - baseA) * eased
            )
        }
        let collapse = SKAction.customAction(withDuration: popFadeDuration) { node, elapsed in
            guard let bubble = node as? BubbleNode else { return }
            let t = popFadeDuration > 0 ? min(1, max(0, CGFloat(elapsed) / CGFloat(popFadeDuration))) : 1
            bubble.baseScale = peak * (1 - t)
        }
        var collapseActions = [collapse, SKAction.fadeOut(withDuration: popFadeDuration)]
        // Spec 52: a light blur grows as the bubble collapses. Nil — a sharp
        // pop — if the pre-blurred frames are not ready yet.
        if let blur = FallBlurFrames.blurAction(duration: popFadeDuration, toRadius: popBlurRadius, delay: 0) {
            collapseActions.append(blur)
        }
        let shrinkAndFade = SKAction.group(collapseActions)
        return SKAction.sequence([flash, shrinkAndFade, cleanup])
    }

    /// `color` moved `fraction` of the way toward white.
    private static func lightened(_ color: SKColor, by fraction: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(
            red: r + (1 - r) * fraction, green: g + (1 - g) * fraction,
            blue: b + (1 - b) * fraction, alpha: a
        )
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
        jelly.reset()
        flightVelocities.removeAll()
        flightBubbles.removeAll()
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
    /// must already have been reset by the caller before calling this). The
    /// reset's own pending events are dropped: the scene is rebuilt here and
    /// now, and a `.boardReset` drained later — after a pour (spec 69) — would
    /// rebuild it a second time, cutting the cannon bubbles' appearance short.
    func rebuild() {
        _ = engine.drainEvents()
        performBoardReset()
    }

    /// Restart, first half (spec 69): every bubble on screen falls off the
    /// way a hanging bubble does in play — the bottom row first, then row
    /// after row up to the top, each bubble at a small random delay within
    /// its row; the cannon and queue bubbles, lowest of all, go first. The
    /// engine freezes, so a bubble in flight stops where it is and falls with
    /// its own row. `completion` runs once the last one is gone; the board
    /// stays frozen for the reset and the pour that follow.
    func collapseBoard(completion: @escaping () -> Void) {
        freezeEngine()
        haptics.prepareForBoardChange()
        // Spec 70: a faint tick as each bubble lets go.
        let letGo = SKAction.run { [weak self] in self?.haptics.boardBubbleLetGo() }
        let bubbles = nodes.values.compactMap { $0 as? BubbleNode }
        let rows = Self.rowsBottomUp(bubbles.map { ($0, $0.position.y) })
        var end: TimeInterval = 0
        for (index, row) in rows.enumerated() {
            for node in row {
                let delay = Double(index) * collapseRowStep + .random(in: 0...boardJitter)
                node.removeAction(forKey: moveActionKey)
                node.removeAction(forKey: fadeActionKey)
                finishRowAppear(node)
                node.run(SKAction.sequence([
                    SKAction.wait(forDuration: delay), letGo, fallAction(), SKAction.removeFromParent()
                ]), withKey: boardTransitionKey)
                end = max(end, delay + fallDuration)
            }
        }
        removeAction(forKey: boardTransitionKey)
        run(SKAction.sequence([SKAction.wait(forDuration: end), SKAction.run(completion)]), withKey: boardTransitionKey)
    }

    /// A new board, the pour (spec 69): its bubbles drop in from above the
    /// top of the screen, picking up speed, and squash a little as they land
    /// in their cells — the bottom row first, then row after row up to the
    /// top, each bubble at a small random delay within its row, so the rows
    /// fill in from below. Once the board is in, the cannon and queue bubbles
    /// slide up into place, the engine thaws and `completion` runs. The bubbles
    /// are moved out of sight at once and start falling `delay` seconds
    /// later, which lets the pour wait behind a fading overlay.
    func pourIn(after delay: TimeInterval, completion: @escaping () -> Void) {
        freezeEngine()
        haptics.prepareForBoardChange()
        let top = CGFloat(geometry.canvasHeight + topExtension) + CGFloat(GameConsts.bubbleSize)
        var board: [(node: BubbleNode, target: CGPoint)] = []
        var cannon: [(node: BubbleNode, alpha: CGFloat)] = []
        for bubble in engine.bubbles {
            guard let node = nodes[bubble.id] as? BubbleNode else { continue }
            node.removeAction(forKey: boardTransitionKey)
            node.removeAction(forKey: moveActionKey)
            node.removeAction(forKey: fadeActionKey)
            finishRowAppear(node)
            let target = geometry.scenePoint(bubble.position)
            if bubble.state == .onBoard {
                node.alpha = 1
                node.position = CGPoint(x: target.x, y: top)
                board.append((node, target))
            } else {
                node.position = target
                node.isHidden = true
                cannon.append((node, bubble.state == .inQueue ? queueBubbleAlpha : 1))
            }
        }

        let rows = Self.rowsBottomUp(board.map { ($0, $0.target.y) })
        var landed = delay
        for (index, row) in rows.enumerated() {
            for entry in row {
                let start = delay + Double(index) * pourRowStep + .random(in: 0...boardJitter)
                let drop = drop(entry.node, from: top, to: entry.target)
                entry.node.run(SKAction.sequence([SKAction.wait(forDuration: start), drop]), withKey: boardTransitionKey)
                landed = max(landed, start + drop.duration)
            }
        }

        removeAction(forKey: boardTransitionKey)
        run(SKAction.sequence([
            SKAction.wait(forDuration: landed),
            SKAction.run { [weak self] in
                guard let self else { return }
                for entry in cannon {
                    self.appear(entry.node, alpha: entry.alpha, after: entry.alpha < 1 ? self.pourAppearStagger : 0)
                }
                self.thawEngine()
                completion()
            }
        ]), withKey: boardTransitionKey)
    }

    /// One poured bubble: a free fall from `top` straight down to `target`,
    /// then a squash on landing, with a faint tick (spec 70).
    private func drop(_ node: BubbleNode, from top: CGFloat, to target: CGPoint) -> SKAction {
        let gravity = pourGravity
        let duration = TimeInterval(((2 * max(0, top - target.y)) / gravity).squareRoot())
        let fall = SKAction.customAction(withDuration: duration) { node, elapsed in
            let t = CGFloat(elapsed)
            node.position = CGPoint(x: target.x, y: max(target.y, top - gravity * t * t / 2))
        }
        let land = SKAction.run { [weak self, weak node] in
            guard let self, let node else { return }
            node.position = target
            self.jelly.impulse(node, direction: CGVector(dx: 0, dy: -1), peak: self.pourLandingSquash)
            self.haptics.boardBubbleSettled()
        }
        return SKAction.sequence([fall, land])
    }

    /// The cannon or queue bubble after a pour: slides up into its place
    /// from `pourAppearOffset` below, fading in to `alpha`, its own opacity
    /// (the queue bubble stays dimmed, spec 44), `delay` seconds from now.
    /// The slide runs under `moveActionKey` and the fade under
    /// `fadeActionKey`, so `sync()` starts neither a move nor a brightening of
    /// its own on top, and a shot fired mid-slide takes the bubble over.
    private func appear(_ node: BubbleNode, alpha: CGFloat, after delay: TimeInterval) {
        let target = node.position
        node.position = CGPoint(x: target.x, y: target.y - pourAppearOffset)
        node.alpha = 0
        node.isHidden = false
        let slide = SKAction.move(to: target, duration: pourAppearDuration)
        slide.timingMode = .easeOut
        let fade = SKAction.fadeAlpha(to: alpha, duration: pourAppearDuration)
        fade.timingMode = .easeOut
        let wait = SKAction.wait(forDuration: delay)
        node.run(SKAction.sequence([wait, slide]), withKey: moveActionKey)
        node.run(SKAction.sequence([wait, fade]), withKey: fadeActionKey)
    }

    private func freezeEngine() {
        isEngineFrozen = true
        aimPoint = nil
        trajectoryNode.isHidden = true
    }

    private func thawEngine() {
        isEngineFrozen = false
        accumulator = 0
    }

    /// Groups items into rows by height — exactly equal heights, rounded to
    /// a logical unit, are one row (a board row; the cannon and the queue
    /// are rows of their own) — ordered from the bottom of the scene up.
    private static func rowsBottomUp<T>(_ items: [(T, CGFloat)]) -> [[T]] {
        let grouped = Dictionary(grouping: items) { $0.1.rounded() }
        return grouped.keys.sorted().map { key in grouped[key, default: []].map(\.0) }
    }

    /// Re-applies the current palette to every live bubble node — the
    /// cannon-loaded ("ready"), queued, on-board, and any in-flight
    /// ("launched") bubble alike (spec 32). `sync()` would eventually repaint
    /// everything on its own next pass too (it calls `apply(color:)`
    /// unconditionally every frame), but calling this explicitly when the
    /// palette changes makes the repaint immediate and the dependency
    /// intentional rather than incidental.
    func repaintBubbles() {
        backgroundColor = Palette.background
        let colorsById = Dictionary(uniqueKeysWithValues: engine.bubbles.map { ($0.id, $0.color) })
        for (id, node) in nodes {
            guard let bubbleNode = node as? BubbleNode, let color = colorsById[id] else { continue }
            bubbleNode.apply(color: color)
        }
    }
}

