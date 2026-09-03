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

    @Test func rewritesImagesToPlaceholderLinks() {
        let input = "看图 ![示意图](https://cdn.example.com/a.png \"title\") 结束"
        let output = MarkdownSupport.rewriteImages(input)
        #expect(!output.contains("!["))
        #expect(output.contains("[🖼 示意图 · cdn.example.com](moepeek-image:"))
        #expect(output.hasSuffix(") 结束"))
    }

    @Test func emptyAltFallsBackToImageLabel() {
        let output = MarkdownSupport.rewriteImages("![](https://example.com/x.png)")
        #expect(output.contains("🖼 "))
        #expect(output.contains("example.com"))
    }

    @Test func placeholderURLRoundTrips() {
        let original = "https://cdn.example.com/path/a b.png?x=1&y=2"
        let rewritten = MarkdownSupport.rewriteImages("![a](\(original.replacingOccurrences(of: " ", with: "%20")))")
        let start = rewritten.range(of: "(moepeek-image:")!.upperBound
        let end = rewritten[start...].firstIndex(of: ")")!
        let placeholder = URL(string: "moepeek-image:" + rewritten[start..<end])!
        #expect(MarkdownSupport.imageURL(fromPlaceholder: placeholder)?.absoluteString
            == original.replacingOccurrences(of: " ", with: "%20"))
        #expect(MarkdownSupport.imageURL(fromPlaceholder: URL(string: "https://example.com")!) == nil)
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
