import CoreImage.CIFilterBuiltins
import SpriteKit
import UIKit
import BubbleShooterCore

/// The connector ("bridge") between two circles — the classic metaball
/// connector by Hiroyuki Sato (spec 38). Pure geometry, no drawing.
///
/// For circles `(c1, r1)` and `(c2, r2)` at distance `d`, `v` says how far the
/// bridge has opened. At `v = 0` the four anchor points collapse into the two
/// touching points and the bridge is a line of zero width; as `v` grows the
/// anchors slide round the circles and the bridge widens, its sides staying
/// concave (the handles are tangent to the circles).
enum BridgeShape {
    /// Contour of the bridge as a closed path in the same y-up space the
    /// centers are given in: from `p1` a Bézier to `p3`, along circle 2's near
    /// side to `p4`, a Bézier back to `p2`, a straight chord closing to `p1`.
    ///
    /// The chord lies inside circle 1 and the arc is pulled `overlap` units
    /// inside circle 2, so the bridge tucks under both circles and no seam
    /// shows where they meet. (The arc must not sit exactly on circle 2's rim:
    /// the bridge and the circle are separate antialiased sprites, and two
    /// half-covered edge pixels on the same rim composite to a dark line.)
    static func path(
        r1: CGFloat, r2: CGFloat, c1: CGPoint, c2: CGPoint,
        v: CGFloat, handleSize: CGFloat, overlap: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        let dx = c2.x - c1.x
        let dy = c2.y - c1.y
        let d = hypot(dx, dy)
        // One circle inside the other (or the same center): no bridge.
        guard d > 0, d > abs(r1 - r2) else { return path }

        func clampUnit(_ x: CGFloat) -> CGFloat { min(1, max(-1, x)) }
        func point(_ c: CGPoint, _ r: CGFloat, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle))
        }

        var u1: CGFloat = 0
        var u2: CGFloat = 0
        if d < r1 + r2 {
            u1 = acos(clampUnit((r1 * r1 + d * d - r2 * r2) / (2 * r1 * d)))
            u2 = acos(clampUnit((r2 * r2 + d * d - r1 * r1) / (2 * r2 * d)))
        }
        let a = atan2(dy, dx)
        let spread = acos(clampUnit((r1 - r2) / d))

        let ang1 = a + u1 + (spread - u1) * v
        let ang2 = a - u1 - (spread - u1) * v
        let ang3 = a + .pi - u2 - (.pi - u2 - spread) * v
        let ang4 = a - .pi + u2 + (.pi - u2 - spread) * v

        let p1 = point(c1, r1, ang1)
        let p2 = point(c1, r1, ang2)
        let p3 = point(c2, r2, ang3)
        let p4 = point(c2, r2, ang4)

        let d2 = min(v * handleSize, hypot(p1.x - p3.x, p1.y - p3.y) / (r1 + r2))
            * min(1, 2 * d / (r1 + r2))
        let h1len = r1 * d2
        let h2len = r2 * d2
        let h1 = point(p1, h1len, ang1 - .pi / 2)
        let h2 = point(p2, h1len, ang2 + .pi / 2)
        let h3 = point(p3, h2len, ang3 + .pi / 2)
        let h4 = point(p4, h2len, ang4 - .pi / 2)

        // Circle 2's arc runs counter-clockwise from `ang3` to `ang4` through
        // the side that faces circle 1.
        var sweep = ang4 - ang3
        while sweep < 0 { sweep += 2 * .pi }
        while sweep >= 2 * .pi { sweep -= 2 * .pi }
        let arcRadius = r2 - overlap

        path.move(to: p1)
        path.addCurve(to: p3, control1: h1, control2: h3)
        path.addLine(to: point(c2, arcRadius, ang3))
        path.addArc(center: c2, radius: arcRadius, startAngle: ang3, endAngle: ang3 + sweep, clockwise: false)
        path.addLine(to: p4)
        path.addCurve(to: p2, control1: h4, control2: h2)
        path.closeSubpath()
        return path
    }
}

