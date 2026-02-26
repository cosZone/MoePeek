import Foundation
import SwiftUI

/// Google Translate provider using the free GTX API (no API key required).
struct GoogleTranslateProvider: TranslationProvider {
    let id = "google"
    let displayName = "Google Translate"
    let iconSystemName = "g.circle.fill"
    let iconAssetName: String? = "Google"
    let category: ProviderCategory = .freeTranslation
    let supportsStreaming = false
    let isAvailable = true

    @MainActor
    var isConfigured: Bool { true }

    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String
    ) -> AsyncThrowingStream<String, Error> {
        singleResultStream { [self] in try await translate(text, from: sourceLang, to: targetLang) }
    }

    @MainActor
    func makeSettingsView() -> AnyView {
        AnyView(GoogleTranslateSettingsView())
    }

    // MARK: - Private

    private func translate(_ text: String, from sourceLang: String?, to targetLang: String) async throws -> String {
        let sl = LanguageCodeMapping.resolve(sourceLang, using: LanguageCodeMapping.google) ?? "auto"
        let tl = LanguageCodeMapping.resolveTarget(targetLang, using: LanguageCodeMapping.google)

        guard var components = URLComponents(string: "https://translate.google.com/translate_a/single") else {
            throw TranslationError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: sl),
            URLQueryItem(name: "tl", value: tl),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "dj", value: "1"),
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "q", value: text),
        ]

        guard let url = components.url else {
            throw TranslationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await translationURLSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }

        let json = try JSONDecoder().decode(GTXResponse.self, from: data)
        let translated = json.sentences.compactMap(\.trans).joined()

        guard !translated.isEmpty else {
            throw TranslationError.emptyResult
        }
        return translated
    }
}

// MARK: - Response Model

private struct GTXResponse: Decodable {
    let sentences: [Sentence]

    struct Sentence: Decodable {
        let trans: String?
    }
}

// MARK: - Settings View

private struct GoogleTranslateSettingsView: View {
    var body: some View {
        Form {
            Section("Status") {
                Label("Free, no API key needed.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                Text("Uses unofficial Google Translate API, may be rate-limited.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
