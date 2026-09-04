import AppKit
import ImageIO

/// Converts imported rich text (RTF, RTFD, HTML) into Markdown. Formatting Markdown cannot
/// express is dropped. Images become attachment placeholders whose bytes are kept aside,
/// bounded by `Limits` so pasting a whole document cannot exhaust memory.
struct AttributedStringMarkdownConverter {
    struct Limits: Sendable {
        var maxImages = 50
        var maxTotalBytes = 50 * 1024 * 1024
    }

    struct Output: Sendable {
        let markdown: String
        let attachments: [String: SourceImageAttachment]
        let omittedImageCount: Int
        /// False when the input carried no formatting or images, so plain text should be used.
        let isRich: Bool
    }

    var limits = Limits()

    private struct Block {
        let text: String
        let isListItem: Bool
    }

    private struct State {
        let bodyFontSize: CGFloat
        var blocks: [Block] = []
        var attachments: [String: SourceImageAttachment] = [:]
        var attachmentBytes = 0
        var imageCount = 0
        var omittedImageCount = 0
        var isRich = false
    }

    private struct InlineToken {
        var text: String
        var bold = false
        var italic = false
        var code = false
        var link: URL?
        var isImage = false

        func hasSameStyle(as other: InlineToken) -> Bool {
            bold == other.bold && italic == other.italic && code == other.code && link == other.link
        }
    }

    private static let bulletMarkerPattern = try! NSRegularExpression(
        pattern: #"^(?:[•◦▪▫‣●○■□\-–—*]|\d{1,3}[.)])[ \t\x{00A0}]*"#
    )
    // Letter markers ("a.", "B)") are only stripped from ordered lists; in bullets they are text.
    private static let orderedMarkerPattern = try! NSRegularExpression(
        pattern: #"^(?:\d{1,3}[.)]|[a-zA-Z][.)])[ \t\x{00A0}]*"#
    )
    private static let bulletGlyphStartPattern = try! NSRegularExpression(
        pattern: #"^[•◦▪▫‣●○■□][ \t\x{00A0}]"#
    )

    func convert(_ attributed: NSAttributedString) -> Output {
        var state = State(bodyFontSize: Self.bodyFontSize(in: attributed))
        let string = attributed.string as NSString
        var location = 0
        while location < string.length {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            appendParagraph(attributed.attributedSubstring(from: paragraphRange), to: &state)
            location = NSMaxRange(paragraphRange)
        }

        var markdown = ""
        for (index, block) in state.blocks.enumerated() {
            if index > 0 {
                let previous = state.blocks[index - 1]
                markdown += (previous.isListItem && block.isListItem) ? "\n" : "\n\n"
            }
            markdown += block.text
        }

        return Output(
            markdown: markdown,
            attachments: state.attachments,
            omittedImageCount: state.omittedImageCount,
            isRich: state.isRich
        )
    }

    // MARK: - Paragraphs

    private func appendParagraph(_ paragraph: NSAttributedString, to state: inout State) {
        guard paragraph.length > 0 else { return }
        let style = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let listDepth = style?.textLists.count ?? 0
        let headingLevel = listDepth == 0 ? headingLevel(of: paragraph, bodyFontSize: state.bodyFontSize) : nil

        var text = renderInline(paragraph, ignoresBold: headingLevel != nil, state: &state)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let startsWithBullet = Self.bulletGlyphStartPattern.firstMatch(
            in: text, range: NSRange(text.startIndex..., in: text)
        ) != nil

        if listDepth > 0 || startsWithBullet {
            let ordered = style?.textLists.last?.isOrdered ?? false
            text = stripListMarker(from: text, ordered: ordered)
            guard !text.isEmpty else { return }
            let indent = String(repeating: "  ", count: max(listDepth - 1, 0))
            state.blocks.append(Block(text: indent + (ordered ? "1. " : "- ") + text, isListItem: true))
            state.isRich = true
        } else if let headingLevel {
            state.blocks.append(Block(text: String(repeating: "#", count: headingLevel) + " " + text, isListItem: false))
            state.isRich = true
        } else {
            state.blocks.append(Block(text: text, isListItem: false))
        }
    }