/// The effect that plays when a cluster of three or more bubbles matches
/// (spec 38, replacing the blur-based gooey merge of spec 37).
///
/// The bubbles do not move and do not change size. Between every pair of
/// neighbouring bubbles a bridge grows, one after another in a wave that
/// starts at the bubble that was just fired and spreads through the cluster;
/// when the last bridge is complete, the whole figure dissolves in place.
///
/// Bridges are sprites, not shapes: `SKShapeNode` is drawn almost without
/// antialiasing in our scaled scene, a texture drawn by Core Graphics (with
/// mipmaps, like the bubble's own circle) is not. Neighbouring bubbles on the
/// hex grid are always exactly one `bubbleSize` apart, so every bridge looks
/// the same up to rotation: the growth frames are drawn once, for a horizontal
/// pair, and shared by all bridges of all effects.
///
/// The dissolve (spec 39) is two things at once: the tint of every part
/// darkens to black, and the figure blurs.
///
/// The darkening lowers the tint rather than the opacity. SpriteKit applies
/// opacity to each node separately, so wherever a bridge tucks under a circle
/// the overlap would show through as a denser patch while fading. The
/// background under a cluster is pure black, so tinting everything to black
/// looks the same as a group fade, minus the artifact.
///
/// The blur is applied to the figure as one image, circles and bridges
/// together, which is why the node is an `SKEffectNode`: parts blurred one by
/// one would leave dark seams where a bridge goes under a circle. The filter
/// chain is a single `CIGaussianBlur` and nothing else — a filter that makes
/// the output extent infinite (a clamp, a color matrix without a crop) takes
/// Metal down, as it did in spec 37. The effect is off for the growth and the
/// pause, so those render as plain sprites with no offscreen buffer, and
/// switches on at the first frame of the dissolve. Its glow falls into the
/// gaps between neighbouring bubbles; the layer stays below the bubbles at
/// rest, so it never paints over them.
///
/// An effect node renders its children into a buffer at one pixel per *local*
/// unit, then draws the buffer scaled like any other node — so at the scene's
/// own scale (a couple of device pixels per logical unit) the figure would
/// turn visibly soft the moment the effect switches on. Same trick as spec 37:
/// the layer is shrunk by `pixelsPerUnit` and everything inside is enlarged by
/// the same factor — positions, bubble and bridge scale, blur radius, margin —
/// so the buffer holds about one pixel per device pixel while the size and
/// position of every part on screen stay put.
///
/// The buffer is cut to the bounds of the children and a blur runs into its
/// edge, shearing the figure off with a straight line. A transparent spacer
/// sprite, larger than the cluster by `bufferMargin` all around, keeps the
/// edge out of reach.
///
/// The first CI blur of a launch stalls for a few hundred milliseconds while
/// the filter pipeline is set up; `warmUp(in:pixelsPerUnit:)` pays that once,
/// off screen, after the game has finished fading in.
///
/// Add the node to the scene at the origin: the bubble nodes are re-parented
/// into it and keep their scene positions (see `init` for the scale the node
/// applies to itself internally).
final class BridgeMergeNode: SKEffectNode {
    // MARK: - Tuning (spec 38)
    //
    // Every number of the effect lives here, side by side, so it can be
    // re-tuned with a single edit. Distances are in the scene's logical units
    // (a bubble is 30 across), durations in seconds.

    /// Largest opening `v` a bridge reaches (see `BridgeShape`).
    static let bridgeSpread: CGFloat = 0.35
    /// Length of the Bézier handles, relative to the bubble radius.
    static let handleSize: CGFloat = 2.4
    /// How long one bridge takes to grow, eased in and out.
    static let bridgeGrowDuration: TimeInterval = 0.22
    /// Largest delay between the starts of two consecutive bridges.
    static let edgeStaggerMax: TimeInterval = 0.07
    /// The whole wave (first start to last start) never spreads over more
    /// than this, so a big cluster does not drag on for seconds.
    static let maxWaveSpread: TimeInterval = 0.45
    /// Pause between the last bridge completing and the dissolve starting.
    static let holdAfterBridges: TimeInterval = 0.1
    /// How long the dissolve takes, eased in and out.
    static let fadeDuration: TimeInterval = 0.3
    /// Blur radius the dissolve ends at (spec 39), logical units. It eases out
    /// over the dissolve, so it builds up a little ahead of the darkening and
    /// can actually be seen.
    static let maxBlurRadius: CGFloat = 5
    /// Empty space kept around the figure inside the effect's buffer, logical
    /// units (see the class comment). Must comfortably exceed 3 ×
    /// `maxBlurRadius`, the reach of the blur kernel.
    static let bufferMargin: CGFloat = 24
    /// Number of pre-drawn growth frames (`v` from 0 to `bridgeSpread`).
    static let bridgeTextureSteps = 24
    /// Two bubbles are neighbours when their centers are closer than this
    /// many bubble sizes (the grid's next-nearest pair is ~1.73 away).
    static let neighbourDistanceFactor: CGFloat = 1.2

