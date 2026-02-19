import Foundation

/// Thread-safe accumulator for raw PCM Float32 samples.
/// Written to from the AVAudioEngine tap thread, drained from the main/transcription thread.
final class AudioBuffer {
    private var samples: [Float] = []
    private var lock = os_unfair_lock()

    func append(_ newSamples: [Float]) {
        os_unfair_lock_lock(&lock)
        samples.append(contentsOf: newSamples)
        os_unfair_lock_unlock(&lock)
    }

    /// Atomically returns all accumulated samples and resets the buffer.
    func drain() -> [Float] {
        os_unfair_lock_lock(&lock)
        let result = samples
        samples = []
        os_unfair_lock_unlock(&lock)
        return result
    }

    var count: Int {
        os_unfair_lock_lock(&lock)
        let c = samples.count
        os_unfair_lock_unlock(&lock)
        return c
    }
}
