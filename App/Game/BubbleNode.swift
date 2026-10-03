import SpriteKit
import UIKit
import BubbleShooterCore

/// A smooth-edged circle representing one bubble on screen.
///
/// Spec 34: previously an `SKShapeNode` drawing a vector ellipse path, whose
/// edge came out visibly jagged — SpriteKit's shape-node antialiasing is
/// weak, and the effect is amplified by the scene's fractional scale-down
/// (logical board width 544 rendered at roughly 402pt, ~0.74x). Now a sprite
/// stamped from a shared, oversized white-circle texture and tinted via
/// `color`/`colorBlendFactor`: the texture is rendered with proper
/// antialiasing at a high resolution, and shrinking that smooth edge down to
/// the tiny final display size is what actually produces a clean edge on
/// screen — a hard vector path rasterized directly at that size would not.
final class BubbleNode: SKSpriteNode {
    /// Logical size of every bubble node — unchanged from the previous
    /// shape-node's 30×30 path; only the rendering technique changes.
    private static let logicalSize = CGSize(width: 30, height: 30)

    /// Shared white-circle texture, built lazily once and reused by every
    /// `BubbleNode`. Besides giving a smooth edge, this also removes the
    /// per-frame cost of drawing ~150 individual vector shape fills.
    ///
    /// Rendered at 256×256 — far larger than the ~30pt on-screen size — with
    /// a 2pt inset from the image edges so the antialiased rim isn't clipped
    /// by the image bounds.
    private static let circleTexture: SKTexture = {
        let textureSize: CGFloat = 256
        let inset: CGFloat = 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: textureSize, height: textureSize))
        let image = renderer.image { _ in
            let rect = CGRect(x: inset, y: inset, width: textureSize - inset * 2, height: textureSize - inset * 2)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect).fill()
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        // The 256px source is minified ~4x on screen; without mipmaps a
        // 2x2 linear sample undersamples that reduction and the edge still
        // aliases. Mipmaps give a properly pre-filtered level to sample.
        texture.usesMipmaps = true
        return texture
    }()

    /// Shared white-ring texture for the bubble's border (spec 35). This
    /// can't be baked into `circleTexture`'s fill: the fill is tinted
    /// per-bubble via `color`/`colorBlendFactor = 1`, which would tint a
    /// baked-in ring too and turn a *white* border into a colored one.
    /// Instead this is applied through a separate child sprite whose
    /// `colorBlendFactor = 0` keeps it white regardless of the parent's tint.
    ///
    /// Same 256×256 size and 2pt inset as `circleTexture`, so both share the
    /// same outer radius (126px) — the ring's outer edge lines up exactly
    /// with the fill's outer edge instead of drifting from independently
    /// rounded numbers. Ring thickness is 1/30 of the fill's 252px diameter
    /// (~8.4px), matching the design's "1 unit out of the bubble's 30".
    /// The stroked path radius is set half a line-width *inside* the fill's
    /// outer radius — a stroke straddles its path, so that inset is what
    /// puts the outer edge of the drawn ring (not its path) exactly at the
    /// fill's outer radius.
    private static let ringTexture: SKTexture = {
        let textureSize: CGFloat = 256
        let inset: CGFloat = 2
        let fillRect = CGRect(x: inset, y: inset, width: textureSize - inset * 2, height: textureSize - inset * 2)
        let lineWidth = fillRect.width / 30
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: textureSize, height: textureSize))
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            // Clip to the ring, then fill that band with the design's
            // diagonal gradient. Stroking with a solid color can't express
            // a gradient, and the alpha has to live in the texture's own
            // pixels — a uniform `alpha` on the sprite would scale the whole
            // ramp and flatten it back out.
            let strokeRect = fillRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let ring = UIBezierPath(ovalIn: strokeRect)
            ring.lineWidth = lineWidth
            cg.addPath(ring.cgPath)
            cg.setLineWidth(lineWidth)
            cg.replacePathWithStrokedPath()
            cg.clip()

            // Figma: linear gradient at 45°, white 5% at the bottom-left end
            // to white 15% at the top-right end. These are UIKit drawing
            // coordinates (y grows down), so bottom-left is the larger y.
            let colors = [
                UIColor(white: 1, alpha: 0.05).cgColor,
                UIColor(white: 1, alpha: 0.15).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: inset, y: textureSize - inset),
                end: CGPoint(x: textureSize - inset, y: inset),
                options: []
            )
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        // Same reasoning as `circleTexture`: without mipmaps this thin ring
        // aliases into a broken, dotted line once minified to on-screen size.
        texture.usesMipmaps = true
        return texture
    }()

    /// The border ring child (spec 35), kept so it can be hidden while the
    /// bubble is part of a gooey merge layer (spec 37) — see
    /// `setBorderHidden(_:)`.
    private var borderNode: SKSpriteNode?

    init(color: BubbleColor) {
        super.init(texture: Self.circleTexture, color: .white, size: Self.logicalSize)
        colorBlendFactor = 1
        zPosition = 10

        // Spec 35: thin white border, as a child sprite rather than baked
        // into the fill (see `ringTexture`'s doc comment for why).
        // `colorBlendFactor = 0` keeps it white no matter what
        // `apply(color:)` later does to this node's own `color`; `alpha`
        // is the border's own opacity from the design. Same 30×30 logical
        // size as the fill, centered on the parent's origin, so its ring
        // lines up exactly with the fill's edge; it needs no independent
        // scale/alpha animation of its own because a child sprite's
        // rendering already inherits the parent's scale and alpha for free.
        let border = SKSpriteNode(texture: Self.ringTexture, color: .white, size: Self.logicalSize)
        border.position = .zero
        border.colorBlendFactor = 0
        // Opacity lives per-pixel in the gradient texture (5%…15%), so the
        // sprite itself stays fully opaque; scaling it here would squash
        // the ramp.
        border.alpha = 1
        border.zPosition = 1
        addChild(border)
        borderNode = border

        apply(color: color)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func apply(color: BubbleColor) {
        self.color = Palette.color(for: color)
    }

    /// Spec 37: hides (or shows) the gradient border ring. A bubble that
    /// joins a gooey merge layer loses its ring there — the layer draws the
    /// drop in one flat color, and a blurred ring would only muddy its edge.
    /// Bubbles at rest keep it.
    func setBorderHidden(_ hidden: Bool) {
        borderNode?.isHidden = hidden
    }
}
