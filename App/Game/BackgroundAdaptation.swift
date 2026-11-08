import Foundation
import simd

/// Bubble colors for any background between black and white (spec 64).
///
/// The background is a neutral grey picked on a slider, given as its OKLab
/// lightness: 0 is black, 1 is white. Every palette is authored for black, and
/// this type derives what its colors become on any other grey — so every
/// ready-made set and every hand-picked color works on every background
/// without a second set of values. On black a palette comes out exactly as
/// authored.
///
/// The model, in OKLCH (perceptual lightness, chroma, hue):
/// - Each color has its own self and a counterpart it takes once the
///   background is lighter than it. For colorful colors and greys up to about
///   0.7 the two are the same color. Whites and pale tints mirror their
///   lightness instead: white becomes black (`ink`), a pale tint a deep tone
///   of its hue (`mirrorFloor`).
/// - Colorful colors keep hue and chroma and only drift darker as the
///   background lightens — above `compressFrom`, so they stand out on white
///   without turning muddy; yellows further, down to `yellowCap`, turning
///   toward amber so they come out golden, not olive. They cross the
///   background's lightness continuously: their chroma carries them there,
///   raised up to `boost` times while they sit close to it.
/// - Greys and faint tints would vanish at the crossing, so they keep
///   `margin` of lightness from the background and switch sides at one point:
///   their own crossing for darker ones, `polarityFlip` for whites and pale
///   tints, a little later (`lateFlip`) for light greys, and in any case
///   before the room above the background runs out. The same `polarityFlip`
///   turns the interface text from white to black (`isLight`).
/// - The six lightnesses are then solved together: colors that differ mostly
///   in lightness (greys, a monochrome ramp) are kept `minGap` apart — never
///   more than they were apart on black — wider for dark colors on a light
///   background, where steps between darks read smaller (`crispening`). How
///   much two colors differ besides lightness is their chroma-plane distance,
///   counted up to `chromaWeight` times more when one of them is nearly grey
///   (as CIEDE2000 does): a pink next to a grey of its lightness is plainly
///   another color. Colorful colors hold their place more firmly than greys
///   (`stiffness`).
/// - On light backgrounds a light surround makes dark colors look darker and
///   closer together (CIECAM02's lightness exponent grows with the
///   background's luminance), so a grey next to black or a dark brown next
///   to a light one would read as the same bubble. Pairs that differ mostly
///   in lightness are also kept `apparentGap` apart in apparent lightness
///   `L^exponent` — by moving the lighter one up, never pushing a dark color
///   into black — fading in over `apparentFrom…apparentUntil`.
///
/// Values are Display P3 hex values (see `Palette`). The constants were tuned
/// on the ready-made sets over the whole slider so that their six colors stay
/// about as distinct from each other as they are on black.
struct BackgroundAdaptation {
    /// Background lightness (OKLab) at which whites and pale tints switch to
    /// their deep counterparts — about where black and white text have equal
    /// contrast on the grey, so the interface text switches here too.
    static let polarityFlip = 0.56

    /// The grey background for a slider value.
    static func background(lightness: Double) -> UInt32 {
        OKLCH.hex(l: min(1, max(0, lightness)), c: 0, h: 0)
    }

    /// Whether interface text and lines should be black rather than white on
    /// this background.
    static func isLight(lightness: Double) -> Bool {
        lightness >= polarityFlip
    }

    private let sources: [Source]
    /// How much two colors differ besides lightness: their chroma-plane
    /// distance, weighted by `chromaWeight`; their full distance as authored;
    /// and the apparent-lightness gap they want on white.
    private let chromaDistance: [[Double]]
    private let originalDistance: [[Double]]
    private let apparentTarget: [[Double]]

    init(palette: [UInt32]) {
        self.init(sources: palette.map(Self.source(for:)))
    }

    private init(sources: [Source]) {
        self.sources = sources
        let n = sources.count
        var chroma = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        var original = chroma
        var apparent = chroma
        for i in 0..<n {
            for j in 0..<n where i != j {
                let meanChroma = (sources[i].c + sources[j].c) / 2
                let weight = 1 + Self.chromaWeight * (1 - Self.smooth(meanChroma, Self.chromaWeightFrom, Self.chromaWeightUntil))
                let distance = weight * hypot(sources[i].a - sources[j].a, sources[i].b - sources[j].b)
                chroma[i][j] = distance
                original[i][j] = hypot(sources[i].l - sources[j].l, distance)
                apparent[i][j] = Self.apparentGap * (1 - Self.smooth(distance, 0, Self.apparentChromaUntil))
            }
        }
        chromaDistance = chroma
        originalDistance = original
        apparentTarget = apparent
    }

