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
        // The panel will accept key events (and ⌘1...⌘9 copy shortcuts) once the user clicks
        // into it, since PopupPanel.canBecomeKey is true.
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
