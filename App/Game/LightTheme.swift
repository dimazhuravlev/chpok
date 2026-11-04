import Foundation
import simd

/// Light-theme counterpart of any palette (spec 57). Palettes are authored for
/// the dark theme — colors on black — and the light theme derives its own from
/// them, so every ready-made set and every hand-picked color works in both
/// without a second set of values to maintain.
///
/// The rule, in OKLCH (perceptual lightness, chroma, hue):
/// - Greys and pale tints flip their lightness, the way the background does:
///   white becomes black, a dark grey a light one, cream a deep brown. A tint
///   with a visible hue lands on a deep tone of that hue (`mirrorFloor`) rather
///   than near-black, so pale aqua and pale sand stay apart.
/// - Colorful colors keep their hue and chroma and only lose lightness above
///   `compressFrom` — enough to stand out on white, not so much that they turn
///   muddy.
/// - Yellows read worst on white: they are capped lower (`yellowCap`) and
///   turned slightly toward amber as they darken, so they come out golden
///   instead of olive.
///
/// Inputs and outputs are Display P3 hex values (see `Palette`). Tuned on the
/// ready-made sets so the six colors of each stay about as distinct from each
/// other as they are on black.
enum LightTheme {
    /// Light-theme counterpart of a dark-theme color.
    static func color(for dark: UInt32) -> UInt32 {
        let source = lch(of: dark)
        let target = adapt(source)
        return hex(l: target.l, c: target.c, h: target.h)
    }

    /// The dark-theme color whose light counterpart comes closest to `light`:
    /// what a slot should store when a color is picked while the light theme
    /// is on, so that the light theme shows (almost exactly) the picked color.
    /// A coarse search over lightness, chroma and hue, then a fine pass on
    /// lightness — a millisecond or two, cheap enough for a color picker that
    /// reports continuously.
    static func darkColor(for light: UInt32) -> UInt32 {
        let target = lab(of: light)
        let picked = lch(of: light)
        // Chroma may have been raised up to `1 + mirrorChromaBoost` times and
        // hue turned up to `yellowTurn` degrees toward amber on the way in.
        let chromaScales = [1.0, 1 / 1.25, 1 / (1 + mirrorChromaBoost)]
        let hueOffsets = [0.0, yellowTurn / 3, yellowTurn * 2 / 3, yellowTurn]

        func error(_ candidate: UInt32) -> Double {
            simd_distance(lab(of: color(for: candidate)), target)
        }

        var best = (error: Double.infinity, hex: light, l: picked.l, c: picked.c, h: picked.h)
        for scale in chromaScales {
            for offset in hueOffsets {
                let c = picked.c * scale
                let h = picked.h + offset
                for step in 0...100 {
                    let l = Double(step) / 100
                    let candidate = hex(l: l, c: c, h: h)
                    let e = error(candidate)
                    if e < best.error { best = (e, candidate, l, c, h) }
                }
            }
        }
        let coarse = best
        for step in -10...10 {
            let l = min(1, max(0, coarse.l + Double(step) / 1000))
            let candidate = hex(l: l, c: coarse.c, h: coarse.h)
            let e = error(candidate)
            if e < best.error { best = (e, candidate, l, coarse.c, coarse.h) }
        }
        return best.hex
    }

    // MARK: - The mapping

    /// Chroma below which a color counts as grey (fully grey at `greyUntil`).
    private static let greyUntil = 0.03, colorfulFrom = 0.12
    /// Lightness range over which a not-very-colorful color counts as a pale
    /// tint, and the chroma range over which that stops being "not very".
    private static let paleFrom = 0.82, paleUntil = 0.94
    private static let paleChromaFrom = 0.10, paleChromaUntil = 0.17
    /// Lowest lightness a flipped tint with a visible hue lands on, and the
    /// chroma range over which a hue counts as visible.
    private static let mirrorFloor = 0.38
    private static let hueVisibleFrom = 0.02, hueVisibleUntil = 0.06
    /// How much richer a flipped tint gets (a share of its chroma).
    private static let mirrorChromaBoost = 0.5
    /// Colorful colors keep lightness up to here and a share of the rest.
    private static let compressFrom = 0.50, compressKeep = 0.60
    /// Yellow: hue center, half-width of the hue band, the lightness cap, the
    /// hue it turns toward and by at most how much.
    private static let yellowHue = 88.0, yellowBand = 30.0, yellowCap = 0.72
    private static let amberHue = 74.0, yellowTurn = 12.0

    private struct LCh { var l: Double; var c: Double; var h: Double }

