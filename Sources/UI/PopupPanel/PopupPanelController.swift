import AppKit
import Defaults
import SwiftUI

/// Manages the lifecycle and positioning of the popup translation panel.
@MainActor
final class PopupPanelController {
    var onDismiss: (() -> Void)?

    private var panel: PopupPanel?
    private var dismissMonitor: PopupDismissMonitor?

    private let coordinator: TranslationCoordinator

    /// The app that was frontmost before we activated ourselves for input mode.
    /// Used to restore focus after dismissing the input panel.
    private var previouslyActiveApp: NSRunningApplication?

    init(coordinator: TranslationCoordinator) {
        self.coordinator = coordinator
    }

    func showAtCursor() {
        let initialSize = setupPanel()
        guard let panel else { return }

        let cursorPos = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPos) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        else { return }
        let frame = PopupPositioning.panelFrame(
            contentSize: initialSize,
            cursor: cursorPos,
            screen: screen
        )
        panel.setFrame(frame, display: true)
        // Non-activating: don't steal focus from the user's active app.
        panel.orderFront(nil)

        startDismissMonitor()
    }

    func showAtScreenCenter() {
        let initialSize = setupPanel()
        guard let panel else { return }

        let cursorPos = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPos) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        else { return }
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - initialSize.width / 2,
            y: visibleFrame.midY - initialSize.height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: initialSize), display: true)
        // Input mode needs the app activated so the panel can receive keyboard events.
        // Without this, makeKeyAndOrderFront alone won't route keystrokes to our panel
        // because macOS keeps delivering them to the previously active app.
        // Remember the previously active app so we can restore focus after dismissal.
        previouslyActiveApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        startDismissMonitor()
    }

    func dismiss() {
        dismissMonitor?.stop()
        dismissMonitor = nil
        panel?.contentView = nil
        panel?.close()
        // Recreate panel on next show to ensure a fresh SwiftUI view tree,
        // avoiding stale @Observable state from previous translation sessions.
        panel = nil
        coordinator.dismiss()
        onDismiss?()

        // Restore focus to the previously active app so the user's workflow isn't interrupted.
        if let previousApp = previouslyActiveApp {
            previousApp.activate(options: [])
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
            let contentView = PopupView(
                coordinator: coordinator,
                onOpenSettings: { [weak self] in
                    self?.dismiss()
                }
            )
            .environment(\.popupPanel, newPanel)
            let hostingView = NSHostingView(rootView: contentView)
            // Prevent NSHostingView from auto-resizing the window on content changes,
            // which causes an infinite constraint update loop during streaming.
            hostingView.sizingOptions = []
            newPanel.contentView = hostingView
            panel = newPanel
        }

        return initialSize
    }

    private func startDismissMonitor() {
        guard let panel else { return }
        dismissMonitor = PopupDismissMonitor(panel: panel) { [weak self] in
            self?.dismiss()
        }
        dismissMonitor?.start()
    }
}
