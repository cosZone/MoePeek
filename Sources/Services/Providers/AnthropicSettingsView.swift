import Defaults
import SwiftUI

/// Settings view for the Anthropic Claude provider.
struct AnthropicSettingsView: View {
    private let provider: AnthropicProvider
    private let metaService = ModelMetadataService.shared

    @State private var connectionManager = AnthropicConnectionManager()
    @State private var baseURLText: String
    @State private var apiKeyText: String
    @State private var modelText: String
    @State private var maxTokensText: String
    @State private var enabledModelsState: Set<String>

    init() {
        let p = AnthropicProvider()
        self.provider = p
        self._baseURLText = State(initialValue: Defaults[p.baseURLKey])
        self._apiKeyText = State(initialValue: Defaults[p.apiKeyKey])
        self._modelText = State(initialValue: Defaults[p.modelKey])
        self._maxTokensText = State(initialValue: String(Defaults[p.maxTokensKey]))
        self._enabledModelsState = State(initialValue: Defaults[p.enabledModelsKey])
    }

    private var model: Binding<String> {
        Binding(
            get: { modelText },
            set: {
                modelText = $0
                Defaults[provider.modelKey] = $0
            }
        )
    }

    private var enabledModels: Binding<Set<String>> {
        Binding(
            get: { enabledModelsState },
            set: {
                enabledModelsState = $0
                Defaults[provider.enabledModelsKey] = $0
            }
        )
    }

    var body: some View {
        Form {
            Section("API Configuration") {
                apiConfigurationSection
            }

            Section("Parallel Models") {
                parallelModelsSection
            }

            Section("System Prompt") {
                TextEditor(text: Defaults.binding(provider.systemPromptKey))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                Text("Use {targetLang} as a placeholder for the target language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                    Label("Get API Key from Anthropic", systemImage: "arrow.up.right.square")
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .onChange(of: baseURLText) { _, newValue in
            Defaults[provider.baseURLKey] = newValue
            connectionManager.clearModels()
        }
        .onChange(of: apiKeyText) { _, newValue in
            Defaults[provider.apiKeyKey] = newValue
            connectionManager.clearModels()
        }
        .onReceive(Defaults.publisher(provider.baseURLKey).map(\.newValue)) { newValue in
            if baseURLText != newValue { baseURLText = newValue }
        }
        .onReceive(Defaults.publisher(provider.apiKeyKey).map(\.newValue)) { newValue in
            if apiKeyText != newValue { apiKeyText = newValue }
        }
        .onReceive(Defaults.publisher(provider.modelKey).map(\.newValue)) { newValue in
            if modelText != newValue { modelText = newValue }
        }
        .onReceive(Defaults.publisher(provider.enabledModelsKey).map(\.newValue)) { newValue in
            if enabledModelsState != newValue { enabledModelsState = newValue }
        }
        .onReceive(Defaults.publisher(provider.maxTokensKey).map(\.newValue)) { newValue in
            let text = String(newValue)
            if maxTokensText != text { maxTokensText = text }
        }
        .task {
            if connectionManager.fetchedModels.isEmpty,
               !apiKeyText.isEmpty, !baseURLText.isEmpty {
                await connectionManager.fetchModels(baseURL: baseURLText, apiKey: apiKeyText, silent: true)
            }
            await metaService.fetchIfNeeded()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var apiConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Base URL
            VStack(alignment: .leading, spacing: 4) {
                Text("Base URL")
                    .font(.subheadline.bold())
                TextField("https://api.anthropic.com", text: $baseURLText)
                    .textFieldStyle(.roundedBorder)
            }

            // API Key
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.subheadline.bold())
                SecureField("sk-ant-...", text: $apiKeyText)
                    .textFieldStyle(.roundedBorder)
            }

            // Default Model
            VStack(alignment: .leading, spacing: 4) {
                Text("Default Model")
                    .font(.subheadline.bold())
                HStack(spacing: 4) {
                    TextField("claude-sonnet-4-5-20250929", text: model)
                        .textFieldStyle(.roundedBorder)
                    AnthropicModelFetchAccessory(
                        connectionManager: connectionManager,
                        model: model,
                        baseURL: baseURLText,
                        apiKey: apiKeyText
                    )
                }
                if enabledModels.wrappedValue.isEmpty {
                    Text("Used when no models are selected below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = connectionManager.modelFetchError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .lineLimit(2)
                }
            }

            // Max Tokens
            VStack(alignment: .leading, spacing: 4) {
                Text("Max Tokens")
                    .font(.subheadline.bold())
                TextField("4096", text: $maxTokensText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: maxTokensText) { _, newValue in
                        if let value = Int(newValue), value > 0 {
                            Defaults[provider.maxTokensKey] = value
                        }
                    }
                Text("Anthropic API requires max_tokens. Default: 4096.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Connection Test
            HStack(spacing: 8) {
                Button {
                    Task {
                        await connectionManager.testConnection(
                            baseURL: baseURLText,
                            apiKey: apiKeyText,
                            model: model.wrappedValue
                        )
                    }
                } label: {
                    Label("Test Connection", systemImage: "bolt.horizontal")
                }
                .disabled(apiKeyText.isEmpty || baseURLText.isEmpty || model.wrappedValue.isEmpty || connectionManager.isTestingConnection)

                if connectionManager.isTestingConnection {
                    ProgressView()
                        .controlSize(.small)
                }

                if let result = connectionManager.testResult {
                    switch result {
                    case .success(let latencyMs):
                        Label("Connection successful (\(latencyMs)ms)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var parallelModelsSection: some View {
        ParallelModelsList(
            fetchedModels: connectionManager.fetchedModels,
            enabledModels: enabledModels,
            metaService: metaService,
            defaultModel: modelText
        )
    }
}

// MARK: - Anthropic Model Fetch Accessory

/// Trailing accessory for model text field: fetch progress, model dropdown, or refresh button.
private struct AnthropicModelFetchAccessory: View {
    let connectionManager: AnthropicConnectionManager
    @Binding var model: String
    let baseURL: String
    let apiKey: String

    var body: some View {
        if connectionManager.isFetchingModels {
            ProgressView()
                .controlSize(.small)
        } else if !connectionManager.fetchedModels.isEmpty {
            HStack(spacing: 2) {
                Menu {
                    ForEach(connectionManager.fetchedModels, id: \.self) { id in
                        Button(id) { model = id }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    Task { await connectionManager.fetchModels(baseURL: baseURL, apiKey: apiKey) }
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .buttonStyle(.borderless)
                .help("Refresh model list")
            }
        } else {
            Button {
                Task { await connectionManager.fetchModels(baseURL: baseURL, apiKey: apiKey) }
            } label: {
                Image(systemName: "arrow.clockwise.circle")
            }
            .buttonStyle(.borderless)
            .disabled(apiKey.isEmpty || baseURL.isEmpty)
            .help("Fetch available models")
        }
    }
}
