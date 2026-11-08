import SwiftUI
import BubbleShooterCore

/// Shared, observable store for the app's six bubble colors (spec 32) — the
/// single source of truth `Palette.color(for:)` reads from. Colors are
/// indexed by `BubbleColor.rawValue` and persisted as a small JSON file next
/// to the match save (see `GameSaveStore`), deliberately not the system
/// preferences database: that's one of the APIs Apple's privacy manifest
/// requires a declared reason for, and this app's manifest currently
/// declares none — plain file storage in the app's own Application Support
/// directory avoids that requirement entirely.
final class PaletteStore: ObservableObject {
    static let shared = PaletteStore()

    /// Current palette as shown, indexed by `BubbleColor.rawValue`: the stored
    /// palette adapted to the background (`BackgroundAdaptation`). Always
    /// exactly `BubbleColor.allCases.count` entries.
    @Published private(set) var colors: [UInt32]
    /// Background as shown: a grey of `backgroundLightness`.
    @Published private(set) var background: UInt32
    /// Id of the `PaletteSet` last applied; `nil` once a single color has
    /// been edited by hand.
    @Published private(set) var selectedSetId: String?
    /// The background slider (spec 64): OKLab lightness of the grey
    /// background, 0 black … 1 white. Independent of the palette — every
    /// palette is stored for black and adapted to it.
    @Published private(set) var backgroundLightness: Double

    /// The palette as stored — authored for black; `colors` is derived from
    /// it.
    private var storedColors: [UInt32]
    private var adaptation: BackgroundAdaptation

    private let fileURL: URL

