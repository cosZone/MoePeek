import Defaults
import SwiftUI

/// Reusable OpenAI-compatible API configuration fields with model fetching and connection testing.
/// Binds directly to Defaults keys so values update immediately when switching providers.
struct OpenAIConfigFields: View {
    let provider: OpenAICompatibleProvider
    var compact: Bool = false

    @State private var connectionManager: OpenAIConnectionManager
    @State private var customModelInput: String
    @State private var modelText: String
    @State private var enabledModelsState: Set<String>
    private let metaService = ModelMetadataService.shared

    init(provider: OpenAICompatibleProvider, compact: Bool = false) {
        self.provider = provider
        self.compact = compact
        self._connectionManager = State(initialValue: OpenAIConnectionManager())
        self._customModelInput = State(initialValue: "")
        self._modelText = State(initialValue: Defaults[provider.modelKey])
        self._enabledModelsState = State(initialValue: Defaults[provider.enabledModelsKey])
    }

    private var baseURL: Binding<String> { Defaults.binding(provider.baseURLKey) }
    private var apiKey: Binding<String> { Defaults.binding(provider.apiKeyKey) }
    private var model: Binding<String> {
        Binding(
            get: { modelText },
            set: { newValue in
                modelText = newValue
                Defaults[provider.modelKey] = newValue
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

    /// Chat-like model IDs to keep; filters out embedding, audio, image, moderation models.
    private static let excludedPrefixes = ["embedding", "text-embedding", "whisper", "dall-e", "tts", "davinci", "babbage"]
    private static let excludedSuffixes = ["-embedding", "-search", "-similarity"]

    private var filteredModels: [String] {
        connectionManager.fetchedModels.filter { id in
            let lower = id.lowercased()
            let excluded = Self.excludedPrefixes.contains { lower.hasPrefix($0) }
                || Self.excludedSuffixes.contains { lower.hasSuffix($0) }
                || lower.contains("embed")
                || lower.contains("moderation")
            return !excluded
        }
    }

    /// All model IDs to display: fetched (filtered) + enabled but not in fetch list.
    private var displayModels: [String] {
        let fetched = Set(filteredModels)
        let enabled = enabledModels.wrappedValue
        let unknown = enabled.subtracting(fetched).sorted()
        return filteredModels + unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Base URL
            VStack(alignment: .leading, spacing: 4) {
                Text("Base URL")
                    .font(.subheadline.bold())
                TextField(provider.baseURLKey.defaultValue, text: baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            // API Key
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.subheadline.bold())
                SecureField("sk-...", text: apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            // Default Model (fallback when no multi-model enabled)
            VStack(alignment: .leading, spacing: 4) {
                Text("Default Model")
                    .font(.subheadline.bold())
                HStack(spacing: 4) {
                    TextField(provider.modelKey.defaultValue, text: model)
                        .textFieldStyle(.roundedBorder)

                    ModelFetchAccessory(
                        connectionManager: connectionManager,
                        model: model,
                        baseURL: baseURL.wrappedValue,
                        apiKey: apiKey.wrappedValue
                    )
                }
                if !compact, enabledModels.wrappedValue.isEmpty {
                    Text("Used when no models are selected below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = connectionManager.modelFetchError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !compact {
                // Multi-model selection
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Parallel Models")
                            .font(.subheadline.bold())
                        Spacer()
                        if !enabledModels.wrappedValue.isEmpty {
                            Button("Clear All") {
                                enabledModels.wrappedValue = []
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }

                    Text("Select models to run in parallel during translation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if displayModels.isEmpty {
                        Text("Click the refresh button above to fetch available models, or add a custom model below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(displayModels, id: \.self) { modelID in
                                    ModelCheckboxRow(
                                        modelID: modelID,
                                        isEnabled: enabledModels.wrappedValue.contains(modelID),
                                        isUnknown: !filteredModels.contains(modelID),
                                        isDisabled: !enabledModels.wrappedValue.contains(modelID) && enabledModels.wrappedValue.count >= maxParallelModels,
                                        metaMatch: metaService.meta(for: modelID),
                                        onToggle: { toggleModel(modelID) }
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 160)
                    }

                    // Add custom model
                    HStack(spacing: 4) {
                        TextField("Add custom model…", text: $customModelInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addCustomModel() }

                        Button {
                            addCustomModel()
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(customModelInput.trimmingCharacters(in: .whitespaces).isEmpty || enabledModels.wrappedValue.count >= maxParallelModels)
                    }

                    let count = enabledModels.wrappedValue.count
                    if count > 0 {
                        Text("\(count) model(s) enabled — will run in parallel during translation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if metaService.hasFetched, let modelsDevURL = URL(string: "https://models.dev") {
                        HStack(spacing: 4) {
                            Text("Capability data from")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Link("Models.dev", destination: modelsDevURL)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            ConnectionTestView(
                connectionManager: connectionManager,
                baseURL: baseURL.wrappedValue,
                apiKey: apiKey.wrappedValue,
                model: model.wrappedValue
            )
        }
        .onChange(of: baseURL.wrappedValue) { _, _ in connectionManager.clearModels() }
        .onChange(of: apiKey.wrappedValue) { _, _ in connectionManager.clearModels() }
        .onReceive(Defaults.publisher(provider.modelKey).map(\.newValue)) { newValue in
            if modelText != newValue { modelText = newValue }
        }
        .onReceive(Defaults.publisher(provider.enabledModelsKey).map(\.newValue)) { newValue in
            if enabledModelsState != newValue { enabledModelsState = newValue }
        }
        .task {
            if !compact,
               connectionManager.fetchedModels.isEmpty,
               !apiKey.wrappedValue.isEmpty,
               !baseURL.wrappedValue.isEmpty {
                await connectionManager.fetchModels(
                    baseURL: baseURL.wrappedValue,
                    apiKey: apiKey.wrappedValue,
                    silent: true
                )
            }
            if !compact {
                await metaService.fetchIfNeeded()
            }
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

    private func addCustomModel() {
        let trimmed = customModelInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, enabledModels.wrappedValue.count < maxParallelModels else { return }
        enabledModels.wrappedValue.insert(trimmed)
        customModelInput = ""
    }
}

// MARK: - Model Checkbox Row

struct ModelCheckboxRow: View {
    let modelID: String
    let isEnabled: Bool
    let isUnknown: Bool
    let isDisabled: Bool
    var metaMatch: ModelMetadataService.MetaMatch? = nil
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isEnabled ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
                Text(modelID)
                    .lineLimit(1)
                if isUnknown && metaMatch == nil {
                    Text("(unknown)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if let match = metaMatch {
                    ModelCapabilityBadges(match: match)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }
}

// MARK: - Model Capability Badges

private struct ModelCapabilityBadges: View {
    let match: ModelMetadataService.MetaMatch

    private var meta: ModelMetadataService.ModelMeta { match.meta }
    private var isApproximate: Bool { match.matchKind == .approximate }

    var body: some View {
        HStack(spacing: 4) {
            if let ctx = meta.contextWindow {
                Text(formatContext(ctx))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if meta.toolCall {
                Image(systemName: "hammer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(LocalizedStringKey("Supports tool calling"))
            }
            if meta.reasoning {
                Image(systemName: "brain")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(LocalizedStringKey("Supports reasoning / chain-of-thought"))
            }
            if isApproximate {
                Image(systemName: "questionmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help(LocalizedStringKey("Capability info based on approximate match and may be inaccurate"))
            }
        }
        .opacity(isApproximate ? 0.6 : 1)
    }

    private func formatContext(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return tokens % 1_000_000 == 0
                ? "\(tokens / 1_000_000)M"
                : String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 { return "\(tokens / 1_000)K" }
        return "\(tokens)"
    }
}
