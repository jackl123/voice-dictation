import Combine
import ServiceManagement
import SwiftUI

/// Manages the "Launch at Login" setting using SMAppService (macOS 13+).
@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published var isEnabled: Bool {
        didSet {
            if isEnabled {
                enable()
            } else {
                disable()
            }
        }
    }

    private init() {
        // Read current registration state.
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Refreshes the published state from the system.
    func refresh() {
        let status = SMAppService.mainApp.status
        let enabled = status == .enabled
        if isEnabled != enabled {
            // Avoid triggering didSet by setting the backing storage directly.
            isEnabled = enabled
        }
    }

    private func enable() {
        do {
            try SMAppService.mainApp.register()
            print("[LaunchAtLogin] Registered for launch at login")
        } catch {
            print("[LaunchAtLogin] Failed to register: \(error.localizedDescription)")
            // Revert UI state without re-triggering didSet.
            Task { @MainActor in
                isEnabled = false
            }
        }
    }

    private func disable() {
        do {
            try SMAppService.mainApp.unregister()
            print("[LaunchAtLogin] Unregistered from launch at login")
        } catch {
            print("[LaunchAtLogin] Failed to unregister: \(error.localizedDescription)")
        }
    }
}
