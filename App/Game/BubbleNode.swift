import SpriteKit
import BubbleShooterCore

/// A flat circle representing one bubble on screen.
final class BubbleNode: SKShapeNode {
    init(color: BubbleColor) {
        super.init()
        path = CGPath(ellipseIn: CGRect(x: -16, y: -16, width: 32, height: 32), transform: nil)
        lineWidth = 1.5
        zPosition = 10
        apply(color: color)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func apply(color: BubbleColor) {
        let fill = Palette.color(for: color)
        fillColor = fill
        strokeColor = fill.darkened(by: 0.25)
    }
}

private extension UIColor {
    /// Returns a copy of the color with each RGB channel scaled down by
    /// `fraction` (e.g. 0.25 = 25% darker), keeping alpha unchanged.
    func darkened(by fraction: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let factor = 1 - fraction
        return UIColor(red: r * factor, green: g * factor, blue: b * factor, alpha: a)
    }
}
