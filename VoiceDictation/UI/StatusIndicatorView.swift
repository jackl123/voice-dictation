import SwiftUI

/// The popover content shown when the user clicks the menu bar icon.
struct StatusIndicatorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            // State indicator
            stateView

            Divider()

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
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
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

    @ViewBuilder
    private var stateView: some View {
        HStack(spacing: 12) {
            stateIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.recordingState.statusText)
                    .font(.headline)
                if appState.recordingState == .idle {
                    Text("Hold ⌥Space anywhere to dictate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                .symbolEffect(.pulse, isActive: appState.recordingState == .recording)
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
