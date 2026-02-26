import Defaults
import Foundation
import SwiftUI

/// Translation provider for Anthropic's Claude API.
/// Uses Anthropic's Messages API which differs from OpenAI-compatible format:
/// - Auth via `x-api-key` header (not Bearer token)
/// - System prompt as top-level `system` field (not in messages array)
/// - `max_tokens` is required
/// - Different SSE event format
struct AnthropicProvider: TranslationProvider {
    static let apiVersion = "2023-06-01"

    let id = "anthropic"
    let displayName = "Anthropic"
    let iconSystemName = "brain.filled.head.profile"
    let iconAssetName: String? = "Anthropic"
    var category: ProviderCategory { .llm }
    let supportsStreaming = true
    let isAvailable = true

    // Namespaced Defaults keys
    let baseURLKey = Defaults.Key<String>("provider_anthropic_baseURL", default: "https://api.anthropic.com")
    let apiKeyKey = Defaults.Key<String>("provider_anthropic_apiKey", default: "")
    let modelKey = Defaults.Key<String>("provider_anthropic_model", default: "claude-sonnet-4-5-20250929")
    let enabledModelsKey = Defaults.Key<Set<String>>("provider_anthropic_enabledModels", default: [])
    let systemPromptKey = Defaults.Key<String>(
        "provider_anthropic_systemPrompt",
        default: "Translate the following text to {targetLang}. Only output the translation, nothing else."
    )
    let maxTokensKey = Defaults.Key<Int>("provider_anthropic_maxTokens", default: 4096)

    var activeModels: [String] {
        let enabled = Defaults[enabledModelsKey]
        return enabled.isEmpty ? [] : enabled.sorted()
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
                    try await streamAnthropicSSE(bytes, response: response, to: continuation)
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
        AnyView(AnthropicSettingsView())
    }

    // MARK: - Private

    private func buildRequest(text: String, sourceLang: String?, targetLang: String, model: String) throws -> URLRequest {
        let baseURL = Defaults[baseURLKey].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw TranslationError.invalidURL
        }
        let apiKey = Defaults[apiKeyKey]
        guard !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey
        }

        let promptTemplate = Defaults[systemPromptKey]
        let systemPrompt = promptTemplate.replacingOccurrences(of: "{targetLang}", with: targetLang)
        let maxTokens = Defaults[maxTokensKey]

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": text],
            ],
        ]

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Parse Anthropic SSE stream format and yield text deltas.
    private func streamAnthropicSSE(
        _ bytes: URLSession.AsyncBytes,
        response: URLResponse,
        to continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            // Try to extract a clear error message from the response
            if let data = errorBody.data(using: .utf8),
               let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
                throw TranslationError.apiError(
                    statusCode: httpResponse.statusCode,
                    message: errorResponse.error.message
                )
            }
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        for try await line in bytes.lines {
            guard !Task.isCancelled else { break }

            // Skip event: lines, empty lines, and non-data lines
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            guard let data = payload.data(using: .utf8),
                  let event = try? JSONDecoder().decode(AnthropicSSEEvent.self, from: data)
            else { continue }

            switch event.type {
            case "content_block_delta":
                if let delta = event.delta, delta.type == "text_delta", let text = delta.text {
                    continuation.yield(text)
                }
            case "message_stop":
                return
            case "error":
                if let error = event.error {
                    throw TranslationError.apiError(statusCode: 0, message: error.message)
                }
            default:
                // message_start, content_block_start, content_block_stop, message_delta, ping — skip
                continue
            }
        }
    }
}

// MARK: - Anthropic SSE Decodable Types (private to this file)

/// Unified Anthropic SSE event with optional fields for different event types.
private struct AnthropicSSEEvent: Decodable {
    let type: String
    let delta: Delta?
    let error: ErrorDetail?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }

    struct ErrorDetail: Decodable {
        let type: String
        let message: String
    }
}

