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
        self.colors = Self.load(from: fileURL) ?? Palette.defaultBubbleColors
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
        colors == Palette.defaultBubbleColors
    }

    /// Sets the color for one slot from a (possibly translucent) system
    /// color-picker value, normalized to opaque before it's ever stored or
    /// shown (spec 32 "Решённые развилки").
    func setColor(_ color: UIColor, for bubbleColor: BubbleColor) {
        colors[bubbleColor.rawValue] = color.opaqueHexValue
        persist()
    }

    /// Restores every slot to the original six colors.
    func resetToDefaults() {
        colors = Palette.defaultBubbleColors
        persist()
    }

    /// Reads and decodes the palette file. `nil` for "no file" *or* "file
    /// exists but is corrupt/wrong shape" — in the latter case the bad file
    /// is deleted so the next save starts clean (same contract as
    /// `GameSaveStore.load()`).
    private static func load(from fileURL: URL) -> [UInt32]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            let hexStrings = try JSONDecoder().decode([String].self, from: data)
            guard hexStrings.count == BubbleColor.allCases.count else {
                throw CocoaError(.coderReadCorrupt)
            }
            var values: [UInt32] = []
            for hexString in hexStrings {
                guard let value = UInt32(hexString, radix: 16) else {
                    throw CocoaError(.coderReadCorrupt)
                }
                values.append(value)
            }
            return values
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    /// Writes the palette atomically as an array of six `"RRGGBB"` strings.
    /// Never throws — failures are logged and the previous file (if any) is
    /// left in place, same contract as `GameSaveStore.save(_:)`.
    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let hexStrings = colors.map { String(format: "%06X", $0) }
            let data = try JSONEncoder().encode(hexStrings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("PaletteStore.persist failed: \(error)")
        }
    }
}
