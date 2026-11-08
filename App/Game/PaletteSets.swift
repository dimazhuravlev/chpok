import Foundation

/// A ready-made bubble palette (spec 56): six slot colors, indexed by
/// `BubbleColor.rawValue`. Values are Display P3 coordinates (see `Palette`),
/// authored for a black background; other backgrounds derive their own from
/// them (`BackgroundAdaptation`, spec 64).
struct PaletteSet: Identifiable, Equatable {
    let id: String
    let name: String
    let family: String
    let colors: [UInt32]
    /// The set's app icon (spec 66): a circle of one of its colors on
    /// another, drawn by `scripts/make-app-icon.py` for the home screen and
    /// by `AppIconView` in the sets sheet. Picked so the circle reads at a
    /// glance and the pair says something about the set, and so no two
    /// icons look alike; a red circle on white stays out (a flag, not a
    /// bubble).
    let icon: IconColors

    /// Indices into `colors`.
    struct IconColors: Equatable {
        let background: Int
        let circle: Int
    }

    /// Every set, in display order, the default first. Mirrors the "Palette
    /// sets sheet" in Figma. The order also decides the app icons
    /// (`scripts/make-app-icon.py`): the first set's is the primary one.
    static let all: [PaletteSet] = [
        // Verner Panton: pink, red, orange, violet, blue, yellow.
        PaletteSet(
            id: "panton", name: "Panton", family: "spaceage",
            colors: [0xE4979F, 0xFF3B30, 0xFF8A1A, 0x9A1EC7, 0x4FA0FF, 0xF8D54B],
            // Pink on violet.
            icon: .init(background: 3, circle: 0)
        ),
        // Alexander Girard textiles: magenta, saffron, turquoise, lime, coral, violet.
        PaletteSet(
            id: "girard", name: "Girard", family: "midcentury",
            colors: [0xE2457A, 0xF2A900, 0x2BB3C0, 0xA3C940, 0xE76C47, 0x9C6ADE],
            // Saffron on magenta.
            icon: .init(background: 0, circle: 1)
        ),
        // The original palette.
        PaletteSet(
            id: "chpok", name: "Chpok", family: "bright",
            colors: [0x03C7FB, 0xFF4D66, 0x87BD00, 0xFFB847, 0xB554FF, 0x9D4E21],
            // Light blue on brown, the original icon.
            icon: .init(background: 5, circle: 0)
        ),
        // Marimekko Unikko poppies on black.
        PaletteSet(
            id: "unikko", name: "Unikko", family: "nordic",
            colors: [0xDA4132, 0xEDA2B2, 0xF28C28, 0x7FC27E, 0x4FA3E0, 0xF2E8D0],
            // Red poppy on pink.
            icon: .init(background: 1, circle: 0)
        ),
        // Fiberglass shell chair colours: parchment, lemon, red-orange, seafoam, ocean, elephant grey.
        PaletteSet(
            id: "eames-shell", name: "Eames Shell", family: "midcentury",
            colors: [0xF8F5EB, 0xF2C84B, 0xE2553A, 0x7CC29F, 0x6998C5, 0x8A8274],
            // Lemon on ocean.
            icon: .init(background: 4, circle: 1)
        ),
        // Teenage Engineering OP-1 knobs and pocket-operator yellow.
        PaletteSet(
            id: "op-1", name: "OP-1", family: "tech",
            colors: [0x2D9CDB, 0x2ECC71, 0xFFFFFF, 0xFF6B1A, 0x8C8C8C, 0xFFD400],
            // The blue knob on the white panel.
            icon: .init(background: 2, circle: 0)
        ),
        // EP-133: greys and one orange accent.
        PaletteSet(
            id: "ko-ii", name: "K.O. II", family: "tech",
            colors: [0xFF5B1F, 0xFFFFFF, 0x9E9E9E, 0x443A3B, 0xFFB38A, 0x4CC2F0],
            // White on orange.
            icon: .init(background: 0, circle: 1)
        ),
        // Complementary cyan/orange axis with light and dark members.
        PaletteSet(
            id: "teal-orange", name: "Teal & Orange", family: "complementary",
            colors: [0x2EC4B6, 0xF19A39, 0xC9F1EE, 0xF7CE8F, 0x3D87AE, 0xF25C54],
            // Orange on blue.
            icon: .init(background: 4, circle: 1)
        ),
        // Moss green, off-white, charcoal, pink, grey, orange.
        PaletteSet(
            id: "tokyo", name: "Tokyo", family: "city",
            colors: [0x447E22, 0xF2F9EC, 0x484041, 0xEF8692, 0x999999, 0xFF9F1C],
            // Pink on moss.
            icon: .init(background: 0, circle: 3)
        ),
        // White, signal red, pink, green, grey, dark brown.
        PaletteSet(
            id: "mars", name: "Mars", family: "spaceage",
            colors: [0xFFFFFF, 0xEA3323, 0xE590AC, 0x447E22, 0x858585, 0x433A36],
            // The red planet in dark space.
            icon: .init(background: 5, circle: 1)
        ),
        // Warm ramp from white through peach, amber and rust to brown.
        PaletteSet(
            id: "amber-mono", name: "Amber", family: "monochrome",
            colors: [0xFFFFFF, 0xF2AB8F, 0xF4B942, 0xC36027, 0x937D66, 0x503C25],
            // Amber on dark brown.
            icon: .init(background: 5, circle: 2)
        )
    ]

    /// The default set — the first one: what a new install starts with and
    /// "reset colors" restores, and the primary app icon.
    static let `default` = all[0]
}
