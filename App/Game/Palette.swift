import UIKit
import BubbleShooterCore

/// Flat, minimalist color palette for the whole app (see spec "Минимализм").
/// All values are the exact hex constants from the spec context.
enum Palette {
    /// Case names below (e.g. `lightblue`) are legacy slot identifiers kept for save
    /// compatibility via `rawValue`; the actual displayed color is defined here.
    static func color(for bubbleColor: BubbleColor) -> UIColor {
        switch bubbleColor {
        case .blue: return UIColor(hex: 0x22BDFF)
        case .red: return UIColor(hex: 0xFF4D66)
        case .green: return UIColor(hex: 0x87BD00)
        case .yellow: return UIColor(hex: 0xFFB847)
        case .purple: return UIColor(hex: 0xB554FF)
        case .lightblue: return UIColor(hex: 0xB36321)
        }
    }

    static let background = UIColor(hex: 0x000000)
    static let cannon = UIColor(hex: 0xB8B8C8)
    static let lifeIcon = UIColor(hex: 0x8E8EA8)
    static let text = UIColor(hex: 0xFFFFFF)
    static let overlayCard = UIColor(hex: 0x1C1C1E)
    static let overlayScrim = UIColor(white: 0, alpha: 0.6)
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
