import AppKit
import SwiftUI
import Textual

/// Renders a completed translation result as Markdown. Remote images are never fetched;
/// their placeholder links copy the original URL to the clipboard when clicked.
struct MarkdownResultView: View {
    let text: String
    let font: Font

    var body: some View {
        StructuredText(markdown: MarkdownSupport.prepareForRendering(text))
            .font(font)
            .textual.textSelection(.enabled)
            .textual.imageAttachmentLoader(NoRemoteImageLoader())
            .environment(\.openURL, OpenURLAction { url in
                guard let imageURL = MarkdownSupport.imageURL(fromPlaceholder: url) else {
                    return .systemAction
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(imageURL.absoluteString, forType: .string)
                return .handled
            })
    }
}

private struct NoRemoteImageLoader: AttachmentLoader {
    struct Blocked: Error {}

    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> AnyAttachment {
        throw Blocked()
    }
}
