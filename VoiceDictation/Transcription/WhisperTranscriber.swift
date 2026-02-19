import Foundation

/// Swift actor that owns a single WhisperBridge instance.
/// Being an actor guarantees serial access — whisper.cpp contexts are not thread-safe.
actor WhisperTranscriber {
    private var bridge: WhisperBridge?
    private var modelURL: URL?

    // MARK: - Model loading

    /// Call once at startup. Loads the bundled tiny.en model by default.
    func loadModel(at url: URL? = nil) {
        let target = url ?? WhisperModelManager.defaultModelURL

        guard let path = target?.path, FileManager.default.fileExists(atPath: path) else {
            print("[WhisperTranscriber] Model file not found at: \(target?.path ?? "nil")")
            return
        }

        bridge = WhisperBridge(modelPath: path)
        modelURL = target

        if bridge == nil {
            print("[WhisperTranscriber] Failed to load bridge for model at: \(path)")
        } else {
            print("[WhisperTranscriber] Model loaded: \(path)")
        }
    }

    /// Reload with a different model (e.g. after the user changes settings).
    func reloadModel(at url: URL) async {
        bridge = nil
        await loadModel(at: url)
    }

    // MARK: - Transcription

    /// Transcribes 16 kHz mono Float32 PCM samples and returns the text.
    func transcribe(_ samples: [Float], language: String = "en") async throws -> String {
        guard let bridge else {
            throw TranscriberError.modelNotLoaded
        }

        guard !samples.isEmpty else {
            return ""
        }

        // Run the blocking C call on a background executor so we don't block the actor's caller.
        return try await Task.detached(priority: .userInitiated) {
            let result = samples.withUnsafeBufferPointer { ptr -> String? in
                bridge.transcribeSamples(ptr.baseAddress!, count: ptr.count, language: language)
            }
            return result ?? ""
        }.value
    }

    // MARK: - Errors

    enum TranscriberError: LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            "Whisper model is not loaded. Please check that the model file exists in Application Support."
        }
    }
}
