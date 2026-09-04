import Foundation

/// Per-request facts a provider needs but the `TranslationProvider` protocol does not carry.
/// The coordinator sets them with `withValue` around each provider task; providers read them
/// while building prompts. Unstructured `Task {}` inside providers inherits the value.
enum TranslationRequestContext {
    @TaskLocal static var sourceIsMarkdown = false

    static let markdownPromptAddendum = """
    The input is Markdown. Preserve its structure and inline formatting in the translation. \
    Keep every image reference such as ![img-1](moepeek-attachment:img-1) exactly as written, in its original position.
    """
}

extension TranslationProvider {
    /// Fills `{targetLang}` and appends the Markdown instruction when the source is Markdown.
    func resolveSystemPrompt(template: String, targetLang: String) -> String {
        var prompt = template.replacingOccurrences(
            of: "{targetLang}",
            with: SupportedLanguages.englishName(for: targetLang)
        )
        if TranslationRequestContext.sourceIsMarkdown {
            prompt += "\n\n" + TranslationRequestContext.markdownPromptAddendum
        }
        return prompt
    }

    /// LLM-style providers follow formatting instructions; machine translation APIs cannot.
    var acceptsMarkdownInput: Bool {
        category == .llm || category == .custom
    }
}
