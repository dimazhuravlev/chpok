import Foundation
import BubbleShooterCore

/// Persists a single in-progress `GameSnapshot` to disk as JSON. There is no
/// history/records — a save only ever represents "the one match that was
/// left in progress".
final class GameSaveStore {
    private let fileURL: URL

    /// `Application Support/BubbleShooter/game.json`. The directory is not
    /// guaranteed to exist yet — `save(_:)` creates it on demand.
    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("BubbleShooter", isDirectory: true)
            .appendingPathComponent("game.json", isDirectory: false)
    }

    init(fileURL: URL = GameSaveStore.defaultURL) {
        self.fileURL = fileURL
    }

    /// `nil` when there is no save. A file that exists but fails to decode
    /// (corrupted or from an incompatible earlier format) is treated as if
    /// it were absent: it is deleted so the next save starts clean, and this
    /// returns `nil`.
    func load() -> GameSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(GameSnapshot.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    /// Writes the snapshot atomically. Never throws — failures (e.g. a full
    /// disk) are logged and otherwise ignored, leaving any previous save in
    /// place.
    func save(_ snapshot: GameSnapshot) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("GameSaveStore.save failed: \(error)")
        }
    }

    /// Removes the save, if any. Safe to call when no file exists.
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
