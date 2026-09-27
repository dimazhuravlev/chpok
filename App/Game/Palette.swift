import UIKit
import CoreImage
import BubbleShooterCore

/// Flat, minimalist color palette for the whole app (see spec "Минимализм").
/// Bubble colors are user-customizable (spec 32) — everything else below
/// stays fixed.
enum Palette {
    /// Original six bubble colors, indexed by `BubbleColor.rawValue` — the
    /// starting palette, and what "reset colors" restores. Case names below
    /// (e.g. `lightblue`) are legacy slot identifiers kept for save
    /// compatibility via `rawValue`; the actual displayed color comes from
    /// `PaletteStore`, seeded from this array.
    static let defaultBubbleColors: [UInt32] = [
        0x22BDFF, // blue
        0xFF4D66, // red
        0x87BD00, // green
        0xFFB847, // yellow
        0xB554FF, // purple
        0xB36321  // lightblue
    ]

    /// Current color for a bubble slot. Reads live from `PaletteStore` so
    /// every call site (bubble nodes, the game-over background cycle) picks
    /// up the user's customization immediately without itself changing.
    static func color(for bubbleColor: BubbleColor) -> UIColor {
        PaletteStore.shared.color(for: bubbleColor)
    }

    static let background = UIColor(hex: 0x000000)
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

    /// Opaque `0xRRGGBB` value for this color, ignoring alpha. The system
    /// color picker can hand back a translucent color; a translucent bubble
    /// over the black background would look broken, so every color is
    /// normalized to opaque before it's stored or applied (spec 32). Goes
    /// through `CIColor` rather than `getRed(_:green:blue:alpha:)` because
    /// the latter can fail for colors outside a plain RGB color space, while
    /// `CIColor(color:)` always yields device-RGB components.
    var opaqueHexValue: UInt32 {
        let components = CIColor(color: self)
        func byte(_ value: CGFloat) -> UInt32 {
            UInt32(max(0, min(255, (value * 255).rounded())))
        }
        return (byte(components.red) << 16) | (byte(components.green) << 8) | byte(components.blue)
    }
}
