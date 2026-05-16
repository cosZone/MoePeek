import AppKit
import Defaults
import SwiftUI

/// Manages the lifecycle and positioning of the popup translation panel.
@MainActor
final class PopupPanelController {
    var onDismiss: (() -> Void)?

    private var panel: PopupPanel?
    private var dismissMonitor: PopupDismissMonitor?
    private var copyShortcutDismissTask: Task<Void, Never>?

    private let coordinator: TranslationCoordinator
    private let ttsCoordinator: TTSCoordinator?
    private let settingsController: SettingsWindowController?

    /// The app that was frontmost before we activated ourselves for input mode.
    private var previouslyActiveApp: NSRunningApplication?

    init(
        coordinator: TranslationCoordinator,
        ttsCoordinator: TTSCoordinator? = nil,
        settingsController: SettingsWindowController? = nil
    ) {
        self.coordinator = coordinator
        self.ttsCoordinator = ttsCoordinator
        self.settingsController = settingsController
    }

    func showAtCursor() {
        let initialSize = setupPanel()
        guard let panel else { return }

        // Coordinator auto-unpins on non-nil globalError via didSet, so checking isPinned alone is safe.
        if coordinator.isPinned, panel.isVisible {
            panel.orderFront(nil)
            startDismissMonitor()
            return
        }

        let frame: NSRect
        if let origin = restoredOrigin(for: initialSize) {
            frame = NSRect(origin: origin, size: initialSize)
        } else {
            let cursorPos = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPos) })
                ?? NSScreen.main
                ?? NSScreen.screens.first
            else { return }
            frame = PopupPositioning.panelFrame(
                contentSize: initialSize,
                cursor: cursorPos,
                screen: screen
            )
        }
        panel.setFrame(frame, display: true)
        // Non-activating: don't steal focus from the user's active app.
        // The panel will accept key events (and ⌘1...⌘9 copy shortcuts) once the user clicks
        // into it, since PopupPanel.canBecomeKey is true.
        panel.orderFront(nil)

        startDismissMonitor()
    }

    func showAtScreenCenter() {
        let initialSize = setupPanel()
        guard let panel else { return }

        let origin: NSPoint
        if let saved = restoredOrigin(for: initialSize) {
            origin = saved
        } else {
            let cursorPos = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPos) })
                ?? NSScreen.main
                ?? NSScreen.screens.first
            else { return }
            let visibleFrame = screen.visibleFrame
            origin = NSPoint(
                x: visibleFrame.midX - initialSize.width / 2,
                y: visibleFrame.midY - initialSize.height / 2
            )
        }
        panel.setFrame(NSRect(origin: origin, size: initialSize), display: true)
        // Input mode needs the app activated so the panel can receive keyboard events.
        // Without this, makeKeyAndOrderFront alone won't route keystrokes to our panel
        // because macOS keeps delivering them to the previously active app.
        // Remember the previously active app so we can restore focus after dismissal.
        previouslyActiveApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.focusSourceInput()

        startDismissMonitor()
    }

    func dismiss() {
        copyShortcutDismissTask?.cancel()
        copyShortcutDismissTask = nil
        dismissMonitor?.stop()
        dismissMonitor = nil
        ttsCoordinator?.stop()
        panel?.contentView = nil
        panel?.close()
        // Recreate panel on next show to ensure a fresh SwiftUI view tree,
        // avoiding stale @Observable state from previous translation sessions.
        panel = nil
        coordinator.dismiss()
        onDismiss?()

        // Restore focus only when MoePeek is still frontmost (user hasn't switched away manually).
        if let previousApp = previouslyActiveApp, NSRunningApplication.current.isActive {
            previousApp.activate()
        }
        previouslyActiveApp = nil
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Private

    @discardableResult
    private func setupPanel() -> CGSize {
        let initialSize = CGSize(
            width: CGFloat(Defaults[.popupDefaultWidth]),
            height: CGFloat(Defaults[.popupDefaultHeight])
        )

        if panel == nil {
            let newPanel = PopupPanel(contentRect: NSRect(origin: .zero, size: initialSize))
            newPanel.onCopyResultShortcut = { [weak self] index in
                self?.copyResultFromShortcut(atDisplayIndex: index) ?? false
            }
            let contentView = PopupView(
                coordinator: coordinator,
                onDismiss: { [weak self] in
                    self?.dismiss()
                },
                onOpenSettings: { [weak self] in
                    self?.dismiss()
                    self?.settingsController?.showWindow()
                }
            )
            .environment(\.popupPanel, newPanel)
            .environment(\.ttsCoordinator, ttsCoordinator)
            let hostingView = NSHostingView(rootView: contentView)
            // Prevent NSHostingView from auto-resizing the window on content changes,
            // which causes an infinite constraint update loop during streaming.
            hostingView.sizingOptions = []
            newPanel.contentView = hostingView
            panel = newPanel
        }

        return initialSize
    }

    private func copyResultFromShortcut(atDisplayIndex index: Int) -> Bool {
        guard coordinator.copyResult(atDisplayIndex: index) else { return false }

        copyShortcutDismissTask?.cancel()
        copyShortcutDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
        return true
    }

    /// Returns the persisted last-dragged origin if the feature is enabled and a position has been
    /// saved. The persisted point is the top-left corner, so we derive the NSWindow origin
    /// (bottom-left) by subtracting the current panel height — this keeps the visual position
    /// anchored even when the panel's width or height differs from the previously saved session.
    /// The result is clamped to the visible frame of the screen containing the saved top-left so a
    /// resized-larger panel doesn't spill off the edge.
    private func restoredOrigin(for size: CGSize) -> NSPoint? {
        guard Defaults[.popupRememberPosition], Defaults[.popupHasSavedPosition] else { return nil }
        let topLeft = NSPoint(
            x: Defaults[.popupLastTopLeftX],
            y: Defaults[.popupLastTopLeftY]
        )
        let origin = NSPoint(x: topLeft.x, y: topLeft.y - size.height)
        let candidate = NSRect(origin: origin, size: size)

        // Prefer the screen that contained the saved top-left point; otherwise any screen the
        // candidate rect still overlaps. If neither holds (e.g. external display disconnected),
        // fall back to cursor/center logic.
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(topLeft) })
            ?? NSScreen.screens.first(where: { $0.visibleFrame.intersects(candidate) })
        else { return nil }

        return clampOrigin(origin, size: size, into: screen.visibleFrame)
    }

    private func clampOrigin(_ origin: NSPoint, size: CGSize, into bounds: NSRect) -> NSPoint {
        let padding: CGFloat = 8
        let minX = bounds.minX + padding
        let maxX = bounds.maxX - size.width - padding
        let minY = bounds.minY + padding
        let maxY = bounds.maxY - size.height - padding
        // If the screen is smaller than the panel along an axis, fall back to the min edge.
        let clampedX = maxX >= minX ? min(max(origin.x, minX), maxX) : minX
        let clampedY = maxY >= minY ? min(max(origin.y, minY), maxY) : minY
        return NSPoint(x: clampedX, y: clampedY)
    }

    private func startDismissMonitor() {
        guard let panel else { return }
        dismissMonitor?.stop()
        dismissMonitor = PopupDismissMonitor(
            panel: panel,
            isPinned: { [weak self] in self?.coordinator.isPinned ?? false }
        ) { [weak self] in
            self?.dismiss()
        }
        dismissMonitor?.start()
    }
}
