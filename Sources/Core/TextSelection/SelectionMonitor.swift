import AppKit
import Defaults

/// Monitors global mouse events and detects text selection via 3-tier fallback:
/// AX API → AppleScript (Safari) → Clipboard (⌘C simulation).
/// Tier 2-3 only trigger on drag or multi-click to avoid invasive clipboard access on plain clicks.
@MainActor
final class SelectionMonitor {
    var onTextSelected: ((String, CGPoint) -> Void)?
    var onMouseDown: ((CGPoint) -> Void)?

    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var mouseDownMonitor: Any?
    private var mouseDownPoint: CGPoint?
    private var isSuppressed = false
    nonisolated(unsafe) private var suppressTask: Task<Void, Never>?
    private var grabTask: Task<Void, Never>?

    deinit {
        if let monitor = mouseDownMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        suppressTask?.cancel()
        grabTask?.cancel()
    }

    func start() {
        guard globalMonitor == nil else { return }
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let screenPoint = NSEvent.mouseLocation
            Task { @MainActor in
                self?.mouseDownPoint = screenPoint
                self?.onMouseDown?(screenPoint)
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            let screenPoint = NSEvent.mouseLocation
            let clickCount = event.clickCount
            Task { @MainActor in
                self?.handleMouseUp(at: screenPoint, clickCount: clickCount)
            }
        }
    }

    func stop() {
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        suppressTask?.cancel()
        suppressTask = nil
        grabTask?.cancel()
        grabTask = nil
    }

    /// Suppress detection for 0.5s — called after dismissing popup/icon to prevent re-trigger.
    func suppressBriefly() {
        isSuppressed = true
        suppressTask?.cancel()
        suppressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.isSuppressed = false
        }
    }

    private func handleMouseUp(at point: CGPoint, clickCount: Int) {
        guard Defaults[.isAutoDetectEnabled], !isSuppressed else { return }

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        guard !Defaults[.excludedAppBundleIDs].contains(frontBundleID) else { return }

        let isFinderFrontmost = frontBundleID == "com.apple.finder"
        let mode = Defaults[.textDetectionMode]

        // Determine if the gesture looks like a text selection (drag or multi-click)
        var wasDragOrMultiClick = clickCount >= 2
        if !wasDragOrMultiClick, let downPoint = mouseDownPoint {
            let dx = point.x - downPoint.x
            let dy = point.y - downPoint.y
            let distance = sqrt(dx * dx + dy * dy)
            wasDragOrMultiClick = distance > 5
        }
        mouseDownPoint = nil

        grabTask?.cancel()
        grabTask = Task { @MainActor [weak self] in
            // Snapshot clipboard state at mouse-up so we can detect if the user
            // presses ⌘+C during the wait / Tier 1-2 evaluation window.
            let clipboardCountAtMouseUp = NSPasteboard.general.changeCount

            // Wait 100ms for the target app to update its AX selection state
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, !Task.isCancelled else { return }

            // Tier 1: Accessibility API — fast, non-invasive
            if self.deliver(AccessibilityGrabber.grabSelectedText(near: point), at: point) { return }

            // Only attempt fallback tiers if the gesture looks like a selection
            guard wasDragOrMultiClick else { return }

            // Double-click word selection updates the AX selection with a delay; the first
            // Tier 1 read can miss it and fall through to the clipboard tiers, which may
            // surface stale clipboard content instead. Retry Tier 1 once. See issue #59.
            if clickCount >= 2 {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                if self.deliver(AccessibilityGrabber.grabSelectedText(near: point), at: point) { return }
            }

            // Conservative mode: only AX API, stop here
            guard mode != .conservative else { return }

            // Tier 2: AppleScript — Safari-specific JS selection (Finder won't match)
            if self.deliver(await AppleScriptGrabber.grabFromSafari(), at: point) { return }

            guard !Task.isCancelled else { return }

            // Tier 3 gate: require full mode, exclude Finder
            guard mode == .full, !isFinderFrontmost else { return }

            // Short-circuit before Tier 3: if the clipboard changed since mouse-up,
            // the user already pressed ⌘+C — read directly without simulating another copy.
            if NSPasteboard.general.changeCount != clipboardCountAtMouseUp {
                // If the clipboard currently contains file URLs, treat it as non-text selection.
                if NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
                    return
                }

                if self.deliver(NSPasteboard.general.string(forType: .string), at: point) { return }
            }

            // Tier 3: Clipboard — simulate ⌘C, read pasteboard, restore
            _ = self.deliver(await ClipboardGrabber.grabViaClipboard(), at: point)
        }
    }

    /// Hands `text` to `onTextSelected` when it carries non-whitespace content, keeping the
    /// acceptance rule every grab tier shares in one place. Returns true when delivered.
    private func deliver(_ text: String?, at point: CGPoint) -> Bool {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        onTextSelected?(text, point)
        return true
    }
}
