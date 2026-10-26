import Foundation

/// Bing can append metadata-only entries (for example inputTransliteration)
/// after the translation result. Those entries do not contain translations.
///
/// Rejected requests come back as an object such as
/// `{"statusCode":205,"errorMessage":""}` and still use HTTP 200, so they must
/// not be mistaken for a translation list.
struct BingTranslateResponse: Decodable {
    let translations: [Translation]?

    struct Translation: Decodable {
        let text: String
        let to: String
    }

    private struct Failure: Decodable {
        let statusCode: Int
        let errorMessage: String?

        /// Bing sends an empty message for most failures; 205 means the cached
        /// session token was rejected.
        var message: String {
            if let errorMessage, !errorMessage.isEmpty { return errorMessage }
            if statusCode == 205 { return String(localized: "Bing session expired. Please try again later.") }
            return String(localized: "Bing rejected the request")
        }
    }

    static func translatedText(from data: Data) throws -> String {
        let decoder = JSONDecoder()

        if let responses = try? decoder.decode([Self].self, from: data) {
            guard let text = responses.first?.translations?.first?.text, !text.isEmpty else {
                throw TranslationError.emptyResult
            }
            return text
        }

        if let failure = try? decoder.decode(Failure.self, from: data) {
            throw TranslationError.apiError(statusCode: failure.statusCode, message: failure.message)
        }

        throw TranslationError.invalidResponse
    }
}
