import AppKit
import Defaults
import SwiftUI

// MARK: - Environment Key

private struct PopupPanelKey: EnvironmentKey {
    static let defaultValue: PopupPanel? = nil
}

extension EnvironmentValues {
    var popupPanel: PopupPanel? {
        get { self[PopupPanelKey.self] }
        set { self[PopupPanelKey.self] = newValue }
    }
}

enum PopupPanelViewIdentifier {
    static let sourceInputTextView = "SourceInputTextView"
}

/// A floating, non-activating panel for showing translation results near the cursor.
final class PopupPanel: NSPanel {
    var onCopyResultShortcut: ((Int) -> Bool)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless, .resizable],
            backing: .buffered,
            defer: true
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        isReleasedWhenClosed = false
        minSize = CGSize(width: 280, height: 200)
        maxSize = CGSize(width: 800, height: 800)

        // Rounded corners
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 12
        contentView?.layer?.masksToBounds = true
    }

    // Allow becoming key window so users can select/copy text within the panel.
    override var canBecomeKey: Bool { true }

    func focusSourceInput(retries: Int = 4) {
        if focusSourceInputNow() { return }
        guard retries > 0 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.focusSourceInput(retries: retries - 1)
        }
    }

    // MARK: - Selective Window Dragging

    /// Intercepts left-mouse-down on non-interactive areas to start a window drag,
    /// while letting interactive controls (text views, buttons, gesture views) handle events normally.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let resultIndex = copyResultShortcutIndex(for: event),
           onCopyResultShortcut?(resultIndex) == true {
            return
        }

        if event.type == .leftMouseDown {
            if shouldStartWindowDrag(for: event) {
                performDrag(with: event)
                return
            }
            // Make panel key so text selection and other interactions work.
            if !isKeyWindow { makeKey() }
        }
        super.sendEvent(event)
    }

    private func copyResultShortcutIndex(for event: NSEvent) -> Int? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let disallowedFlags: NSEvent.ModifierFlags = [.shift, .option, .control]
        guard flags.contains(.command),
              flags.intersection(disallowedFlags).isEmpty,
              let characters = event.charactersIgnoringModifiers,
              characters.count == 1,
              let number = Int(characters),
              (1...9).contains(number)
        else { return nil }

        return number - 1
    }

    private func focusSourceInputNow() -> Bool {
        guard let contentView,
              let textView = findSourceInputTextView(in: contentView)
        else { return false }

        makeKey()
        return makeFirstResponder(textView)
    }

    private func shouldStartWindowDrag(for event: NSEvent) -> Bool {
        guard let contentView else { return true }
        let point = contentView.convert(event.locationInWindow, from: nil)
        guard let hitView = contentView.hitTest(point) else { return true }

        // Walk up the view hierarchy: any standard AppKit control that refuses
        // mouseDownCanMoveWindow means the user is interacting with it.
        var view: NSView? = hitView
        while let v = view, v !== contentView {
            if !v.mouseDownCanMoveWindow { return false }
            view = v.superview
        }

        // Check if the click lands on an InteractiveMarkerView (SwiftUI gesture views).
        let windowPoint = event.locationInWindow
        return !hasInteractiveMarker(in: contentView, containing: windowPoint)
    }

    private func hasInteractiveMarker(in view: NSView, containing point: NSPoint) -> Bool {
        if let marker = view as? InteractiveMarkerView {
            let rect = marker.convert(marker.bounds, to: nil)
            if rect.contains(point) { return true }
        }
        for subview in view.subviews {
            if hasInteractiveMarker(in: subview, containing: point) { return true }
        }
        return false
    }

    private func findSourceInputTextView(in view: NSView) -> NSTextView? {
        if view.identifier?.rawValue == PopupPanelViewIdentifier.sourceInputTextView,
           let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findSourceInputTextView(in: subview) {
                return textView
            }
        }

        return nil
    }
}
