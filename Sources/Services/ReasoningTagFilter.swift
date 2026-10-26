import Foundation

/// Incrementally strips leading reasoning blocks (e.g. `<thought>…</thought>` from Gemma
/// on Google AI Studio, `<think>…</think>` from DeepSeek-R1 / Qwen) out of a streamed
/// LLM response, so only the final answer reaches the UI.
///
/// Only blocks at the very start of the response (ignoring whitespace) are removed; a tag
/// appearing later is treated as regular content, which keeps translations of XML/HTML
/// text intact. Tags split across chunk boundaries are handled by holding back output
/// until the prefix is unambiguous.
struct ReasoningTagFilter {
    private static let tagPairs: [(open: String, close: String)] = [
        ("<thought>", "</thought>"),
        ("<thinking>", "</thinking>"),
        ("<think>", "</think>"),
    ]

    private enum State {
        /// Still deciding whether the response opens with a reasoning block.
        case detecting
        /// Inside a reasoning block, waiting for its closing tag.
        case inBlock(close: String)
        /// No (more) leading reasoning; everything is forwarded verbatim.
        case passthrough
    }

    private var state: State = .detecting
    private var buffer = ""
    private var strippedAny = false

    /// Feed a streamed chunk; returns the text that is safe to display now (may be empty).
    mutating func process(_ chunk: String) -> String {
        if case .passthrough = state { return chunk }
        buffer += chunk
        return drain()
    }

    /// Call once the stream ends; returns any text still held back.
    mutating func finish() -> String {
        defer { buffer = "" }
        switch state {
        case .detecting:
            state = .passthrough
            return strippedAny ? Self.trimmingLeadingWhitespace(buffer) : buffer
        case .inBlock:
            // Unterminated reasoning block: nothing in it is part of the answer.
            state = .passthrough
            return ""
        case .passthrough:
            return ""
        }
    }

    private mutating func drain() -> String {
        while true {
            switch state {
            case .passthrough:
                return ""
            case let .inBlock(close):
                guard let range = buffer.range(of: close) else {
                    // Keep only a tail long enough to match a split closing tag.
                    buffer = String(buffer.suffix(close.count - 1))
                    return ""
                }
                buffer = String(buffer[range.upperBound...])
                strippedAny = true
                state = .detecting
            case .detecting:
                let trimmed = Self.trimmingLeadingWhitespace(buffer)
                if trimmed.isEmpty { return "" }
                if let pair = Self.tagPairs.first(where: { trimmed.hasPrefix($0.open) }) {
                    buffer = String(trimmed.dropFirst(pair.open.count))
                    state = .inBlock(close: pair.close)
                    continue
                }
                if Self.tagPairs.contains(where: { $0.open.hasPrefix(trimmed) }) {
                    return "" // Possibly a tag split across chunks; wait for more.
                }
                state = .passthrough
                let output = strippedAny ? trimmed : buffer
                buffer = ""
                return output
            }
        }
    }

    private static func trimmingLeadingWhitespace(_ text: String) -> String {
        String(text.drop(while: \.isWhitespace))
    }
}
