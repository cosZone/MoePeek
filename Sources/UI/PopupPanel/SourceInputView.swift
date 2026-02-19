import SwiftUI

/// Editable source text input with Enter to translate, Shift+Enter for newline.
struct SourceInputView: View {
    @Binding var text: String
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $text)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .frame(minHeight: 36, maxHeight: 80)
                .fixedSize(horizontal: false, vertical: true)
                .onKeyPress(phases: .down) { press in
                    guard press.key == .return else { return .ignored }
                    if press.modifiers.contains(.shift) {
                        return .ignored // Let TextEditor handle Shift+Enter as newline
                    }
                    onSubmit()
                    return .handled
                }

            HStack(spacing: 4) {
                Spacer()

                Text("↵ Translate · ⇧↵ Newline")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        // SwiftUI requires at least one layout pass before @FocusState can take effect;
        // a short yield lets the hosting view finish its initial layout.
        .task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            isFocused = true
        }
    }
}
