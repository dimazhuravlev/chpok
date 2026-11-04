import Foundation

/// A ready-made bubble palette (spec 56): six slot colors (indexed by
/// `BubbleColor.rawValue`) and the background they are meant to sit on.
struct PaletteSet: Identifiable, Equatable {
    let id: String
    let name: String
    let family: String
    let isLight: Bool
    let background: UInt32
    let colors: [UInt32]

    /// Every set, in display order; `chpok` — the original palette — first.
    static let all: [PaletteSet] = [
        // Current default.
        PaletteSet(
            id: "chpok", name: "Chpok", family: "bright", isLight: false,
            background: 0x000000,
            colors: [0x03C7FB, 0xFF4D66, 0x87BD00, 0xFFB847, 0xB554FF, 0x9D4E21]
        ),
        // Eames Hang-It-All ball colours, lifted for black.
        PaletteSet(
            id: "hang-it-all", name: "Hang-It-All", family: "midcentury", isLight: false,
            background: 0x000000,
            colors: [0xE8553E, 0xF28C28, 0xF5D547, 0x5DBB63, 0x5FA8E8, 0xC77DD4]
        ),
        // Fiberglass shell chair colours: parchment, lemon, red-orange, seafoam, ocean, elephant grey.
        PaletteSet(
            id: "eames-shell", name: "Eames Shell", family: "midcentury", isLight: false,
            background: 0x000000,
            colors: [0xF2E8D0, 0xF2C84B, 0xE2553A, 0x8CC7B3, 0x6AA0C8, 0xA39E93]
        ),
        // Alexander Girard textiles: magenta, saffron, turquoise, lime, coral, violet.
        PaletteSet(
            id: "girard", name: "Girard", family: "midcentury", isLight: false,
            background: 0x000000,
            colors: [0xE2457A, 0xF2A900, 0x2BB3C0, 0xA3C940, 0xF07A5A, 0x9C6ADE]
        ),
        // Verner Panton's hot analogous ramps from pink through red, orange and violet.
        PaletteSet(
            id: "panton", name: "Panton", family: "spaceage", isLight: false,
            background: 0x000000,
            colors: [0xFF4F9A, 0xFF3B30, 0xFF8A1A, 0xD63AF9, 0x4FA0FF, 0xFFC400]
        ),
        // Sottsass/Memphis candy primaries.
        PaletteSet(
            id: "memphis", name: "Memphis", family: "modernism", isLight: false,
            background: 0x000000,
            colors: [0xFF5C8A, 0x4FA3E0, 0xFFC21A, 0x4CC38A, 0xB79CED, 0xFF8C61]
        ),
        // Dieter Rams: warm greys with ET66 accent buttons.
        PaletteSet(
            id: "braun", name: "Braun", family: "modernism", isLight: false,
            background: 0x000000,
            colors: [0xF2F0EB, 0xA6A39C, 0x707070, 0xF26B1D, 0xF2C230, 0x6FAF5F]
        ),
        // Teenage Engineering OP-1 knobs and pocket-operator yellow.
        PaletteSet(
            id: "op-1", name: "OP-1", family: "tech", isLight: false,
            background: 0x000000,
            colors: [0x2D9CDB, 0x2ECC71, 0xF5F5F5, 0xFF6B1A, 0xA9A9A9, 0xFFD400]
        ),
        // EP-133: greys and one orange accent.
        PaletteSet(
            id: "ko-ii", name: "K.O. II", family: "tech", isLight: false,
            background: 0x000000,
            colors: [0xFF5B1F, 0xF2F2F2, 0xADADAD, 0x6E6E6E, 0xFFB38A, 0x4CC2F0]
        ),
        // Saturated neon on black, hues 60 degrees apart.
        PaletteSet(
            id: "neon", name: "Neon", family: "bright", isLight: false,
            background: 0x000000,
            colors: [0xFF2E88, 0x00F5D4, 0xF9F871, 0x7B61FF, 0xFF9F1C, 0x4DA3FF]
        ),
        // Complementary cyan/orange axis with light and dark members.
        PaletteSet(
            id: "teal-orange", name: "Teal & Orange", family: "complementary", isLight: false,
            background: 0x000000,
            colors: [0x2EC4B6, 0xFF9F1C, 0xCBF3F0, 0xFFE0B5, 0x118AB2, 0xF25C54]
        ),
        // Pastels on black, 60 degree hue steps.
        PaletteSet(
            id: "sorbet", name: "Sorbet", family: "pastel", isLight: false,
            background: 0x000000,
            colors: [0xF8A49D, 0xFFD08A, 0xD5F1A7, 0x9FEDDD, 0x9CBFF8, 0xE0AAF2]
        ),
        // Moss, lichen, bark, mushroom, berry, pond.
        PaletteSet(
            id: "forest", name: "Forest", family: "natural", isLight: false,
            background: 0x000000,
            colors: [0x8DB255, 0xE6EBCF, 0xA0785A, 0xC75B7A, 0x5FA3A0, 0xF2C14E]
        ),
        // Terracotta, sand, sage, sun, dusk lilac, clay.
        PaletteSet(
            id: "desert", name: "Desert", family: "natural", isLight: false,
            background: 0x000000,
            colors: [0xD9734E, 0xF5E6CC, 0xA3B18A, 0xF2B33D, 0xB39BC8, 0x8C5A44]
        ),
        // Coral, reef teal, lagoon, deep water, sand, kelp.
        PaletteSet(
            id: "reef", name: "Reef", family: "natural", isLight: false,
            background: 0x000000,
            colors: [0xFF7F6E, 0x2EC4B6, 0x7FD8F0, 0x4A8FE0, 0xF2DDB0, 0x8FBF5A]
        ),
        // Maple, pumpkin, mustard, olive, plum, oak.
        PaletteSet(
            id: "autumn", name: "Autumn", family: "natural", isLight: false,
            background: 0x000000,
            colors: [0xE4572E, 0xF28C38, 0xE3C23C, 0x9AA145, 0xA85C87, 0xF5E9D3]
        ),
        // Japanese traditional: sakura, kurenai, yamabuki, wakatake, ruri, fuji.
        PaletteSet(
            id: "nippon", name: "Nippon", family: "natural", isLight: false,
            background: 0x000000,
            colors: [0xF7B6C2, 0xE8414E, 0xFFB11B, 0x5DAC81, 0x4D8BE0, 0xA99BD9]
        ),
        // Lemon, lime, orange, grapefruit, mint, peach.
        PaletteSet(
            id: "citrus", name: "Citrus", family: "bright", isLight: false,
            background: 0x000000,
            colors: [0xFFE64E, 0xB3E635, 0xFE8B29, 0xFF5E7A, 0x6FE3B0, 0xFFC8A2]
        ),
        // Ice, frost, fjord, slate, aurora, twilight.
        PaletteSet(
            id: "nordic", name: "Nordic", family: "nordic", isLight: false,
            background: 0x000000,
            colors: [0xE8F1F5, 0x9CC3DB, 0x5F8FC0, 0x7FD6A8, 0xC4A6E0, 0xF2C6A0]
        ),
        // One hue family: blues from ice to violet-blue, with a grey and a cyan.
        PaletteSet(
            id: "blue-mono", name: "Blue", family: "monochrome", isLight: false,
            background: 0x000000,
            colors: [0xE3EEFF, 0x8FB8F5, 0x3F72E0, 0x45D4F5, 0x3FD6A8, 0xC2A3F7]
        ),
        // Warm one-hue ramp with tan and brown.
        PaletteSet(
            id: "amber-mono", name: "Amber", family: "monochrome", isLight: false,
            background: 0x000000,
            colors: [0xFFF1D6, 0xFFD27A, 0xFF9F1C, 0xD96A1F, 0xC9A27E, 0x8F6A45]
        ),
        // Artek Stool 60 colours with birch.
        PaletteSet(
            id: "aalto", name: "Aalto", family: "nordic", isLight: false,
            background: 0x000000,
            colors: [0xE8D3A9, 0xD94A4A, 0xF2C230, 0x5C8FD6, 0x6FAF7A, 0xF59AB0]
        ),
        // Marimekko Unikko poppies on black.
        PaletteSet(
            id: "unikko", name: "Unikko", family: "nordic", isLight: false,
            background: 0x000000,
            colors: [0xE5342B, 0xF5A3B5, 0xF28C28, 0x5BBF6A, 0x4FA3E0, 0xF2E8D0]
        ),
        // Space-age silver, white and signal colours.
        PaletteSet(
            id: "moonbase", name: "Moonbase", family: "spaceage", isLight: false,
            background: 0x000000,
            colors: [0x9AA3AE, 0xFF6F00, 0xF4F4F4, 0x33C3C3, 0xFF3D3D, 0xFFD23F]
        ),
        // Ruby, emerald, sapphire, amethyst, topaz, aquamarine.
        PaletteSet(
            id: "gems", name: "Gems", family: "natural", isLight: false,
            background: 0x000000,
            colors: [0xF0346E, 0x2ECC71, 0x4C8DF6, 0xB57EDC, 0xFFC845, 0x7FFFD4]
        ),
        // Eames palette on warm paper: red-orange, ochre, teal, olive, navy, plum.
        PaletteSet(
            id: "paper-eames", name: "Eames Paper", family: "midcentury", isLight: true,
            background: 0xF3EEE3,
            colors: [0xC8442B, 0x9A6B12, 0x1F7A7A, 0x6B7A2A, 0x2B3A67, 0x7A3B69]
        ),
        // Primaries on white with black and grey.
        PaletteSet(
            id: "bauhaus-white", name: "Bauhaus White", family: "modernism", isLight: true,
            background: 0xFFFFFF,
            colors: [0xE03C31, 0x1F4FB8, 0xB07D00, 0x222222, 0x7A7A7A, 0x2E8B57]
        ),
        // Teenage Engineering accents on light grey.
        PaletteSet(
            id: "te-grey", name: "TE Grey", family: "tech", isLight: true,
            background: 0xEDEDED,
            colors: [0x1F6FD1, 0xD2501A, 0x1E8F52, 0x1A1A1A, 0x707070, 0xC62877]
        ),
        // Girard on white.
        PaletteSet(
            id: "girard-white", name: "Girard White", family: "midcentury", isLight: true,
            background: 0xFFFFFF,
            colors: [0xC2185B, 0x00838F, 0xA86F00, 0x5E7F1E, 0xD9534F, 0x6A4C9C]
        ),
        // Moss, pine, bark, berry, slate, ochre on cream.
        PaletteSet(
            id: "forest-cream", name: "Forest Cream", family: "natural", isLight: true,
            background: 0xF5F0E6,
            colors: [0x5B7F2B, 0x2F5D50, 0x7A4E2D, 0x9C2F5A, 0x3E5C8A, 0xA0701A]
        ),
        // International style red/black plus signal colours.
        PaletteSet(
            id: "swiss", name: "Swiss", family: "modernism", isLight: true,
            background: 0xFFFFFF,
            colors: [0xE30613, 0x111111, 0x0055A4, 0x8A8A8A, 0x7A2E8E, 0x00897B]
        ),
        // Artek colours on birch.
        PaletteSet(
            id: "aalto-birch", name: "Aalto Birch", family: "nordic", isLight: true,
            background: 0xF2E9D8,
            colors: [0xB53A2E, 0x2F5E9E, 0x3E7D52, 0x2A2A2A, 0x8C6A12, 0x2A7A80]
        ),
        // Japanese traditional colours on washi paper.
        PaletteSet(
            id: "washi", name: "Washi", family: "natural", isLight: true,
            background: 0xF7F3EA,
            colors: [0xC3272B, 0x1E50A2, 0x3A7F55, 0x7058A3, 0x9E6B00, 0x3A3A3A]
        )
    ]

    static let chpok = all[0]
}
