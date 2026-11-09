import AppKit
import Defaults
import os

enum ClipboardGrabber {
    @MainActor private static let accessGate = ClipboardAccessGate()

    /// Tag applied to synthetic CGEvents so the keyboard monitor can distinguish
    /// our simulated ⌘+C from a real user keypress.
    private static let syntheticEventTag: Int64 = 0x4D6F6550 // "MoeP"

    /// Grab selected text by simulating ⌘+C and reading the clipboard.
    @MainActor static func grabViaClipboard() async -> String? {
        await grab { pasteboard in
            pasteboard.string(forType: .string).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// Like `grabViaClipboard`, but keeps formatting and embedded images when the source app
    /// provides them. Falls back to the plain string, so nil means the copy produced nothing.
    @MainActor static func grabRichViaClipboard() async -> RichSourceDocument? {
        guard let payload = await grab(RichTextImporter.payload(from:)) else { return nil }
        return await RichTextImporter.document(from: payload)
    }

    /// Read only after any simulated copy has restored the original clipboard.
    @MainActor static func readStable<Value: Sendable>(
        _ read: @MainActor (NSPasteboard) -> Value?
    ) async -> Value? {
        await withStableAccess { read($0) }
    }

    /// Keep clipboard operations exclusive until a pending simulated copy has been restored.
    @MainActor static func withStableAccess<Value: Sendable>(
        to pasteboard: NSPasteboard = .general,
        _ access: @MainActor (NSPasteboard) async -> Value?
    ) async -> Value? {
        guard await accessGate.acquire() else { return nil }
        defer { accessGate.release() }
        return await access(pasteboard)
    }

    /// Simulates ⌘+C, hands the updated pasteboard to `read`, then restores the previous
    /// clipboard content unless an external modification (real user ⌘+C) was detected.
    @MainActor private static func grab<Value: Sendable>(
        _ read: @MainActor (NSPasteboard) -> Value?
    ) async -> Value? {
        guard await accessGate.acquire() else { return nil }
        defer { accessGate.release() }

        // Skip synthesizing ⌘C while a screenshot tool's capture overlay is on screen —
        // it would swallow the keypress as its own shortcut and abort the capture. See issue #67.
        guard !ScreenshotOverlayDetector.isCapturingScreenshot() else { return nil }

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

        guard !Task.isCancelled else { return nil }
        simulateCopy()

        // Once ⌘C has been emitted, cancellation must not abandon its delayed pasteboard write.
        // Complete the bounded wait and restoration flow, then suppress the returned value.
        let timeoutMs = Defaults[.clipboardTimeout]
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        let didChange = await waitForPasteboardChange(
            previousCount: previousCount,
            deadline: deadline,
            changeCount: { pasteboard.changeCount },
            wait: { await sleepIgnoringCancellation(for: .milliseconds(20)) }
        )

        // If changeCount didn't change, ⌘C copied nothing — don't return stale clipboard content
        guard didChange else {
            return nil
        }

        let postCopyCount = pasteboard.changeCount

        // Detect file URLs (e.g. Finder items) — only match file:// URLs,
        // not web URLs which may accompany normal text copies.
        let isFileSelection = pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )

        let value = (isFileSelection || Task.isCancelled) ? nil : read(pasteboard)

        // 30ms grace period: if the user's real ⌘+C arrives slightly after our polling
        // finishes, the changeCount will bump again.
        await sleepIgnoringCancellation(for: .milliseconds(30))

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

        return Task.isCancelled ? nil : value
    }

    @MainActor
    static func waitForPasteboardChange(
        previousCount: Int,
        deadline: Date,
        changeCount: @MainActor () -> Int,
        wait: @MainActor () async -> Void
    ) async -> Bool {
        while changeCount() == previousCount, Date() < deadline {
            await wait()
        }
        return changeCount() != previousCount
    }

    private static func sleepIgnoringCancellation(for duration: Duration) async {
        await Task.detached {
            try? await Task.sleep(for: duration)
        }.value
    }

    private static func simulateCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // 'c'
        keyDown?.flags = .maskCommand
        keyDown?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}

/// Keeps capture, snapshot reads, and writes exclusive across suspension points.
@MainActor
final class ClipboardAccessGate {
    private var isLocked = false

    func acquire() async -> Bool {
        while isLocked {
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return false
            }
        }
        guard !Task.isCancelled else { return false }
        isLocked = true
        return true
    }

    func release() {
        isLocked = false
    }
}