    /// Debug launch argument that slows the whole effect down by
    /// `slowMotionFactor`, so it can be looked at frame by frame and tuned.
    /// Stays in the code, like `-showGameOverDemo`.
    static let slowMotionArgument = "-slowMotionGoo"
    static let slowMotionFactor: TimeInterval = 8
    /// Time multiplier applied to every duration: `slowMotionFactor` when the
    /// debug argument is present, otherwise 1.
    static let timeScale: TimeInterval = CommandLine.arguments.contains(slowMotionArgument) ? slowMotionFactor : 1

    /// `zPosition` of the layer: below bubbles at rest (10), so a bubble in
    /// flight over the cluster is never hidden by the effect. Inside the layer
    /// bridges sit at 0 and circles at 1, so a circle covers the end of every
    /// bridge that tucks under it.
    static let layerZPosition: CGFloat = 2
    private static let bridgeZPosition: CGFloat = 0
    private static let circleZPosition: CGFloat = 1

    // MARK: - Bridge textures

    /// Radius of the visible bubble circle: the shared circle texture is
    /// 256 px with a 2 px inset, drawn into a 30-unit sprite.
    private static let circleRadius: CGFloat = 30 * (256 - 2 * 2) / 256 / 2
    /// Distance between neighbouring centers on the grid.
    private static let pairDistance = CGFloat(GameConsts.bubbleSize)
    /// Texture density, pixels per logical unit: about what the circle
    /// texture has, so a bridge's edge is as soft as a circle's.
    private static let texturePixelsPerUnit: CGFloat = 8
    /// How far the bridge is tucked under circle 2, logical units.
    private static let tuck: CGFloat = 1
    /// Empty margin around the largest bridge in its texture, logical units.
    private static let textureMargin: CGFloat = 2

    /// Growth frames of a bridge between a horizontal pair, centered on the
    /// pair's midpoint, plus the sprite size that maps them 1:1.
    private static let growth: (frames: [SKTexture], size: CGSize) = {
        let r = circleRadius
        let d = pairDistance
        let c1 = CGPoint(x: -d / 2, y: 0)
        let c2 = CGPoint(x: d / 2, y: 0)
        func path(_ v: CGFloat) -> CGPath {
            BridgeShape.path(r1: r, r2: r, c1: c1, c2: c2, v: v, handleSize: handleSize, overlap: tuck)
        }

        // The box has to hold the widest bridge; it is centered on the pair's
        // midpoint so the sprite can simply be placed there.
        let widest = path(bridgeSpread).boundingBoxOfPath
        let halfWidth = max(abs(widest.minX), abs(widest.maxX)) + textureMargin
        let halfHeight = max(abs(widest.minY), abs(widest.maxY)) + textureMargin
        let scale = texturePixelsPerUnit
        let pixelSize = CGSize(width: ceil(halfWidth * 2 * scale), height: ceil(halfHeight * 2 * scale))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)

