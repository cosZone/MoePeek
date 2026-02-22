import Defaults
import Foundation
import SwiftUI

/// Ollama local LLM provider. Uses Ollama's native API for model listing
/// and OpenAI-compatible endpoint for translation.
struct OllamaProvider: TranslationProvider {
    let id = "ollama"
    let displayName = "Ollama"
    let iconSystemName = "desktopcomputer"
    let category: ProviderCategory = .llm
    let supportsStreaming = true
    let isAvailable = true

    let baseURLKey = Defaults.Key<String>("provider_ollama_baseURL", default: "http://localhost:11434")
    let modelKey = Defaults.Key<String>("provider_ollama_model", default: "")
    let enabledModelsKey = Defaults.Key<Set<String>>("provider_ollama_enabledModels", default: [])
    let systemPromptKey = Defaults.Key<String>(
        "provider_ollama_systemPrompt",
        default: "Translate the following text to {targetLang}. Only output the translation, nothing else."
    )

    /// Models explicitly enabled for parallel translation. Empty means use default single model.
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

                    guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
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
                        message: String(localized: "Ollama server not running at \(baseURL)")
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
        AnyView(OllamaSettingsView(provider: self))
    }

    /// Fetch available models from Ollama's native API.
    func fetchModels() async throws -> [String] {
        guard let url = URL(string: "\(resolvedBaseURL)/api/tags") else {
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

        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models.map(\.name)
    }
}

// MARK: - Response Models

private struct OllamaTagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
        let name: String
    }
}

// MARK: - Settings View

private struct OllamaSettingsView: View {
    let provider: OllamaProvider

    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var serverStatus: ServerStatus = .unknown

    private var baseURL: Binding<String> { Defaults.binding(provider.baseURLKey) }
    private var model: Binding<String> { Defaults.binding(provider.modelKey) }
    private var systemPrompt: Binding<String> { Defaults.binding(provider.systemPromptKey) }
    private var enabledModels: Binding<Set<String>> {
        Binding(
            get: { Defaults[provider.enabledModelsKey] },
            set: { Defaults[provider.enabledModelsKey] = $0 }
        )
    }

    private enum ServerStatus {
        case unknown, checking, running, notDetected
    }

    var body: some View {
        Form {
            Section("Server") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL")
                        .font(.subheadline.bold())
                    TextField("http://localhost:11434", text: baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 8) {
                    statusIndicator
                    Spacer()
                    Button("Check Connection") {
                        Task { await checkServer() }
                    }
                    .controlSize(.small)
                }
            }

            Section("Default Model") {
                HStack(spacing: 4) {
                    if availableModels.isEmpty {
                        TextField("Model name", text: model)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("", selection: model) {
                            Text("Select a model").tag("")
                            ForEach(availableModels, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                    }

                    Button {
                        Task { await fetchModels() }
                    } label: {
                        if isFetchingModels {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isFetchingModels)
                }

                if !availableModels.isEmpty {
                    if enabledModels.wrappedValue.isEmpty {
                        Text("Used when no models are selected below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Parallel Models") {
                Text("Select models to run in parallel during translation (max \(maxParallelModels)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let persistedUnknown = enabledModels.wrappedValue.subtracting(Set(availableModels)).sorted()
                let allDisplayModels = availableModels + persistedUnknown

                if allDisplayModels.isEmpty {
                    Text("Click the refresh button above to fetch available models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(availableModels, id: \.self) { modelID in
                        ModelCheckboxRow(
                            modelID: modelID,
                            isEnabled: enabledModels.wrappedValue.contains(modelID),
                            isUnknown: false,
                            isDisabled: !enabledModels.wrappedValue.contains(modelID) && enabledModels.wrappedValue.count >= maxParallelModels,
                            onToggle: { toggleModel(modelID) }
                        )
                    }

                    ForEach(persistedUnknown, id: \.self) { modelID in
                        ModelCheckboxRow(
                            modelID: modelID,
                            isEnabled: true,
                            isUnknown: true,
                            isDisabled: false,
                            onToggle: { toggleModel(modelID) }
                        )
                    }
                }

                let count = enabledModels.wrappedValue.count
                if count > 0 {
                    Text("\(count) model(s) enabled — will run in parallel during translation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Running multiple local models in parallel requires sufficient VRAM. Ollama may swap models causing increased latency.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("System Prompt") {
                TextEditor(text: systemPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                Text("Use {targetLang} as a placeholder for the target language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Link(destination: URL(string: "https://ollama.com")!) {
                    Label("Download Ollama", systemImage: "arrow.up.right.square")
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .task {
            await checkServer()
            if serverStatus == .running, availableModels.isEmpty {
                await fetchModels(silent: true)
            }
        }
        .onChange(of: baseURL.wrappedValue) { _, _ in
            serverStatus = .unknown
            availableModels = []
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch serverStatus {
        case .unknown:
            Label("Not checked", systemImage: "questionmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.callout).foregroundStyle(.secondary)
            }
        case .running:
            Label("Running", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .notDetected:
            Label("Not detected", systemImage: "xmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    @MainActor
    private func checkServer() async {
        serverStatus = .checking
        let trimmed = baseURL.wrappedValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let pingURL = URL(string: "\(trimmed)/api/tags") else {
            serverStatus = .notDetected
            return
        }
        var request = URLRequest(url: pingURL)
        request.timeoutInterval = 3
        do {
            let (_, response) = try await translationURLSession.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                serverStatus = .running
            } else {
                serverStatus = .notDetected
            }
        } catch {
            serverStatus = .notDetected
        }
    }

    @MainActor
    private func fetchModels(silent: Bool = false) async {
        isFetchingModels = true
        defer { isFetchingModels = false }
        do {
            availableModels = try await provider.fetchModels()
            if !availableModels.isEmpty, model.wrappedValue.isEmpty {
                model.wrappedValue = availableModels[0]
            }
            serverStatus = .running
        } catch {
            if !silent { serverStatus = .notDetected }
        }
    }

    private func toggleModel(_ modelID: String) {
        var current = enabledModels.wrappedValue
        if current.contains(modelID) {
            current.remove(modelID)
        } else {
            guard current.count < maxParallelModels else { return }
            current.insert(modelID)
        }
        enabledModels.wrappedValue = current
    }
}
