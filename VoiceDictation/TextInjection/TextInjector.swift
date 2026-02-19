import AppKit
import CoreGraphics

/// Injects transcribed text into the currently focused application.
///
/// Strategy: clipboard injection (Cmd+V). This is the most universally compatible
/// approach — it works in native apps, Electron apps, web browsers, and terminals.
/// The original clipboard content is restored after a short delay.
final class TextInjector {

    // MARK: - Public

    func inject(_ text: String) {
        guard !text.isEmpty else { return }

        // Save current clipboard so we can restore it.
        let pasteboard = NSPasteboard.general
        let savedContents = savedClipboard(from: pasteboard)

        // Write the transcript to the clipboard.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure the clipboard write is flushed before pasting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.postPaste()
        }

        // Restore the original clipboard content after a generous delay.
        // 0.5 s gives the target app time to read the clipboard before we overwrite it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.restoreClipboard(savedContents, to: pasteboard)
        }
    }

    // MARK: - Private

    private func postPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Cmd+V key down
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand

        // Cmd+V key up
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand

        // Post at the HID level so it reaches any foreground app including Electron apps.
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Clipboard save/restore

    private struct ClipboardContents {
        let items: [[NSPasteboard.PasteboardType: Any]]
    }

    private func savedClipboard(from pasteboard: NSPasteboard) -> ClipboardContents {
        var saved: [[NSPasteboard.PasteboardType: Any]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var dict: [NSPasteboard.PasteboardType: Any] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            saved.append(dict)
        }
        return ClipboardContents(items: saved)
    }

    private func restoreClipboard(_ contents: ClipboardContents, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for itemDict in contents.items {
            let item = NSPasteboardItem()
            for (type, value) in itemDict {
                if let data = value as? Data {
                    item.setData(data, forType: type)
                }
            }
            pasteboard.writeObjects([item])
        }
    }
}
