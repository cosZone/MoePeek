import Foundation
import Testing
@testable import MoePeek

@Suite struct MarkdownSupportTests {
    @Test func detectsCommonLLMMarkdown() {
        #expect(MarkdownSupport.looksLikeMarkdown("有以下几种译法：\n\n- **马具**（名词）\n- **利用**（动词）"))
        #expect(MarkdownSupport.looksLikeMarkdown("## 标题"))
        #expect(MarkdownSupport.looksLikeMarkdown("1. 第一\n2. 第二"))
        #expect(MarkdownSupport.looksLikeMarkdown("用 `git status` 查看"))
        #expect(MarkdownSupport.looksLikeMarkdown("见 [文档](https://example.com)"))
        #expect(MarkdownSupport.looksLikeMarkdown("```swift\nlet a = 1\n```"))
    }

    @Test func plainTextIsNotMarkdown() {
        #expect(!MarkdownSupport.looksLikeMarkdown("Hello world"))
        #expect(!MarkdownSupport.looksLikeMarkdown("2*3*4 = 24 and snake_case_name"))
        #expect(!MarkdownSupport.looksLikeMarkdown("东京 - 大阪 的新干线"))
        #expect(!MarkdownSupport.looksLikeMarkdown("a | b"))
    }

    @Test func emptyAltFallsBackToImageLabel() {
        let segments = MarkdownSupport.renderingSegments("![](https://example.com/x.png)")
        guard case .image(let placeholder) = segments.first else {
            Issue.record("Expected an image rendering segment")
            return
        }
        #expect(placeholder.label.hasPrefix("🖼 "))
        #expect(placeholder.label.contains("example.com"))
        #expect(placeholder.url == URL(string: "https://example.com/x.png")!)
    }

    @Test func splitsImagesIntoDedicatedRenderingSegments() {
        let input = """
            ```swift
            let message = "Hello"
            ```

            ![示意图](https://cdn.example.com/a.png)

            结束
            """

        let segments = MarkdownSupport.renderingSegments(input)

        #expect(segments.count == 3)
        #expect(segments[0] == .markdown("```swift\nlet message = \"Hello\"\n```\n\n"))
        #expect(segments[1] == .image(.init(
            label: "🖼 示意图 · cdn.example.com",
            url: URL(string: "https://cdn.example.com/a.png")!
        )))
        #expect(segments[2] == .markdown("\n\n结束"))
    }

    @Test func preservesEncodedImageURL() {
        let original = "https://cdn.example.com/path/a%20b.png?x=1&y=2"
        let segments = MarkdownSupport.renderingSegments("![a](\(original))")
        guard case .image(let placeholder) = segments.first else {
            Issue.record("Expected an image rendering segment")
            return
        }
        #expect(placeholder.url.absoluteString == original)
    }

    @Test func plainTextStripsSyntaxAndAttachmentPlaceholders() {
        let markdown = "## 标题\n\n**加粗** 和 [链接](https://example.com) ![img-1](moepeek-attachment:img-1)\n\n- `代码`"
        #expect(MarkdownSupport.plainText(from: markdown) == "标题\n\n加粗 和 链接\n\n- 代码")
        #expect(MarkdownSupport.plainText(from: "纯文本") == "纯文本")
    }

    @Test func hardensSingleLineBreaksBetweenPlainLines() {
        #expect(MarkdownSupport.hardenLineBreaks("第一行\n第二行\n\n第三行") == "第一行  \n第二行\n\n第三行")
    }

    @Test func leavesBlockConstructsAlone() {
        let list = "- a\n- b"
        #expect(MarkdownSupport.hardenLineBreaks(list) == list)
        let heading = "# 标题\n正文"
        #expect(MarkdownSupport.hardenLineBreaks(heading) == heading)
        let intro = "说明：\n- a"
        #expect(MarkdownSupport.hardenLineBreaks(intro) == intro)
        let fence = "```\nline1\nline2\n```"
        #expect(MarkdownSupport.hardenLineBreaks(fence) == fence)
    }

    @Test func listItemContinuationGetsHardBreak() {
        #expect(MarkdownSupport.hardenLineBreaks("- a\n续行") == "- a  \n续行")
    }
}
