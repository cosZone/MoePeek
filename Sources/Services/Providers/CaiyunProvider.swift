import Defaults
import Foundation
import SwiftUI

/// Caiyun (彩云小译) translation API provider.
struct CaiyunProvider: TranslationProvider {
    let id = "caiyun"
    let displayName = "Caiyun"
    let iconSystemName = "cloud.fill"
    let category: ProviderCategory = .traditional
    let supportsStreaming = false
    let isAvailable = true

    let tokenKey = Defaults.Key<String>("provider_caiyun_token", default: "")

    @MainActor
    var isConfigured: Bool { !Defaults[tokenKey].isEmpty }

    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String
    ) -> AsyncThrowingStream<String, Error> {
        singleResultStream { [self] in try await translate(text, from: sourceLang, to: targetLang) }
    }

    @MainActor
    func makeSettingsView() -> AnyView {
        AnyView(CaiyunSettingsView(provider: self))
    }

    // MARK: - Private

    private func translate(_ text: String, from sourceLang: String?, to targetLang: String) async throws -> String {
        let token = Defaults[tokenKey]
        guard !token.isEmpty else { throw TranslationError.missingAPIKey }

        guard let url = URL(string: "https://api.interpreter.caiyunai.com/v1/translator") else {
            throw TranslationError.invalidURL
        }

        let fromCode = LanguageCodeMapping.resolve(sourceLang, using: LanguageCodeMapping.caiyun) ?? "auto"
        let toCode = LanguageCodeMapping.resolveTarget(targetLang, using: LanguageCodeMapping.caiyun)

        // Check language support
        if fromCode != "auto", !LanguageCodeMapping.caiyunSupported.contains(fromCode) {
            throw TranslationError.languageUnsupported(source: sourceLang, target: targetLang)
        }
        if !LanguageCodeMapping.caiyunSupported.contains(toCode) {
            throw TranslationError.languageUnsupported(source: sourceLang, target: targetLang)
        }

        let isAutoDetect = fromCode == "auto"
        let transType = "\(isAutoDetect ? "auto" : fromCode)2\(toCode)"

        let sourceLines = text.components(separatedBy: "\n")

        let body: [String: Any] = [
            "source": sourceLines,
            "trans_type": transType,
            "media": "text",
            "request_id": "MoePeek",
            "detect": isAutoDetect,
        ]

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("token \(token)", forHTTPHeaderField: "x-authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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

        let decoded = try JSONDecoder().decode(CaiyunResponse.self, from: data)
        let translated = decoded.target.joined(separator: "\n")

        guard !translated.isEmpty else {
            throw TranslationError.emptyResult
        }
        return translated
    }
}

// MARK: - Response Model

private struct CaiyunResponse: Decodable {
    let target: [String]
}

// MARK: - Settings View

private struct CaiyunSettingsView: View {
    let provider: CaiyunProvider

    private var token: Binding<String> { Defaults.binding(provider.tokenKey) }

    var body: some View {
        Form {
            Section("API Configuration") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Token")
                        .font(.subheadline.bold())
                    SecureField("Enter Caiyun Token", text: token)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                Link(destination: URL(string: "https://platform.caiyunapp.com")!) {
                    Label("Get a token at platform.caiyunapp.com", systemImage: "arrow.up.right.square")
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}
