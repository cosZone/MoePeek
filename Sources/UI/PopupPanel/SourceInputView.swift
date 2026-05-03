import AppKit
import Defaults
import SwiftUI

/// Editable source text input with Enter to translate, Shift+Enter for newline.
struct SourceInputView: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCopyAndClose: () -> Void
    var onContentHeightChange: ((CGFloat) -> Void)?
    @Default(.popupFontSize) private var fontSize
    @Default(.popupFontName) private var fontName

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SourceTextEditor(
                text: $text,
                fontSize: CGFloat(fontSize),
                fontName: fontName,
                onSubmit: onSubmit,
                onCopyAndClose: onCopyAndClose,
                onContentHeightChange: { editorHeight in
                    onContentHeightChange?(sourceInputHeight(forEditorHeight: editorHeight))
                }
            )
                .frame(maxHeight: .infinity)
                .background { InteractiveMarker() }

            HStack(spacing: 4) {
                Spacer()

                Text("↵ Translate · ⌘↵ Copy & Close · ⇧↵ Newline")
                    .font(.popup(name: fontName, size: CGFloat(fontSize - 4)))
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private func sourceInputHeight(forEditorHeight editorHeight: CGFloat) -> CGFloat {
        let hintSize = max(CGFloat(fontSize - 4), 8)
        let hintHeight = NSFont.popup(name: fontName, size: hintSize).lineHeight
        return ceil(editorHeight + hintHeight + 8)
    }
}

private struct SourceTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let fontName: String
    let onSubmit: () -> Void
    let onCopyAndClose: () -> Void
    let onContentHeightChange: (CGFloat) -> Void

    private var resolvedFont: NSFont {
        .popup(name: fontName, size: fontSize)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false

        let contentSize = scrollView.contentSize
        let textView = SubmitAwareTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.identifier = NSUserInterfaceItemIdentifier(PopupPanelViewIdentifier.sourceInputTextView)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = coordinator
        textView.textContainerInset = .zero
        textView.onSubmit = onSubmit
        textView.onCopyAndClose = onCopyAndClose
        textView.textContainer?.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.applyDisplayAttributes(font: resolvedFont)
        textView.setExternalText(text)

        scrollView.documentView = textView
        coordinator.textView = textView
        coordinator.onContentHeightChange = onContentHeightChange

        Task { @MainActor in
            coordinator.reportContentHeight()
            coordinator.focusTextViewIfPossible()
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        let coordinator = context.coordinator
        coordinator.onContentHeightChange = onContentHeightChange
        textView.applyDisplayAttributes(font: resolvedFont)
        textView.updateLayout(for: nsView.contentSize)

        if textView.string != text {
            textView.setExternalText(text)
        }

        textView.onSubmit = onSubmit
        textView.onCopyAndClose = onCopyAndClose

        if !coordinator.didFocusInitially {
            Task { @MainActor in
                coordinator.focusTextViewIfPossible()
            }
        }

        coordinator.reportContentHeight()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: SubmitAwareTextView?
        var onContentHeightChange: ((CGFloat) -> Void)?
        var didFocusInitially = false
        private var lastReportedContentHeight: CGFloat?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? SubmitAwareTextView else { return }
            textView.refreshDisplay()
            text = textView.string
            reportContentHeight()
        }

        @discardableResult
        func focusTextViewIfPossible() -> Bool {
            guard let textView, let window = textView.window else { return false }
            let didFocus = window.makeFirstResponder(textView)
            didFocusInitially = didFocus
            return didFocus
        }

        func reportContentHeight() {
            guard let textView else { return }
            let height = textView.measuredContentHeight()
            guard lastReportedContentHeight.map({ abs($0 - height) > 0.5 }) ?? true else { return }
            lastReportedContentHeight = height
            let onContentHeightChange = onContentHeightChange
            DispatchQueue.main.async {
                onContentHeightChange?(height)
            }
        }
    }
}

private final class SubmitAwareTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCopyAndClose: (() -> Void)?
    private var displayFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize)

    func applyDisplayAttributes(font: NSFont) {
        displayFont = font
        self.font = displayFont
        textColor = .labelColor
        insertionPointColor = .labelColor
        typingAttributes = mergedTypingAttributes()
        selectedTextAttributes = [
            .foregroundColor: NSColor.selectedTextColor,
            .backgroundColor: NSColor.selectedTextBackgroundColor,
        ]
        applyDisplayAttributesToTextStorage()
        refreshDisplay()
    }

    func setExternalText(_ newValue: String) {
        string = newValue
        typingAttributes = mergedTypingAttributes()
        applyDisplayAttributesToTextStorage()
        setSelectedRange(NSRange(location: (newValue as NSString).length, length: 0))
        refreshDisplay()
    }

    func updateLayout(for contentSize: NSSize) {
        minSize = NSSize(width: 0, height: contentSize.height)
        if let textContainer {
            textContainer.containerSize = NSSize(
                width: contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
            textContainer.widthTracksTextView = true
        }
        frame.size.width = contentSize.width
        refreshDisplay()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyDisplayAttributes(font: displayFont)
    }

    override func keyDown(with event: NSEvent) {
        let isReturnKey = event.keyCode == 36 || event.keyCode == 76
        let hasShift = event.modifierFlags.contains(.shift)
        let hasCommand = event.modifierFlags.contains(.command)

        // During IME composition (e.g. Chinese Pinyin), Enter should first commit marked text.
        // Only handle Return shortcuts when composition has ended.
        if isReturnKey, hasCommand, !hasShift, !hasMarkedText() {
            guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            onCopyAndClose?()
            return
        }

        if isReturnKey, !hasCommand, !hasShift, !hasMarkedText() {
            guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }

    private func mergedTypingAttributes() -> [NSAttributedString.Key: Any] {
        var attributes = typingAttributes
        attributes[.font] = displayFont
        attributes[.foregroundColor] = NSColor.labelColor
        return attributes
    }

    private func applyDisplayAttributesToTextStorage() {
        guard let textStorage else { return }
        let range = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        if range.length > 0 {
            textStorage.addAttributes(
                [
                    .font: displayFont,
                    .foregroundColor: NSColor.labelColor,
                ],
                range: range
            )
        }
        textStorage.endEditing()
    }

    func refreshDisplay() {
        if let textContainer, let layoutManager {
            layoutManager.ensureLayout(for: textContainer)
        }
        needsDisplay = true
        setNeedsDisplay(bounds)
        enclosingScrollView?.contentView.needsDisplay = true
        enclosingScrollView?.needsDisplay = true
    }

    func measuredContentHeight() -> CGFloat {
        guard let textContainer, let layoutManager else {
            return ceil(displayFont.lineHeight)
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        return ceil(max(displayFont.lineHeight, usedHeight))
    }
}
