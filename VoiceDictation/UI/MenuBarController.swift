import AppKit
import SwiftUI
import Combine

/// Manages the menu bar status item and its popover.
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        setupStatusItem()
        setupPopover()
        observeState()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = menuBarImage(for: .idle)
            button.imagePosition = .imageLeft
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 220)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: StatusIndicatorView()
                .environmentObject(appState)
        )
        self.popover = popover
    }

    private func observeState() {
        appState.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateStatusItem(for: state)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Icon updates

    private func updateStatusItem(for state: RecordingState) {
        statusItem?.button?.image = menuBarImage(for: state)
        statusItem?.button?.title = ""
    }

    private func menuBarImage(for state: RecordingState) -> NSImage? {
        let symbolName: String
        switch state {
        case .idle:
            symbolName = "mic"
        case .recording:
            symbolName = "mic.fill"
        case .transcribing:
            symbolName = "waveform"
        case .error:
            symbolName = "mic.slash"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: state.statusText)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true // Adapts to light/dark menu bar automatically.
        return image
    }
}
