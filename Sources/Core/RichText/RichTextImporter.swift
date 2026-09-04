import AppKit

/// Reads rich text from a pasteboard and turns it into a `RichSourceDocument`.
/// RTFD carries embedded images, so it wins over RTF and HTML. Plain text is the last resort.
enum RichTextImporter {
    struct Payload: Sendable {
        var rtfd: Data?
        var rtf: Data?
        var html: Data?
        var plain: String?

        var isEmpty: Bool {
            rtfd == nil && rtf == nil && html == nil && (plain?.isEmpty ?? true)
        }
    }

    @MainActor
    static func payload(from pasteboard: NSPasteboard) -> Payload? {
        let payload = Payload(
            rtfd: pasteboard.data(forType: .rtfd),
            rtf: pasteboard.data(forType: .rtf),
            html: pasteboard.data(forType: .html),
            plain: pasteboard.string(forType: .string)
        )
        return payload.isEmpty ? nil : payload
    }

    @MainActor
    static func document(from payload: Payload) async -> RichSourceDocument? {
        if let data = payload.rtfd ?? payload.rtf {
            let isRTFD = payload.rtfd != nil
            let output = await Task.detached(priority: .userInitiated) {
                let attributed = isRTFD
                    ? NSAttributedString(rtfd: data, documentAttributes: nil)
                    : NSAttributedString(rtf: data, documentAttributes: nil)
                return attributed.map { AttributedStringMarkdownConverter().convert($0) }
            }.value
            if let output, output.isRich {
                return RichSourceDocument(markdown: output.markdown, attachments: output.attachments)
            }
        }

        // The HTML importer is main-thread only and may fetch subresources, hence the timeout.
        if let html = payload.html,
           let attributed = try? NSAttributedString(
               data: html,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
                   .timeout: 2.0,
               ],
               documentAttributes: nil
           ) {
            let output = AttributedStringMarkdownConverter().convert(attributed)
            if output.isRich {
                return RichSourceDocument(markdown: output.markdown, attachments: output.attachments)
            }
        }

        guard let plain = payload.plain,
              !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return .plain(plain)
    }
}
