import Foundation

/// Transcribes audio using OpenAI's Whisper API.
/// Takes 16 kHz mono Float32 PCM samples, converts to WAV,
/// and POSTs to the transcriptions endpoint.
final class OpenAITranscriber {
    static let shared = OpenAITranscriber()

    private let endpoint = "https://api.openai.com/v1/audio/transcriptions"

    private init() {}

    // MARK: - Public API

    /// Transcribe PCM samples using the OpenAI Whisper API.
    /// Returns the transcribed text, or throws on failure.
    func transcribe(_ samples: [Float], language: String = "en", apiKey: String, prompt: String? = nil) async throws -> String {
        guard !samples.isEmpty else { return "" }
        guard !apiKey.isEmpty else { throw OpenAIError.noAPIKey }

        // Convert raw PCM to WAV data.
        let wavData = createWAVData(from: samples, sampleRate: 16000)

        // Build multipart form data.
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        // File field.
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.appendString("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        body.appendString("\r\n")

        // Model field.
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendString("whisper-1\r\n")

        // Language field.
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.appendString("\(language)\r\n")

        // Response format.
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.appendString("text\r\n")

        // Vocabulary prompt (biases Whisper toward specific spellings).
        if let prompt, !prompt.isEmpty {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            body.appendString("\(prompt)\r\n")
        }

        // End boundary.
        body.appendString("--\(boundary)--\r\n")

        // Build the request.
        guard let url = URL(string: endpoint) else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[OpenAITranscriber] API error \(httpResponse.statusCode): \(errorBody)")
            throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Response format "text" returns plain text directly.
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - WAV conversion

    /// Creates a WAV file in memory from Float32 PCM samples.
    /// Converts to 16-bit PCM for compatibility with the API.
    private func createWAVData(from samples: [Float], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * Int(bitsPerSample / 8))
        let fileSize = 36 + dataSize

        var data = Data()

        // RIFF header.
        data.appendString("RIFF")
        data.appendUInt32(fileSize)
        data.appendString("WAVE")

        // fmt  sub-chunk.
        data.appendString("fmt ")
        data.appendUInt32(16)                    // Sub-chunk size.
        data.appendUInt16(1)                     // Audio format (PCM).
        data.appendUInt16(numChannels)
        data.appendUInt32(UInt32(sampleRate))
        data.appendUInt32(byteRate)
        data.appendUInt16(blockAlign)
        data.appendUInt16(bitsPerSample)

        // data sub-chunk.
        data.appendString("data")
        data.appendUInt32(dataSize)

        // Convert Float32 [-1.0, 1.0] to Int16.
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * Float(Int16.max))
            data.appendUInt16(UInt16(bitPattern: int16Value))
        }

        return data
    }

    // MARK: - Errors

    enum OpenAIError: LocalizedError {
        case noAPIKey
        case invalidURL
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No OpenAI API key configured. Add your key in Settings."
            case .invalidURL:
                return "Invalid API endpoint URL."
            case .invalidResponse:
                return "Invalid response from OpenAI API."
            case .apiError(let code, let message):
                return "OpenAI API error (\(code)): \(message)"
            }
        }
    }
}

// MARK: - Data helpers

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendUInt16(_ value: UInt16) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 2))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 4))
    }
}
