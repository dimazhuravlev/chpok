import CoreImage.CIFilterBuiltins
import SpriteKit
import UIKit

/// The metaball ("gooey") effect that plays when a cluster of three or more
/// bubbles matches (spec 37): the bubbles melt into one drop, then the drop
/// contracts to a point and disappears. It replaces the old pop flash.
///
/// Technique: blur, then threshold. `SKEffectNode` takes a single filter, so
/// the effect is two nested nodes. This node is the *outer* one; its filter
/// (`GooThresholdFilter`) thresholds whatever its child draws. The child
/// (`blurNode`) is the *inner* one and applies a `CIGaussianBlur` to the
/// cluster's bubble nodes, which are its children. Blur smears every bubble
/// into a soft cloud; the threshold — a steep ramp on the cloud's alpha —
/// turns the cloud's 50% contour back into a hard edge, and wherever two
/// clouds overlap their summed alpha crosses that level in the gap between
/// them: that is the bridge between neighbouring bubbles.
///
/// The threshold never lets the blurred image's colors through: every
/// surviving pixel is exactly the cluster color, and only alpha comes from
/// the blur. That avoids the dark fringe this trick normally leaves, where an
/// edge pixel's color has been diluted with the transparent black around it.
/// It only works because a cluster is always a single color — which is also
/// the game's own rule.
///
/// The bubbles already sit almost touching on the grid (a 2-unit gap), so a
/// constant blur would fuse them on the very first frame and there would be
/// nothing to watch. The merge is therefore animated by growing the blur
/// radius from zero — at zero, blur plus threshold just draws ordinary
/// circles, and the bridges pull out as the radius grows — with a drift
/// toward the cluster's center as the second ingredient.
///
/// Add the node to the scene at the origin: the bubble nodes are re-parented
/// into it and keep their scene positions (see `init` for the scale the node
/// applies to itself internally).
final class GooMergeNode: SKEffectNode {
    // MARK: - Tuning (spec 37)
    //
    // Every number of the effect lives here, side by side, so it can be
    // re-tuned with a single edit. Distances are in the scene's logical units
    // (a bubble is 30 across), durations in seconds.

    /// First phase: the blur radius grows from 0 to `maxBlurRadius` and the
    /// bubbles drift `mergePull` of the way to the cluster's center, both
    /// eased in and out. The bubbles melt together.
    static let mergeDuration: TimeInterval = 0.18
    /// Second phase: the bubbles keep converging on the center and scale down
    /// to zero, so the fused drop is pulled into a point.
    static let vanishDuration: TimeInterval = 0.14
    /// Blur radius reached at the end of the merge phase, in logical units.
    static let maxBlurRadius: CGFloat = 7
    /// Share of the distance to the cluster's center covered by the end of
    /// the merge phase (the vanish phase covers the rest).
    static let mergePull: CGFloat = 0.35
    /// Alpha level `t` of the blurred image that becomes the drop's edge:
    /// the threshold's output alpha is `k·a − k·t`, clamped to 0…1.
    static let thresholdLevel: CGFloat = 0.5
    /// Steepness `k` of that alpha ramp. Lower is a softer edge, higher a
    /// sharper one — but a very high value shows stair-stepping.
    static let thresholdSlope: CGFloat = 12
    /// `zPosition` of the layer: above the bubbles at rest (10), so the drop
    /// is drawn over the neighbours it leaves behind.
    static let layerZPosition: CGFloat = 20
    /// Empty space kept around the cluster inside the effect's buffer, in
    /// logical units, so the blur never runs into the buffer's edge (see
    /// `init`). Must comfortably exceed `maxBlurRadius`.
    static let bufferMargin: CGFloat = 32

    /// Debug launch argument that slows the whole effect down by
    /// `slowMotionFactor`, so it can be looked at frame by frame and tuned.
    /// Stays in the code, like `-showGameOverDemo`.
    static let slowMotionArgument = "-slowMotionGoo"
    static let slowMotionFactor: TimeInterval = 8
    /// Time multiplier applied to both phases: `slowMotionFactor` when the
    /// debug argument is present, otherwise 1.
    static let timeScale: TimeInterval = CommandLine.arguments.contains(slowMotionArgument) ? slowMotionFactor : 1

    // MARK: - State

    /// Inner effect node: blurs the bubbles.
    private let blurNode = SKEffectNode()
    private let blurFilter = CIFilter.gaussianBlur()

    private struct Member {
        let node: BubbleNode
        /// Where the bubble stood when the merge began, in the layer's own
        /// pixel space (`pixelsPerUnit` times its scene position).
        let start: CGPoint
    }
    private var members: [Member] = []
    /// Centroid of the members' start positions, in the layer's pixel space.
    private var center: CGPoint = .zero
    /// Device pixels per logical unit. See `init`.
    private let pixelsPerUnit: CGFloat

