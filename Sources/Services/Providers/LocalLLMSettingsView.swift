import Defaults
import Foundation
import SwiftUI

/// Configuration that captures the differences between LM Studio and Ollama settings views.
struct LocalLLMSettingsConfig {
    let baseURLPlaceholder: String
    let serverCheckPath: String
    let providerName: String
    let downloadURL: String
    let downloadLabel: String
}

/// Shared settings view for local LLM providers (LM Studio, Ollama).
/// Renders the Anthropic-style Form layout with separate sections for API config,
/// parallel models, system prompt, and a download link.
struct LocalLLMSettingsView: View {
    let config: LocalLLMSettingsConfig
    let baseURLKey: Defaults.Key<String>
    let modelKey: Defaults.Key<String>
    let enabledModelsKey: Defaults.Key<Set<String>>
    let systemPromptKey: Defaults.Key<String>
    let fetchModelsFromProvider: () async throws -> [String]

    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var isTestingConnection = false
    @State private var testResult: ConnectionTestResult?
    @State private var baseURLText: String
    @State private var modelText: String
    @State private var enabledModelsState: Set<String>
    private let metaService = ModelMetadataService.shared

    private enum ConnectionTestResult {
        case success(latencyMs: Int)
        case failure(message: String)
    }

    init(
        config: LocalLLMSettingsConfig,
        baseURLKey: Defaults.Key<String>,
        modelKey: Defaults.Key<String>,
        enabledModelsKey: Defaults.Key<Set<String>>,
        systemPromptKey: Defaults.Key<String>,
        fetchModels: @escaping () async throws -> [String]
    ) {
        self.config = config
        self.baseURLKey = baseURLKey
        self.modelKey = modelKey
        self.enabledModelsKey = enabledModelsKey
        self.systemPromptKey = systemPromptKey
        self.fetchModelsFromProvider = fetchModels
        self._baseURLText = State(initialValue: Defaults[baseURLKey])
        self._modelText = State(initialValue: Defaults[modelKey])
        self._enabledModelsState = State(initialValue: Defaults[enabledModelsKey])
    }

    private var model: Binding<String> {
        Binding(
            get: { modelText },
            set: {
                modelText = $0
                Defaults[modelKey] = $0
            }
        )
    }
    private var enabledModels: Binding<Set<String>> {
        Binding(
            get: { enabledModelsState },
            set: {
                enabledModelsState = $0
                Defaults[enabledModelsKey] = $0
            }
        )
    }

    var body: some View {
        Form {
            Section("API Configuration") {
                apiConfigurationSection
            }

            Section("Parallel Models") {
                ParallelModelsList(
                    fetchedModels: availableModels,
                    enabledModels: enabledModels,
                    metaService: metaService,
                    defaultModel: modelText
                )

                if !enabledModels.wrappedValue.isEmpty {
                    Text("Running multiple local models in parallel requires sufficient VRAM. \(config.providerName) may swap models causing increased latency.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("System Prompt") {
                TextEditor(text: Defaults.binding(systemPromptKey))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                Text("Use {targetLang} as a placeholder for the target language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let downloadURL = URL(string: config.downloadURL) {
                Section {
                    Link(destination: downloadURL) {
                        Label(config.downloadLabel, systemImage: "arrow.up.right.square")
                    }
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: baseURLText) { _, newValue in
            Defaults[baseURLKey] = newValue
            availableModels = []
            testResult = nil
        }
        .onReceive(Defaults.publisher(baseURLKey).map(\.newValue)) { newValue in
            if baseURLText != newValue { baseURLText = newValue }
        }
        .onReceive(Defaults.publisher(modelKey).map(\.newValue)) { newValue in
            if modelText != newValue { modelText = newValue }
        }
        .onReceive(Defaults.publisher(enabledModelsKey).map(\.newValue)) { newValue in
            if enabledModelsState != newValue { enabledModelsState = newValue }
        }
        .task {
            if availableModels.isEmpty, !baseURLText.isEmpty {
                await fetchModels(silent: true)
            }
            await metaService.fetchIfNeeded()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var apiConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Base URL")
                    .font(.subheadline.bold())
                TextField(config.baseURLPlaceholder, text: $baseURLText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Default Model")
                    .font(.subheadline.bold())
                HStack(spacing: 4) {
                    TextField("Model name", text: model)
                        .textFieldStyle(.roundedBorder)
                    localModelFetchAccessory
                }
                if enabledModels.wrappedValue.isEmpty {
                    Text("Used when no models are selected below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await testConnection() }
                } label: {
                    Label("Test Connection", systemImage: "bolt.horizontal")
                }
                .disabled(baseURLText.isEmpty || isTestingConnection)

                if isTestingConnection {
                    ProgressView()
                        .controlSize(.small)
                }

                if let result = testResult {
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
    private var localModelFetchAccessory: some View {
        if isFetchingModels {
            ProgressView()
                .controlSize(.small)
        } else if !availableModels.isEmpty {
            HStack(spacing: 2) {
                Menu {
                    ForEach(availableModels, id: \.self) { id in
                        Button(id) { model.wrappedValue = id }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    Task { await fetchModels() }
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .buttonStyle(.borderless)
                .help("Refresh model list")
            }
        } else {
            Button {
                Task { await fetchModels() }
            } label: {
                Image(systemName: "arrow.clockwise.circle")
            }
            .buttonStyle(.borderless)
            .disabled(baseURLText.isEmpty)
            .help("Fetch available models")
        }
    }

    // MARK: - Actions

    @MainActor
    private func testConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        let trimmed = baseURLText.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let pingURL = URL(string: "\(trimmed)\(config.serverCheckPath)") else {
            testResult = .failure(message: "Invalid URL")
            return
        }
        var request = URLRequest(url: pingURL)
        request.timeoutInterval = 3
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await translationURLSession.data(for: request)
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                testResult = .success(latencyMs: elapsed)
            } else {
                testResult = .failure(message: "Server returned non-200 status")
            }
        } catch {
            testResult = .failure(message: error.localizedDescription)
        }
    }

    @MainActor
    private func fetchModels(silent: Bool = false) async {
        isFetchingModels = true
        defer { isFetchingModels = false }
        do {
            availableModels = try await fetchModelsFromProvider()
            if !availableModels.isEmpty, modelText.isEmpty {
                model.wrappedValue = availableModels[0]
            }
        } catch {
            if !silent { testResult = .failure(message: error.localizedDescription) }
        }
    }
}
