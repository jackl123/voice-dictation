import CoreGraphics
import Carbon.HIToolbox
import AppKit

/// Monitors for the Option+Space global hotkey using a CGEventTap.
/// The tap runs on a dedicated background thread so it never blocks the main run loop.
final class HotKeyMonitor {
    private weak var appState: AppState?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    // Prevents repeat-key events from re-triggering recording.
    var isRecording = false
    private var isHeld = false

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Lifecycle

    func start() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        // We pass an unretained pointer to self as the userInfo so the C callback can reach us.
        // The tap keeps the process alive as long as it is installed, so no retain cycle issue.
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEventTap.create(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            print("[HotKeyMonitor] Failed to create CGEventTap — Input Monitoring permission likely missing.")
            // Release the retained self since the tap was never installed.
            Unmanaged<HotKeyMonitor>.fromOpaque(selfPtr).release()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        // Run the tap on a dedicated background thread with its own CFRunLoop.
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
        // Only act on Space key with Option modifier, without Command/Control/Shift.
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let isOptionSpace = (keyCode == kVK_Space) &&
                            flags.contains(.maskAlternate) &&
                            !flags.contains(.maskCommand) &&
                            !flags.contains(.maskControl) &&
                            !flags.contains(.maskShift)

        guard isOptionSpace else {
            // Not our hotkey — pass the event through unmodified.
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isRepeat && !isHeld {
                isHeld = true
                DispatchQueue.main.async {
                    self.appState?.startRecording()
                }
            }
            // Suppress the event so "˙" or Spotlight doesn't appear.
            return nil
        }

        if type == .keyUp {
            if isHeld {
                isHeld = false
                DispatchQueue.main.async {
                    self.appState?.stopRecordingAndTranscribe()
                }
            }
            // Suppress the key-up as well.
            return nil
        }

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
