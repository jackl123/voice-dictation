import AppKit
import AVFoundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var menuBarController: MenuBarController?
    private var hotKeyMonitor: HotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Wire up the state machine callbacks.
        appState.onStartRecording = { [weak self] in
            self?.hotKeyMonitor?.isRecording = true
        }

        // Set up the menu bar presence.
        menuBarController = MenuBarController(appState: appState)

        // Check permissions (deferred to avoid blocking launch).
        PermissionChecker.shared.checkAll(appState: appState)

        // Defer hotkey tap creation slightly so CGEvent.tapCreate's
        // TCC IPC doesn't block the main thread during launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.hotKeyMonitor = HotKeyMonitor(appState: self.appState)
            self.hotKeyMonitor?.start()
        }

        // Load the Whisper model on a background thread.
        let state = self.appState
        DispatchQueue.global(qos: .userInitiated).async {
            let modelURL = WhisperModelManager.defaultModelURL
            guard let path = modelURL?.path,
                  FileManager.default.fileExists(atPath: path) else {
                print("[AppDelegate] Model file not found")
                return
            }

            print("[AppDelegate] Loading model from: \(path)")
            let bridge = WhisperBridge(modelPath: path)
            let success = bridge != nil
            print("[AppDelegate] Model loaded: \(success)")

            DispatchQueue.main.async {
                if let bridge {
                    state.setBridge(bridge)
                }
                state.modelLoaded = success
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
    }
}
