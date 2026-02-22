import AppKit
import SwiftUI
import Combine

/// A small floating panel that shows recording/transcribing/formatting status
/// near the menu bar. Non-activating so it doesn't steal focus from the
/// app the user is dictating into.
final class RecordingOverlayWindow {
    private var panel: NSPanel?
    private var appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        observeState()
    }

    // MARK: - State observation

    private func observeState() {
        appState.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .recording, .transcribing, .formatting, .copiedToClipboard:
                    self?.showOverlay(for: state)
                case .idle, .error:
                    self?.hideOverlay()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Show / Hide

    private func showOverlay(for state: RecordingState) {
        if panel == nil {
            createPanel()
        }

        // Update the content for the current state.
        panel?.contentViewController = NSHostingController(
            rootView: OverlayContentView(state: state)
        )

        // Size to fit content.
        panel?.contentViewController?.view.frame.size = NSSize(width: 160, height: 40)

        positionPanel()
        panel?.orderFrontRegardless()
    }

    private func hideOverlay() {
        panel?.orderOut(nil)
    }

    // MARK: - Panel creation

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 40),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Non-activating — won't steal focus from the target app.
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        self.panel = panel
    }

    /// Position the panel centered below the menu bar.
    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let menuBarHeight: CGFloat = NSStatusBar.system.thickness
        let panelWidth: CGFloat = 160
        let panelHeight: CGFloat = 40

        // Center horizontally, just below the menu bar.
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - menuBarHeight - panelHeight - 8

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}

// MARK: - SwiftUI overlay content

private struct OverlayContentView: View {
    let state: RecordingState

    var body: some View {
        HStack(spacing: 8) {
            indicator
            Text(state.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .recording:
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
                .modifier(PulseModifier())
        case .transcribing, .formatting:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        case .copiedToClipboard:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        default:
            EmptyView()
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .recording:         return .red
        case .transcribing:      return .blue
        case .formatting:        return .purple
        case .copiedToClipboard: return .green
        default:                 return .secondary
        }
    }
}

/// Pulsing animation modifier for the recording dot.
private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