    private let animationKey = "gooMerge"

    /// Takes over `bubbles` — the nodes of one matched cluster, all of one
    /// color, at their final scene positions — re-parenting them into the
    /// effect and drawing them as one drop of `color`. `pixelsPerUnit` is the
    /// density the scene is shown at (device pixels per logical unit).
    init(bubbles: [BubbleNode], color: UIColor, pixelsPerUnit: CGFloat) {
        self.pixelsPerUnit = max(1, pixelsPerUnit)
        super.init()
        zPosition = Self.layerZPosition
        // An effect node renders its children into a buffer at one pixel per
        // *local* unit, then draws that buffer scaled like any other node —
        // so at the scene's own scale (a few device pixels per logical unit)
        // the drop would be rendered small and stretched up, soft at the edge
        // (measured at the start of the effect: a 10–90% edge transition of
        // ~1.6 px, against ~0.9 px for a bubble at rest). Instead the layer
        // is shrunk by `pixelsPerUnit` and everything inside is enlarged by
        // the same factor — positions, bubble scale, blur radius, margin — so
        // the buffer holds one pixel per device pixel while the drop's size
        // on screen is unchanged (edge transition ~1.2 px).
        setScale(1 / self.pixelsPerUnit)

        // Outer node: the threshold, tinted with the cluster color.
        filter = GooThresholdFilter(color: color, level: Self.thresholdLevel, slope: Self.thresholdSlope)
        shouldEnableEffects = true
        // No cached rasterization on either node: the blur radius changes
        // every frame, so the filters must be re-run every frame.
        shouldRasterize = false

        // Inner node: the blur, starting at radius 0 (plain circles).
        blurFilter.radius = 0
        blurNode.filter = blurFilter
        blurNode.shouldEnableEffects = true
        blurNode.shouldRasterize = false
        addChild(blurNode)

        let unit = self.pixelsPerUnit
        var sum = CGPoint.zero
        var bounds = CGRect.null
        for bubble in bubbles {
            let start = CGPoint(x: bubble.position.x * unit, y: bubble.position.y * unit)
            sum.x += start.x
            sum.y += start.y
            bounds = bounds.union(CGRect(
                x: bubble.frame.minX * unit, y: bubble.frame.minY * unit,
                width: bubble.frame.width * unit, height: bubble.frame.height * unit
            ))
            members.append(Member(node: bubble, start: start))
            // The layer sits at the origin, so positions survive the move once
            // converted to its pixel space. The ring goes: a blurred ring
            // would only muddy the drop's edge.
            bubble.removeFromParent()
            bubble.position = start
            bubble.setScale(unit)
            bubble.setBorderHidden(true)
            blurNode.addChild(bubble)
        }
        if !bubbles.isEmpty {
            center = CGPoint(x: sum.x / CGFloat(bubbles.count), y: sum.y / CGFloat(bubbles.count))

            // An effect node renders into a buffer sized to its children's
            // bounds, and the bubbles touch those bounds. Blur against the
            // buffer's edge flattens the drop there (a straight, squared-off
            // top and sides). A transparent sprite, larger than the cluster
            // by `bufferMargin` all around, keeps the edge out of reach.
            let padded = bounds.insetBy(dx: -Self.bufferMargin * unit, dy: -Self.bufferMargin * unit)
            let spacer = SKSpriteNode(color: .clear, size: padded.size)
            spacer.position = CGPoint(x: padded.midX, y: padded.midY)
            blurNode.addChild(spacer)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Warm-up

    private static var isWarm = false

    /// Renders a throwaway layer once, off screen, so the one-time cost of
    /// setting up the filter pipeline — a frame hitch of a few hundred
    /// milliseconds on a cold start, which at the first match of a session
    /// would swallow most of the 0.32 s effect — is paid up front, while the
    /// game is still fading in, instead of in the middle of the first pop.
    /// Runs only once per launch; pass the view the scene is shown in.
    static func warmUp(in view: SKView) {
        guard !isWarm else { return }
        isWarm = true

        let layer = GooMergeNode(bubbles: [BubbleNode(color: .blue)], color: .black, pixelsPerUnit: 1)
        // Mid-merge: the blur radius must be non-zero, since a blur of zero
        // is skipped and the real kernels only run once it grows.
        let merge = mergeDuration * timeScale
        layer.render(elapsed: merge / 2, merge: merge, vanish: vanishDuration * timeScale)
        // `texture(from:)` draws the node tree right away; asking for the
        // image makes sure the work has actually happened by the time we
        // return.
        _ = view.texture(from: layer)?.cgImage()
    }

    // MARK: - Animation

    /// Runs the merge and vanish phases (stretched by `timeScale`) as one
    /// action, then calls `completion` — the owner removes the layer there.
    func play(completion: @escaping () -> Void) {
        let merge = Self.mergeDuration * Self.timeScale
        let vanish = Self.vanishDuration * Self.timeScale
        let animate = SKAction.customAction(withDuration: merge + vanish) { node, elapsed in
            (node as? GooMergeNode)?.render(elapsed: TimeInterval(elapsed), merge: merge, vanish: vanish)
        }
        run(SKAction.sequence([animate, SKAction.run(completion)]), withKey: animationKey)
    }

    /// Sets the blur radius and every bubble's position/scale for the moment
    /// `elapsed` seconds into the effect.
    private func render(elapsed: TimeInterval, merge: TimeInterval, vanish: TimeInterval) {
        let radius: CGFloat
        let pull: CGFloat
        let scale: CGFloat
        if elapsed < merge {
            let progress = Self.easeInOut(CGFloat(elapsed / merge))
            radius = Self.maxBlurRadius * progress
            pull = Self.mergePull * progress
            scale = 1
        } else {
            let progress = Self.easeInOut(CGFloat(min(1, (elapsed - merge) / vanish)))
            radius = Self.maxBlurRadius
            pull = Self.mergePull + (1 - Self.mergePull) * progress
            // Never exactly zero: an empty frame would leave the effect
            // nodes with nothing to render into.
            scale = max(0.001, 1 - progress)
        }

        blurFilter.radius = Float(radius * pixelsPerUnit)
        for member in members {
            member.node.position = CGPoint(
                x: member.start.x + (center.x - member.start.x) * pull,
                y: member.start.y + (center.y - member.start.y) * pull
            )
            member.node.setScale(scale * pixelsPerUnit)
        }
    }

    /// Smoothstep: slow start, slow end.
    private static func easeInOut(_ t: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, t))
        return clamped * clamped * (3 - 2 * clamped)
    }
}

