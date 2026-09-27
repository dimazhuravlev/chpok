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

    /// The slot color currently applied via `color`/`colorBlendFactor`, kept
    /// in sync by `apply(color:)`. Spec 33: the match-removal flash reads
    /// this back to compute its lightened tint, so it works from the
    /// bubble's *actual* displayed color — which may be a spec-32 user
    /// palette customization — rather than some fixed default.
    private(set) var currentColor: SKColor = .white

    init(color: BubbleColor) {
        super.init(texture: Self.circleTexture, color: .white, size: Self.logicalSize)
        colorBlendFactor = 1
        zPosition = 10
        apply(color: color)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func apply(color: BubbleColor) {
        currentColor = Palette.color(for: color)
        self.color = currentColor
    }
}

extension SKColor {
    /// Blends this color toward white by `fraction` (0 = unchanged, 1 = pure
    /// white). Spec 33: lightening is done by mixing with white rather than
    /// boosting HSB brightness — brightness barely changes the look of some
    /// of the palette's already-saturated colors, while mixing with white
    /// gives a predictable result for any hue.
    func lightened(by fraction: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(
            red: r + (1 - r) * fraction,
            green: g + (1 - g) * fraction,
            blue: b + (1 - b) * fraction,
            alpha: a
        )
    }
}
