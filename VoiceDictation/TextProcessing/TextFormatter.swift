import Foundation

/// Formats raw Whisper transcription output into properly structured text.
///
/// Two formatting modes:
/// 1. **Rule-based** (always available, free, offline): Converts spoken commands
///    like "bullet point", "new line", "comma" into actual formatting.
/// 2. **OpenAI API** (optional): Sends raw text to GPT-4o-mini for intelligent
///    punctuation, capitalization, and structural formatting.
final class TextFormatter {
    static let shared = TextFormatter()

    private init() {}

    // MARK: - Public API

    /// Format the raw transcript. Uses OpenAI if enabled and key is set,
    /// otherwise falls back to rule-based formatting.
    func format(_ text: String) async -> String {
        let apiKey = UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
        let useAI = UserDefaults.standard.bool(forKey: "useAIFormatting")

        if useAI && !apiKey.isEmpty {
            // Try API formatting; fall back to rule-based on failure.
            if let aiFormatted = await formatWithOpenAI(text, apiKey: apiKey) {
                return aiFormatted
            }
        }

        return applyRuleBasedFormatting(text)
    }

    // MARK: - Rule-based formatting

    /// Detects spoken formatting commands and converts them to actual characters.
    func applyRuleBasedFormatting(_ text: String) -> String {
        var result = text

        // Structural commands (order matters — do multi-word replacements first).
        let structuralReplacements: [(pattern: String, replacement: String)] = [
            ("new paragraph", "\n\n"),
            ("new line", "\n"),
            ("next line", "\n"),
            ("line break", "\n"),
            ("bullet point", "\n\u{2022} "),
            ("dash point", "\n- "),
            ("numbered list", "\n1. "),
        ]

        for (pattern, replacement) in structuralReplacements {
            result = replaceCaseInsensitive(result, pattern: pattern, with: replacement)
        }

        // Punctuation commands.
        let punctuationReplacements: [(pattern: String, replacement: String)] = [
            ("full stop", "."),
            ("period", "."),
            ("comma", ","),
            ("question mark", "?"),
            ("exclamation mark", "!"),
            ("exclamation point", "!"),
            ("colon", ":"),
            ("semicolon", ";"),
            ("semi colon", ";"),
            ("open quote", "\""),
            ("close quote", "\""),
            ("open bracket", "("),
            ("close bracket", ")"),
            ("hyphen", "-"),
            ("ellipsis", "..."),
        ]

        for (pattern, replacement) in punctuationReplacements {
            result = replaceCaseInsensitive(result, pattern: pattern, with: replacement)
        }

        // Clean up whitespace around punctuation: remove space before punctuation.
        result = result.replacingOccurrences(
            of: "\\s+([.,!?;:\\)\"\\-])",
            with: "$1",
            options: .regularExpression
        )

        // Clean up multiple spaces.
        result = result.replacingOccurrences(
            of: "  +",
            with: " ",
            options: .regularExpression
        )

        // Auto-capitalize after sentence-ending punctuation.
        result = capitalizeAfterSentenceEnd(result)

        // Capitalize the very first character.
        if let first = result.first, first.isLetter && first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OpenAI API formatting

    /// Sends raw transcript to GPT-4o-mini for intelligent formatting.
    /// Returns nil on failure so the caller can fall back to rule-based.
    private func formatWithOpenAI(_ text: String, apiKey: String) async -> String? {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            return nil
        }

        let systemPrompt = """
        You are a text formatter for voice dictation. The user has spoken text into a \
        microphone and it has been transcribed. Your job is to format it properly:
        - Add correct punctuation and capitalization
        - Add paragraph breaks where the speaker clearly changes topic
        - Format bullet points or numbered lists if the speaker indicates them
        - Fix obvious transcription errors if the intended word is clear
        - Preserve the speaker's exact words and meaning
        - Return ONLY the formatted text, no explanations or preamble
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 2048
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("[TextFormatter] OpenAI API error: HTTP \(statusCode)")
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                print("[TextFormatter] Failed to parse OpenAI response")
                return nil
            }

            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("[TextFormatter] OpenAI request failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    /// Case-insensitive replacement that handles word boundaries.
    private func replaceCaseInsensitive(_ text: String, pattern: String, with replacement: String) -> String {
        // Use regex with word boundaries so "period" doesn't match inside other words.
        let escapedPattern = NSRegularExpression.escapedPattern(for: pattern)
        let regex = "\\b\(escapedPattern)\\b"
        return text.replacingOccurrences(
            of: regex,
            with: replacement,
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// Capitalizes the first letter after sentence-ending punctuation (. ? !).
    private func capitalizeAfterSentenceEnd(_ text: String) -> String {
        var result = ""
        var capitalizeNext = false

        for char in text {
            if capitalizeNext && char.isLetter {
                result.append(char.uppercased().first!)
                capitalizeNext = false
            } else {
                result.append(char)
                if char == "." || char == "?" || char == "!" {
                    capitalizeNext = true
                } else if !char.isWhitespace && char != "\n" {
                    capitalizeNext = false
                }
            }
        }

        return result
    }
}
