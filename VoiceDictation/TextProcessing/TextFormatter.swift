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

    /// The user's chosen writing tone.
    enum Tone: String {
        case formal      = "formal"       // Full caps + full punctuation
        case casual      = "casual"       // Full caps + lighter punctuation
        case veryCasual  = "very_casual"  // No caps + lighter punctuation

        /// Human-readable description for the AI prompt.
        var description: String {
            switch self {
            case .formal:     return "Formal: proper capitalisation, full punctuation (commas, periods, etc.)"
            case .casual:     return "Casual: normal capitalisation, lighter punctuation (skip commas where optional, keep question marks and periods)"
            case .veryCasual: return "Very casual: all lowercase, minimal punctuation (only question marks, skip most commas and periods)"
            }
        }
    }

    /// Reads the current tone from UserDefaults.
    private var currentTone: Tone {
        let raw = UserDefaults.standard.string(forKey: "writingTone") ?? "formal"
        return Tone(rawValue: raw) ?? .formal
    }

    /// Result of formatting that includes the estimated API cost.
    struct FormatResult {
        let text: String
        let costCents: Double  // Estimated cost in US cents
    }

    /// Format the raw transcript based on the user's formatting preference.
    /// - "ai": Uses OpenAI GPT-4o-mini, falls back to rule-based on failure.
    /// - "rules": Converts spoken commands to formatting.
    /// - "off": Returns text as-is.
    func format(_ text: String, overrideTone: Tone? = nil) async -> String {
        let result = await formatWithCost(text, overrideTone: overrideTone)
        return result.text
    }

    /// Format the raw transcript and return the estimated API cost.
    func formatWithCost(_ text: String, overrideTone: Tone? = nil) async -> FormatResult {
        let mode = UserDefaults.standard.string(forKey: "formattingMode") ?? "rules"
        let apiKey = UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
        let tone = overrideTone ?? currentTone

        let formatted: String
        var costCents: Double = 0

        switch mode {
        case "ai":
            if !apiKey.isEmpty, let aiResult = await formatWithOpenAI(text, apiKey: apiKey, tone: tone) {
                formatted = aiResult.text
                costCents = aiResult.costCents
            } else {
                // Fall back to rule-based if API fails.
                formatted = applyRuleBasedFormatting(text, tone: tone)
            }
        case "rules":
            formatted = applyRuleBasedFormatting(text, tone: tone)
        default:
            // "off" — return as-is.
            formatted = text
        }

        // Apply custom vocabulary replacements as a final post-processing step.
        let final = VocabularyManager.shared.applyReplacements(formatted)
        return FormatResult(text: final, costCents: costCents)
    }

    // MARK: - Rule-based formatting

    /// Detects spoken formatting commands and converts them to actual characters,
    /// then applies the chosen tone.
    func applyRuleBasedFormatting(_ text: String, tone: Tone = .formal) -> String {
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

        // Apply tone-specific transformations.
        result = applyTone(result, tone: tone)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tone application

    /// Applies capitalisation and punctuation rules based on the selected tone.
    private func applyTone(_ text: String, tone: Tone) -> String {
        var result = text

        switch tone {
        case .formal:
            // Full capitalisation + all punctuation kept as-is.
            result = capitalizeAfterSentenceEnd(result)
            if let first = result.first, first.isLetter && first.isLowercase {
                result = first.uppercased() + result.dropFirst()
            }

        case .casual:
            // Normal capitalisation, but strip some optional commas
            // (keep sentence-ending punctuation and question marks).
            result = capitalizeAfterSentenceEnd(result)
            if let first = result.first, first.isLetter && first.isLowercase {
                result = first.uppercased() + result.dropFirst()
            }

        case .veryCasual:
            // All lowercase, minimal punctuation.
            result = result.lowercased()
            // Remove periods at end of sentences (but keep ? and !).
            result = result.replacingOccurrences(
                of: "\\.(?=\\s|$)",
                with: "",
                options: .regularExpression
            )
            // Remove commas.
            result = result.replacingOccurrences(of: ",", with: "")
            // Remove semicolons and colons.
            result = result.replacingOccurrences(of: ";", with: "")
            result = result.replacingOccurrences(of: ":", with: "")
            // Clean up double spaces left by removed punctuation.
            result = result.replacingOccurrences(
                of: "  +",
                with: " ",
                options: .regularExpression
            )
        }

        return result
    }

    // MARK: - OpenAI API formatting

    /// Result from the OpenAI formatting call, including cost.
    private struct OpenAIFormatResult {
        let text: String
        let costCents: Double
    }

    /// Sends raw transcript to GPT-4o-mini for intelligent formatting.
    /// Returns nil on failure so the caller can fall back to rule-based.
    private func formatWithOpenAI(_ text: String, apiKey: String, tone: Tone = .formal) async -> OpenAIFormatResult? {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            return nil
        }

        let toneInstruction: String
        switch tone {
        case .formal:
            toneInstruction = """
            Tone: FORMAL
            - Use proper capitalisation (sentence case)
            - Use full punctuation: commas, periods, question marks, etc.
            - Example: "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you."
            """
        case .casual:
            toneInstruction = """
            Tone: CASUAL
            - Use normal capitalisation (sentence case)
            - Use lighter punctuation: keep periods and question marks, but skip optional commas
            - Example: "Hey are you free for lunch tomorrow? Let's do 12 if that works for you"
            """
        case .veryCasual:
            toneInstruction = """
            Tone: VERY CASUAL
            - Use all lowercase letters (no capitalisation at all, not even for "I")
            - Use minimal punctuation: only question marks, skip periods and most commas
            - Example: "hey are you free for lunch tomorrow? let's do 12 if that works for you"
            """
        }

        let vocabSection = VocabularyManager.shared.aiPromptSection

        let systemPrompt = """
        You are a text formatter for voice dictation. The user has spoken text into a \
        microphone and it has been transcribed. Your job is to format it properly:
        - Format bullet points or numbered lists if the speaker indicates them
        - Fix obvious transcription errors if the intended word is clear
        - Preserve the speaker's exact words and meaning
        - Return ONLY the formatted text, no explanations or preamble

        \(toneInstruction)\(vocabSection)
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

            // Calculate cost from token usage.
            // GPT-4o-mini: $0.15 per 1M input tokens, $0.60 per 1M output tokens.
            var costCents: Double = 0
            if let usage = json["usage"] as? [String: Any] {
                let inputTokens = usage["prompt_tokens"] as? Int ?? 0
                let outputTokens = usage["completion_tokens"] as? Int ?? 0
                costCents = (Double(inputTokens) * 0.015 + Double(outputTokens) * 0.06) / 1000.0
            }

            return OpenAIFormatResult(
                text: content.trimmingCharacters(in: .whitespacesAndNewlines),
                costCents: costCents
            )
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
