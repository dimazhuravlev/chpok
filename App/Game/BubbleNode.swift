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

    // MARK: - Glass (spec 67)

    /// The glass look of the app icon under iOS 26, on every bubble: lighter
    /// at the top, darker at the bottom, and a thin light rim, brightest at
    /// the top, faint on the sides, a little brighter again at the bottom.
    /// Light comes from straight above. Replaces the faint diagonal ring of
    /// spec 35.
    ///
    /// Body: white over the top half, from `glassHighlight` at the top to
    /// nothing at the middle; black over the bottom half, down to
    /// `glassShadow`. The middle of the bubble keeps its palette color.
    private static let glassHighlight: CGFloat = 0.14
    private static let glassShadow: CGFloat = 0.12
    /// Rim: white at the very edge, at these opacities at the top, on the
    /// sides and at the bottom (blended around by the angle), fading inward
    /// over `glassRimWidth` logical units.
    private static let glassRimTop: CGFloat = 0.6
    private static let glassRimSide: CGFloat = 0.12
    private static let glassRimBottom: CGFloat = 0.28
    private static let glassRimWidth: CGFloat = 1
    /// Blur radius (logical units) by which a blurring bubble has lost its
    /// glass (`fadeGlass(forBlurRadius:)`): a cloud has no rim.
    static let glassFadeBlurRadius: CGFloat = 4

    /// Shared glass overlay. It can't be baked into `circleTexture`: the fill
    /// is tinted per bubble via `color`/`colorBlendFactor = 1`, which only
    /// darkens toward the color and would tint a white highlight too. So it
    /// is a child sprite with `colorBlendFactor = 0`, white and black at
    /// per-pixel opacities, blended over the fill — which brightens the top
    /// and darkens the bottom of any color alike.
    ///
    /// Same 256×256 size and 2 px inset as `circleTexture`, so its edge lies
    /// on the fill's (radius 126 px), antialiased the same way. Computed pixel
    /// by pixel: the rim's opacity changes around the circle, which no
    /// CoreGraphics gradient draws.
    private static let glassTexture: SKTexture = {
        let side = 256
        let center = CGFloat(side) / 2
        let radius = center - 2
        let pixelsPerUnit = 2 * radius / logicalSize.width
        let rimWidth = glassRimWidth * pixelsPerUnit
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for row in 0..<side {
            for column in 0..<side {
                let x = CGFloat(column) + 0.5 - center
                let up = center - (CGFloat(row) + 0.5)
                let distance = (x * x + up * up).squareRoot()
                let coverage = min(1, max(0, radius - distance + 0.5))
                guard coverage > 0 else { continue }

                let height = up / radius
                let bodyShade: CGFloat = height >= 0 ? 1 : 0
                let bodyAlpha = height >= 0 ? glassHighlight * height : glassShadow * -height

                let cosine = up / max(distance, 0.0001)
                let toward = cosine > 0 ? glassRimTop : glassRimBottom
                let rimStrength = glassRimSide + (toward - glassRimSide) * cosine * cosine
                let falloff = max(0, 1 - (radius - distance) / rimWidth)
                let rim = rimStrength * falloff * falloff

                // White rim over the body.
                let alpha = rim + bodyAlpha * (1 - rim)
                let shade = alpha > 0 ? (rim + bodyShade * bodyAlpha * (1 - rim)) / alpha : 0
                let a = alpha * coverage
                let index = (row * side + column) * 4
                let value = UInt8((shade * a * 255).rounded())
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
                pixels[index + 3] = UInt8((a * 255).rounded())
            }
        }
        let image = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
        let texture = image.map { SKTexture(cgImage: $0) } ?? SKTexture()
        texture.filteringMode = .linear
        // Same reasoning as `circleTexture`: without mipmaps the thin rim
        // aliases into a broken, dotted line once minified to on-screen size.
        texture.usesMipmaps = true
        return texture
    }()

    /// The glass child, kept so it can be hidden while the bubble is part of
    /// a bridge merge layer (spec 38) and faded while it blurs (spec 45).
    private var glassNode: SKSpriteNode?

    init(color: BubbleColor) {
        super.init(texture: Self.circleTexture, color: .white, size: Self.logicalSize)
        colorBlendFactor = 1
        zPosition = 10

        // Spec 67: the glass, as a child sprite rather than baked into the
        // fill (see `glassTexture`'s doc comment for why).
        // `colorBlendFactor = 0` keeps it as drawn no matter what
        // `apply(color:)` later does to this node's own `color`. Same 30×30
        // logical size as the fill, centered on the parent's origin, so its
        // edge lines up exactly with the fill's; it needs no independent
        // scale/alpha animation of its own because a child sprite's
        // rendering already inherits the parent's scale and alpha for free.
        // Opacity lives per pixel in the texture, so the sprite itself stays
        // fully opaque.
        let glass = SKSpriteNode(texture: Self.glassTexture, color: .white, size: Self.logicalSize)
        glass.position = .zero
        glass.colorBlendFactor = 0
        glass.zPosition = 1
        addChild(glass)
        glassNode = glass

        apply(color: color)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    /// Uniform scale the bubble is drawn at before any deformation. 1 on the
    /// scene; a bridge merge layer draws its figure at `pixelsPerUnit` times
    /// the size (spec 38) and sets this instead of `setScale`, so a squash
    /// that began on the scene carries on inside the layer (spec 47).
    var baseScale: CGFloat = 1 {
        didSet { applyTransform() }
    }
    private var deformationAngle: CGFloat = 0
    private var deformationStretch: CGFloat = 0

    /// Spec 47: stretches the bubble by `exp(stretch)` along `angle` and
    /// squeezes it by `exp(-stretch)` across, so its area stays the same. A
    /// negative `stretch` squashes it along `angle`. Rest is `(0, 0)`.
    func setDeformation(angle: CGFloat, stretch: CGFloat) {
        deformationAngle = angle
        deformationStretch = stretch
        applyTransform()
    }

    /// The one place the node's transform is written. SpriteKit composes a
    /// node's transform as `R(θ)·S`, and the glass is a child with `R(-θ)`,
    /// so the glass ends up with `R(θ)·S·R(-θ)`: the same stretch along `θ`,
    /// but its light keeps coming from above instead of turning with the
    /// bubble. The fill is a radially symmetric circle, so for it `R(θ)·S`
    /// looks the same as a plain stretch along `θ`.
    private func applyTransform() {
        zRotation = deformationAngle
        xScale = baseScale * exp(deformationStretch)
        yScale = baseScale * exp(-deformationStretch)
        glassNode?.zRotation = -deformationAngle
    }

    func apply(color: BubbleColor) {
        self.color = Palette.color(for: color)
    }

    /// Spec 38: hides (or shows) the glass. A bubble that joins a bridge
    /// merge layer loses it there — the layer draws the figure in one flat
    /// color, which the glass would only muddy. Bubbles at rest keep it.
    func setGlassHidden(_ hidden: Bool) {
        glassNode?.isHidden = hidden
    }

    /// Fades the glass out as the bubble blurs into a cloud (spec 45): whole
    /// while sharp, gone at `glassFadeBlurRadius`.
    func fadeGlass(forBlurRadius radius: CGFloat) {
        glassNode?.alpha = max(0, 1 - radius / Self.glassFadeBlurRadius)
    }
}
