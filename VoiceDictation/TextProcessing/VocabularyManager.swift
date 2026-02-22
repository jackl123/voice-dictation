import Foundation

/// Parses the user's custom vocabulary list and provides correction data
/// to the Whisper API, GPT formatter, and post-processing replacement step.
///
/// Entry format (one per line):
/// - `Siobhan`              — hint-only (Whisper prompt + AI formatting)
/// - `shiv on → Siobhan`    — hint + explicit find-and-replace
/// - `# comment`            — ignored
/// - empty lines            — ignored
@MainActor
final class VocabularyManager {
    static let shared = VocabularyManager()

    private init() {}

    // MARK: - Parsed data

    /// All "correct" terms — the right-hand side of `→` entries, plus plain hint words.
    /// Used for Whisper prompt hints and AI formatting context.
    var hintWords: [String] {
        parseEntries().hints
    }

    /// Explicit replacement pairs from `wrong → right` entries.
    var replacements: [(from: String, to: String)] {
        parseEntries().replacements
    }

    // MARK: - Integration helpers

    /// Comma-separated hint words for the Whisper API `prompt` parameter.
    /// Returns an empty string if no vocabulary is defined.
    var whisperPrompt: String {
        let hints = hintWords
        guard !hints.isEmpty else { return "" }
        return hints.joined(separator: ", ")
    }

    /// A section to append to the GPT-4o-mini system prompt.
    /// Returns an empty string if no vocabulary is defined.
    var aiPromptSection: String {
        let hints = hintWords
        let repls = replacements
        guard !hints.isEmpty || !repls.isEmpty else { return "" }

        var lines = ["\n\nCUSTOM VOCABULARY — always use these exact spellings:"]

        for word in hints {
            lines.append("- \(word)")
        }

        for r in repls {
            lines.append("- If you see \"\(r.from)\", replace it with \"\(r.to)\"")
        }

        return lines.joined(separator: "\n")
    }

    /// Applies explicit `wrong → right` replacements to the text.
    /// Uses case-insensitive matching with word boundaries.
    /// Returns the text unchanged if no replacements are defined.
    func applyReplacements(_ text: String) -> String {
        let repls = replacements
        guard !repls.isEmpty else { return text }

        var result = text
        for r in repls {
            let escaped = NSRegularExpression.escapedPattern(for: r.from)
            let pattern = "\\b\(escaped)\\b"
            result = result.replacingOccurrences(
                of: pattern,
                with: r.to,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    // MARK: - Parsing

    private struct ParsedEntries {
        let hints: [String]
        let replacements: [(from: String, to: String)]
    }

    /// Parses the raw vocabulary string from UserDefaults.
    private func parseEntries() -> ParsedEntries {
        let raw = UserDefaults.standard.string(forKey: "customVocabulary") ?? ""
        guard !raw.isEmpty else { return ParsedEntries(hints: [], replacements: []) }

        var hints: [String] = []
        var replacements: [(from: String, to: String)] = []

        let arrow = "\u{2192}"  // →

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.contains(arrow) {
                let parts = trimmed.components(separatedBy: arrow)
                if parts.count == 2 {
                    let from = parts[0].trimmingCharacters(in: .whitespaces)
                    let to = parts[1].trimmingCharacters(in: .whitespaces)
                    if !from.isEmpty && !to.isEmpty {
                        replacements.append((from: from, to: to))
                        hints.append(to)  // The correct spelling is also a hint
                    }
                }
            } else {
                hints.append(trimmed)
            }
        }

        return ParsedEntries(hints: hints, replacements: replacements)
    }
}