    private func stripListMarker(from text: String, ordered: Bool) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let pattern = ordered ? Self.orderedMarkerPattern : Self.bulletMarkerPattern
        guard let match = pattern.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text)
        else { return text }
        return String(text[swiftRange.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    private func headingLevel(of paragraph: NSAttributedString, bodyFontSize: CGFloat) -> Int? {
        guard paragraph.length <= 200,
              !paragraph.string.contains("\u{FFFC}"),
              let font = paragraph.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        else { return nil }
        let ratio = font.pointSize / bodyFontSize
        if ratio >= 1.8 { return 1 }
        if ratio >= 1.4 { return 2 }
        if ratio >= 1.2, font.fontDescriptor.symbolicTraits.contains(.bold) { return 3 }
        return nil
    }

    /// Most common font size by character count; headings are detected relative to it.
    private static func bodyFontSize(in attributed: NSAttributedString) -> CGFloat {
        var weights: [CGFloat: Int] = [:]
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            weights[font.pointSize, default: 0] += range.length
        }
        return weights.max { $0.value < $1.value }?.key ?? NSFont.systemFontSize
    }

    // MARK: - Inline runs

    private func renderInline(_ paragraph: NSAttributedString, ignoresBold: Bool, state: inout State) -> String {
        var tokens: [InlineToken] = []
        let fullRange = NSRange(location: 0, length: paragraph.length)

        paragraph.enumerateAttributes(in: fullRange) { attributes, range, _ in
            let runText = (paragraph.string as NSString).substring(with: range)

            if let attachment = attributes[.attachment] as? NSTextAttachment, runText.contains("\u{FFFC}") {
                if let placeholder = registerImage(attachment, state: &state) {
                    tokens.append(InlineToken(text: placeholder, isImage: true))
                }
                return
            }

            let cleaned = runText
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\u{FFFC}", with: "")
                .replacingOccurrences(of: "\r", with: "")
            guard !cleaned.isEmpty else { return }

            var token = InlineToken(text: cleaned)
            if let font = attributes[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                token.bold = traits.contains(.bold) && !ignoresBold
                token.italic = traits.contains(.italic)
                token.code = traits.contains(.monoSpace)
            }
            if let link = attributes[.link] {
                token.link = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            }
            if let last = tokens.last, last.hasSameStyle(as: token) {
                tokens[tokens.count - 1].text += token.text
            } else {
                tokens.append(token)
            }
        }

        var output = ""
        for (index, token) in tokens.enumerated() {
            guard token.isImage else {
                output += emit(token, state: &state)
                continue
            }
            if let last = output.last, !last.isWhitespace {
                output += " "
            }
            output += token.text
            if index + 1 < tokens.count, let first = tokens[index + 1].text.first, !first.isWhitespace {
                output += " "
            }
        }
        return output
    }

    private func emit(_ token: InlineToken, state: inout State) -> String {
        let text = token.text
        let core = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return text }
        let leading = String(text.prefix(while: { $0.isWhitespace }))
        let trailing = String(text.reversed().prefix(while: { $0.isWhitespace }).reversed())

        var wrapped = core
        if token.code, !core.contains("`") {
            wrapped = "`\(wrapped)`"
            state.isRich = true
        }
        if token.bold, token.italic {
            wrapped = "***\(wrapped)***"
            state.isRich = true
        } else if token.bold {
            wrapped = "**\(wrapped)**"
            state.isRich = true
        } else if token.italic {
            wrapped = "*\(wrapped)*"
            state.isRich = true
        }
        if let link = token.link, !core.contains("]") {
            wrapped = "[\(wrapped)](\(link.absoluteString))"
            state.isRich = true
        }
        return leading + wrapped + trailing
    }

    // MARK: - Images

    /// Returns the placeholder for an image attachment, storing its bytes while under the limits.
    /// Over-limit images still get a placeholder so the reader sees where they were.
    private func registerImage(_ attachment: NSTextAttachment, state: inout State) -> String? {
        guard let data = Self.imageData(from: attachment) else { return nil }
        state.imageCount += 1
        state.isRich = true
        let id = SourceAttachmentReference.id(index: state.imageCount)

        if state.attachments.count < limits.maxImages,
           state.attachmentBytes + data.count <= limits.maxTotalBytes {
            state.attachments[id] = SourceImageAttachment(id: id, data: data)
            state.attachmentBytes += data.count
        } else {
            state.omittedImageCount += 1
        }
        return SourceAttachmentReference.placeholder(id: id)
    }

    private static func imageData(from attachment: NSTextAttachment) -> Data? {
        let candidates = [attachment.fileWrapper?.regularFileContents, attachment.contents]
        for case let data? in candidates where isImageData(data) {
            return data
        }
        if let tiff = attachment.image?.tiffRepresentation, isImageData(tiff) {
            return tiff
        }
        return nil
    }

    private static func isImageData(_ data: Data) -> Bool {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
}
