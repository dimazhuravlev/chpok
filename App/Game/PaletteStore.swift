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

    /// Dark or light theme (spec 57) — a separate switch, independent of the
    /// palette: every palette is stored for the dark theme and the light one
    /// is derived from it (`LightTheme`).
    enum Appearance: String, Codable {
        case dark, light
    }

    /// Current palette as shown, indexed by `BubbleColor.rawValue`: the
    /// stored palette in the dark theme, its `LightTheme` counterpart in the
    /// light one. Always exactly `BubbleColor.allCases.count` entries.
    @Published private(set) var colors: [UInt32]
    /// Background as shown (spec 56): the set's own (black) in the dark
    /// theme, its counterpart (white) in the light one.
    @Published private(set) var background: UInt32
    /// Id of the `PaletteSet` last applied; `nil` once a single color has
    /// been edited by hand.
    @Published private(set) var selectedSetId: String?
    @Published private(set) var appearance: Appearance

    /// The palette as stored — the dark-theme values `colors` and
    /// `background` are derived from.
    private var storedColors: [UInt32]
    private var storedBackground: UInt32

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
        var background = saved?.background ?? Palette.defaultBackground
        var setId = saved == nil ? PaletteSet.chpok.id : saved?.setId
        // A selected set is re-read from `PaletteSet.all`, so edits to its
        // values reach a device that already had it selected; a set that no
        // longer exists falls back to the default one.
        if let id = setId {
            let set = PaletteSet.all.first { $0.id == id } ?? .chpok
            colors = set.colors
            background = set.background
            setId = set.id
        }
        let appearance = saved?.appearance ?? .dark
        self.storedColors = colors
        self.storedBackground = background
        self.selectedSetId = setId
        self.appearance = appearance
        self.colors = Self.shown(colors, in: appearance)
        self.background = Self.shown([background], in: appearance)[0]
    }

    private static func shown(_ values: [UInt32], in appearance: Appearance) -> [UInt32] {
        switch appearance {
        case .dark: return values
        case .light: return values.map(LightTheme.color(for:))
        }
    }

    /// Recomputes what is shown from what is stored. Assigns only what
    /// changed, so a repaint isn't triggered for nothing.
    private func refresh() {
        let newColors = Self.shown(storedColors, in: appearance)
        let newBackground = Self.shown([storedBackground], in: appearance)[0]
        if newColors != colors { colors = newColors }
        if newBackground != background { background = newBackground }
    }

    /// Whether the background is light (relative luminance >= 0.5, as in the
    /// palette validator) — HUD, status bar and tinting follow it.
    var isLight: Bool {
        func linear(_ byte: UInt32) -> Double {
            let c = Double(byte & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(background >> 16) + 0.7152 * linear(background >> 8) + 0.0722 * linear(background)
        return luminance >= 0.5
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
    /// Independent of the theme: resetting doesn't touch it.
    var isDefault: Bool {
        storedColors == Palette.defaultBubbleColors && storedBackground == Palette.defaultBackground
    }

    /// Sets the color for one slot from a (possibly translucent) system
    /// color-picker value, normalized to opaque before it's ever stored or
    /// shown (spec 32 "Решённые развилки").
    func setColor(_ color: UIColor, for bubbleColor: BubbleColor) {
        // Slots hold Display P3 coordinates (see `Palette`), so the picked
        // color is stored in P3 too — otherwise it would come back more
        // saturated than picked.
        let picked = Palette.usesDisplayP3 ? color.opaqueDisplayP3HexValue : color.opaqueHexValue
        // Slots hold dark-theme values; a color picked in the light theme is
        // stored as the dark color whose light counterpart it is.
        storedColors[bubbleColor.rawValue] = appearance == .light ? LightTheme.darkColor(for: picked) : picked
        selectedSetId = nil
        refresh()
        persist()
    }

    /// Switches to a ready-made set: its colors and its background (spec 56).
    func apply(_ set: PaletteSet) {
        storedColors = set.colors
        storedBackground = set.background
        selectedSetId = set.id
        refresh()
        persist()
    }

    /// Switches between the dark and the light theme (spec 57).
    func setAppearance(_ newValue: Appearance) {
        guard newValue != appearance else { return }
        appearance = newValue
        refresh()
        persist()
    }

    /// Restores the `chpok` set — original six colors on black.
    func resetToDefaults() {
        apply(.chpok)
    }

    /// Reads and decodes the palette file: an object `{colors, background,
    /// set, appearance}`, or the older bare array of six hex strings (black
    /// background, dark theme).
    /// `nil` for "no file" *or* "file exists but is corrupt/wrong shape" — in
    /// the latter case the bad file is deleted so the next save starts clean
    /// (same contract as `GameSaveStore.load()`).
    private static func load(from fileURL: URL) -> (colors: [UInt32], background: UInt32, setId: String?, appearance: Appearance)? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            let file: FileFormat
            if let legacy = try? JSONDecoder().decode([String].self, from: data) {
                file = FileFormat(colors: legacy, background: nil, set: nil, appearance: nil)
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
            var background = Palette.defaultBackground
            if let hexString = file.background {
                guard let value = UInt32(hexString, radix: 16) else {
                    throw CocoaError(.coderReadCorrupt)
                }
                background = value
            }
            return (values, background, file.set, file.appearance ?? .dark)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    private struct FileFormat: Codable {
        var colors: [String]
        var background: String?
        var set: String?
        var appearance: Appearance?
    }

    /// Writes the palette atomically as `{"colors": [six "RRGGBB"],
    /// "background": "RRGGBB", "set": id or null, "appearance": "dark" or
    /// "light"}` — colors and background as stored, i.e. dark-theme values. Never throws — failures
    /// are logged and the previous file (if any) is left in place, same
    /// contract as `GameSaveStore.save(_:)`.
    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = FileFormat(
                colors: storedColors.map { String(format: "%06X", $0) },
                background: String(format: "%06X", storedBackground),
                set: selectedSetId,
                appearance: appearance
            )
            let data = try JSONEncoder().encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("PaletteStore.persist failed: \(error)")
        }
    }
}
