import SwiftUI

/// Trailing accessory for a model text field: fetch progress, model dropdown, or refresh button.
struct ModelFetchAccessory: View {
    let connectionManager: OpenAIConnectionManager
    @Binding var model: String
    let baseURL: String
    let apiKey: String
    var extraHeaders: [String: String]? = nil

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
                    Task { await connectionManager.fetchModels(baseURL: baseURL, apiKey: apiKey, extraHeaders: extraHeaders) }
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .buttonStyle(.borderless)
                .help("Refresh model list")
            }
        } else {
            Button {
                Task { await connectionManager.fetchModels(baseURL: baseURL, apiKey: apiKey, extraHeaders: extraHeaders) }
            } label: {
                Image(systemName: "arrow.clockwise.circle")
            }
            .buttonStyle(.borderless)
            .disabled(apiKey.isEmpty || baseURL.isEmpty)
            .help("Fetch available models")
        }
    }
}

/// Connection test button with progress indicator and result display.
struct ConnectionTestView: View {
    let connectionManager: OpenAIConnectionManager
    let baseURL: String
    let apiKey: String
    let model: String
    var extraHeaders: [String: String]? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task { await connectionManager.testConnection(baseURL: baseURL, apiKey: apiKey, model: model, extraHeaders: extraHeaders) }
            } label: {
                Label("Test Connection", systemImage: "bolt.horizontal")
            }
            .disabled(apiKey.isEmpty || baseURL.isEmpty || model.isEmpty || connectionManager.isTestingConnection)

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
                        .lineLimit(2)
                }
            }
        }
    }
}
