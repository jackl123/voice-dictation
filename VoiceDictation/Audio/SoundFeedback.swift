import AppKit
import AVFoundation

/// Plays short synthesised audio feedback when recording starts and stops.
/// No bundled sound files needed — generates tones programmatically.
@MainActor
final class SoundFeedback {
    static let shared = SoundFeedback()

    private init() {}

    /// Whether sound feedback is enabled (read from UserDefaults).
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundFeedbackEnabled") as? Bool ?? true
    }

    // MARK: - Public API

    /// Rising two-tone to indicate recording started.
    func playStartSound() {
        guard isEnabled else { return }
        playTone(frequencies: [880, 1100], duration: 0.08)
    }

    /// Falling two-tone to indicate recording stopped.
    func playStopSound() {
        guard isEnabled else { return }
        playTone(frequencies: [1100, 880], duration: 0.08)
    }

    /// Single low tone for error / cancellation.
    func playErrorSound() {
        guard isEnabled else { return }
        playTone(frequencies: [440], duration: 0.15)
    }

    // MARK: - Tone synthesis

    private func playTone(frequencies: [Double], duration: Double) {
        let freqs = frequencies
        let dur = duration
        Task.detached(priority: .userInitiated) {
            Self.synthesiseAndPlay(frequencies: freqs, duration: dur)
        }
    }

    /// Builds a PCM buffer of sine tones and plays it through a one-shot AVAudioEngine.
    private nonisolated static func synthesiseAndPlay(frequencies: [Double], duration: Double) {
        let sampleRate: Double = 44100
        let samplesPerTone = Int(sampleRate * duration)
        let totalSamples = samplesPerTone * frequencies.count
        let fadeLen = min(100, samplesPerTone / 4)

        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(totalSamples))
        else { return }

        buf.frameLength = AVAudioFrameCount(totalSamples)
        guard let floats = buf.floatChannelData?[0] else { return }

        let amp: Float = 0.25
        var idx = 0
        for freq in frequencies {
            for i in 0..<samplesPerTone {
                var s = amp * Float(sin(2.0 * .pi * freq * Double(i) / sampleRate))
                if i < fadeLen { s *= Float(i) / Float(fadeLen) }
                if i >= samplesPerTone - fadeLen { s *= Float(samplesPerTone - 1 - i) / Float(fadeLen) }
                floats[idx] = s
                idx += 1
            }
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)

        do {
            try engine.start()
            player.play()
            player.scheduleBuffer(buf, completionHandler: nil)
            let wait = duration * Double(frequencies.count) + 0.05
            Thread.sleep(forTimeInterval: wait)
            player.stop()
            engine.stop()
        } catch {
            print("[SoundFeedback] \(error.localizedDescription)")
        }
    }
}
