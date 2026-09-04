import AppKit
import SwiftUI
import Textual

/// Renders Markdown for a translation result or a rich source. Remote images are never fetched;
/// their placeholder links copy the original URL to the clipboard when clicked. Local attachments
/// captured with the source are drawn inline only when `showsAttachments` is set.
struct MarkdownResultView: View {
    let text: String
    let font: Font
    var attachments: [String: SourceImageAttachment] = [:]
    var showsAttachments = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(MarkdownSupport.renderingSegments(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .markdown(let markdown):
                    StructuredText(markdown: MarkdownSupport.hardenLineBreaks(markdown))
                        .textual.textSelection(.enabled)
                        .textual.imageAttachmentLoader(NoRemoteImageLoader())
                case .image(let placeholder):
                    imageSegment(placeholder)
                }
            }
        }
        .font(font)
    }

    @ViewBuilder
    private func imageSegment(_ placeholder: MarkdownImagePlaceholder) -> some View {
        if let id = SourceAttachmentReference.id(from: placeholder.url) {
            if let attachment = attachments[id] {
                if showsAttachments {
                    LocalAttachmentImageView(data: attachment.data, label: id)
                        .padding(.vertical, 2)
                } else {
                    Text("🖼 \(id)")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("🖼 \(id) · \(String(localized: "Image omitted"))")
                    .foregroundStyle(.secondary)
            }
        } else {
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

private struct NoRemoteImageLoader: AttachmentLoader {
    struct Blocked: Error {}

    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> AnyAttachment {
        throw Blocked()
    }
}