    /// `Application Support/BubbleShooter/palette.json` — same directory
    /// `GameSaveStore` uses for the match save, just a different file.
    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("BubbleShooter", isDirectory: true)
            .appendingPathComponent("palette.json", isDirectory: false)
    }

    init(fileURL: URL = PaletteStore.defaultURL) {
        self.fileURL = fileURL
        let saved = Self.load(from: fileURL)
        var colors = saved?.colors ?? Palette.defaultBubbleColors
        var setId = saved == nil ? PaletteSet.default.id : saved?.setId
        // A selected set is re-read from `PaletteSet.all`, so edits to its
        // values reach a device that already had it selected; a set that no
        // longer exists falls back to the default one.
        if let id = setId {
            let set = PaletteSet.all.first { $0.id == id } ?? .default
            colors = set.colors
            setId = set.id
        }
        let lightness = saved?.backgroundLightness ?? 0
        let adaptation = BackgroundAdaptation(palette: colors)
        self.storedColors = colors
        self.adaptation = adaptation
        self.selectedSetId = setId
        self.backgroundLightness = lightness
        self.colors = adaptation.colors(lightness: lightness)
        self.background = BackgroundAdaptation.background(lightness: lightness)
    }

    /// Recomputes what is shown from what is stored. Assigns only what
    /// changed, so a repaint isn't triggered for nothing.
    private func refresh() {
        let newColors = adaptation.colors(lightness: backgroundLightness)
        let newBackground = BackgroundAdaptation.background(lightness: backgroundLightness)
        if newColors != colors { colors = newColors }
        if newBackground != background { background = newBackground }
    }

    /// Whether the background is light enough for black text — HUD, status
    /// bar, sheets and the aim line follow it.
    var isLight: Bool {
        BackgroundAdaptation.isLight(lightness: backgroundLightness)
    }

    /// Raw slot color for the game scene: its components are the stored
    /// hex values, which the scene's P3-tagged layer reads as Display P3.
    func color(for bubbleColor: BubbleColor) -> UIColor {
        UIColor(hex: colors[bubbleColor.rawValue])
    }

    /// Slot color for SwiftUI, matching what the scene shows — see
    /// `Palette.display(_:)`.
    func displayColor(for bubbleColor: BubbleColor) -> UIColor {
        Palette.display(colors[bubbleColor.rawValue])
    }

    /// Whether every slot currently matches `Palette.defaultBubbleColors`,
    /// compared by actual value rather than by "has the player touched
    /// anything" — dialing a color back to its original value by hand counts
    /// as default again. Drives the dimmed state of "reset colors" (owner
    /// feedback on spec 32): nothing to reset, nothing to draw attention to.
    /// Independent of the background: resetting doesn't touch it.
    var isDefault: Bool {
        storedColors == Palette.defaultBubbleColors
    }

    /// Sets the color for one slot from a (possibly translucent) system
    /// color-picker value, normalized to opaque before it's ever stored or
    /// shown (spec 32 "Решённые развилки").
    func setColor(_ color: UIColor, for bubbleColor: BubbleColor) {
        // Slots hold Display P3 coordinates (see `Palette`), so the picked
        // color is stored in P3 too — otherwise it would come back more
        // saturated than picked.
        let picked = Palette.usesDisplayP3 ? color.opaqueDisplayP3HexValue : color.opaqueHexValue
        // Slots hold colors for black; a color picked on another background
        // is stored as the color that shows as the picked one there.
        storedColors[bubbleColor.rawValue] = BackgroundAdaptation.storedColor(
            showing: picked, slot: bubbleColor.rawValue, of: storedColors, lightness: backgroundLightness
        )
        adaptation = BackgroundAdaptation(palette: storedColors)
        selectedSetId = nil
        refresh()
        persist()
    }

    /// Switches to a ready-made set (spec 56).
    func apply(_ set: PaletteSet) {
        storedColors = set.colors
        adaptation = BackgroundAdaptation(palette: storedColors)
        selectedSetId = set.id
        refresh()
        persist()
    }

    /// Moves the background slider (spec 64). Called continuously while the
    /// slider is dragged, so it only repaints; `saveBackground()` writes the
    /// file once the drag ends.
    func setBackgroundLightness(_ value: Double) {
        let clamped = min(1, max(0, value))
        guard clamped != backgroundLightness else { return }
        backgroundLightness = clamped
        refresh()
    }

    /// Persists the background slider's value.
    func saveBackground() {
        persist()
    }

    /// Restores the default set (`PaletteSet.default`).
    func resetToDefaults() {
        apply(.default)
    }

    /// Reads and decodes the palette file: an object `{colors, set,
    /// backgroundLightness}`, an older one with `appearance` instead of the
    /// lightness (`light` reads as white), or the oldest bare array of six hex
    /// strings (black background).
    /// `nil` for "no file" *or* "file exists but is corrupt/wrong shape" — in
    /// the latter case the bad file is deleted so the next save starts clean
    /// (same contract as `GameSaveStore.load()`).
    private static func load(from fileURL: URL) -> (colors: [UInt32], setId: String?, backgroundLightness: Double)? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            let file: FileFormat
            if let legacy = try? JSONDecoder().decode([String].self, from: data) {
                file = FileFormat(colors: legacy)
            } else {
                file = try JSONDecoder().decode(FileFormat.self, from: data)
            }
            guard file.colors.count == BubbleColor.allCases.count else {
                throw CocoaError(.coderReadCorrupt)
            }
            var values: [UInt32] = []
            for hexString in file.colors {
                guard let value = UInt32(hexString, radix: 16) else {
                    throw CocoaError(.coderReadCorrupt)
                }
                values.append(value)
            }
            let lightness = file.backgroundLightness ?? (file.appearance == "light" ? 1 : 0)
            return (values, file.set, min(1, max(0, lightness)))
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    /// `appearance` ("dark" or "light") is read from older files only.
    private struct FileFormat: Codable {
        var colors: [String]
        var set: String?
        var backgroundLightness: Double?
        var appearance: String?
    }

    /// Writes the palette atomically as `{"colors": [six "RRGGBB"], "set": id
    /// or null, "backgroundLightness": 0…1}` — colors as stored, i.e. for
    /// black. Never throws — failures are logged and the previous file (if
    /// any) is left in place, same contract as `GameSaveStore.save(_:)`.
    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = FileFormat(
                colors: storedColors.map { String(format: "%06X", $0) },
                set: selectedSetId,
                backgroundLightness: backgroundLightness
            )
            let data = try JSONEncoder().encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("PaletteStore.persist failed: \(error)")
        }
    }
}
