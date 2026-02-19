import Foundation
import Combine

/// Manages whisper.cpp model files on disk.
/// Models are stored in ~/Library/Application Support/VoiceDictation/models/
final class WhisperModelManager: ObservableObject {
    static let shared = WhisperModelManager()

    // MARK: - Paths

    private static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("VoiceDictation/models", isDirectory: true)
    }

    /// The default model URL. First looks in the app bundle (for bundled tiny.en),
    /// then falls back to Application Support.
    static var defaultModelURL: URL? {
        // 1. Check the app bundle (set this up in Xcode: drag ggml-tiny.en.bin into Resources).
        if let bundled = Bundle.main.url(forResource: "ggml-tiny.en", withExtension: "bin") {
            return bundled
        }
        // 2. Fall back to Application Support.
        let appSupportURL = modelsDirectory.appendingPathComponent("ggml-tiny.en.bin")
        if FileManager.default.fileExists(atPath: appSupportURL.path) {
            return appSupportURL
        }
        return nil
    }

    // MARK: - Download

    private let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    @Published var downloadProgress: Double = 0
    @Published var isDownloading: Bool = false
    @Published var downloadError: String?

    private var downloadTask: URLSessionDownloadTask?

    func isModelDownloaded(named name: String) -> Bool {
        let url = WhisperModelManager.modelsDirectory.appendingPathComponent("ggml-\(name).bin")
        return FileManager.default.fileExists(atPath: url.path)
    }

    func downloadModel(named name: String) {
        guard !isDownloading else { return }
        guard let url = URL(string: "\(baseURL)/ggml-\(name).bin") else { return }

        do {
            try FileManager.default.createDirectory(
                at: WhisperModelManager.modelsDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            downloadError = error.localizedDescription
            return
        }

        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        let destination = WhisperModelManager.modelsDirectory.appendingPathComponent("ggml-\(name).bin")

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
        downloadTask = session.downloadTask(with: url) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                self?.isDownloading = false
                if let error {
                    self?.downloadError = error.localizedDescription
                    return
                }
                guard let tempURL else { return }
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    self?.downloadProgress = 1.0
                } catch {
                    self?.downloadError = error.localizedDescription
                }
            }
        }

        // Track download progress via observation.
        downloadTask?.progress.addObserver(
            ProgressObserver { [weak self] progress in
                DispatchQueue.main.async { self?.downloadProgress = progress }
            },
            forKeyPath: "fractionCompleted",
            options: .new,
            context: nil
        )

        downloadTask?.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        isDownloading = false
    }
}

// MARK: - KVO helper

private final class ProgressObserver: NSObject {
    let handler: (Double) -> Void
    init(_ handler: @escaping (Double) -> Void) { self.handler = handler }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if let progress = (object as? Progress)?.fractionCompleted {
            handler(progress)
        }
    }
}
