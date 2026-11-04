import Foundation

/// A ready-made bubble palette (spec 56): six slot colors (indexed by
/// `BubbleColor.rawValue`) and the background they are meant to sit on.
/// Values are Display P3 coordinates (see `Palette`) for the dark theme; the
/// light theme derives its own from them (see `LightTheme`).
struct PaletteSet: Identifiable, Equatable {
    let id: String
    let name: String
    let family: String
    let background: UInt32
    let colors: [UInt32]

    /// Every set, in display order; `chpok` — the original palette — first.
    /// Mirrors the "Chpok · Palette sets" sheet in Figma.
    static let all: [PaletteSet] = [
        // Current default.
        PaletteSet(
            id: "chpok", name: "Chpok", family: "bright",
            background: 0x000000,
            colors: [0x03C7FB, 0xFF4D66, 0x87BD00, 0xFFB847, 0xB554FF, 0x9D4E21]
        ),
        // Fiberglass shell chair colours: parchment, lemon, red-orange, seafoam, ocean, elephant grey.
        PaletteSet(
            id: "eames-shell", name: "Eames Shell", family: "midcentury",
            background: 0x000000,
            colors: [0xF8F5EB, 0xF2C84B, 0xE2553A, 0x7CC29F, 0x6998C5, 0x8A8274]
        ),
        // Alexander Girard textiles: magenta, saffron, turquoise, lime, coral, violet.
        PaletteSet(
            id: "girard", name: "Girard", family: "midcentury",
            background: 0x000000,
            colors: [0xE2457A, 0xF2A900, 0x2BB3C0, 0xA3C940, 0xE76C47, 0x9C6ADE]
        ),
        // Verner Panton: pink, red, orange, violet, blue, yellow.
        PaletteSet(
            id: "panton", name: "Panton", family: "spaceage",
            background: 0x000000,
            colors: [0xE4979F, 0xFF3B30, 0xFF8A1A, 0x9A1EC7, 0x4FA0FF, 0xF8D54B]
        ),
        // Teenage Engineering OP-1 knobs and pocket-operator yellow.
        PaletteSet(
            id: "op-1", name: "OP-1", family: "tech",
            background: 0x000000,
            colors: [0x2D9CDB, 0x2ECC71, 0xFFFFFF, 0xFF6B1A, 0x8C8C8C, 0xFFD400]
        ),
        // EP-133: greys and one orange accent.
        PaletteSet(
            id: "ko-ii", name: "K.O. II", family: "tech",
            background: 0x000000,
            colors: [0xFF5B1F, 0xFFFFFF, 0x9E9E9E, 0x443A3B, 0xFFB38A, 0x4CC2F0]
        ),
        // Complementary cyan/orange axis with light and dark members.
        PaletteSet(
            id: "teal-orange", name: "Teal & Orange", family: "complementary",
            background: 0x000000,
            colors: [0x2EC4B6, 0xF19A39, 0xC9F1EE, 0xF7CE8F, 0x3D87AE, 0xF25C54]
        ),
        // Moss green, off-white, charcoal, pink, grey, orange.
        PaletteSet(
            id: "tokyo", name: "Tokyo", family: "city",
            background: 0x000000,
            colors: [0x447E22, 0xF2F9EC, 0x484041, 0xEF8692, 0x999999, 0xFF9F1C]
        ),
        // Warm ramp from white through peach, amber and rust to brown.
        PaletteSet(
            id: "amber-mono", name: "Amber", family: "monochrome",
            background: 0x000000,
            colors: [0xFFFFFF, 0xF2AB8F, 0xF4B942, 0xC36027, 0x937D66, 0x503C25]
        ),
        // Marimekko Unikko poppies on black.
        PaletteSet(
            id: "unikko", name: "Unikko", family: "nordic",
            background: 0x000000,
            colors: [0xDA4132, 0xEDA2B2, 0xF28C28, 0x7FC27E, 0x4FA3E0, 0xF2E8D0]
        ),
        // White, signal red, pink, green, grey, dark brown.
        PaletteSet(
            id: "mars", name: "Mars", family: "spaceage",
            background: 0x000000,
            colors: [0xFFFFFF, 0xEA3323, 0xE590AC, 0x447E22, 0x858585, 0x433A36]
        )
    ]

    static let chpok = all[0]
}
