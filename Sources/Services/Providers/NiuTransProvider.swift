import Defaults
import Foundation
import SwiftUI

/// NiuTrans (小牛翻译) translation API provider.
struct NiuTransProvider: TranslationProvider {
    let id = "niutrans"
    let displayName = "NiuTrans"
    let iconSystemName = "textformat.abc"
    let category: ProviderCategory = .traditional
    let supportsStreaming = false
    let isAvailable = true

    let apiKeyKey = Defaults.Key<String>("provider_niutrans_apiKey", default: "")

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
        AnyView(NiuTransSettingsView(provider: self))
    }

    // MARK: - Private

    private func translate(_ text: String, from sourceLang: String?, to targetLang: String) async throws -> String {
        let apiKey = Defaults[apiKeyKey]
        guard !apiKey.isEmpty else { throw TranslationError.missingAPIKey }

        guard let url = URL(string: "https://api.niutrans.com/NiuTransServer/translation") else {
            throw TranslationError.invalidURL
        }

        let fromCode = LanguageCodeMapping.resolve(sourceLang, using: LanguageCodeMapping.niuTrans) ?? "auto"
        let toCode = LanguageCodeMapping.resolveTarget(targetLang, using: LanguageCodeMapping.niuTrans)

        let formParts = [
            "from=\(URLFormEncoding.encode(fromCode))",
            "to=\(URLFormEncoding.encode(toCode))",
            "apikey=\(URLFormEncoding.encode(apiKey))",
            "src_text=\(URLFormEncoding.encode(text))",
        ]

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formParts.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw TranslationError.apiError(
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8) ?? ""
            )
        }

        // NiuTrans returns Content-Type: text/html but body is JSON
        let decoded = try JSONDecoder().decode(NiuTransResponse.self, from: data)

        if let errorCode = decoded.error_code {
            throw TranslationError.apiError(
                statusCode: 0,
                message: "NiuTrans error \(errorCode): \(decoded.error_msg ?? String(localized: "Unknown error"))"
            )
        }

        guard let translated = decoded.tgt_text, !translated.isEmpty else {
            throw TranslationError.emptyResult
        }
        return translated
    }
}

// MARK: - Response Model

private struct NiuTransResponse: Decodable {
    let tgt_text: String?
    let error_code: String?
    let error_msg: String?
}

// MARK: - Settings View

private struct NiuTransSettingsView: View {
    let provider: NiuTransProvider

    private var apiKey: Binding<String> { Defaults.binding(provider.apiKeyKey) }

    var body: some View {
        Form {
            Section("API Configuration") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key")
                        .font(.subheadline.bold())
                    SecureField("Enter NiuTrans API Key", text: apiKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                Link(destination: URL(string: "https://niutrans.com/cloud")!) {
                    Label("Get an API key at niutrans.com", systemImage: "arrow.up.right.square")
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}
