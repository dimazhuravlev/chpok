import Foundation

/// Persists the player's personal best (spec 36): the fastest *winning* match
/// time, in milliseconds, stored as one bare JSON number. Only wins count —
/// the shortest loss would just be the match that fell apart fastest, which
/// says nothing about skill.
///
/// Lives in its own file, `best-time.json`, in the same directory as the match
/// save (see `GameSaveStore`) and the palette (see `PaletteStore`), and is
/// deliberately *not* part of the match save: `GameSaveStore.clear()` runs at
/// the end of every match and the record has to outlive that. Plain file
/// storage rather than the system preferences database, which is one of the
/// APIs Apple's privacy manifest requires a declared reason for — this app's
/// manifest declares none.
final class BestTimeStore {
    private let fileURL: URL

    /// `Application Support/BubbleShooter/best-time.json`. The directory is not
    /// guaranteed to exist yet — `submit(_:)` creates it on demand.
    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("BubbleShooter", isDirectory: true)
            .appendingPathComponent("best-time.json", isDirectory: false)
    }

    init(fileURL: URL = BestTimeStore.defaultURL) {
        self.fileURL = fileURL
    }

    /// The best winning time in milliseconds, or `nil` when there is no record
    /// yet. A file that exists but does not hold a positive whole number
    /// (corrupted, hand-edited, or from an incompatible earlier format) is
    /// treated as if it were absent: it is deleted so the next win starts a
    /// clean record, and this returns `nil` — same contract as
    /// `GameSaveStore.load()`.
    func load() -> Int? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            let elapsedMs = try JSONDecoder().decode(Int.self, from: data)
            guard elapsedMs > 0 else { throw CocoaError(.coderReadCorrupt) }
            return elapsedMs
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    /// Offers the time of a match that was just *won*. It is written only if
    /// there is no record yet or it is strictly faster than the current one;
    /// otherwise the file is left alone. A non-positive time is not a real
    /// result and is ignored (`load()` would reject it anyway). Never throws —
    /// failures (e.g. a full disk) are logged and otherwise ignored, leaving
    /// any previous record in place.
    func submit(_ elapsedMs: Int) {
        guard elapsedMs > 0 else { return }
        if let best = load(), best <= elapsedMs { return }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(elapsedMs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("BestTimeStore.submit failed: \(error)")
        }
    }

    /// Removes the record, if any. Safe to call when no file exists.
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
