import Defaults
import Foundation
import SwiftUI

/// A parameterized provider for any OpenAI-compatible API (OpenAI, DeepSeek, etc.).
struct OpenAICompatibleProvider: TranslationProvider {
    let id: String
    let displayName: String
    let iconSystemName: String
    let isCustom: Bool
    let supportsStreaming = true
    let isAvailable = true

    var category: ProviderCategory { isCustom ? .custom : .llm }
    var isDeletable: Bool { isCustom }

    // Namespaced Defaults keys
    let baseURLKey: Defaults.Key<String>
    let modelKey: Defaults.Key<String>
    let enabledModelsKey: Defaults.Key<Set<String>>
    let systemPromptKey: Defaults.Key<String>
    let apiKeyKey: Defaults.Key<String>
    let guideURL: String?

    /// Models explicitly enabled for parallel translation. Empty means use default single model.
    var activeModels: [String] {
        let enabled = Defaults[enabledModelsKey]
        return enabled.isEmpty ? [] : enabled.sorted()
    }

    /// All UserDefaults suffixes used by this provider type.
    private static let defaultsSuffixes = ["baseURL", "apiKey", "model", "enabledModels", "systemPrompt"]

    /// Remove all UserDefaults keys associated with the given provider id.
    /// Uses `UserDefaults.standard` directly because the Defaults library
    /// does not expose an API for removing keys by name.
    static func cleanupDefaults(for id: String) {
        for suffix in defaultsSuffixes {
            UserDefaults.standard.removeObject(forKey: "provider_\(id)_\(suffix)")
        }
    }

    init(
        id: String,
        displayName: String,
        iconSystemName: String = "globe",
        defaultBaseURL: String,
        defaultModel: String,
        guideURL: String? = nil,
        isCustom: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.iconSystemName = iconSystemName
        self.isCustom = isCustom
        self.baseURLKey = .init("provider_\(id)_baseURL", default: defaultBaseURL)
        self.modelKey = .init("provider_\(id)_model", default: defaultModel)
        self.enabledModelsKey = .init("provider_\(id)_enabledModels", default: [])
        self.systemPromptKey = .init(
            "provider_\(id)_systemPrompt",
            default: "Translate the following text to {targetLang}. Only output the translation, nothing else."
        )
        self.apiKeyKey = .init("provider_\(id)_apiKey", default: "")
        self.guideURL = guideURL
    }

    init(definition: CustomProviderDefinition) {
        self.init(
            id: definition.id,
            displayName: definition.name,
            iconSystemName: "server.rack",
            defaultBaseURL: definition.defaultBaseURL,
            defaultModel: definition.defaultModel,
            isCustom: true
        )
    }

    @MainActor
    var isConfigured: Bool {
        !Defaults[apiKeyKey].isEmpty
    }

    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String
    ) -> AsyncThrowingStream<String, Error> {
        translateStream(text, from: sourceLang, to: targetLang, model: Defaults[modelKey])
    }

    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(text: text, sourceLang: sourceLang, targetLang: targetLang, model: model)
                    let (bytes, response) = try await translationURLSession.bytes(for: request)
                    try await streamOpenAISSE(bytes, response: response, to: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @MainActor
    func makeSettingsView() -> AnyView {
        AnyView(OpenAICompatibleSettingsView(provider: self))
    }

    // MARK: - Private

    private func buildRequest(text: String, sourceLang: String?, targetLang: String, model: String) throws -> URLRequest {
        let baseURL = Defaults[baseURLKey].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw TranslationError.invalidURL
        }
        let apiKey = Defaults[apiKeyKey]
        guard !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey
        }

        let promptTemplate = Defaults[systemPromptKey]
        let systemPrompt = promptTemplate.replacingOccurrences(of: "{targetLang}", with: targetLang)

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
        ]

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
