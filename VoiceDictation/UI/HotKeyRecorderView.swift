import SwiftUI
import Carbon.HIToolbox
import CoreGraphics

/// Hotkey settings UI with a dropdown of presets and a custom recorder button.
struct HotKeyRecorderView: View {
    @State private var isListening = false
    @State private var currentConfig = HotKeyConfiguration.load()
    @State private var selectedPresetID: String = HotKeyConfiguration.load().matchingPresetID

    /// Called after the user records a new hotkey so the parent can react.
    var onHotkeyChanged: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Preset picker
            Picker("Hotkey", selection: $selectedPresetID) {
                ForEach(HotKeyConfiguration.presets) { preset in
                    Text(preset.label).tag(preset.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedPresetID) { _, newValue in
                if newValue == "custom" {
                    // Show the recorder — don't save yet.
                } else if let preset = HotKeyConfiguration.presets.first(where: { $0.id == newValue }) {
                    currentConfig = preset.config
                    currentConfig.save()
                    onHotkeyChanged?()
                }
            }

            // Custom recorder (shown only when "Custom..." is selected)
            if selectedPresetID == "custom" {
                HStack {
                    Text("Record custom hotkey")
                        .font(.callout)

                    Spacer()

                    HotKeyRecorderButton(
                        isListening: $isListening,
                        currentConfig: $currentConfig,
                        onHotkeyChanged: {
                            // After recording, update the preset selector.
                            selectedPresetID = currentConfig.matchingPresetID
                            onHotkeyChanged?()
                        }
                    )
                    .frame(minWidth: 120)
                }

                Text(isListening
                     ? "Press your desired key combination now... (Esc to cancel)"
                     : "Click the button above, then press your desired key combo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Current hotkey display
            HStack(spacing: 4) {
                Text("Current:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(currentConfig.displayString)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text("— hold to record, tap to toggle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - NSViewRepresentable key recorder

/// Wraps an NSButton that installs a local NSEvent monitor to capture the next
/// keyDown event (with modifiers) and saves it as the new hotkey.
struct HotKeyRecorderButton: NSViewRepresentable {
    @Binding var isListening: Bool
    @Binding var currentConfig: HotKeyConfiguration
    var onHotkeyChanged: (() -> Void)?

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: currentConfig.displayString,
            target: context.coordinator,
            action: #selector(Coordinator.buttonClicked(_:))
        )
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        if isListening {
            button.title = "Press a key..."
            button.contentTintColor = .systemRed
        } else {
            button.title = currentConfig.displayString
            button.contentTintColor = nil
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject {
        var parent: HotKeyRecorderButton
        private var eventMonitor: Any?

        init(parent: HotKeyRecorderButton) {
            self.parent = parent
        }

        deinit {
            stopListening()
        }

        @objc func buttonClicked(_ sender: NSButton) {
            if parent.isListening {
                stopListening()
                parent.isListening = false
            } else {
                startListening()
                parent.isListening = true
            }
        }

        private func startListening() {
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .flagsChanged]
            ) { [weak self] event in
                guard let self else { return event }

                if event.type == .keyDown {
                    let keyCode = Int(event.keyCode)
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                    // Convert NSEvent modifier flags to CGEventFlags.
                    var cgFlags: CGEventFlags = []
                    if flags.contains(.option)  { cgFlags.insert(.maskAlternate) }
                    if flags.contains(.command) { cgFlags.insert(.maskCommand) }
                    if flags.contains(.control) { cgFlags.insert(.maskControl) }
                    if flags.contains(.shift)   { cgFlags.insert(.maskShift) }

                    // Require at least one modifier — except for function keys.
                    let kc = Int32(keyCode)
                    if cgFlags.isEmpty {
                        let isFunctionKey = (kc >= kVK_F1 && kc <= kVK_F12) ||
                                            kc == kVK_F13 || kc == kVK_F14 ||
                                            kc == kVK_F15 || kc == kVK_F16 ||
                                            kc == kVK_F17 || kc == kVK_F18 ||
                                            kc == kVK_F19 || kc == kVK_F20
                        if !isFunctionKey {
                            return nil  // need at least one modifier
                        }
                    }

                    // Escape cancels without saving.
                    if kc == kVK_Escape {
                        self.stopListening()
                        DispatchQueue.main.async {
                            self.parent.isListening = false
                        }
                        return nil
                    }

                    // Save the new hotkey.
                    let newConfig = HotKeyConfiguration(
                        keyCode: keyCode,
                        modifierFlags: cgFlags.rawValue,
                        isModifierOnly: false
                    )
                    newConfig.save()

                    self.stopListening()
                    DispatchQueue.main.async {
                        self.parent.currentConfig = newConfig
                        self.parent.isListening = false
                        self.parent.onHotkeyChanged?()
                    }
                    return nil
                }

                // Let flagsChanged events through normally.
                return event
            }
        }

        private func stopListening() {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }
}