    /// The palette as shown on the background of the given lightness.
    func colors(lightness: Double) -> [UInt32] {
        let b = min(1, max(0, lightness))
        let solved = solve(b)
        return sources.indices.map {
            Self.finish(sources[$0], lightness: solved.lightness[$0], above: solved.above[$0], background: b)
        }
    }

    /// The color a slot should store so that, on this background, it shows
    /// (almost exactly) `shown` — what a color picked on a grey background is
    /// saved as. A coarse search over lightness, chroma and hue, then a fine
    /// pass on lightness. Of two equally good answers it prefers the one that
    /// reads on black (white rather than near-black for a near-black pick on
    /// a light background).
    static func storedColor(showing shown: UInt32, slot: Int, of palette: [UInt32], lightness: Double) -> UInt32 {
        let b = min(1, max(0, lightness))
        guard b > 0, palette.indices.contains(slot) else { return shown }
        let target = OKLCH.lab(of: shown)
        let picked = OKLCH.lch(of: shown)
        var sources = palette.map(Self.source(for:))

        func error(_ candidate: UInt32) -> Double {
            let source = Self.source(for: candidate)
            sources[slot] = source
            let adaptation = BackgroundAdaptation(sources: sources)
            let solved = adaptation.solve(b)
            let result = Self.finish(source, lightness: solved.lightness[slot], above: solved.above[slot], background: b)
            return simd_distance(OKLCH.lab(of: result), target) + 0.1 * max(0, 0.35 - source.l)
        }

        // Chroma may have been raised by up to `boost` on the way out (not
        // worth searching for a grey), and a yellow's hue turned by up to
        // `yellowTurn` toward amber — which only ever lands between
        // `amberHue` and the far edge of the yellow band.
        let chromaScales = picked.c > 0.02 ? [1.0, 1 / 1.25, 1 / boost] : [1.0]
        let turnable = picked.h >= amberHue - 4 && picked.h <= yellowHue + 39
        let hueOffsets = turnable ? [0.0, yellowTurn / 3, yellowTurn * 2 / 3, yellowTurn] : [0.0]
        var best = (error: Double.infinity, hex: shown, l: picked.l, c: picked.c, h: picked.h)
        for scale in chromaScales {
            for offset in hueOffsets {
                let c = picked.c * scale
                let h = picked.h + offset
                for step in 0...50 {
                    let l = Double(step) / 50
                    let candidate = OKLCH.hex(l: l, c: c, h: h)
                    let e = error(candidate)
                    if e < best.error { best = (e, candidate, l, c, h) }
                }
            }
        }
        let coarse = best
        for step in -10...10 {
            let l = min(1, max(0, coarse.l + Double(step) / 500))
            let candidate = OKLCH.hex(l: l, c: coarse.c, h: coarse.h)
            let e = error(candidate)
            if e < best.error { best = (e, candidate, l, coarse.c, coarse.h) }
        }
        return best.hex
    }

    // MARK: - Tuning

    /// Chroma over which a color goes from grey (crosses the background by
    /// switching sides) to colorful (crosses it continuously).
    private static let colorfulFrom = 0.04, colorfulUntil = 0.12
    /// Colorful colors keep lightness up to here and a share of the rest on
    /// white.
    private static let compressFrom = 0.68, compressKeep = 0.5
    /// Yellow: hue center, the lightness cap on white, the hue it turns toward
    /// as it darkens and by at most how much.
    private static let yellowHue = 88.0, yellowCap = 0.78
    private static let amberHue = 74.0, yellowTurn = 12.0
    /// Mirrored lightness of white is `1 - ink`; a mirrored tint with a
    /// visible hue lands no lower than `mirrorFloor`.
    private static let ink = 1.0, mirrorFloor = 0.38
    /// Lightness over which a grey goes from keeping itself on white to
    /// mirroring.
    private static let mirrorFrom = 0.70, mirrorUntil = 0.92
    /// Lightness and chroma ranges of a pale tint, which mirrors like a grey.
    private static let paleFrom = 0.82, paleUntil = 0.94
    private static let paleChromaFrom = 0.10, paleChromaUntil = 0.17
    /// Lightness a grey keeps from the background.
    private static let margin = 0.21
    /// How much later than its crossing a light grey switches sides.
    private static let lateFlip = 0.10
    /// Lightness kept between colors that differ mostly in lightness.
    private static let minGap = 0.17
    /// How much wider that gap gets per unit of distance from the background,
    /// below it.
    private static let crispening = 0.6
    /// A chroma-plane difference counts up to `1 + chromaWeight` times when
    /// the pair's mean chroma is below `chromaWeightFrom`, 1 time above
    /// `chromaWeightUntil`.
    private static let chromaWeight = 0.6
    private static let chromaWeightFrom = 0.05, chromaWeightUntil = 0.15
    /// Apparent-lightness gap on white between colors that differ only in
    /// lightness, gone for pairs that differ by `apparentChromaUntil` in the
    /// chroma plane; it fades in over that background lightness range.
    private static let apparentGap = 0.27, apparentChromaUntil = 0.15
    private static let apparentFrom = 0.5, apparentUntil = 0.8
    /// Lightness exponent of apparent lightness on black; it grows with the
    /// background's luminance as CIECAM02's `z = 1.48 + sqrt(n)` does.
    private static let apparentExponent = 1.29
    /// How much more firmly a colorful color holds its lightness than a grey.
    private static let stiffness = 4.0
    /// OKLab distance from the background a color close to its lightness is
    /// brought to by chroma, and by at most how many times its chroma.
    private static let visibility = 0.18, boost = 1.5
    private static let iterations = 80

