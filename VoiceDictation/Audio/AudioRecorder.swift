import AVFoundation

/// Captures microphone audio using AVAudioEngine, resampling to 16 kHz mono Float32
/// — the exact format whisper.cpp requires.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let buffer = AudioBuffer()
    private var converter: AVAudioConverter?

    // Whisper requires 16 kHz mono Float32.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Public API

    func startCapture() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterCreationFailed
        }
        converter = conv

        // Frame capacity for the converter output buffer.
        // 4096 input frames / sample rate ratio gives the approximate output frame count.
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(4096) * ratio + 1)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcmBuffer, _ in
            guard let self, let conv = self.converter else { return }
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: outputCapacity) else { return }

            var conversionError: NSError?
            var inputConsumed = false

            conv.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return pcmBuffer
            }

            if conversionError == nil, let channelData = outputBuffer.floatChannelData {
                let frameCount = Int(outputBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                self.buffer.append(samples)
            }
        }

        try engine.start()
    }

    /// Stops capture and returns all accumulated samples.
    func stopCapture() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        return buffer.drain()
    }

    // MARK: - Errors

    enum RecorderError: LocalizedError {
        case converterCreationFailed

        var errorDescription: String? {
            switch self {
            case .converterCreationFailed:
                return "Could not create audio format converter. Check microphone permissions."
            }
        }
    }
}
