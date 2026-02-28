import AppKit
import Defaults
import os

enum ClipboardGrabber {
    /// Prevents concurrent pasteboard access which causes EXC_BAD_ACCESS.
    private static let isGrabbing = OSAllocatedUnfairLock(initialState: false)

    /// Tag applied to synthetic CGEvents so the keyboard monitor can distinguish
    /// our simulated ⌘+C from a real user keypress.
    private static let syntheticEventTag: Int64 = 0x4D6F6550 // "MoeP"

    /// Grab selected text by simulating ⌘+C and reading the clipboard.
    /// Saves and restores the previous clipboard content, unless an external
    /// modification (real user ⌘+C) is detected during the grab window.
    @MainActor static func grabViaClipboard() async -> String? {
        guard isGrabbing.withLock({ val in
            if val { return false }
            val = true
            return true
        }) else { return nil }
        defer { isGrabbing.withLock { $0 = false } }

        let pasteboard = NSPasteboard.general
        let previousCount = pasteboard.changeCount

        // Save current clipboard contents — preserve ALL types per item for full fidelity
        let savedItems: [[(NSPasteboard.PasteboardType, Data)]]? = pasteboard.pasteboardItems?.compactMap { item in
            let pairs = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return pairs.isEmpty ? nil : pairs
        }

        // Install a temporary keyboard monitor to detect real user ⌘+C during the grab window.
        // Our synthetic events are tagged with `syntheticEventTag` via eventSourceUserData.
        let userCopied = OSAllocatedUnfairLock(initialState: false)
        let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command),
               event.keyCode == 0x08, // 'c'
               event.cgEvent?.getIntegerValueField(.eventSourceUserData) != syntheticEventTag {
                userCopied.withLock { $0 = true }
            }
        }
        defer { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }

        // Simulate ⌘+C
        simulateCopy()

        // Wait for clipboard to update
        let timeoutMs = Defaults[.clipboardTimeout]
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)

        while pasteboard.changeCount == previousCount, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        let postCopyCount = pasteboard.changeCount
        let text = pasteboard.string(forType: .string)

        // 30ms grace period: if the user's real ⌘+C arrives slightly after our polling
        // finishes, the changeCount will bump again.
        try? await Task.sleep(for: .milliseconds(30))

        let externalModification = pasteboard.changeCount != postCopyCount || userCopied.withLock { $0 }

        // Restore previous clipboard ONLY if no external modification was detected
        if !externalModification {
            pasteboard.clearContents()
            if let savedItems {
                let items = savedItems.map { itemTypes -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in itemTypes {
                        item.setData(data, forType: type)
                    }
                    return item
                }
                pasteboard.writeObjects(items)
            }
        }
        // Otherwise skip restore — preserve the user's clipboard content

        guard let text, !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func simulateCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // 'c'
        keyDown?.flags = .maskCommand
        keyDown?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        keyUp?.post(tap: .cghidEventTap)
    }
}
