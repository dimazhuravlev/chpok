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

    /// Current palette, indexed by `BubbleColor.rawValue`. Always exactly
    /// `BubbleColor.allCases.count` entries.
    @Published private(set) var colors: [UInt32]
    /// Background the palette sits on (spec 56) — black for every dark set,
    /// the set's own paper-like color for a light one.
    @Published private(set) var background: UInt32
    /// Id of the `PaletteSet` last applied; `nil` once a single color has
    /// been edited by hand.
    @Published private(set) var selectedSetId: String?

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
        self.colors = saved?.colors ?? Palette.defaultBubbleColors
        self.background = saved?.background ?? Palette.defaultBackground
        self.selectedSetId = saved == nil ? PaletteSet.chpok.id : saved?.setId
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

    func color(for bubbleColor: BubbleColor) -> UIColor {
        UIColor(hex: colors[bubbleColor.rawValue])
    }

    /// Whether every slot currently matches `Palette.defaultBubbleColors`,
    /// compared by actual value rather than by "has the player touched
    /// anything" — dialing a color back to its original value by hand counts
    /// as default again. Drives the dimmed state of "reset colors" (owner
    /// feedback on spec 32): nothing to reset, nothing to draw attention to.
    var isDefault: Bool {
        colors == Palette.defaultBubbleColors && background == Palette.defaultBackground
    }

    /// Sets the color for one slot from a (possibly translucent) system
    /// color-picker value, normalized to opaque before it's ever stored or
    /// shown (spec 32 "Решённые развилки").
    func setColor(_ color: UIColor, for bubbleColor: BubbleColor) {
        colors[bubbleColor.rawValue] = color.opaqueHexValue
        selectedSetId = nil
        persist()
    }

    /// Switches to a ready-made set: its colors and its background (spec 56).
    func apply(_ set: PaletteSet) {
        colors = set.colors
        background = set.background
        selectedSetId = set.id
        persist()
    }

    /// Restores the `chpok` set — original six colors on black.
    func resetToDefaults() {
        apply(.chpok)
    }

    /// Reads and decodes the palette file: an object `{colors, background,
    /// set}`, or the older bare array of six hex strings (black background).
    /// `nil` for "no file" *or* "file exists but is corrupt/wrong shape" — in
    /// the latter case the bad file is deleted so the next save starts clean
    /// (same contract as `GameSaveStore.load()`).
    private static func load(from fileURL: URL) -> (colors: [UInt32], background: UInt32, setId: String?)? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            let file: FileFormat
            if let legacy = try? JSONDecoder().decode([String].self, from: data) {
                file = FileFormat(colors: legacy, background: nil, set: nil)
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
            return (values, background, file.set)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    private struct FileFormat: Codable {
        var colors: [String]
        var background: String?
        var set: String?
    }

    /// Writes the palette atomically as `{"colors": [six "RRGGBB"],
    /// "background": "RRGGBB", "set": id or null}`. Never throws — failures
    /// are logged and the previous file (if any) is left in place, same
    /// contract as `GameSaveStore.save(_:)`.
    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = FileFormat(
                colors: colors.map { String(format: "%06X", $0) },
                background: String(format: "%06X", background),
                set: selectedSetId
            )
            let data = try JSONEncoder().encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("PaletteStore.persist failed: \(error)")
        }
    }
}
