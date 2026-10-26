import Testing
@testable import MoePeek

@Suite struct ReasoningTagFilterTests {
    private func run(_ chunks: [String]) -> String {
        var filter = ReasoningTagFilter()
        return chunks.map { filter.process($0) }.joined() + filter.finish()
    }

    @Test func stripsLeadingThoughtBlock() {
        #expect(run(["<thought>\nThe user wants…\n</thought>\n你好"]) == "你好")
    }

    @Test func stripsThinkBlocksSplitAcrossChunks() {
        #expect(run(["  <th", "ink>reason", "ing</th", "ink>", "\n\nHello", " world"]) == "Hello world")
        #expect(run(["<thinking>a</thinking>", "b"]) == "b")
    }

    @Test func stripsConsecutiveLeadingBlocks() {
        #expect(run(["<thought>a</thought>\n<think>b</think>\nResult"]) == "Result")
    }

    @Test func leavesPlainAndLaterTagsUntouched() {
        #expect(run(["Hello ", "world"]) == "Hello world")
        #expect(run(["  Hello"]) == "  Hello")
        #expect(run(["Use <think>", " tags</think>"]) == "Use <think> tags</think>")
        #expect(run(["<b>bold</b>"]) == "<b>bold</b>")
        #expect(run(["<th"]) == "<th")
    }

    @Test func dropsUnterminatedBlock() {
        #expect(run(["<thought>never closed"]) == "")
    }
}