/// The threshold step of the effect: turns the blurred alpha `a` into a solid
/// `color` with alpha `k·a − k·t`, clamped to 0…1.
///
/// Two `CIColorMatrix` stages with a clamp in between:
/// 1. the alpha ramp — R, G, B vectors zero, alpha `k·a − k·t`;
/// 2. `CIColorClamp` to 0…1;
/// 3. the tint — R, G, B vectors zero, the cluster color in the bias, alpha
///    passed through.
///
/// So the output's RGB is the cluster color whatever the blurred image held —
/// no dark fringe from edge pixels diluted with the transparent black around
/// them. The clamp must sit between the two matrices, not after one: a lone
/// `CIColorMatrix` premultiplies its result by the *unclamped* alpha (up to
/// `k·(1 − t)` = 6 inside the drop), so every color channel overshoots and the
/// whole drop comes out white, with a faintly colored rim only where alpha is
/// still small.
///
/// The crop at the end is why this is a `CIFilter` subclass and not a bare
/// matrix on the effect node. With a non-zero alpha bias Core Image reports an
/// *infinite* output extent (it never evaluates the clamp that keeps
/// transparent input transparent), and `SKEffectNode` then tries to allocate a
/// texture of that size and crashes inside Metal. The result is transparent
/// outside the input anyway, so cropping changes nothing visible.
private final class GooThresholdFilter: CIFilter {
    /// Set by `SKEffectNode` with the rendered (blurred) content.
    @objc dynamic var inputImage: CIImage?
    private let ramp = CIFilter.colorMatrix()
    private let clamp = CIFilter.colorClamp()
    private let tint = CIFilter.colorMatrix()

    init(color: UIColor, level: CGFloat, slope: CGFloat) {
        super.init()
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)

        ramp.rVector = zero
        ramp.gVector = zero
        ramp.bVector = zero
        ramp.aVector = CIVector(x: 0, y: 0, z: 0, w: slope)
        ramp.biasVector = CIVector(x: 0, y: 0, z: 0, w: -slope * level)

        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        tint.rVector = zero
        tint.gVector = zero
        tint.bVector = zero
        tint.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        tint.biasVector = CIVector(x: red, y: green, z: blue, w: 0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var outputImage: CIImage? {
        guard let input = inputImage else { return nil }
        ramp.inputImage = input
        clamp.inputImage = ramp.outputImage
        tint.inputImage = clamp.outputImage
        return tint.outputImage?.cropped(to: input.extent)
    }
}
