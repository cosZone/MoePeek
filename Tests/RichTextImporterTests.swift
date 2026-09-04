import AppKit
import Testing
@testable import MoePeek

@Suite struct AttributedStringMarkdownConverterTests {
    private let body = NSFont.systemFont(ofSize: 12)

    private func run(_ text: String, _ attributes: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        var merged: [NSAttributedString.Key: Any] = [.font: body]
        merged.merge(attributes) { _, new in new }
        return NSAttributedString(string: text, attributes: merged)
    }

    private func join(_ parts: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        parts.forEach(result.append)
        return result
    }

    private func pngData() -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func plainParagraphsAreNotRich() {
        let output = AttributedStringMarkdownConverter().convert(join([run("第一段\n"), run("第二段")]))
        #expect(output.markdown == "第一段\n\n第二段")
        #expect(!output.isRich)
        #expect(output.attachments.isEmpty)
    }

    @Test func wrapsBoldItalicAndLinks() {
        let bold = NSFont.boldSystemFont(ofSize: 12)
        let italic = NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
        let output = AttributedStringMarkdownConverter().convert(join([
            run("普通 "),
            run("加粗 ", [.font: bold]),
            run("斜体", [.font: italic]),
            run(" 和 "),
            run("链接", [.link: URL(string: "https://example.com")!]),
        ]))
        #expect(output.markdown == "普通 **加粗** *斜体* 和 [链接](https://example.com)")
        #expect(output.isRich)
    }

    @Test func mergesAdjacentRunsWithSameStyle() {
        let bold = NSFont.boldSystemFont(ofSize: 12)
        let output = AttributedStringMarkdownConverter().convert(join([
            run("Hello", [.font: bold]),
            run(" World", [.font: bold]),
        ]))
        #expect(output.markdown == "**Hello World**")
    }

    @Test func convertsTextListsAndStripsLiteralMarkers() {
        let style = NSMutableParagraphStyle()
        style.textLists = [NSTextList(markerFormat: .disc, options: 0)]
        let ordered = NSMutableParagraphStyle()
        ordered.textLists = [NSTextList(markerFormat: .decimal, options: 0)]
        let output = AttributedStringMarkdownConverter().convert(join([
            run("•\t苹果\n", [.paragraphStyle: style]),
            run("•\t香蕉\n", [.paragraphStyle: style]),
            run("1.\t第一\n", [.paragraphStyle: ordered]),
            run("尾段"),
        ]))
        #expect(output.markdown == "- 苹果\n- 香蕉\n1. 第一\n\n尾段")
        #expect(output.isRich)
    }

    @Test func detectsHeadingsByRelativeFontSize() {
        let output = AttributedStringMarkdownConverter().convert(join([
            run("标题\n", [.font: NSFont.boldSystemFont(ofSize: 24)]),
            run("正文一\n"),
            run("正文二"),
        ]))
        #expect(output.markdown == "# 标题\n\n正文一\n\n正文二")
    }

    @Test func extractsImagesAsAttachments() {
        let attachment = NSTextAttachment(data: pngData(), ofType: "public.png")
        let output = AttributedStringMarkdownConverter().convert(join([
            run("图前 "),
            NSAttributedString(attachment: attachment),
            run(" 图后"),
        ]))
        #expect(output.markdown == "图前 ![img-1](moepeek-attachment:img-1) 图后")
        #expect(output.attachments["img-1"]?.data == pngData())
        #expect(output.omittedImageCount == 0)
        #expect(output.isRich)
    }

    @Test func enforcesImageLimitsButKeepsPlaceholders() {
        var converter = AttributedStringMarkdownConverter()
        converter.limits = .init(maxImages: 1, maxTotalBytes: 1024 * 1024)
        let parts = (0..<3).map { _ in NSAttributedString(attachment: NSTextAttachment(data: pngData(), ofType: "public.png")) }
        let output = converter.convert(join(parts))
        #expect(output.attachments.count == 1)
        #expect(output.omittedImageCount == 2)
        #expect(output.markdown.contains("img-3"))
    }

    @Test func ignoresNonImageAttachments() {
        let attachment = NSTextAttachment(data: Data("not an image".utf8), ofType: "public.plain-text")
        let output = AttributedStringMarkdownConverter().convert(join([
            run("A"),
            NSAttributedString(attachment: attachment),
            run("B"),
        ]))
        #expect(output.markdown == "AB")
        #expect(output.attachments.isEmpty)
    }
}

@Suite struct SourceAttachmentReferenceTests {
    @Test func placeholderRoundTrips() {
        let placeholder = SourceAttachmentReference.placeholder(id: "img-2")
        #expect(placeholder == "![img-2](moepeek-attachment:img-2)")
        #expect(SourceAttachmentReference.id(from: URL(string: "moepeek-attachment:img-2")!) == "img-2")
        #expect(SourceAttachmentReference.id(from: URL(string: "https://example.com/img-2")!) == nil)
    }

    @Test func retainsOnlyReferencedAttachments() {
        let attachments = [
            "img-1": SourceImageAttachment(id: "img-1", data: Data([1])),
            "img-2": SourceImageAttachment(id: "img-2", data: Data([2])),
        ]
        let retained = SourceAttachmentReference.retainedAttachments(
            attachments, referencedIn: "text ![img-2](moepeek-attachment:img-2)"
        )
        #expect(retained.keys.sorted() == ["img-2"])
    }
}

@Suite struct RichTextImporterTests {
    private func pngData() -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    @MainActor
    @Test func importsRTFDWithEmbeddedImage() async {
        let source = NSMutableAttributedString(string: "标题前 ", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        source.append(NSAttributedString(attachment: NSTextAttachment(data: pngData(), ofType: "public.png")))
        source.append(NSAttributedString(string: " 之后", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        let rtfd = source.rtfd(from: NSRange(location: 0, length: source.length), documentAttributes: [:])!

        let document = await RichTextImporter.document(from: .init(rtfd: rtfd, plain: source.string))

        #expect(document?.markdown == "**标题前** ![img-1](moepeek-attachment:img-1) 之后")
        #expect(document?.attachments["img-1"] != nil)
    }

    @MainActor
    @Test func importsHTMLFormatting() async {
        let html = Data("<p><b>Bold</b> text</p><ul><li>item one</li><li>item two</li></ul>".utf8)

        let document = await RichTextImporter.document(from: .init(html: html, plain: "Bold text\nitem one\nitem two"))

        #expect(document?.markdown == "**Bold** text\n\n- item one\n- item two")
        #expect(document?.attachments.isEmpty == true)
    }

    @MainActor
    @Test func fallsBackToPlainTextWhenNothingIsRich() async {
        let plain = NSAttributedString(string: "just text", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let rtf = plain.rtf(from: NSRange(location: 0, length: plain.length), documentAttributes: [:])!

        let document = await RichTextImporter.document(from: .init(rtf: rtf, plain: "just text"))

        #expect(document == .plain("just text"))
    }
}
