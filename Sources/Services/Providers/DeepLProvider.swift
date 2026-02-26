import Defaults
import Foundation
import SwiftUI

/// DeepL Official API provider (supports both Free and Pro keys).
struct DeepLProvider: TranslationProvider {
    let id = "deepl"
    let displayName = "DeepL"
    let iconSystemName = "doc.text"
    let iconAssetName: String? = "DeepL"
    let category: ProviderCategory = .traditional
    let supportsStreaming = false
    let isAvailable = true

    let apiKeyKey = Defaults.Key<String>("provider_deepl_apiKey", default: "")

    @MainActor
    var isConfigured: Bool { !Defaults[apiKeyKey].isEmpty }

    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String
    ) -> AsyncThrowingStream<String, Error> {
        singleResultStream { [self] in try await translate(text, from: sourceLang, to: targetLang) }
    }

    @MainActor
    func makeSettingsView() -> AnyView {
        AnyView(DeepLSettingsView(provider: self))
    }

    // MARK: - Private

    private func translate(_ text: String, from sourceLang: String?, to targetLang: String) async throws -> String {
        let apiKey = Defaults[apiKeyKey]
        guard !apiKey.isEmpty else { throw TranslationError.missingAPIKey }

        let isFree = apiKey.hasSuffix(":fx")
        let baseURL = isFree
            ? "https://api-free.deepl.com/v2/translate"
            : "https://api.deepl.com/v2/translate"

        guard let url = URL(string: baseURL) else { throw TranslationError.invalidURL }

        let targetCode = LanguageCodeMapping.resolveTarget(targetLang, using: LanguageCodeMapping.deepLTarget)

        var formParts = [
            "text=\(URLFormEncoding.encode(text))",
            "target_lang=\(URLFormEncoding.encode(targetCode))",
        ]

        if let source = sourceLang {
            let sourceCode = LanguageCodeMapping.resolve(source, using: LanguageCodeMapping.deepLSource) ?? source
            formParts.append("source_lang=\(URLFormEncoding.encode(sourceCode))")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formParts.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await translationURLSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw TranslationError.apiError(
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8) ?? ""
            )
        }

        let decoded = try JSONDecoder().decode(DeepLResponse.self, from: data)
        guard let translated = decoded.translations.first?.text, !translated.isEmpty else {
            throw TranslationError.emptyResult
        }
        return translated
    }
}

// MARK: - Response Model

private struct DeepLResponse: Decodable {
    let translations: [Translation]

    struct Translation: Decodable {
        let text: String
    }
}

// MARK: - Settings View

private struct DeepLSettingsView: View {
    let provider: DeepLProvider

    private var apiKey: Binding<String> { Defaults.binding(provider.apiKeyKey) }

    private var planLabel: String {
        let key = apiKey.wrappedValue
        if key.isEmpty { return "" }
        return key.hasSuffix(":fx") ? "Free" : "Pro"
    }

    var body: some View {
        Form {
            Section("API Configuration") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key")
                        .font(.subheadline.bold())
                    SecureField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx:fx", text: apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                if !planLabel.isEmpty {
                    Label("Plan: \(planLabel)", systemImage: "checkmark.seal.fill")
                        .font(.callout)
                        .foregroundStyle(apiKey.wrappedValue.hasSuffix(":fx") ? .blue : .purple)
                }
            }

            Section {
                Link(destination: URL(string: "https://www.deepl.com/pro-api")!) {
                    Label("Get a free API key at deepl.com", systemImage: "arrow.up.right.square")
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}
