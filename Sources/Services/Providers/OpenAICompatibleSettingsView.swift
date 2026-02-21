import Defaults
import SwiftUI

/// Settings view for an OpenAI-compatible provider with model fetching and connection testing.
struct OpenAICompatibleSettingsView: View {
    let provider: OpenAICompatibleProvider

    var body: some View {
        Form {
            Section("API Configuration") {
                OpenAIConfigFields(provider: provider)
            }

            Section("System Prompt") {
                TextEditor(text: Defaults.binding(provider.systemPromptKey))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                Text("Use {targetLang} as a placeholder for the target language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let urlString = provider.guideURL, let url = URL(string: urlString) {
                Section {
                    Link(destination: url) {
                        Label("Get API Key from \(provider.displayName)", systemImage: "arrow.up.right.square")
                    }
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Defaults Binding Helper

extension Defaults {
    static func binding(_ key: Defaults.Key<String>) -> Binding<String> {
        Binding(
            get: { Defaults[key] },
            set: { Defaults[key] = $0 }
        )
    }
}
