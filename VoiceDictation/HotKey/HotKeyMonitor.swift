import CoreGraphics
import Carbon.HIToolbox
import AppKit

/// Monitors for the user-configured global hotkey using a CGEventTap.
/// The tap runs on a dedicated background thread so it never blocks the main run loop.
///
/// Supports two recording modes:
/// - **Hold mode**: Hold the hotkey to record; release to stop.
/// - **Toggle mode**: Quick-tap the hotkey to start recording; tap again to stop.
///
/// The mode is determined automatically: if the key is held longer than `holdThreshold`
/// seconds before release, it's treated as a hold. If released sooner, it's a toggle.
///
/// Supports three hotkey types:
/// - Modifier + key  (e.g. ⌥Space)
/// - Modifier-only   (e.g. fn, Right ⌘)
/// - Function key     (e.g. F5)
final class HotKeyMonitor {
    private weak var appState: AppState?
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    // Prevents repeat-key events from re-triggering recording.
    var isRecording = false

    /// Tracks whether the physical key is currently pressed down.
    private var isKeyDown = false

    /// Timestamp of the most recent keyDown event (monotonic clock).
    private var keyDownTime: CFAbsoluteTime = 0

    /// When true, recording was started by a quick tap and will persist until the next tap.
    private var isToggleMode = false

    /// Duration (seconds) that distinguishes a "tap" from a "hold".
    /// If the key is held ≥ this duration, release stops recording.
    /// If released sooner, recording continues in toggle mode.
    private let holdThreshold: CFAbsoluteTime = 0.3

    /// The current hotkey configuration. Can be reloaded at runtime.
    private var hotkeyConfig: HotKeyConfiguration

    /// For modifier-only hotkeys: tracks whether another key was pressed
    /// while the modifier was held. If so, the modifier release should
    /// NOT trigger the hotkey (the user was using it as a normal modifier).
    private var otherKeyPressedDuringModifier = false

    init(appState: AppState) {
        self.appState = appState
        self.hotkeyConfig = HotKeyConfiguration.load()
    }

    /// Reloads the hotkey configuration from UserDefaults.
    /// Call this after the user changes the hotkey in Settings.
    func reloadConfiguration() {
        hotkeyConfig = HotKeyConfiguration.load()
        // Reset state when hotkey changes.
        isKeyDown = false
        isToggleMode = false
        otherKeyPressedDuringModifier = false
        print("[HotKeyMonitor] Hotkey changed to: \(hotkeyConfig.displayString)")
    }

    // MARK: - Lifecycle

