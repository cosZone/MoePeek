import AppKit
import Defaults

enum ClipboardGrabber {
    /// Grab selected text by simulating ⌘+C and reading the clipboard.
    /// Saves and restores the previous clipboard content.
    static func grabViaClipboard() async -> String? {
        let pasteboard = NSPasteboard.general
        let previousCount = pasteboard.changeCount
        // Save current clipboard contents
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
            guard let type = item.types.first, let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data)
        }

        // Simulate ⌘+C
        simulateCopy()

        // Wait for clipboard to update
        let timeoutMs = Defaults[.clipboardTimeout]
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)

        while pasteboard.changeCount == previousCount, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        let text = pasteboard.string(forType: .string)

        // Restore previous clipboard
        pasteboard.clearContents()
        if let savedItems {
            for (typeRaw, data) in savedItems {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
            }
        }

        guard let text, !text.isEmpty, pasteboard.changeCount != previousCount || !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func simulateCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // 'c'
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
