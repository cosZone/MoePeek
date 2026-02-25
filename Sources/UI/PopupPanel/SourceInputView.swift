import AppKit
import Defaults
import SwiftUI

/// Editable source text input with Enter to translate, Shift+Enter for newline.
struct SourceInputView: View {
    @Binding var text: String
    let onSubmit: () -> Void
    @Default(.popupFontSize) private var fontSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SourceTextEditor(
                text: $text,
                fontSize: CGFloat(fontSize),
                onSubmit: onSubmit
            )
                .frame(maxHeight: .infinity)
                .background { InteractiveMarker() }

            HStack(spacing: 4) {
                Spacer()

                Text("↵ Translate · ⇧↵ Newline")
                    .font(.system(size: CGFloat(fontSize - 4)))
                    .foregroundStyle(.quaternary)
            }
        }
    }
}

private struct SourceTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = SubmitAwareTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: fontSize)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.onSubmit = onSubmit

        scrollView.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            guard let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            textView.string = text
        }

        textView.font = .systemFont(ofSize: fontSize)
        textView.onSubmit = onSubmit

        if !context.coordinator.didFocusInitially {
            context.coordinator.didFocusInitially = true
            DispatchQueue.main.async {
                guard let window = textView.window else { return }
                window.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: SubmitAwareTextView?
        var didFocusInitially = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private final class SubmitAwareTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturnKey = event.keyCode == 36 || event.keyCode == 76
        let hasShift = event.modifierFlags.contains(.shift)

        if isReturnKey, !hasShift {
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }
}