    // MARK: - The model

    private struct Source {
        var l: Double, c: Double, h: Double
        var a: Double, b: Double
        /// 0 for a grey, 1 for a colorful color.
        var colorful: Double
        /// How much the color behaves like a grey: greys and pale tints.
        var neutral: Double
        /// Lightness the color drifts to on white.
        var drift: Double
        /// Lightness of its counterpart below the background.
        var counterpart: Double
        /// Background lightness from which it sits below the background.
        var flip: Double
        /// Lightness it keeps from the background.
        var margin: Double
    }

    private static func source(for hex: UInt32) -> Source {
        let (l, c, h) = OKLCH.lch(of: hex)
        let colorful = smooth(c, colorfulFrom, colorfulUntil)
        let pale = smooth(l, paleFrom, paleUntil) * (1 - smooth(c, paleChromaFrom, paleChromaUntil))
        let neutral = max(1 - colorful, pale)

        var drift = l <= compressFrom ? l : compressFrom + compressKeep * (l - compressFrom)
        if drift > yellowCap {
            drift += (yellowCap - drift) * yellowness(of: h)
        }
        drift = l + (drift - l) * (1 - neutral)

        var mirror = 1 - ink * l
        mirror += max(0, mirrorFloor - mirror) * smooth(c, 0.02, 0.06)
        let mirrored = smooth(l, mirrorFrom, mirrorUntil)
        let counterpart = l + (mirror - l) * mirrored

        let margin = max(0, min((1 - colorful) * Self.margin, l))
        // Where the color's own lightness path meets the background.
        let denominator = 1 - drift + l
        let crossing = denominator > 0 ? l / denominator : 1
        var flip = crossing + (polarityFlip - crossing) * mirrored * neutral
        flip += lateFlip * (1 - colorful) * smooth(l, polarityFlip, polarityFlip + 0.1) * (1 - smooth(l, 0.85, 0.95))
        flip = min(flip, max(0, 1 - margin))

        let radians = h * .pi / 180
        return Source(
            l: l, c: c, h: h, a: c * cos(radians), b: c * sin(radians),
            colorful: colorful, neutral: neutral, drift: drift, counterpart: counterpart,
            flip: flip, margin: margin
        )
    }

