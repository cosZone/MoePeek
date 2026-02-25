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
/// Parameterized via `LocalLLMSettingsConfig` to handle the small differences between providers.
struct LocalLLMSettingsView: View {
    let config: LocalLLMSettingsConfig
    let baseURLKey: Defaults.Key<String>
    let modelKey: Defaults.Key<String>
    let enabledModelsKey: Defaults.Key<Set<String>>
    let systemPromptKey: Defaults.Key<String>
    let fetchModelsFromProvider: () async throws -> [String]

    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var serverStatus: ServerStatus = .unknown
    @State private var enabledModelsState: Set<String>
    @State private var modelSearchQuery: String = ""

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
        self._enabledModelsState = State(initialValue: Defaults[enabledModelsKey])
    }

    private var baseURL: Binding<String> { Defaults.binding(baseURLKey) }
    private var model: Binding<String> { Defaults.binding(modelKey) }
    private var systemPrompt: Binding<String> { Defaults.binding(systemPromptKey) }
    private var enabledModels: Binding<Set<String>> {
        Binding(
            get: { enabledModelsState },
            set: {
                enabledModelsState = $0
                Defaults[enabledModelsKey] = $0
            }
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
                    TextField(config.baseURLPlaceholder, text: baseURL)
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
                let allModels = availableModels + persistedUnknown

                if allModels.isEmpty {
                    Text("Click the refresh button above to fetch available models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    TextField("Search models…", text: $modelSearchQuery)
                        .textFieldStyle(.roundedBorder)

                    let query = modelSearchQuery.trimmingCharacters(in: .whitespaces).lowercased()
                    let filteredAvailable = query.isEmpty ? availableModels : availableModels.filter { $0.lowercased().contains(query) }
                    let filteredUnknown = query.isEmpty ? persistedUnknown : persistedUnknown.filter { $0.lowercased().contains(query) }

                    if filteredAvailable.isEmpty && filteredUnknown.isEmpty && !query.isEmpty {
                        Text("No models match your search.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filteredAvailable, id: \.self) { modelID in
                            ModelCheckboxRow(
                                modelID: modelID,
                                isEnabled: enabledModels.wrappedValue.contains(modelID),
                                isUnknown: false,
                                isDisabled: !enabledModels.wrappedValue.contains(modelID) && enabledModels.wrappedValue.count >= maxParallelModels,
                                onToggle: { toggleModel(modelID) }
                            )
                        }

                        ForEach(filteredUnknown, id: \.self) { modelID in
                            ModelCheckboxRow(
                                modelID: modelID,
                                isEnabled: true,
                                isUnknown: true,
                                isDisabled: false,
                                onToggle: { toggleModel(modelID) }
                            )
                        }
                    }
                }

                let count = enabledModels.wrappedValue.count
                if count > 0 {
                    Text("\(count) model(s) enabled — will run in parallel during translation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Running multiple local models in parallel requires sufficient VRAM. \(config.providerName) may swap models causing increased latency.")
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
        guard let pingURL = URL(string: "\(trimmed)\(config.serverCheckPath)") else {
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
            availableModels = try await fetchModelsFromProvider()
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
