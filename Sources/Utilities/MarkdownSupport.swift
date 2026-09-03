import Foundation

struct MarkdownImagePlaceholder: Equatable {
    let label: String
    let url: URL
}

enum MarkdownRenderingSegment: Equatable {
    case markdown(String)
    case image(MarkdownImagePlaceholder)
}

/// Pure helpers that decide whether a translation result should be rendered as Markdown
/// and rewrite it into a form the renderer can display without any network access.
enum MarkdownSupport {
    private static let blockPatterns: [NSRegularExpression] = [
        #"^#{1,6}\s+\S"#,
        #"^\s*[-*+]\s+\S"#,
        #"^\s*\d+[.)]\s+\S"#,
        #"^\s*>\s?\S"#,
        #"^\s*(```|~~~)"#,
        #"^\s*\|.+\|\s*$"#,
        #"^\s*([-*_])(\s*\1){2,}\s*$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }

    private static let inlinePatterns: [NSRegularExpression] = [
        #"\*\*[^*\n]+\*\*"#,
        #"__[^_\n]+__"#,
        #"`[^`\n]+`"#,
        #"~~[^~\n]+~~"#,
        #"!?\[[^\]\n]*\]\([^)\s]+\)"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    private static let imagePattern = try! NSRegularExpression(
        pattern: #"!\[([^\]\n]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)"#
    )

    private static let blockStartPattern = try! NSRegularExpression(
        pattern: #"^\s*(#{1,6}\s|[-*+]\s|\d+[.)]\s|>|```|~~~|\||([-*_])(\s*\2){2,}\s*$)"#
    )

    static func looksLikeMarkdown(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return (blockPatterns + inlinePatterns).contains { $0.firstMatch(in: text, range: range) != nil }
    }

    /// Separates images from Textual's link interaction layer so their placeholders can be
    /// rendered as native buttons while preserving their position in the document.
    static func renderingSegments(_ text: String) -> [MarkdownRenderingSegment] {
        let nsText = text as NSString
        let matches = imagePattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return [.markdown(text)] }

        var segments: [MarkdownRenderingSegment] = []
        var cursor = 0

        func appendMarkdown(_ markdown: String) {
            guard !markdown.isEmpty else { return }
            if case .markdown(let previous) = segments.last {
                segments.removeLast()
                segments.append(.markdown(previous + markdown))
            } else {
                segments.append(.markdown(markdown))
            }
        }

        for match in matches {
            if match.range.location > cursor {
                appendMarkdown(nsText.substring(with: NSRange(
                    location: cursor,
                    length: match.range.location - cursor
                )))
            }

            let alt = nsText.substring(with: match.range(at: 1))
            let urlString = nsText.substring(with: match.range(at: 2))
            if let url = URL(string: urlString) {
                segments.append(.image(.init(
                    label: imagePlaceholderLabel(alt: alt, urlString: urlString),
                    url: url
                )))
            } else {
                appendMarkdown(nsText.substring(with: match.range))
            }
            cursor = NSMaxRange(match.range)
        }

        if cursor < nsText.length {
            appendMarkdown(nsText.substring(from: cursor))
        }
        return segments
    }

    /// LLM output uses single newlines as visual line breaks, but CommonMark folds them into
    /// spaces. Appends a hard break to plain lines followed by another plain line. Fenced code
    /// blocks and block constructs (lists, headings, tables) are left untouched.
    static func hardenLineBreaks(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        output.reserveCapacity(lines.count)
        var inFence = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                output.append(line)
                continue
            }
            guard !inFence, !trimmed.isEmpty, index + 1 < lines.count else {
                output.append(line)
                continue
            }
            let next = lines[index + 1]
            let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
            let currentIsHeadingOrTable = isMatch(#"^\s*(#{1,6}\s|\|)"#, line)
            if nextTrimmed.isEmpty || isBlockStart(next) || currentIsHeadingOrTable
                || line.hasSuffix("  ") || line.hasSuffix("\\") {
                output.append(line)
            } else {
                output.append(line + "  ")
            }
        }
        return output.joined(separator: "\n")
    }

    private static func isBlockStart(_ line: String) -> Bool {
        blockStartPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    private static func isMatch(_ pattern: String, _ line: String) -> Bool {
        line.range(of: pattern, options: .regularExpression) != nil
    }

    private static func imagePlaceholderLabel(alt: String, urlString: String) -> String {
        var label = alt.isEmpty ? String(localized: "Image") : alt
        if let host = URL(string: urlString)?.host, !host.isEmpty {
            label += " · \(host)"
        }
        return "🖼 \(label)"
    }
}
