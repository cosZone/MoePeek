import AppKit
import SwiftUI
import Textual

/// Renders a completed translation result as Markdown. Remote images are never fetched;
/// their placeholder links copy the original URL to the clipboard when clicked.
struct MarkdownResultView: View {
    let text: String
    let font: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(MarkdownSupport.renderingSegments(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .markdown(let markdown):
                    StructuredText(markdown: MarkdownSupport.hardenLineBreaks(markdown))
                        .textual.textSelection(.enabled)
                        .textual.imageAttachmentLoader(NoRemoteImageLoader())
                case .image(let placeholder):
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(placeholder.url.absoluteString, forType: .string)
                    } label: {
                        Text(placeholder.label)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(placeholder.label)
                }
            }
        }
        .font(font)
    }
}

private struct NoRemoteImageLoader: AttachmentLoader {
    struct Blocked: Error {}

    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> AnyAttachment {
        throw Blocked()
    }
}
