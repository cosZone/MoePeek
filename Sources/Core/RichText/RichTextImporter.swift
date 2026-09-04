import AppKit

/// Reads rich text from a pasteboard and turns it into a `RichSourceDocument`.
/// RTFD carries embedded images, so it wins over RTF and HTML. Plain text is the last resort.
/// Browsers only offer HTML, whose images are remote URLs; those become Markdown links that
/// the renderer shows as click-to-copy placeholders instead of fetching them.
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
        // <iframe>...). Images are rewritten to Markdown and every other resource reference is
        // stripped beforehand, so the importer never has a URL left to fetch.
        if let sanitized = payload.html.flatMap(Self.sanitize),
           let attributed = try? NSAttributedString(
               data: sanitized.html,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
                   .timeout: 2.0,
               ],
               documentAttributes: nil
           ) {
            let output = AttributedStringMarkdownConverter().convert(attributed)
            if output.isRich || sanitized.hasImages {
                return RichSourceDocument(markdown: output.markdown, attachments: output.attachments)
            }
        }

        guard let plain = payload.plain,
              !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return .plain(plain)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let scriptBlockPattern = regex(#"<(script|style)\b[^>]*>[\s\S]*?</\1\s*>"#)
    private static let imageTagPattern = regex(#"<img\b[^>]*>"#)
    private static let remoteResourcePatterns: [NSRegularExpression] = [
        #"<(?:img|link|script|style|iframe|frame|video|audio|source|track|object|embed|base|meta)\b[^>]*>"#,
        #"\sstyle\s*=\s*(?:"[^"]*url\([^"]*"|'[^']*url\([^']*')"#,
    ].map(regex)

    /// Rewrites `<img>` into Markdown and removes every other remote reference. Attribute values
    /// keep their HTML entities so the importer decodes them exactly once.
    private static func sanitize(_ html: Data) -> (html: Data, hasImages: Bool)? {
        guard var string = String(data: html, encoding: .utf8) ?? String(data: html, encoding: .utf16) else {
            return nil
        }
        string = replacingAll(scriptBlockPattern, in: string, with: "")

        let text = string as NSString
        let images = imageTagPattern.matches(in: string, range: NSRange(location: 0, length: text.length))
        // Splice from the end so earlier ranges stay valid; the number still counts from the start.
        for (offset, match) in images.enumerated().reversed() {
            let tag = text.substring(with: match.range)
            let markdown = " \(markdownImage(for: tag, index: offset + 1)) "
            string = (string as NSString).replacingCharacters(in: match.range, with: markdown)
        }

        for pattern in remoteResourcePatterns {
            string = replacingAll(pattern, in: string, with: "")
        }
        return string.data(using: .utf8).map { ($0, !images.isEmpty) }
    }

    /// Only http(s) sources become click-to-copy links. Anything else (`data:`, relative paths)
    /// has no URL worth showing, so it reuses the omitted-attachment placeholder.
    private static func markdownImage(for tag: String, index: Int) -> String {
        let alt = attributeValue("alt", in: tag)?
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "\n", with: " ") ?? ""
        guard let source = attributeValue("src", in: tag),
              let scheme = URL(string: source)?.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return SourceAttachmentReference.placeholder(id: SourceAttachmentReference.id(index: index))
        }
        let url = source
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
        return "![\(alt)](\(url))"
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let pattern = regex("\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")
        guard let match = pattern.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else {
            return nil
        }
        for group in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: group), in: tag) {
                return String(tag[range])
            }
        }
        return nil
    }

    private static func replacingAll(
        _ pattern: NSRegularExpression, in string: String, with template: String
    ) -> String {
        pattern.stringByReplacingMatches(
            in: string, range: NSRange(string.startIndex..., in: string), withTemplate: template
        )
    }
}
