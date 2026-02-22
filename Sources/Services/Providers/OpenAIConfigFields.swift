import Defaults
import SwiftUI

/// Reusable OpenAI-compatible API configuration fields with model fetching and connection testing.
/// Binds directly to Defaults keys so values update immediately when switching providers.
struct OpenAIConfigFields: View {
    let provider: OpenAICompatibleProvider

    @State private var connectionManager = OpenAIConnectionManager()
    @State private var customModelInput = ""

    private var baseURL: Binding<String> { Defaults.binding(provider.baseURLKey) }
    private var apiKey: Binding<String> { Defaults.binding(provider.apiKeyKey) }
    private var model: Binding<String> { Defaults.binding(provider.modelKey) }
    private var enabledModels: Binding<Set<String>> {
        Binding(
            get: { Defaults[provider.enabledModelsKey] },
            set: { Defaults[provider.enabledModelsKey] = $0 }
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
                if enabledModels.wrappedValue.isEmpty {
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

                Text("Select models to run in parallel during translation (max 5).")
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
                                    isDisabled: !enabledModels.wrappedValue.contains(modelID) && enabledModels.wrappedValue.count >= 5,
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
                    .disabled(customModelInput.trimmingCharacters(in: .whitespaces).isEmpty || enabledModels.wrappedValue.count >= 5)
                }

                let count = enabledModels.wrappedValue.count
                if count > 0 {
                    Text("\(count) model(s) enabled — will run in parallel during translation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .task {
            if connectionManager.fetchedModels.isEmpty,
               !apiKey.wrappedValue.isEmpty,
               !baseURL.wrappedValue.isEmpty {
                await connectionManager.fetchModels(
                    baseURL: baseURL.wrappedValue,
                    apiKey: apiKey.wrappedValue,
                    silent: true
                )
            }
        }
    }

    private func toggleModel(_ modelID: String) {
        var current = enabledModels.wrappedValue
        if current.contains(modelID) {
            current.remove(modelID)
        } else {
            guard current.count < 5 else { return }
            current.insert(modelID)
        }
        enabledModels.wrappedValue = current
    }

    private func addCustomModel() {
        let trimmed = customModelInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, enabledModels.wrappedValue.count < 5 else { return }
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
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isEnabled ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
                Text(modelID)
                    .lineLimit(1)
                if isUnknown {
                    Text("(unknown)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
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
