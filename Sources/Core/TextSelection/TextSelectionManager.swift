import Defaults

/// Three-tier fallback strategy for grabbing selected text:
/// 1. Accessibility API (most apps)
/// 2. AppleScript (Safari-specific)
/// 3. Clipboard simulation (universal fallback)
enum TextSelectionManager {
    /// Rich capture needs ⌘C simulation, which only the full detection mode permits.
    static var isRichCaptureEnabled: Bool {
        Defaults[.captureRichText] && Defaults[.textDetectionMode] == .full
    }

    @MainActor
    static func grabSelectedText() async -> String? {
        // Tier 1: Accessibility API
        if let text = AccessibilityGrabber.grabSelectedText() {
            return text
        }

        // Tier 2: Safari AppleScript
        if let text = await AppleScriptGrabber.grabFromSafari() {
            return text
        }

        // Tier 3: Clipboard simulation
        return await ClipboardGrabber.grabViaClipboard()
    }

    /// Rich capture goes straight to the clipboard because the Accessibility API only exposes
    /// plain text. When the copy yields nothing, the plain-text tiers run as usual.
    @MainActor
    static func grabSelectedDocument() async -> RichSourceDocument? {
        if isRichCaptureEnabled, let document = await ClipboardGrabber.grabRichViaClipboard() {
            return document
        }
        return await grabSelectedText().map(RichSourceDocument.plain)
    }
}
