import Foundation

/// App settings beyond the palette (spec 60) — for now whether the aim line
/// is drawn. Persisted as `settings.json` next to `palette.json`, for the
/// same reason the palette is: plain file storage, not the system
/// preferences database (see `PaletteStore`).
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// Draw the shot's path, wall bounces included, while the finger is down.
    @Published private(set) var showsTrajectory: Bool

    private let fileURL: URL

    /// `Application Support/BubbleShooter/settings.json`.
    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("BubbleShooter", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    init(fileURL: URL = SettingsStore.defaultURL) {
        self.fileURL = fileURL
        let saved = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(FileFormat.self, from: $0) }
        self.showsTrajectory = saved?.showsTrajectory ?? false
    }

    func setShowsTrajectory(_ value: Bool) {
        guard value != showsTrajectory else { return }
        showsTrajectory = value
        persist()
    }

    /// Every field optional, so a file from an older or newer build still
    /// reads.
    private struct FileFormat: Codable {
        var showsTrajectory: Bool?
    }

    /// Writes atomically; failures are logged and the old file is kept, as
    /// in `PaletteStore`.
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(FileFormat(showsTrajectory: showsTrajectory))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("SettingsStore.persist failed: \(error)")
        }
    }
}
