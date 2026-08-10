import AppKit
import CoreGraphics

/// Detects whether a screenshot tool is mid-capture.
///
/// Region-capture tools (CleanShot X, Shottr, Cap, macOS native screenshot, …) present a
/// fullscreen overlay that swallows keyboard shortcuts. Our Tier 3 grab synthesizes `⌘C`,
/// which such an overlay interprets as *its own* "copy capture" shortcut and aborts the
/// capture flow. Callers consult this before synthesizing `⌘C` so they can skip it while a
/// capture overlay is on screen. See issue #67.
enum ScreenshotOverlayDetector {
    /// Bundle IDs of screenshot tools known to present a shortcut-capturing overlay, lowercased
    /// for case-insensitive comparison (Snipaste ships a mixed-case identifier).
    private static let captureToolBundleIDs: Set<String> = [
        "pl.maketheweb.cleanshotx",  // CleanShot X
        "com.apple.screencaptureui", // macOS native screenshot
        "cc.ffitch.shottr",          // Shottr
        "so.cap.desktop",            // Cap
        "com.zzd.xnip",              // Xnip
        "com.snipaste",              // Snipaste
    ]

    /// Fraction of a display an overlay must cover to read as an active capture. Demanding
    /// near-full coverage keeps a capture tool's *resident* windows — a Snipaste pinned
    /// screenshot, a CleanShot annotation — from registering as a capture in progress, which
    /// would disable clipboard grabbing for as long as they stayed on screen.
    private static let displayCoverageThreshold: CGFloat = 0.9

    /// True when a screenshot capture appears to be in progress.
    ///
    /// Looks for an above-normal-layer window covering a whole display, owned by either a known
    /// capture tool or the frontmost app. The frontmost check extends the fix to unlisted tools
    /// while still ignoring persistent background overlays (screen dimmers, pinned images),
    /// which never hold focus while the user is selecting text elsewhere.
    @MainActor
    static func isCapturingScreenshot() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let displays = displayRectsInWindowSpace()
        guard !displays.isEmpty else { return false }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer > 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  coversWholeDisplay(bounds, displays),
                  let pidValue = window[kCGWindowOwnerPID as String] as? Int,
                  let pid = pid_t(exactly: pidValue)
            else { continue }

            if let frontmostPID, pid == frontmostPID { return true }
            if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
               captureToolBundleIDs.contains(bundleID.lowercased()) {
                return true
            }
        }
        return false
    }

    /// `NSScreen.frame` measures from the bottom-left of the primary display while
    /// `kCGWindowBounds` measures from its top-left, so flip the screen rects before comparing.
    @MainActor
    private static func displayRectsInWindowSpace() -> [CGRect] {
        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return [] }
        return NSScreen.screens.map { screen in
            let frame = screen.frame
            return CGRect(x: frame.minX, y: primaryMaxY - frame.maxY, width: frame.width, height: frame.height)
        }
    }

    /// Compares the overlay against each display individually — a threshold derived from the
    /// largest display would miss a fullscreen overlay on a small secondary monitor.
    private static func coversWholeDisplay(_ rect: CGRect, _ displays: [CGRect]) -> Bool {
        displays.contains { display in
            let overlap = display.intersection(rect)
            return overlap.width * overlap.height >= display.width * display.height * displayCoverageThreshold
        }
    }
}
