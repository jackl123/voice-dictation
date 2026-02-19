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
    // There is no programmatic prompt for Input Monitoring on macOS 12+.
    // The system shows a dialog the first time CGEventTapCreate is called.
    // We can only direct the user to System Settings.

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
        inputMonitoringGranted = checkInputMonitoringAccess()
    }

    /// Polls every second after the user has been directed to System Settings,
    /// so the UI updates automatically when they grant the permission.
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

    private func checkInputMonitoringAccess() -> Bool {
        // IOHIDCheckAccess is the correct API on macOS 10.15+.
        // If the CGEventTap is running, Input Monitoring was granted.
        // We use a lightweight check here — the real verification happens
        // when CGEventTapCreate succeeds in HotKeyMonitor.
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        // We use AXIsProcessTrustedWithOptions as a proxy:
        // Input Monitoring is a separate permission but we check it indirectly.
        // The definitive check is whether CGEventTapCreate returns non-nil.
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == IOHIDAccessType(rawValue: 1)! // kIOHIDAccessTypeGranted
    }
}

// MARK: - IOHIDCheckAccess bridging

// IOHIDCheckAccess is a C function in IOKit. We declare it here to avoid needing
// a custom bridging header entry just for this function.
@_silgen_name("IOHIDCheckAccess")
private func IOHIDCheckAccess(_ requestType: UInt32) -> UInt32

private let kIOHIDRequestTypeListenEvent: UInt32 = 1

extension IOHIDAccessType {
    static let granted = IOHIDAccessType(rawValue: 1)!
}
