import UIKit
import BubbleShooterCore

/// Flat, minimalist color palette for the whole app (see spec "Минимализм").
/// All values are the exact hex constants from the spec context.
enum Palette {
    static func color(for bubbleColor: BubbleColor) -> UIColor {
        switch bubbleColor {
        case .blue: return UIColor(hex: 0x3B7DFF)
        case .red: return UIColor(hex: 0xF0443C)
        case .green: return UIColor(hex: 0x3CC45A)
        case .yellow: return UIColor(hex: 0xFFD338)
        case .purple: return UIColor(hex: 0xA45DE8)
        case .lightblue: return UIColor(hex: 0x63D2F5)
        }
    }

    static let background = UIColor(hex: 0xE9E6F7)
    static let cannon = UIColor(hex: 0x4A4A6A)
    static let lifeIcon = UIColor(hex: 0x8E8EA8)
    static let text = UIColor(hex: 0x22223A)
}

extension UIColor {
    /// Builds an opaque color from a `0xRRGGBB` literal.
    convenience init(hex: UInt32) {
        let r = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hex & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(hex & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