    /// Lightness of every color on background `b`, and whether it sits above
    /// the background (lighter) or below it.
    private func solve(_ b: Double) -> (lightness: [Double], above: [Bool]) {
        let n = sources.count
        var above = [Bool](repeating: true, count: n)
        var low = [Double](repeating: 0, count: n)
        var high = [Double](repeating: 1, count: n)
        var preferred = [Double](repeating: 0, count: n)
        for (k, s) in sources.enumerated() {
            let own = s.l + (s.drift - s.l) * b
            if b < s.flip {
                low[k] = min(b + s.margin, 1)
                preferred[k] = own
            } else {
                above[k] = false
                high[k] = max(b - s.margin, 0)
                preferred[k] = (1 - s.neutral) * own + s.neutral * s.counterpart
            }
        }
        let weights = sources.map { 1 + Self.stiffness * $0.colorful }
        var x = (0..<n).map { min(high[$0], max(low[$0], preferred[$0])) }

        // Tie-break for colors at the same lightness: below before above,
        // then by preferred lightness, own lightness, slot.
        let order = (0..<n).sorted {
            (above[$0] ? 1 : 0, preferred[$0], sources[$0].l, $0) < (above[$1] ? 1 : 0, preferred[$1], sources[$1].l, $1)
        }
        var rank = [Int](repeating: 0, count: n)
        for (r, k) in order.enumerated() { rank[k] = r }

        func gap(_ i: Int, _ j: Int) -> Double {
            var wanted = Self.minGap
            if !above[i] {
                wanted *= 1 + Self.crispening * abs((x[i] + x[j]) / 2 - b)
            }
            let target = min(wanted, originalDistance[i][j])
            let chroma = chromaDistance[i][j]
            return max(0, target * target - chroma * chroma).squareRoot()
        }

        // Apparent lightness on this background.
        let exponent = Self.apparentExponent * (1.48 + pow(b, 1.5)) / 1.48
        let apparentShare = Self.smooth(b, Self.apparentFrom, Self.apparentUntil)
        func apparent(_ lightness: Double) -> Double { pow(max(0, lightness), exponent) }
        func lightness(_ apparent: Double) -> Double { pow(max(0, apparent), 1 / exponent) }
        func apparentNeeded(_ i: Int, _ j: Int) -> Double {
            let target = apparentTarget[i][j] * apparentShare
            let chroma = chromaDistance[i][j]
            return max(0, target * target - chroma * chroma).squareRoot()
        }

        for _ in 0..<Self.iterations {
            var moved = false
            for i in 0..<n {
                for j in (i + 1)..<n where above[i] == above[j] {
                    let (lower, upper) = (x[i], rank[i]) < (x[j], rank[j]) ? (i, j) : (j, i)
                    let needed = gap(i, j)
                    let current = x[upper] - x[lower]
                    if needed > 0, current < needed - 1e-9 {
                        let delta = needed - current
                        let total = weights[lower] + weights[upper]
                        x[lower] = min(high[lower], max(low[lower], x[lower] - delta * weights[upper] / total))
                        x[upper] = min(high[upper], max(low[upper], x[upper] + delta * weights[lower] / total))
                        moved = true
                    }
                    // Apparent lightness: only the lighter one moves (up, as
                    // far as it may), so a dark color is never pushed into
                    // black.
                    let apparentWanted = apparentNeeded(i, j)
                    guard apparentWanted > 0 else { continue }
                    let apparentCurrent = apparent(x[upper]) - apparent(x[lower])
                    guard apparentCurrent < apparentWanted - 1e-9 else { continue }
                    let raised = min(apparent(high[upper]), apparent(x[upper]) + apparentWanted - apparentCurrent)
                    if raised - apparent(x[upper]) > 1e-9 {
                        x[upper] = min(high[upper], max(low[upper], lightness(raised)))
                        moved = true
                    }
                }
            }
            if !moved { break }
        }
        return (x, above)
    }

    /// The color at its solved lightness: below the background a pale tint's
    /// counterpart gets richer, a darkened yellow turns toward amber, and a
    /// color close to the background's lightness gets more chroma.
    private static func finish(_ s: Source, lightness x: Double, above: Bool, background b: Double) -> UInt32 {
        var c = s.c
        var h = s.h
        if !above {
            c *= 1 + 0.5 * s.neutral * smooth(c, 0.02, 0.06)
        }
        if h > amberHue {
            let darkened = max(0, s.l - x)
            h -= min(yellowTurn * yellowness(of: s.h) * min(1, darkened / 0.12), h - amberHue)
        }
        let distance = abs(x - b)
        let needed = max(0, visibility * visibility - distance * distance).squareRoot()
        if needed > c, c > 0.02 {
            c = min(needed, c * boost)
        }
        return OKLCH.hex(l: x, c: c, h: h)
    }

    /// 1 for yellow hues, fading out 15–35 degrees away.
    private static func yellowness(of hue: Double) -> Double {
        let distance = min(abs(hue - yellowHue), 360 - abs(hue - yellowHue))
        return 1 - smooth(distance, 15, 35)
    }

    private static func smooth(_ x: Double, _ from: Double, _ to: Double) -> Double {
        let t = min(1, max(0, (x - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }
}

/// OKLab / OKLCH for Display P3 hex values.
enum OKLCH {
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

    static func lab(of hex: UInt32) -> SIMD3<Double> {
        func decode(_ byte: UInt32) -> Double {
            let c = Double(byte & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let lms = p3ToLMS * SIMD3(decode(hex >> 16), decode(hex >> 8), decode(hex))
        return lmsToLab * SIMD3(cbrt(lms.x), cbrt(lms.y), cbrt(lms.z))
    }

    static func lch(of hex: UInt32) -> (l: Double, c: Double, h: Double) {
        let lab = lab(of: hex)
        let hue = atan2(lab.z, lab.y) * 180 / .pi
        return (lab.x, hypot(lab.y, lab.z), hue < 0 ? hue + 360 : hue)
    }

    private static func linearP3(l: Double, c: Double, h: Double) -> SIMD3<Double> {
        let radians = h * .pi / 180
        let lms = labToLMS * SIMD3(l, c * cos(radians), c * sin(radians))
        return lmsToP3 * (lms * lms * lms)
    }

    /// The hex for an OKLCH color, with chroma reduced (hue and lightness
    /// kept) until it fits Display P3.
    static func hex(l: Double, c: Double, h: Double) -> UInt32 {
        let l = min(1, max(0, l))
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
