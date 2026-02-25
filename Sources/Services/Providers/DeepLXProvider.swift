import Defaults
import Foundation
import SwiftUI

/// DeepLX self-hosted translation proxy (uses DeepL language codes, JSON API).
struct DeepLXProvider: TranslationProvider {
    let id = "deeplx"
    let displayName = "DeepLX"
    let iconSystemName = "server.rack"
    let category: ProviderCategory = .traditional
    let supportsStreaming = false
    let isAvailable = true

    let baseURLKey = Defaults.Key<String>("provider_deeplx_baseURL", default: "")
    let authTokenKey = Defaults.Key<String>("provider_deeplx_authToken", default: "")
    let endpointKey = Defaults.Key<Endpoint>("provider_deeplx_endpoint", default: .free)

    // MARK: - Endpoint

    enum Endpoint: String, CaseIterable, Defaults.Serializable {
        case free, pro, official

        var path: String {
            switch self {
            case .free: "/translate"
            case .pro: "/v1/translate"
            case .official: "/v2/translate"
            }
        }

        var displayName: LocalizedStringKey {
            switch self {
            case .free: "Free"
            case .pro: "Pro"
            case .official: "Official"
            }
        }
    }

    @MainActor
    var isConfigured: Bool { !Defaults[baseURLKey].isEmpty }

    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String
    ) -> AsyncThrowingStream<String, Error> {
        singleResultStream { [self] in try await translate(text, from: sourceLang, to: targetLang) }
    }

    @MainActor
    func makeSettingsView() -> AnyView {
        AnyView(DeepLXSettingsView(provider: self))
    }

    // MARK: - Private

    private func translate(_ text: String, from sourceLang: String?, to targetLang: String) async throws -> String {
        let rawURL = Defaults[baseURLKey]
        guard !rawURL.isEmpty else { throw TranslationError.invalidURL }

        let endpoint = Defaults[endpointKey]
        var trimmed = rawURL
        // Strip trailing slashes
        while trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        // Strip endpoint path if user accidentally included it (sort by length descending to avoid partial matches)
        if let ep = Endpoint.allCases.sorted(by: { $0.path.count > $1.path.count }).first(where: { trimmed.hasSuffix($0.path) }) {
            trimmed = String(trimmed.dropLast(ep.path.count))
        }
        while trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        guard let url = URL(string: "\(trimmed)\(endpoint.path)") else { throw TranslationError.invalidURL }

        let targetCode = LanguageCodeMapping.resolveTarget(targetLang, using: LanguageCodeMapping.deepLTarget)

        var body: [String: String] = [
            "text": text,
            "target_lang": targetCode,
        ]

        if let source = sourceLang {
            let sourceCode = LanguageCodeMapping.resolve(source, using: LanguageCodeMapping.deepLSource) ?? source
            body["source_lang"] = sourceCode
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let token = Defaults[authTokenKey]
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await translationURLSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(DeepLXResponse.self, from: data))
                .flatMap { $0.message ?? $0.data }
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(httpResponse.statusCode)"
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(DeepLXResponse.self, from: data)

        guard decoded.code == 200 else {
            throw TranslationError.apiError(
                statusCode: decoded.code,
                message: decoded.message ?? decoded.data ?? String(localized: "Unknown DeepLX error")
            )
        }

        guard let translated = decoded.data, !translated.isEmpty else {
            throw TranslationError.emptyResult
        }
        return translated
    }
}

// MARK: - Response Model

private struct DeepLXResponse: Decodable {
    let code: Int
    let data: String?
    let message: String?
}

// MARK: - Settings View

private struct DeepLXSettingsView: View {
    let provider: DeepLXProvider

    private var baseURL: Binding<String> { Defaults.binding(provider.baseURLKey) }
    private var authToken: Binding<String> { Defaults.binding(provider.authTokenKey) }
    private var endpoint: Binding<DeepLXProvider.Endpoint> {
        Binding(
            get: { Defaults[provider.endpointKey] },
            set: { Defaults[provider.endpointKey] = $0 }
        )
    }

    var body: some View {
        Form {
            Section("API Configuration") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server URL")
                        .font(.subheadline.bold())
                    TextField("https://api.deeplx.org/your-api-key", text: baseURL)
                        .textFieldStyle(.roundedBorder)
                    Text("For api.deeplx.org, include your API key in the URL.\nFor self-hosted: `http://localhost:1188`\nDo not include /translate path suffix.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Endpoint")
                        .font(.subheadline.bold())
                    Picker("Endpoint", selection: endpoint) {
                        ForEach(DeepLXProvider.Endpoint.allCases, id: \.self) { ep in
                            Text(ep.displayName).tag(ep)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(endpoint.wrappedValue.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)

                    Group {
                        switch endpoint.wrappedValue {
                        case .free:
                            Text("Simulates DeepL iOS client. No authentication required. Rate limits (HTTP 429) may apply.")
                        case .pro:
                            Text("Uses DeepL Pro session. Requires `dl_session` cookie configured on the DeepLX server.")
                        case .official:
                            Text("Uses DeepL official API (`/v2`). Requires `authKey` configured on the DeepLX server.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Access Token")
                        .font(.subheadline.bold())
                    SecureField("Optional", text: authToken)
                        .textFieldStyle(.roundedBorder)
                    Text("Protects your self-hosted DeepLX server. Set via `--token` flag or `TOKEN` environment variable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Link(destination: URL(string: "https://github.com/OwO-Network/DeepLX")!) {
                    Label("Learn more about DeepLX", systemImage: "arrow.up.right.square")
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}
