import Foundation

/// Bing can append metadata-only entries (for example inputTransliteration)
/// after the translation result. Those entries do not contain translations.
struct BingTranslateResponse: Decodable {
    let translations: [Translation]?

    struct Translation: Decodable {
        let text: String
        let to: String
    }

    static func translatedText(from data: Data) throws -> String {
        let responses = try JSONDecoder().decode([Self].self, from: data)
        guard let text = responses.first?.translations?.first?.text, !text.isEmpty else {
            throw TranslationError.emptyResult
        }
        return text
    }
}
