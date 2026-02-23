import Foundation
import Combine

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case recording
    case transcribing
    case formatting
    case copiedToClipboard
    case error(String)

    var isRecording: Bool { self == .recording }
    var isTranscribing: Bool { self == .transcribing }
    var isFormatting: Bool { self == .formatting }

    var statusText: String {
        switch self {
        case .idle:
            let hotkey = HotKeyConfiguration.load().displayString
            return "Hold or tap \(hotkey) to dictate"
        case .recording:          return "Recording..."
        case .transcribing:       return "Transcribing..."
        case .formatting:         return "Formatting..."
        case .copiedToClipboard:  return "Copied to clipboard"
        case .error(let msg):     return "Error: \(msg)"
        }
    }
}

// MARK: - AppState

/// Central state machine. All components interact through this class.
@MainActor
final class AppState: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var lastTranscript: String = ""
    @Published var lastCostCents: Double? = nil
    @Published var permissionsGranted: Bool = false
    @Published var modelLoaded: Bool = false

    // Child components
    let recorder = AudioRecorder()
    let transcriber = WhisperTranscriber()
    let apiTranscriber = OpenAITranscriber.shared
    let injector = TextInjector()
    let formatter = TextFormatter.shared
    let soundFeedback = SoundFeedback.shared

    /// Minimum audio duration in seconds required for transcription.
    /// Anything shorter is almost certainly a mis-tap, not speech.
    private let minimumAudioDuration: Double = 0.3

    /// Patterns commonly hallucinated by small Whisper models on silence/noise.
    private let hallucinationPatterns: [String] = [
        "thank you",
        "thanks for watching",
        "subscribe",
        "like and subscribe",
        "see you next time",
        "bye",
        "the end",
        "you",
        "i'm going to",
        "so",
    ]

    /// Returns true if the transcript looks like a Whisper hallucination.
    private func isLikelyHallucination(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[.!?,]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        if cleaned.isEmpty { return true }

        // Exact match against common hallucination phrases.
        for pattern in hallucinationPatterns {
            if cleaned == pattern { return true }
        }

        return false
    }

    // Callback hook for AppDelegate to wire additional side-effects.
    var onStartRecording: (() -> Void)?

    /// Whether the app is configured to use API transcription.
    var isAPITranscriptionEnabled: Bool {
        let mode = UserDefaults.standard.string(forKey: "transcriptionMode") ?? "local"
        let apiKey = UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
        return mode == "api" && !apiKey.isEmpty
    }

    /// Called from AppDelegate after the model is loaded on a background thread.
    func setBridge(_ bridge: WhisperBridge) {
        Task {
            await transcriber.setBridge(bridge)
        }
    }

    // MARK: - Hotkey handlers

    /// Called when the user presses and holds the hotkey.
    func startRecording() {
        guard recordingState == .idle else { return }
        recordingState = .recording
        soundFeedback.playStartSound()
        onStartRecording?()
        do {
            try recorder.startCapture()
        } catch {
            soundFeedback.playErrorSound()
            recordingState = .error(error.localizedDescription)
        }
    }

    /// Cancels an in-progress recording without transcribing.
    /// Used when a modifier-only hotkey was actually used as a normal modifier
    /// (e.g. Right ⌘ was held and another key was pressed).
    func cancelRecording() {
        guard recordingState == .recording else { return }
        _ = recorder.stopCapture()  // discard samples
        recordingState = .idle
        print("[AppState] Recording cancelled")
    }

    /// Called when the user releases the hotkey.
    func stopRecordingAndTranscribe() {
        guard recordingState == .recording else { return }
        soundFeedback.playStopSound()
        recordingState = .transcribing

        let samples = recorder.stopCapture()

        // Reject empty or too-short recordings (likely a mis-tap).
        let audioDuration = Double(samples.count) / 16000.0
        guard !samples.isEmpty, audioDuration >= minimumAudioDuration else {
            recordingState = .idle
            return
        }

        Task {
            do {
                let text: String
                var costCents: Double = 0

                if isAPITranscriptionEnabled {
                    // Use OpenAI Whisper API for fast cloud transcription.
                    let apiKey = UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
                    let language = UserDefaults.standard.string(forKey: "language") ?? "en"
                    let vocabPrompt = VocabularyManager.shared.whisperPrompt
                    text = try await apiTranscriber.transcribe(samples, language: language, apiKey: apiKey, prompt: vocabPrompt.isEmpty ? nil : vocabPrompt)

                    // Whisper API costs $0.006 per minute of audio.
                    let audioMinutes = Double(samples.count) / 16000.0 / 60.0
                    costCents += audioMinutes * 0.6  // $0.006/min = 0.6 cents/min
                } else {
                    // Use local whisper.cpp.
                    let rawText = try await transcriber.transcribe(samples)

                    // Guard against Whisper hallucinations on short/noisy audio.
                    if isLikelyHallucination(rawText) {
                        print("[AppState] Discarded likely hallucination: \"\(rawText)\"")
                        recordingState = .idle
                        return
                    }
                    text = rawText
                }

                // Format the raw transcript, using a per-app tone override if configured.
                recordingState = .formatting
                let appTone = AppToneManager.shared.toneForFrontmostApp()
                let result = await formatter.formatWithCost(text, overrideTone: appTone)
                costCents += result.costCents

                let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lastTranscript = trimmed
                    lastCostCents = costCents > 0 ? costCents : nil
                    TranscriptHistoryStore.shared.addEntry(trimmed)

                    let autoPaste = UserDefaults.standard.object(forKey: "autoPasteEnabled") as? Bool ?? true
                    if autoPaste {
                        injector.inject(trimmed)
                        recordingState = .idle
                    } else {
                        injector.copyToClipboard(trimmed)
                        recordingState = .copiedToClipboard
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if recordingState == .copiedToClipboard {
                            recordingState = .idle
                        }
                    }
                } else {
                    recordingState = .idle
                }
            } catch {
                soundFeedback.playErrorSound()
                recordingState = .error(error.localizedDescription)
                // Auto-clear error after 3 seconds.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if case .error = recordingState {
                    recordingState = .idle
                }
            }
        }
    }
}
