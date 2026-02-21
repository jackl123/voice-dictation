import AppKit
import SwiftUI
import Combine

/// Manages the menu bar status item, popover, floating overlay, and settings window.
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var overlayWindow: RecordingOverlayWindow?
    private var settingsWindow: NSWindow?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
        // Popover is created lazily on first click — not eagerly —
        // so SwiftUI view construction doesn't interfere with hover events.
        observeState()
        overlayWindow = RecordingOverlayWindow(appState: appState)
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

    /// Creates the popover lazily on first use.
    private func getOrCreatePopover() -> NSPopover {
        if let popover { return popover }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 220)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: StatusIndicatorView(onOpenSettings: { [weak self] in
                self?.openSettings()
            })
            .environmentObject(appState)
        )
        self.popover = popover
        return popover
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

        let pop = getOrCreatePopover()
        if pop.isShown {
            pop.performClose(nil)
        } else {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Settings window

    func openSettings() {
        // Close the popover first.
        popover?.performClose(nil)

        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(appState)

        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "VoiceDictation Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: 520))
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
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
        case .formatting:
            symbolName = "text.badge.checkmark"
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
