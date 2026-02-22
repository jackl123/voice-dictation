import SwiftUI

/// The popover content shown when the user clicks the menu bar icon.
struct StatusIndicatorView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var permissions = PermissionChecker.shared
    @State private var showCopied = false

    /// Callback to open the settings window, provided by MenuBarController.
    var onOpenSettings: (() -> Void)?
    /// Callback to open the transcript history window.
    var onOpenHistory: (() -> Void)?

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
                HStack {
                    Text("Last transcript")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !appState.lastTranscript.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(appState.lastTranscript, forType: .string)
                            showCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopied = false
                            }
                        } label: {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(showCopied ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if let cost = appState.lastCostCents {
                        Text(costLabel(cost))
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

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
                    onOpenSettings?()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onOpenHistory?()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("History")
                    }
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
                        Text("Hold or tap \(HotKeyConfiguration.load().displayString) anywhere to dictate")
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
        case .idle:              return .secondary
        case .recording:         return .red
        case .transcribing:      return .blue
        case .formatting:        return .purple
        case .copiedToClipboard: return .green
        case .error:             return .orange
        }
    }

    /// Formats an API cost in cents into a friendly label like "Cost: <$0.01" or "Cost: $0.02".
    private func costLabel(_ cents: Double) -> String {
        let dollars = cents / 100.0
        if dollars < 0.01 {
            return "Cost: <$0.01"
        } else {
            return String(format: "Cost: $%.2f", dollars)
        }
    }

    private var stateSymbol: String {
        switch appState.recordingState {
        case .idle:              return "mic"
        case .recording:         return "mic.fill"
        case .transcribing:      return "waveform"
        case .formatting:        return "text.badge.checkmark"
        case .copiedToClipboard: return "doc.on.clipboard"
        case .error:             return "exclamationmark.triangle"
        }
    }
}
