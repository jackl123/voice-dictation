import SwiftUI

/// The popover content shown when the user clicks the menu bar icon.
struct StatusIndicatorView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var permissions = PermissionChecker.shared

    var body: some View {
        VStack(spacing: 16) {
            // State indicator
            stateView

            Divider()

            // Permissions section (shown if any permission is missing)
            if !permissions.microphoneGranted || !permissions.accessibilityGranted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Permissions needed")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !permissions.microphoneGranted {
                        permissionRow("Microphone") {
                            PermissionChecker.shared.requestMicrophone()
                        }
                    }
                    if !permissions.accessibilityGranted {
                        permissionRow("Accessibility & Input") {
                            PermissionChecker.shared.openAccessibilitySettings()
                        }
                    }
                }

                Divider()
            }

            // Last transcript
            VStack(alignment: .leading, spacing: 6) {
                Text("Last transcript")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(appState.lastTranscript.isEmpty ? "Nothing yet." : appState.lastTranscript)
                        .font(.body)
                        .foregroundStyle(appState.lastTranscript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 60)
            }

            Divider()

            // Footer buttons
            HStack {
                Button("Settings") {
                    openSettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Settings opener

    private func openSettings() {
        // Close the popover first so it doesn't steal focus.
        if let popover = NSApp.windows.compactMap({ $0.contentViewController?.view.window }).first {
            popover.close()
        }

        // Try the macOS 14+ selector first, then fall back to macOS 13.
        if NSApp.responds(to: Selector(("showSettingsWindow:"))) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func permissionRow(_ name: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
            Text(name)
                .font(.callout)
            Spacer()
            Button("Grant") { action() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var stateView: some View {
        HStack(spacing: 12) {
            stateIcon
            VStack(alignment: .leading, spacing: 2) {
                if !appState.modelLoaded && appState.recordingState == .idle {
                    Text("Loading model...")
                        .font(.headline)
                    Text("Please wait a moment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(appState.recordingState.statusText)
                        .font(.headline)
                    if appState.recordingState == .idle {
                        Text("Hold \u{2325}Space anywhere to dictate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        ZStack {
            Circle()
                .fill(stateColor.opacity(0.15))
                .frame(width: 36, height: 36)

            Image(systemName: stateSymbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(stateColor)
                .symbolEffect(.pulse, isActive: appState.recordingState == .recording || !appState.modelLoaded)
        }
    }

    private var stateColor: Color {
        switch appState.recordingState {
        case .idle:         return .secondary
        case .recording:    return .red
        case .transcribing: return .blue
        case .error:        return .orange
        }
    }

    private var stateSymbol: String {
        switch appState.recordingState {
        case .idle:         return "mic"
        case .recording:    return "mic.fill"
        case .transcribing: return "waveform"
        case .error:        return "exclamationmark.triangle"
        }
    }
}
