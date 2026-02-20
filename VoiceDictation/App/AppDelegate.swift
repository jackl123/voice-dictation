import AppKit
import AVFoundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var menuBarController: MenuBarController?
    private var hotKeyMonitor: HotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the app from the Dock (belt-and-suspenders alongside LSUIElement).
        NSApp.setActivationPolicy(.accessory)

        // Wire up the state machine callbacks before starting anything.
        appState.onStartRecording = { [weak self] in
            self?.hotKeyMonitor?.isRecording = true
        }

        // Set up the menu bar presence.
        menuBarController = MenuBarController(appState: appState)

        // Check permissions and guide the user if needed.
        PermissionChecker.shared.checkAll(appState: appState)

        // Start listening for the global hotkey.
        hotKeyMonitor = HotKeyMonitor(appState: appState)
        hotKeyMonitor?.start()

        // Load the Whisper model in the background so it is ready when needed.
        Task {
            await appState.transcriber.loadModel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
    }
}
