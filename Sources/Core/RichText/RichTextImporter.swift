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

        // The HTML importer is main-thread only and fetches subresources (<img>, CSS url(...),
        // <iframe>...). Everything that can reference a resource is stripped first so nothing
        // leaves the machine; RTFD is the only image source anyway.
        if let html = payload.html.flatMap(Self.strippingRemoteResources),
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

    private static let remoteResourcePatterns: [NSRegularExpression] = [
        #"<(script|style)\b[^>]*>[\s\S]*?</\1\s*>"#,
        #"<(?:img|link|script|style|iframe|frame|video|audio|source|track|object|embed|base|meta)\b[^>]*>"#,
        #"\sstyle\s*=\s*(?:"[^"]*url\([^"]*"|'[^']*url\([^']*')"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static func strippingRemoteResources(_ html: Data) -> Data? {
        guard var string = String(data: html, encoding: .utf8) ?? String(data: html, encoding: .utf16) else {
            return nil
        }
        for pattern in remoteResourcePatterns {
            string = pattern.stringByReplacingMatches(
                in: string, range: NSRange(string.startIndex..., in: string), withTemplate: ""
            )
        }
        return string.data(using: .utf8)
    }
}
