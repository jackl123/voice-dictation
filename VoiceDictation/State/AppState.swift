import Foundation
import Combine

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case recording
    case transcribing
    case formatting
    case error(String)

    var isRecording: Bool { self == .recording }
    var isTranscribing: Bool { self == .transcribing }
    var isFormatting: Bool { self == .formatting }

    var statusText: String {
        switch self {
        case .idle:           return "Hold \u{2325}Space to dictate"
        case .recording:      return "Recording..."
        case .transcribing:   return "Transcribing..."
        case .formatting:     return "Formatting..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - AppState

/// Central state machine. All components interact through this class.
@MainActor
final class AppState: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var lastTranscript: String = ""
    @Published var permissionsGranted: Bool = false
    @Published var modelLoaded: Bool = false

    // Child components
    let recorder = AudioRecorder()
    let transcriber = WhisperTranscriber()
    let injector = TextInjector()
    let formatter = TextFormatter.shared

    // Callback hook for AppDelegate to wire additional side-effects.
    var onStartRecording: (() -> Void)?

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
        onStartRecording?()
        do {
            try recorder.startCapture()
        } catch {
            recordingState = .error(error.localizedDescription)
        }
    }

    /// Called when the user releases the hotkey.
    func stopRecordingAndTranscribe() {
        guard recordingState == .recording else { return }
        recordingState = .transcribing

        let samples = recorder.stopCapture()

        guard !samples.isEmpty else {
            recordingState = .idle
            return
        }

        Task {
            do {
                let text = try await transcriber.transcribe(samples)

                // Format the raw transcript.
                recordingState = .formatting
                let formatted = await formatter.format(text)

                let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lastTranscript = trimmed
                    injector.inject(trimmed)
                }
                recordingState = .idle
            } catch {
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
