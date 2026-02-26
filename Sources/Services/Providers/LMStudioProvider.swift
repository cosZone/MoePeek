import Defaults
import Foundation
import SwiftUI

/// LM Studio local LLM provider. Uses OpenAI-compatible API endpoints
/// (default: http://localhost:1234/v1). No API key required.
struct LMStudioProvider: TranslationProvider {
    let id = "lmstudio"
    let displayName = "LM Studio"
    let iconSystemName = "cpu"
    let iconAssetName: String? = "LMStudio"
    let category: ProviderCategory = .llm
    let supportsStreaming = true
    let isAvailable = true

    let baseURLKey = Defaults.Key<String>("provider_lmstudio_baseURL", default: "http://localhost:1234/v1")
    let modelKey = Defaults.Key<String>("provider_lmstudio_model", default: "")
    let enabledModelsKey = Defaults.Key<Set<String>>("provider_lmstudio_enabledModels", default: [])
    let systemPromptKey = Defaults.Key<String>(
        "provider_lmstudio_systemPrompt",
        default: "Translate the following text to {targetLang}. Only output the translation, nothing else."
    )

    var activeModels: [String] {
        let enabled = Defaults[enabledModelsKey]
        return enabled.isEmpty ? [] : enabled.sorted()
    }

    var resolvedBaseURL: String {
        Defaults[baseURLKey].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    @MainActor
    var isConfigured: Bool { !Defaults[modelKey].isEmpty }

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
                let baseURL = resolvedBaseURL
                do {
                    guard !model.isEmpty else {
                        throw TranslationError.apiError(
                            statusCode: 0,
                            message: String(localized: "No model selected. Please select a model in Settings.")
                        )
                    }

                    guard let url = URL(string: "\(baseURL)/chat/completions") else {
                        throw TranslationError.invalidURL
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
                    request.timeoutInterval = 60
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await translationURLSession.bytes(for: request)
                    try await streamOpenAISSE(bytes, response: response, to: continuation)
                    continuation.finish()
                } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .timedOut {
                    continuation.finish(throwing: TranslationError.apiError(
                        statusCode: 0,
                        message: String(localized: "LM Studio server not running at \(baseURL)")
                    ))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @MainActor
    func makeSettingsView() -> AnyView {
        AnyView(LocalLLMSettingsView(
            config: LocalLLMSettingsConfig(
                baseURLPlaceholder: "http://localhost:1234/v1",
                serverCheckPath: "/models",
                providerName: "LM Studio",
                downloadURL: "https://lmstudio.ai",
                downloadLabel: "Download LM Studio"
            ),
            baseURLKey: baseURLKey,
            modelKey: modelKey,
            enabledModelsKey: enabledModelsKey,
            systemPromptKey: systemPromptKey,
            fetchModels: fetchModels
        ))
    }

    /// Fetch available models from LM Studio's OpenAI-compatible `/models` endpoint.
    func fetchModels() async throws -> [String] {
        guard let url = URL(string: "\(resolvedBaseURL)/models") else {
            throw TranslationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

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

        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data.map(\.id).sorted()
    }
}

// MARK: - Response Models

private struct OpenAIModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}

