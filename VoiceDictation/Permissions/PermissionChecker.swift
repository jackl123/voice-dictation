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
        refreshStatus()
    }

    // MARK: - Check all

    func checkAll(appState: AppState) {
        refreshStatus()
        startPolling()
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
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    // MARK: - Helpers

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
