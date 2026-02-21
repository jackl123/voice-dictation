import Foundation

/// Swift actor that owns a single WhisperBridge instance.
/// Being an actor guarantees serial access — whisper.cpp contexts are not thread-safe.
actor WhisperTranscriber {
    private var bridge: WhisperBridge?
    private var modelURL: URL?
    private(set) var isModelLoaded: Bool = false

    // MARK: - Model loading

    /// Accept a pre-loaded WhisperBridge from outside the actor.
    /// The heavy model loading is done on a GCD background queue in AppDelegate,
    /// so by the time this is called the bridge is ready.
    func setBridge(_ loadedBridge: WhisperBridge) {
        bridge = loadedBridge
        isModelLoaded = true
        print("[WhisperTranscriber] Bridge set, model is ready")
    }

    /// Reload with a different model (e.g. after the user changes settings).
    func reloadModel(at url: URL) async {
        bridge = nil
        isModelLoaded = false

        guard let path = url.path as String?,
              FileManager.default.fileExists(atPath: path) else {
            print("[WhisperTranscriber] Model file not found at: \(url.path)")
            return
        }

        let loadedBridge = await Task.detached(priority: .userInitiated) {
            return WhisperBridge(modelPath: path)
        }.value

        bridge = loadedBridge
        isModelLoaded = (bridge != nil)
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
        return await Task.detached(priority: .userInitiated) {
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
