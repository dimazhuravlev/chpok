import SpriteKit
import BubbleShooterCore

/// A flat circle representing one bubble on screen.
final class BubbleNode: SKShapeNode {
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
        fillColor = Palette.color(for: color)
    }
}