        let steps = max(2, bridgeTextureSteps)
        let frames = (0..<steps).map { step -> SKTexture in
            let v = bridgeSpread * CGFloat(step) / CGFloat(steps - 1)
            let image = renderer.image { context in
                let cg = context.cgContext
                // Unit space, y up, origin at the pair's midpoint.
                cg.translateBy(x: pixelSize.width / 2, y: pixelSize.height / 2)
                cg.scaleBy(x: scale, y: -scale)
                cg.setFillColor(UIColor.white.cgColor)
                cg.addPath(path(v))
                cg.fillPath()
            }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            // Minified ~3.5x on screen, like the circle: without mipmaps the
            // edge would alias.
            texture.usesMipmaps = true
            return texture
        }
        return (frames, CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale))
    }()

    // MARK: - State

    private struct Bridge {
        let sprite: SKSpriteNode
        /// Seconds (before `timeScale`) into the effect at which it starts growing.
        let start: TimeInterval
        /// Growth frame currently shown; -1 while hidden.
        var shownFrame: Int
    }

    private let bubbles: [BubbleNode]
    private var bridges: [Bridge] = []
    private let red: CGFloat
    private let green: CGFloat
    private let blue: CGFloat
    /// Seconds, before `timeScale`: when the last bridge is complete.
    private let bridgesDoneAt: TimeInterval
    /// Darkening currently applied to the tint, 0...1.
    private var appliedDark: CGFloat = 0
    /// Blur radius currently applied, logical units.
    private var appliedRadius: CGFloat = 0
    /// Device pixels per logical unit. See the class comment.
    private let pixelsPerUnit: CGFloat
    private let blurFilter = CIFilter.gaussianBlur()
    private let animationKey = "bridgeMerge"

    /// Takes over `bubbles` — the nodes of one matched cluster, all of one
    /// color, at their final scene positions — re-parenting them into the
    /// effect. The bridge wave starts at `bubbles[startIndex]`. `pixelsPerUnit`
    /// is the density the scene is shown at (device pixels per logical unit).
    init(bubbles: [BubbleNode], startIndex: Int, color: UIColor, pixelsPerUnit: CGFloat) {
        self.bubbles = bubbles
        self.pixelsPerUnit = max(1, pixelsPerUnit)
        let hex = color.opaqueHexValue
        red = CGFloat((hex >> 16) & 0xFF) / 255
        green = CGFloat((hex >> 8) & 0xFF) / 255
        blue = CGFloat(hex & 0xFF) / 255

        let edges = Self.waveOrderedEdges(
            positions: bubbles.map(\.position),
            startIndex: startIndex
        )
        let stagger = min(Self.edgeStaggerMax, Self.maxWaveSpread / Double(max(1, edges.count - 1)))
        bridgesDoneAt = edges.isEmpty ? 0 : Double(edges.count - 1) * stagger + Self.bridgeGrowDuration

        super.init()
        zPosition = Self.layerZPosition

        // The layer is shrunk by `unit` and everything inside is enlarged by
        // it (see the class comment): on screen nothing changes size or place.
        let unit = self.pixelsPerUnit
        setScale(1 / unit)

        // The blur, off until the dissolve starts: no buffer, no filter, the
        // children are drawn straight to the screen. No cached rasterization
        // either — the radius changes every frame.
        blurFilter.radius = 0
        filter = blurFilter
        shouldEnableEffects = false
        shouldRasterize = false

        var bounds = CGRect.null
        for bubble in bubbles {
            bounds = bounds.union(CGRect(
                x: bubble.frame.minX * unit, y: bubble.frame.minY * unit,
                width: bubble.frame.width * unit, height: bubble.frame.height * unit
            ))
            // The layer sits at the origin, so scene positions carry over
            // once converted to its pixel space. The ring goes for the
            // duration: the figure is drawn in one flat color.
            bubble.removeFromParent()
            bubble.position = CGPoint(x: bubble.position.x * unit, y: bubble.position.y * unit)
            bubble.setScale(unit)
            bubble.zPosition = Self.circleZPosition
            bubble.setBorderHidden(true)
            addChild(bubble)
        }

        if !bounds.isNull {
            // The buffer is sized to the children's bounds, and the bubbles
            // touch them; see the class comment.
            let padded = bounds.insetBy(dx: -Self.bufferMargin * unit, dy: -Self.bufferMargin * unit)
            let spacer = SKSpriteNode(color: .clear, size: padded.size)
            spacer.position = CGPoint(x: padded.midX, y: padded.midY)
            addChild(spacer)
        }

        let growth = Self.growth
        for (order, edge) in edges.enumerated() {
            // The bubbles are in pixel space by now, and so is the bridge.
            let from = bubbles[edge.a].position
            let to = bubbles[edge.b].position
            let sprite = SKSpriteNode(texture: growth.frames[0], color: color, size: growth.size)
            sprite.colorBlendFactor = 1
            sprite.position = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            sprite.zRotation = atan2(to.y - from.y, to.x - from.x)
            sprite.setScale(unit)
            sprite.zPosition = Self.bridgeZPosition
            sprite.isHidden = true
            addChild(sprite)
            bridges.append(Bridge(sprite: sprite, start: Double(order) * stagger, shownFrame: -1))
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Wave

    private struct Edge {
        let a: Int
        let b: Int
    }

    /// Every neighbouring pair of the cluster, in the order the wave reaches
    /// it: breadth-first from `startIndex`; a pair gets its number the first
    /// time the traversal reaches either of its ends (so the pairs around the
    /// start bubble go first, then the pairs around its neighbours, ...).
    /// Clusters are connected by the game's own rules; a part that somehow
    /// is not gets a second traversal of its own so no pair is left out.
    private static func waveOrderedEdges(positions: [CGPoint], startIndex: Int) -> [Edge] {
        let count = positions.count
        guard count > 1 else { return [] }
        let limit = CGFloat(GameConsts.bubbleSize) * neighbourDistanceFactor

        var neighbours = [[Int]](repeating: [], count: count)
        for i in 0..<count {
            for j in (i + 1)..<count where hypot(positions[i].x - positions[j].x, positions[i].y - positions[j].y) < limit {
                neighbours[i].append(j)
                neighbours[j].append(i)
            }
        }

        var visited = [Bool](repeating: false, count: count)
        var numbered = Set<Int>() // a * count + b with a < b
        var ordered: [Edge] = []
        var queue: [Int] = []

        func traverse(from root: Int) {
            visited[root] = true
            queue.append(root)
            var head = queue.count - 1
            while head < queue.count {
                let node = queue[head]
                head += 1
                for other in neighbours[node] {
                    let key = min(node, other) * count + max(node, other)
                    if numbered.insert(key).inserted {
                        ordered.append(Edge(a: node, b: other))
                    }
                    if !visited[other] {
                        visited[other] = true
                        queue.append(other)
                    }
                }
            }
        }

        traverse(from: min(max(0, startIndex), count - 1))
        for index in 0..<count where !visited[index] {
            traverse(from: index)
        }
        return ordered
    }

    // MARK: - Warm-up

    private static var isWarm = false

    /// Renders a throwaway layer once, off screen, so the one-time cost of
    /// setting up the blur pipeline — a stall of a few hundred milliseconds on
    /// a cold start, which at the first match of a session would swallow the
    /// whole dissolve — is paid up front instead of in the middle of the first
    /// pop. It must not run before the first frame (the stall would show as a
    /// black screen at launch): the scene schedules it for after the game has
    /// faded in. Runs only once per launch, and not at all if a real dissolve
    /// got there first (`render` sets the flag too). Pass the view the scene
    /// is shown in and its density.
    static func warmUp(in view: SKView, pixelsPerUnit: CGFloat) {
        guard !isWarm else { return }
        isWarm = true

        let layer = BridgeMergeNode(
            bubbles: [BubbleNode(color: .blue)], startIndex: 0, color: .black, pixelsPerUnit: pixelsPerUnit
        )
        // Mid-dissolve: a blur of radius zero is skipped, the real kernels
        // only run once the radius is above it.
        layer.render(at: holdAfterBridges + fadeDuration / 2)
        // `texture(from:)` draws the node tree right away; asking for the
        // image makes sure the work has actually happened by the time we
        // return.
        _ = view.texture(from: layer)?.cgImage()
    }

    // MARK: - Animation

    /// Runs growth, hold and dissolve (all stretched by `timeScale`) as one
    /// action, then calls `completion` — the owner removes the layer there.
    func play(completion: @escaping () -> Void) {
        let scale = Self.timeScale
        let total = (bridgesDoneAt + Self.holdAfterBridges + Self.fadeDuration) * scale
        let animate = SKAction.customAction(withDuration: total) { node, elapsed in
            (node as? BridgeMergeNode)?.render(at: TimeInterval(elapsed) / scale)
        }
        run(SKAction.sequence([animate, SKAction.run(completion)]), withKey: animationKey)
    }

    /// Sets every bridge's growth frame, the figure's tint and the blur for
    /// the moment `time` seconds (before `timeScale`) into the effect.
    private func render(at time: TimeInterval) {
        let top = Self.growth.frames.count - 1
        for index in bridges.indices {
            let progress = CGFloat((time - bridges[index].start) / Self.bridgeGrowDuration)
            let frame = progress <= 0 ? -1 : Int((Self.smooth(progress) * CGFloat(top)).rounded())
            // Frame 0 is the degenerate zero-width bridge: nothing to draw.
            let shown = frame <= 0 ? -1 : frame
            guard shown != bridges[index].shownFrame else { continue }
            bridges[index].shownFrame = shown
            if shown < 0 {
                bridges[index].sprite.isHidden = true
            } else {
                bridges[index].sprite.texture = Self.growth.frames[shown]
                bridges[index].sprite.isHidden = false
            }
        }

        let dissolveStart = bridgesDoneAt + Self.holdAfterBridges
        let dissolve = min(1, max(0, CGFloat((time - dissolveStart) / Self.fadeDuration)))

        // The blur gets ahead of the darkening, so it can be seen. Effects are
        // on from the first frame of the dissolve and not before.
        let radius = Self.maxBlurRadius * Self.easeOut(dissolve)
        if radius != appliedRadius {
            appliedRadius = radius
            blurFilter.radius = Float(radius * pixelsPerUnit)
            shouldEnableEffects = radius > 0
            if radius > 0 { Self.isWarm = true }
        }

        let dark = Self.smooth(dissolve)
        guard dark != appliedDark else { return }
        appliedDark = dark
        let tint = UIColor(red: red * (1 - dark), green: green * (1 - dark), blue: blue * (1 - dark), alpha: 1)
        for bubble in bubbles { bubble.color = tint }
        for bridge in bridges { bridge.sprite.color = tint }
    }

    /// Smoothstep clamped to 0...1: slow start, slow end.
    private static func smooth(_ t: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, t))
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// Quadratic ease-out clamped to 0...1: fast start, slow end.
    private static func easeOut(_ t: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, t))
        return 1 - (1 - clamped) * (1 - clamped)
    }
}
