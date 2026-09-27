import SpriteKit
import BubbleShooterCore

/// A flat circle representing one bubble on screen.
final class BubbleNode: SKShapeNode {
    /// The slot color currently applied to `fillColor`, kept in sync by
    /// `apply(color:)`. Spec 33: the match-removal flash reads this back to
    /// compute its lightened tint, so it works from the bubble's *actual*
    /// displayed color — which may be a spec-32 user palette customization —
    /// rather than some fixed default.
    private(set) var currentColor: SKColor = .white

    init(color: BubbleColor) {
        super.init()
        path = CGPath(ellipseIn: CGRect(x: -15, y: -15, width: 30, height: 30), transform: nil)
        lineWidth = 0
        strokeColor = .clear
        zPosition = 10
        apply(color: color)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func apply(color: BubbleColor) {
        currentColor = Palette.color(for: color)
        fillColor = currentColor
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
