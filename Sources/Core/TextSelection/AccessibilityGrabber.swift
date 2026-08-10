import AppKit
import ApplicationServices
import os

enum AccessibilityGrabber {
    private static let log = Logger(subsystem: "com.nahida.MoePeek", category: "AccessibilityGrabber")

    /// Read the selected text from the frontmost application using the Accessibility API.
    /// Returns nil if no text is selected or the app doesn't support AX text selection.
    ///
    /// - Parameter clickPoint: If provided, validates that the click occurred within (or near)
    ///   the focused element's bounds. This filters out stale selections from distant text fields
    ///   when the user clicks on non-text elements. Uses `NSEvent.mouseLocation` coordinate space
    ///   (bottom-left origin).
    @MainActor
    static func grabSelectedText(near clickPoint: CGPoint? = nil) -> String? {
        guard let focusedElement = copyFocusedElement() else { return nil }

        var selectedValue: CFTypeRef?
        let selectResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        guard selectResult == .success, let text = selectedValue as? String, !text.isEmpty else {
            log.debug("kAXSelectedTextAttribute unavailable (status: \(selectResult.rawValue, privacy: .public))")
            return nil
        }

        // If a click point is provided, verify the click is within the focused element's bounds.
        // This prevents returning stale selected text from a distant text field when the user
        // clicks on a non-text element (button, icon, etc.).
        if let clickPoint {
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            AXUIElementCopyAttributeValue(focusedElement, kAXPositionAttribute as CFString, &positionValue)
            AXUIElementCopyAttributeValue(focusedElement, kAXSizeAttribute as CFString, &sizeValue)

            if let positionValue, let sizeValue,
               CFGetTypeID(positionValue) == AXValueGetTypeID(),
               CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                var position = CGPoint.zero
                var size = CGSize.zero
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

                // NSEvent.mouseLocation uses bottom-left origin; AX uses top-left origin
                let screenHeight = NSScreen.screens.first?.frame.height ?? 0
                let axClickY = screenHeight - clickPoint.y

                let tolerance: CGFloat = 20
                let expandedRect = CGRect(
                    x: position.x - tolerance,
                    y: position.y - tolerance,
                    width: size.width + tolerance * 2,
                    height: size.height + tolerance * 2
                )

                if !expandedRect.contains(CGPoint(x: clickPoint.x, y: axClickY)) {
                    return nil
                }
            }
        }

        return text
    }

    /// Resolve the currently focused UI element. Tries the frontmost app's element first, then
    /// falls back to the system-wide element — some apps (and newer macOS releases) expose the
    /// focused element only via the system-wide accessibility object. See issue #75.
    @MainActor
    private static func copyFocusedElement() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            log.debug("no frontmost application")
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        if let element = copyFocusedUIElement(of: appElement) {
            return element
        }
        log.debug("app-level focused element unavailable for \(frontApp.bundleIdentifier ?? "?", privacy: .public)")

        guard let element = copyFocusedUIElement(of: AXUIElementCreateSystemWide()) else {
            log.debug("system-wide focused element unavailable")
            return nil
        }

        // The system-wide object can hand back an element owned by another process — a
        // non-activating panel holding key focus, for instance. Callers scope exclusions and
        // stale-selection checks to the frontmost app, so reject anything outside it.
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element, &elementPID) == .success,
              elementPID == frontApp.processIdentifier
        else {
            log.debug("system-wide focused element belongs to another process")
            return nil
        }
        return element
    }

    private static func copyFocusedUIElement(of element: AXUIElement) -> AXUIElement? {
        var focusedValue: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            element,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusResult == .success,
              let focusedRef = focusedValue,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }

        // Safe: CFGetTypeID verified above; as?/as! cannot express CF type casts cleanly.
        return unsafeBitCast(focusedRef, to: AXUIElement.self)
    }
}
