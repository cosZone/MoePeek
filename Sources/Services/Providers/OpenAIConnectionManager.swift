import Foundation

/// Shared manager for fetching models and testing connections against an OpenAI-compatible API.
/// Pure value-in, value-out — no dependency on Defaults or Keychain.
@MainActor @Observable
final class OpenAIConnectionManager {

    // MARK: - Model Fetching State

    var fetchedModels: [String] = []
    var isFetchingModels = false
    var modelFetchError: String?

    // MARK: - Connection Test State

    var isTestingConnection = false
    var testResult: TestResult?

    enum TestResult: Equatable {
        case success(latencyMs: Int)
        case failure(message: String)
    }

    // MARK: - Actions

    func fetchModels(baseURL: String, apiKey: String, silent: Bool = false) async {
        guard !isFetchingModels else { return }
        guard let url = validatedURL(base: baseURL, path: "/models", apiKey: apiKey) else {
            if !silent {
                modelFetchError = String(localized: "Please enter a valid Base URL (starting with http:// or https://) and API Key")
            }
            return
        }

        isFetchingModels = true
        modelFetchError = nil
        defer { isFetchingModels = false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await translationURLSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                if !silent { modelFetchError = String(localized: "Invalid response") }
                return
            }
            guard httpResponse.statusCode == 200 else {
                if !silent { modelFetchError = String(localized: "Request failed (\(httpResponse.statusCode))") }
                return
            }
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            fetchedModels = decoded.data.map(\.id).sorted()
        } catch is DecodingError {
            if !silent { modelFetchError = String(localized: "Invalid response format") }
        } catch {
            if !silent { modelFetchError = String(localized: "Network error: \(error.localizedDescription)") }
        }
    }

    func testConnection(baseURL: String, apiKey: String, model: String) async {
        guard !isTestingConnection else { return }
        guard !model.isEmpty,
              let url = validatedURL(base: baseURL, path: "/chat/completions", apiKey: apiKey) else {
            testResult = .failure(message: String(localized: "Please fill in the complete configuration (URL must start with http:// or https://)"))
            return
        }

        isTestingConnection = true
        testResult = nil
        defer { isTestingConnection = false }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1,
            "stream": false,
            "messages": [
                ["role": "user", "content": "Hi"],
            ],
        ]

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            testResult = .failure(message: String(localized: "Request build failed"))
            return
        }

        let start = ContinuousClock.now
        do {
            let (data, response) = try await translationURLSession.data(for: request)
            let ms = Int((ContinuousClock.now - start) / .milliseconds(1))

            guard let httpResponse = response as? HTTPURLResponse else {
                testResult = .failure(message: String(localized: "Invalid response"))
                return
            }
            guard httpResponse.statusCode == 200 else {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                let preview = String(bodyText.prefix(200))
                testResult = .failure(message: "HTTP \(httpResponse.statusCode): \(preview)")
                return
            }
            testResult = .success(latencyMs: ms)
        } catch {
            testResult = .failure(message: error.localizedDescription)
        }
    }

    func clearModels() {
        fetchedModels = []
        modelFetchError = nil
        testResult = nil
    }

    // MARK: - Private

    private func validatedURL(base: String, path: String, apiKey: String) -> URL? {
        let trimmed = base.trimmingCharacters(in: .init(charactersIn: "/"))
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
              !apiKey.isEmpty else { return nil }
        return URL(string: "\(trimmed)\(path)")
    }
}

// MARK: - Models Response

private struct ModelsResponse: Decodable {
    let data: [ModelEntry]
    struct ModelEntry: Decodable {
        let id: String
    }
}
