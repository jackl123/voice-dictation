import Combine
import Foundation

/// Persists transcript history to a JSON file in Application Support.
@MainActor
final class TranscriptHistoryStore: ObservableObject {
    static let shared = TranscriptHistoryStore()

    @Published private(set) var entries: [TranscriptEntry] = []

    static let maxEntries = 50

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("VoiceDictation", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("transcript_history.json")
    }

    private init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// Adds a new transcript entry (newest first) and persists to disk.
    func addEntry(_ text: String) {
        let entry = TranscriptEntry(text: text)
        entries.insert(entry, at: 0)

        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }

        saveToDisk()
    }

    /// Removes a single entry and persists.
    func deleteEntry(_ entry: TranscriptEntry) {
        entries.removeAll { $0.id == entry.id }
        saveToDisk()
    }

    /// Removes all entries and persists.
    func clearAll() {
        entries.removeAll()
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: Self.fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([TranscriptEntry].self, from: data)
        } catch {
            print("[TranscriptHistoryStore] Failed to load: \(error.localizedDescription)")
        }
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(entries)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("[TranscriptHistoryStore] Failed to save: \(error.localizedDescription)")
        }
    }
}
