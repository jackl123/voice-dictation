import AppKit
import AVFoundation
import Combine

/// Checks and requests the three permissions this app needs.
/// Published properties drive the Settings UI.
final class PermissionChecker: ObservableObject {
    static let shared = PermissionChecker()

    @Published var microphoneGranted: Bool = false
    @Published var inputMonitoringGranted: Bool = false
    @Published var accessibilityGranted: Bool = false

    private var pollingTimer: Timer?

    private init() {
        // Don't check permissions eagerly — defer to checkAll() so
        // AXIsProcessTrusted() IPC doesn't block singleton construction.
    }

    // MARK: - Check all

    func checkAll(appState: AppState) {
        // Defer the first permission check so AXIsProcessTrusted() IPC
        // doesn't block the main thread during app launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshStatus()
            self?.startPolling()
        }
    }

    // MARK: - Microphone

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.microphoneGranted = granted
            }
        }
    }

    // MARK: - Input Monitoring

    func openInputMonitoringSettings() {
        openPrivacyPane("Privacy_InputMonitoring")
    }

    // MARK: - Accessibility

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    // MARK: - Refresh

    private func refreshStatus() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        // Input Monitoring: best proxy is whether Accessibility is trusted.
        // The definitive check happens when CGEventTapCreate succeeds in HotKeyMonitor.
        inputMonitoringGranted = accessibilityGranted
    }

    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    // MARK: - Helpers

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