    func start() {
        // Listen for keyDown, keyUp, AND flagsChanged (for modifier-only hotkeys).
        let eventMask = (1 << CGEventType.keyDown.rawValue)
                      | (1 << CGEventType.keyUp.rawValue)
                      | (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            print("[HotKeyMonitor] Failed to create CGEventTap — Input Monitoring permission likely missing.")
            Unmanaged<HotKeyMonitor>.fromOpaque(selfPtr).release()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        tapThread = Thread {
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), self.runLoopSource, .commonModes)
            CFRunLoopRun()
        }
        tapThread?.name = "com.voicedictation.eventtap"
        tapThread?.qualityOfService = .userInteractive
        tapThread?.start()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let loop = tapRunLoop {
            CFRunLoopStop(loop)
        }
        runLoopSource = nil
        eventTap = nil
    }

    // MARK: - Event handling (called from C callback)

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // ── Modifier-only hotkeys (fn, Right ⌘, etc.) ──
        if hotkeyConfig.isModifierOnly {
            return handleModifierOnlyEvent(type: type, keyCode: keyCode, flags: flags, event: event)
        }

        // ── Regular hotkeys (modifier + key) ──
        guard hotkeyConfig.matches(keyCode: keyCode, flags: flags) else {
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isRepeat { return nil }

            if !isKeyDown {
                isKeyDown = true
                keyDownTime = CFAbsoluteTimeGetCurrent()

                if isToggleMode {
                    isToggleMode = false
                    print("[HotKeyMonitor] Toggle OFF — stopping recording")
                    DispatchQueue.main.async { self.appState?.stopRecordingAndTranscribe() }
                } else {
                    print("[HotKeyMonitor] Key down — starting recording")
                    DispatchQueue.main.async { self.appState?.startRecording() }
                }
            }
            return nil  // suppress
        }

        if type == .keyUp {
            if isKeyDown {
                isKeyDown = false
                let holdDuration = CFAbsoluteTimeGetCurrent() - keyDownTime

                if isToggleMode {
                    print("[HotKeyMonitor] Key up (toggle stop already handled)")
                } else if holdDuration >= holdThreshold {
                    print("[HotKeyMonitor] Hold release (\(String(format: "%.2f", holdDuration))s) — stopping recording")
                    DispatchQueue.main.async { self.appState?.stopRecordingAndTranscribe() }
                } else {
                    isToggleMode = true
                    print("[HotKeyMonitor] Quick tap (\(String(format: "%.2f", holdDuration))s) — toggle mode ON")
                }
            }
            return nil  // suppress
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - Modifier-only handling

    /// Handles hotkeys that are a single modifier key (fn, Right ⌘, etc.).
    /// Uses flagsChanged events. If the user presses another key while the
    /// modifier is held, the release is ignored (they were using it normally).
    private func handleModifierOnlyEvent(
        type: CGEventType, keyCode: Int64, flags: CGEventFlags, event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        if type == .flagsChanged {
            // Modifier pressed down?
            if hotkeyConfig.matchesModifierDown(keyCode: keyCode, flags: flags) {
                if !isKeyDown {
                    isKeyDown = true
                    keyDownTime = CFAbsoluteTimeGetCurrent()
                    otherKeyPressedDuringModifier = false

                    if isToggleMode {
                        // Second tap → stop.
                        isToggleMode = false
                        print("[HotKeyMonitor] Modifier toggle OFF — stopping recording")
                        DispatchQueue.main.async { self.appState?.stopRecordingAndTranscribe() }
                    } else {
                        // Start recording.
                        print("[HotKeyMonitor] Modifier down — starting recording")
                        DispatchQueue.main.async { self.appState?.startRecording() }
                    }
                }
                // Don't suppress — let the modifier propagate so other apps work.
                return Unmanaged.passRetained(event)
            }

            // Modifier released?
            if hotkeyConfig.matchesModifierUp(keyCode: keyCode, flags: flags) {
                if isKeyDown {
                    isKeyDown = false
                    let holdDuration = CFAbsoluteTimeGetCurrent() - keyDownTime

                    if otherKeyPressedDuringModifier {
                        // The modifier was used with another key (e.g. ⌘C).
                        // If we started recording, cancel it.
                        if !isToggleMode {
                            print("[HotKeyMonitor] Modifier used with other key — cancelling")
                            DispatchQueue.main.async { self.appState?.cancelRecording() }
                        }
                        otherKeyPressedDuringModifier = false
                    } else if isToggleMode {
                        // Toggle-off was handled on modifier-down; nothing to do.
                        print("[HotKeyMonitor] Modifier up (toggle stop already handled)")
                    } else if holdDuration >= holdThreshold {
                        print("[HotKeyMonitor] Modifier hold release (\(String(format: "%.2f", holdDuration))s) — stopping recording")
                        DispatchQueue.main.async { self.appState?.stopRecordingAndTranscribe() }
                    } else {
                        isToggleMode = true
                        print("[HotKeyMonitor] Modifier quick tap (\(String(format: "%.2f", holdDuration))s) — toggle mode ON")
                    }
                }
                return Unmanaged.passRetained(event)
            }

            // Some other modifier changed — pass through.
            return Unmanaged.passRetained(event)
        }

        // For modifier-only hotkeys, if any regular key is pressed while the
        // modifier is held, mark it so we know the modifier was used normally.
        if type == .keyDown && isKeyDown {
            otherKeyPressedDuringModifier = true
        }

        // Pass all regular key events through unmodified.
        return Unmanaged.passRetained(event)
    }
}

// MARK: - CGEventTap C callback

/// Must be a free function (not a closure or method) to satisfy the CGEventTap callback signature.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = userInfo else { return Unmanaged.passRetained(event) }
    let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(ptr).takeUnretainedValue()

    // If the tap is disabled by the system (e.g. after a crash), re-enable it.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = monitor.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return nil
    }

    return monitor.handleEvent(type: type, event: event)
}
