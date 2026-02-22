import AppKit
import Combine
import Foundation

/// A per-app tone override entry.
struct AppToneOverride: Identifiable, Equatable {
    let id: String          // bundle identifier
    let appName: String
    let tone: TextFormatter.Tone

    var bundleID: String { id }
}

/// Manages per-app tone overrides so dictation tone automatically adapts
/// to the frontmost application (e.g. very casual in Messages, formal in Mail).
@MainActor
final class AppToneManager: ObservableObject {
    static let shared = AppToneManager()

    @Published private(set) var overrides: [AppToneOverride] = []

    private let defaultsKey = "appToneOverrides"

    private init() {
        loadFromDefaults()
    }

    // MARK: - Lookup

    /// Returns the tone override for the given bundle identifier, or nil if none is set.
    func toneForApp(_ bundleID: String?) -> TextFormatter.Tone? {
        guard let bundleID else { return nil }
        return overrides.first(where: { $0.bundleID == bundleID })?.tone
    }

    /// Returns the tone for the currently frontmost application, or nil.
    func toneForFrontmostApp() -> TextFormatter.Tone? {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return toneForApp(bundleID)
    }

    // MARK: - Mutations

    func setTone(_ tone: TextFormatter.Tone, forApp bundleID: String, appName: String) {
        if let idx = overrides.firstIndex(where: { $0.bundleID == bundleID }) {
            overrides[idx] = AppToneOverride(id: bundleID, appName: appName, tone: tone)
        } else {
            overrides.append(AppToneOverride(id: bundleID, appName: appName, tone: tone))
        }
        overrides.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        saveToDefaults()
    }

    func removeTone(forApp bundleID: String) {
        overrides.removeAll { $0.bundleID == bundleID }
        saveToDefaults()
    }

    // MARK: - Persistence

    /// Stored as `{ "bundleID": { "tone": "formal", "appName": "Mail" } }`.
    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let dict = try? JSONDecoder().decode([String: StoredOverride].self, from: data)
        else { return }

        overrides = dict.map { (bundleID, stored) in
            AppToneOverride(
                id: bundleID,
                appName: stored.appName,
                tone: TextFormatter.Tone(rawValue: stored.tone) ?? .formal
            )
        }
        .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    private func saveToDefaults() {
        var dict: [String: StoredOverride] = [:]
        for o in overrides {
            dict[o.bundleID] = StoredOverride(tone: o.tone.rawValue, appName: o.appName)
        }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private struct StoredOverride: Codable {
        let tone: String
        let appName: String
    }
}
