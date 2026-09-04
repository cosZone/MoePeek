import Foundation

/// An image captured alongside rich source text. Markdown refers to it as
/// `![img-N](moepeek-attachment:img-N)`; the bytes never leave the app.
struct SourceImageAttachment: Sendable, Equatable {
    let id: String
    let data: Data
}

/// Source text as Markdown plus the local images its placeholders refer to.
struct RichSourceDocument: Sendable, Equatable {
    let markdown: String
    let attachments: [String: SourceImageAttachment]

    static func plain(_ text: String) -> RichSourceDocument {
        RichSourceDocument(markdown: text, attachments: [:])
    }
}

enum SourceAttachmentReference {
    static let scheme = "moepeek-attachment"

    static func id(index: Int) -> String {
        "img-\(index)"
    }

    static func placeholder(id: String) -> String {
        "![\(id)](\(scheme):\(id))"
    }

    static func id(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        let specifier = url.absoluteString.dropFirst(scheme.count + 1)
        return specifier.isEmpty ? nil : String(specifier)
    }

    /// Keeps only the attachments `markdown` still references so edited-away images are released.
    static func retainedAttachments(
        _ attachments: [String: SourceImageAttachment],
        referencedIn markdown: String
    ) -> [String: SourceImageAttachment] {
        attachments.filter { markdown.contains("\(scheme):\($0.key)") }
    }
}