    private static func adapt(_ color: LCh) -> LCh {
        let (l, c, h) = (color.l, color.c, color.h)
        let grey = 1 - smooth(c, greyUntil, colorfulFrom)
        let pale = smooth(l, paleFrom, paleUntil) * (1 - smooth(c, paleChromaFrom, paleChromaUntil))
        let flip = max(grey, pale)

        // Flipped: lightness mirrors; a tinted one lands on a deep tone.
        let hueVisible = smooth(c, hueVisibleFrom, hueVisibleUntil)
        var flippedL = 1 - l
        flippedL += max(0, mirrorFloor - flippedL) * hueVisible
        let flippedC = c * (1 + mirrorChromaBoost * hueVisible)

        // Kept: lightness compressed above `compressFrom`.
        var keptL = l <= compressFrom ? l : compressFrom + compressKeep * (l - compressFrom)
        let distance = min(abs(h - yellowHue), 360 - abs(h - yellowHue))
        let yellowness = 1 - smooth(distance, yellowBand / 2, yellowBand)
        if keptL > yellowCap {
            keptL += (yellowCap - keptL) * yellowness
        }
        var keptH = h
        if h > amberHue {
            let darkened = max(0, l - keptL)
            keptH -= min(yellowTurn * yellowness * min(1, darkened / 0.12), h - amberHue)
        }

        return LCh(
            l: flip * flippedL + (1 - flip) * keptL,
            c: flip * flippedC + (1 - flip) * c,
            h: h + (1 - flip) * (keptH - h)
        )
    }

    private static func smooth(_ x: Double, _ from: Double, _ to: Double) -> Double {
        let t = min(1, max(0, (x - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }

    // MARK: - OKLab in Display P3

    /// Linear Display P3 → XYZ (D65) → OKLab's LMS, and OKLab's second matrix.
    private static let p3ToLMS: simd_double3x3 = {
        let p3ToXYZ = simd_double3x3(rows: [
            SIMD3(0.4865709, 0.2656677, 0.1982173),
            SIMD3(0.2289746, 0.6917385, 0.0792869),
            SIMD3(0.0000000, 0.0451134, 1.0439444)
        ])
        let xyzToLMS = simd_double3x3(rows: [
            SIMD3(0.8189330101, 0.3618667424, -0.1288597137),
            SIMD3(0.0329845436, 0.9293118715, 0.0361456387),
            SIMD3(0.0482003018, 0.2643662691, 0.6338517070)
        ])
        return xyzToLMS * p3ToXYZ
    }()
    private static let lmsToLab = simd_double3x3(rows: [
        SIMD3(0.2104542553, 0.7936177850, -0.0040720468),
        SIMD3(1.9779984951, -2.4285922050, 0.4505937099),
        SIMD3(0.0259040371, 0.7827717662, -0.8086757660)
    ])
    private static let lmsToP3 = p3ToLMS.inverse
    private static let labToLMS = lmsToLab.inverse

    private static func lab(of hex: UInt32) -> SIMD3<Double> {
        func decode(_ byte: UInt32) -> Double {
            let c = Double(byte & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let lms = p3ToLMS * SIMD3(decode(hex >> 16), decode(hex >> 8), decode(hex))
        return lmsToLab * SIMD3(cbrt(lms.x), cbrt(lms.y), cbrt(lms.z))
    }

    private static func lch(of hex: UInt32) -> LCh {
        let lab = lab(of: hex)
        let hue = atan2(lab.z, lab.y) * 180 / .pi
        return LCh(l: lab.x, c: hypot(lab.y, lab.z), h: hue < 0 ? hue + 360 : hue)
    }

    private static func linearP3(l: Double, c: Double, h: Double) -> SIMD3<Double> {
        let radians = h * .pi / 180
        let lms = labToLMS * SIMD3(l, c * cos(radians), c * sin(radians))
        return lmsToP3 * (lms * lms * lms)
    }

    /// The hex for an OKLCH color, with chroma reduced (hue and lightness
    /// kept) until it fits Display P3.
    private static func hex(l: Double, c: Double, h: Double) -> UInt32 {
        func fits(_ rgb: SIMD3<Double>) -> Bool {
            rgb.min() >= -1e-6 && rgb.max() <= 1 + 1e-6
        }
        var rgb = linearP3(l: l, c: c, h: h)
        if !fits(rgb) {
            var low = 0.0, high = c
            for _ in 0..<30 {
                let mid = (low + high) / 2
                if fits(linearP3(l: l, c: mid, h: h)) { low = mid } else { high = mid }
            }
            rgb = linearP3(l: l, c: low, h: h)
        }
        func encode(_ value: Double) -> UInt32 {
            let v = min(1, max(0, value))
            let c = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
            return UInt32((min(1, max(0, c)) * 255).rounded())
        }
        return (encode(rgb.x) << 16) | (encode(rgb.y) << 8) | encode(rgb.z)
    }
}
