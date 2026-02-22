import Foundation
import SwiftUI

// MARK: - Provider Category

enum ProviderCategory: String, CaseIterable {
    case freeTranslation, traditional, llm, custom, system

    var displayName: String {
        switch self {
        case .freeTranslation: String(localized: "Free Translation")
        case .llm: String(localized: "LLM Services")
        case .traditional: String(localized: "Translation APIs")
        case .custom: String(localized: "Custom")
        case .system: String(localized: "System")
        }
    }
}

/// Plugin protocol for translation backends. Each provider is self-contained:
/// owns its translation logic, settings UI, and configuration storage.
protocol TranslationProvider: Sendable {
    /// Unique identifier used for Defaults/Keychain namespacing, e.g. "openai", "apple".
    var id: String { get }
    /// Display name shown in UI.
    var displayName: String { get }
    /// SF Symbol icon name.
    var iconSystemName: String { get }
    /// Provider category for UI grouping.
    var category: ProviderCategory { get }
    /// Whether this provider supports streaming output.
    var supportsStreaming: Bool { get }
    /// Whether this provider is available on the current system.
    var isAvailable: Bool { get }
    /// Whether the provider has been configured (e.g. API key set).
    @MainActor var isConfigured: Bool { get }
    /// Whether the provider can be deleted by the user (e.g. custom providers).
    var isDeletable: Bool { get }

    /// Models explicitly enabled for parallel translation. Empty means single-model (use default).
    var activeModels: [String] { get }

    /// Stream translation results. Non-streaming providers yield the full result at once.
    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String
    ) -> AsyncThrowingStream<String, Error>

    /// Stream translation using a specific model override.
    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String,
        model: String
    ) -> AsyncThrowingStream<String, Error>

    /// Return a settings view for this provider.
    @MainActor func makeSettingsView() -> AnyView
}

// MARK: - Default Implementation

/// Maximum number of models that can be enabled for parallel translation per provider.
let maxParallelModels = 20

extension TranslationProvider {
    var category: ProviderCategory { .llm }
    var isDeletable: Bool { false }
    var activeModels: [String] { [] }

    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        translateStream(text, from: sourceLang, to: targetLang)
    }
}

// MARK: - ModelSlotProvider

/// Wraps a provider to run a specific model. Conforms to `TranslationProvider`,
/// so downstream code (Coordinator, PopupView, ResultCard) needs zero changes.
struct ModelSlotProvider: TranslationProvider {
    let inner: any TranslationProvider
    let modelOverride: String

    var id: String { "\(inner.id):\(modelOverride)" }
    var displayName: String { "\(inner.displayName) · \(modelOverride)" }
    var iconSystemName: String { inner.iconSystemName }
    var category: ProviderCategory { inner.category }
    var supportsStreaming: Bool { inner.supportsStreaming }
    var isAvailable: Bool { inner.isAvailable }
    @MainActor var isConfigured: Bool { inner.isConfigured }
    // activeModels is intentionally `[]` via the protocol default —
    // a ModelSlotProvider is already a single-model leaf; nesting is not supported.

    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String
    ) -> AsyncThrowingStream<String, Error> {
        inner.translateStream(text, from: sourceLang, to: targetLang, model: modelOverride)
    }

    @MainActor func makeSettingsView() -> AnyView { inner.makeSettingsView() }
}

// MARK: - Shared URLSession (zero-cache)

/// A shared URLSession with caching disabled. Translation API responses are unique
/// per request and should not be cached; using the default URLSession.shared would
/// accumulate up to 25 MB+ of useless cache data over time.
let translationURLSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: config)
}()

// MARK: - Non-Streaming Helper

extension TranslationProvider {
    /// Wrap a single-result async translation as a one-shot `AsyncThrowingStream`.
    /// Used by non-streaming providers to avoid duplicating the stream boilerplate.
    func singleResultStream(
        _ operation: @escaping @Sendable () async throws -> String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await operation()
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - OpenAI-Compatible SSE Streaming Helper

extension TranslationProvider {
    /// Stream an OpenAI-compatible SSE response, validating the HTTP status
    /// and yielding content deltas to the continuation.
    func streamOpenAISSE(
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
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        for try await line in bytes.lines {
            guard !Task.isCancelled else { break }

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONDecoder().decode(OpenAISSEChunk.self, from: data),
                  let content = json.choices.first?.delta.content
            else { continue }

            continuation.yield(content)
        }
    }
}

// MARK: - Shared SSE Models

/// OpenAI-compatible SSE chunk format used by streaming providers (OpenAI, Ollama, etc.).
struct OpenAISSEChunk: Decodable, Sendable {
    let choices: [Choice]

    struct Choice: Decodable, Sendable {
        let delta: Delta
    }

    struct Delta: Decodable, Sendable {
        let content: String?
    }
}

// MARK: - Translation Errors

enum TranslationError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingAPIKey
    case apiError(statusCode: Int, message: String)
    case emptyResult
    case languageNotInstalled(source: String?, target: String)
    case languageUnsupported(source: String?, target: String)
    case translationSessionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return String(localized: "Invalid API URL")
        case .invalidResponse: return String(localized: "Invalid response from server")
        case .missingAPIKey: return String(localized: "API key not configured. Go to Settings to set it up.")
        case let .apiError(code, msg): return String(localized: "API error (\(code)): \(msg)")
        case .emptyResult: return String(localized: "Translation returned empty result")
        case let .languageNotInstalled(src, tgt):
            let source = src ?? String(localized: "auto")
            return String(localized: "Language pack not downloaded (\(source) → \(tgt)). Download it in Settings or try another provider.")
        case let .languageUnsupported(src, tgt):
            let source = src ?? String(localized: "auto")
            return String(localized: "Language pair not supported (\(source) → \(tgt)). Try another provider.")
        case .translationSessionFailed:
            return String(localized: "Translation session ended unexpectedly. Please try again.")
        }
    }
}
