import AppKit
import Defaults

// MARK: - TriggerTrackingView

/// A circular icon view with mouse tracking for hover and click detection.
@MainActor
final class TriggerTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onMouseDown: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 1, dy: 1)

        // Circle background
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.fillEllipse(in: rect)

        // Border
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.strokeEllipse(in: rect)

        // SF Symbol icon
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: .labelColor)
        if let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Translate")?
            .withSymbolConfiguration(sizeConfig.applying(colorConfig))
        {
            let imageSize = image.size
            let imageRect = NSRect(
                x: (bounds.width - imageSize.width) / 2,
                y: (bounds.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}

// MARK: - TriggerIconController

/// Manages the trigger icon lifecycle: show near cursor, hover/click to translate, auto-dismiss.
@MainActor
final class TriggerIconController {
    var onTranslateRequested: ((String) -> Void)?
    var onDismissed: (() -> Void)?

    private var panel: TriggerIconPanel?
    private var trackingView: TriggerTrackingView?
    private var currentText: String = ""
    private var hoverTimer: Timer?
    private var autoDismissTimer: Timer?

    /// Show the trigger icon near the given screen point.
    /// If already visible, silently replace without triggering suppress.
    func show(text: String, near point: CGPoint) {
        // Silently close any existing icon (no dismiss callback)
        dismissSilently()

        currentText = text

        let panel = TriggerIconPanel()
        let trackingView = TriggerTrackingView(frame: NSRect(x: 0, y: 0, width: TriggerIconPanel.size, height: TriggerIconPanel.size))

        let activationMode = Defaults[.triggerActivationMode]

        trackingView.onMouseEntered = { [weak self] in
            guard let self else { return }
            switch activationMode {
            case .hover:
                self.startHoverTimer()
            case .click:
                // Pause auto-dismiss while cursor is over the icon so the user has time to click.
                self.cancelAutoDismissTimer()
            }
        }
        trackingView.onMouseExited = { [weak self] in
            guard let self else { return }
            switch activationMode {
            case .hover:
                self.cancelHoverTimer()
            case .click:
                // In click mode, mouseEntered paused auto-dismiss; restart it on exit
                // so the icon eventually disappears if the user never clicks.
                self.startAutoDismissTimer()
            }
        }
        trackingView.onMouseDown = { [weak self] in
            self?.triggerTranslation()
        }

        panel.contentView = trackingView

        // Position: offset to the right and below the cursor
        let offset: CGFloat = 8
        let size = TriggerIconPanel.size
        var x = point.x + offset
        var y = point.y - offset - size

        // Adjust for screen bounds
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            if x + size > visibleFrame.maxX { x = point.x - size - offset }
            if y + size > visibleFrame.maxY { y = point.y - size - offset }
            if x < visibleFrame.minX { x = visibleFrame.minX }
            if y < visibleFrame.minY { y = visibleFrame.minY }
        }

        panel.setFrame(NSRect(x: x, y: y, width: size, height: size), display: true)
        panel.alphaValue = 0
        panel.orderFront(nil)

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        self.trackingView = trackingView

        startAutoDismissTimer()
    }

    /// Dismiss the icon with fade-out and notify via onDismissed.
    func dismiss() {
        guard let panel else { return }
        cancelAllTimers()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.contentView = nil
                panel.close()
                self?.cleanup()
                self?.onDismissed?()
            }
        })
    }

    /// Dismiss silently — used when replacing with a new icon. Does NOT trigger onDismissed.
    func dismissSilently() {
        guard let panel else { return }
        cancelAllTimers()
        panel.contentView = nil
        panel.close()
        cleanup()
    }

    private func cleanup() {
        panel = nil
        trackingView = nil
        currentText = ""
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Timers

    private func startHoverTimer() {
        cancelHoverTimer()
        cancelAutoDismissTimer()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.triggerTranslation()
            }
        }
    }

    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func startAutoDismissTimer() {
        cancelAutoDismissTimer()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func cancelAutoDismissTimer() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }

    private func cancelAllTimers() {
        cancelHoverTimer()
        cancelAutoDismissTimer()
    }

    private func triggerTranslation() {
        let text = currentText
        cancelAllTimers()

        guard let panel else { return }
        // Immediately hide the icon
        panel.contentView = nil
        panel.close()
        cleanup()

        onTranslateRequested?(text)
    }
}
