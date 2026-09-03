import Foundation

/// Pure helpers that decide whether a translation result should be rendered as Markdown
/// and rewrite it into a form the renderer can display without any network access.
enum MarkdownSupport {
    static let imagePlaceholderScheme = "moepeek-image"

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

    static func prepareForRendering(_ text: String) -> String {
        hardenLineBreaks(rewriteImages(text))
    }

    /// Replaces `![alt](url)` with a link to a private scheme so the renderer never fetches
    /// remote images. The link label shows the alt text and the image host.
    static func rewriteImages(_ text: String) -> String {
        let nsText = text as NSString
        var result = text
        for match in imagePattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed() {
            let alt = nsText.substring(with: match.range(at: 1))
            let urlString = nsText.substring(with: match.range(at: 2))
            guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { continue }
            var label = alt.isEmpty ? String(localized: "Image") : alt
            label = label.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            if let host = URL(string: urlString)?.host, !host.isEmpty {
                label += " · \(host)"
            }
            let replacement = "[🖼 \(label)](\(imagePlaceholderScheme):\(encoded))"
            let swiftRange = Range(match.range, in: result)!
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }

    static func imageURL(fromPlaceholder url: URL) -> URL? {
        guard url.scheme == imagePlaceholderScheme else { return nil }
        let encoded = url.absoluteString.dropFirst(imagePlaceholderScheme.count + 1)
        guard let decoded = String(encoded).removingPercentEncoding else { return nil }
        return URL(string: decoded)
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
}
