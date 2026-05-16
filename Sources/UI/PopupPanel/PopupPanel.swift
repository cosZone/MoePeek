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

    /// Set when `focusSourceInput()` is called before the source text view has been mounted.
    /// `SubmitAwareTextView.viewDidMoveToWindow` consumes this flag once the view attaches.
    private(set) var pendingSourceInputFocus = false

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

    /// Move first responder to the source input text view. If the text view has not
    /// been mounted yet (SwiftUI renders asynchronously), arms a one-shot flag that
    /// `SubmitAwareTextView.viewDidMoveToWindow` will consume when the view attaches.
    func focusSourceInput() {
        if let contentView, let textView = findSourceInputTextView(in: contentView) {
            makeKey()
            _ = makeFirstResponder(textView)
            return
        }
        pendingSourceInputFocus = true
    }

    /// Called by `SubmitAwareTextView` once it enters the window hierarchy.
    /// Consumes the one-shot `pendingSourceInputFocus` flag.
    /// Responder-chain mutation is deferred to the next runloop tick to avoid
    /// reentering AppKit during the `viewDidMoveToWindow` callback.
    func consumePendingSourceInputFocus(into textView: NSTextView) {
        guard pendingSourceInputFocus else { return }
        pendingSourceInputFocus = false
        Task { @MainActor [weak self, weak textView] in
            guard let self, let textView, textView.window === self else { return }
            self.makeKey()
            _ = self.makeFirstResponder(textView)
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
                if Defaults[.popupRememberPosition] {
                    // Persist the top-left corner: NSWindow.frame.origin is bottom-left in
                    // screen coordinates, so the top-left y equals origin.y + height. Storing
                    // top-left keeps the visual anchor stable across size changes between sessions.
                    let f = frame
                    Defaults[.popupLastTopLeftX] = Double(f.origin.x)
                    Defaults[.popupLastTopLeftY] = Double(f.origin.y + f.height)
                    Defaults[.popupHasSavedPosition] = true
                }
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
