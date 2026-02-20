import Defaults
import SwiftUI

/// Reusable OpenAI-compatible API configuration fields with model fetching and connection testing.
/// Loads from provider on appear; saves to Defaults/Keychain on submit and disappear — not on every keystroke.
struct OpenAIConfigFields: View {
    let provider: OpenAICompatibleProvider
    /// Exposed so parents can observe the current API key state (e.g. to highlight a button).
    @Binding var apiKey: String

    @State private var connectionManager = OpenAIConnectionManager()
    @State private var baseURL = ""
    @State private var model = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Base URL")
                    .font(.subheadline.bold())
                TextField("https://api.openai.com/v1", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.subheadline.bold())
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.subheadline.bold())
                HStack(spacing: 4) {
                    TextField("gpt-4o-mini", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { save() }

                    ModelFetchAccessory(
                        connectionManager: connectionManager,
                        model: $model,
                        baseURL: baseURL,
                        apiKey: apiKey
                    )
                }
            }

            if let error = connectionManager.modelFetchError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ConnectionTestView(
                connectionManager: connectionManager,
                baseURL: baseURL,
                apiKey: apiKey,
                model: model
            )
        }
        .onAppear { load() }
        .onDisappear { save() }
        .onChange(of: baseURL) { _, _ in connectionManager.clearModels() }
        .onChange(of: apiKey) { _, _ in connectionManager.clearModels() }
    }

    private func save() {
        if apiKey.isEmpty {
            KeychainHelper.delete(key: provider.keychainKey)
        } else {
            KeychainHelper.save(key: provider.keychainKey, value: apiKey)
        }
        Defaults[provider.baseURLKey] = baseURL
        Defaults[provider.modelKey] = model
    }

    private func load() {
        baseURL = Defaults[provider.baseURLKey]
        model = Defaults[provider.modelKey]
        apiKey = KeychainHelper.load(key: provider.keychainKey) ?? ""
    }
}
