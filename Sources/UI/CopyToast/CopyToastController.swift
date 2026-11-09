import AppKit
import SwiftUI

// Toast written after tinycast's HUD recipe (Tinycast/Core/HUD): one borderless never-key
// panel, reused rather than stacked, SwiftUI pill sized by `fittingSize`, window-level fades.

/// Borderless panel for a transient readout: never key, never clickable.
final class CopyToastPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        // Suppresses AppKit's own window animation; fadeIn/fadeOut replace it.
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// How the toast arrives and leaves: the window fades, on one duration pair.
private extension NSWindow {
    /// Fades the whole window — shadow included. `order` runs while the window is still invisible.
    func toastFadeIn(duration: TimeInterval, order: () -> Void) {
        alphaValue = 0
        order()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    /// Safe to interrupt: the handler checks opacity before hiding, so a re-shown toast is rescued.
    func toastFadeOut(duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        }
    }

    /// Snaps back to full opacity, replacing any running fade on the same key path.
    func toastCancelFade() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            animator().alphaValue = 1
        }
    }
}

/// The message pill. The glyph trails the message and is the tone: the message says what
/// happened, the icon only says how it went. Dark dimming over the material is what makes
/// the capsule read against any backdrop — the bare material alone renders near-invisible.
private struct MessagePillView: View {
    let message: String
    let isError: Bool

    private var iconSystemName: String {
        isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            Image(systemName: iconSystemName)
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isError ? Color.red : Color.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .fixedSize()
        .background(Color.black.opacity(0.12))
        .background(VisualEffectView(material: .popover))
        .clipShape(Capsule())
    }
}

private struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// One panel at a time, replace rather than stack, fade in, dwell, fade away.
@MainActor
final class CopyToastController {
    private var panel: CopyToastPanel?
    private var dismissal: Task<Void, Never>?

    private let dwell: TimeInterval = 1.6
    private let enterDuration: TimeInterval = 0.18
    private let exitDuration: TimeInterval = 0.12
    /// Where the panel sits above the bottom of the visible frame.
    private let edgeInset: CGFloat = 48

    /// Replaces whatever is up; the pill tracks its message via SwiftUI measurement.
    func show(message: String, isError: Bool = false) {
        let panel = self.panel ?? CopyToastPanel()
        self.panel = panel
        let host = NSHostingView(rootView: MessagePillView(message: message, isError: isError))
        // Never size from `host.frame` after attaching: AppKit resets it to the window's
        // content rect, zero on a fresh panel, and a zero-width window "centers" with its
        // leading edge on the midline.
        let content = host.fittingSize
        host.setFrameSize(content)
        panel.setContentSize(content)
        panel.contentView = host
        place(panel)
        // A panel already on screen may be mid-fade; bring it back rather than starting over.
        if panel.isVisible {
            panel.toastCancelFade()
        } else {
            panel.toastFadeIn(duration: enterDuration) { panel.orderFrontRegardless() }
        }
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            self?.panel?.toastFadeOut(duration: exitDuration)
        }
    }

    private func place(_ panel: NSPanel) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(
            NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + edgeInset))
    }
}
