import AppKit
import AVFoundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var menuBarController: MenuBarController?
    private var hotKeyMonitor: HotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        print("[AppDelegate] === LAUNCH START ===")

        // STEP 1: Just the menu bar icon — nothing else.
        print("[AppDelegate] Creating menu bar...")
        menuBarController = MenuBarController(appState: appState)
        print("[AppDelegate] Menu bar created.")

        // STEP 2: Defer EVERYTHING else by 2 seconds so we can test
        // whether the menu bar icon alone causes the beachball.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            print("[AppDelegate] Deferred init starting...")

            // Wire up callbacks
            self.appState.onStartRecording = { [weak self] in
                self?.hotKeyMonitor?.isRecording = true
            }

            // Permissions
            PermissionChecker.shared.checkAll(appState: self.appState)

            // Hotkey monitor
            self.hotKeyMonitor = HotKeyMonitor(appState: self.appState)
            self.hotKeyMonitor?.start()

            // Model loading
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

            print("[AppDelegate] Deferred init complete.")
        }

        print("[AppDelegate] === LAUNCH END (main sync) ===")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
    }
}
