import Defaults
import SwiftUI

/// Settings view for an OpenAI-compatible provider with model fetching and connection testing.
struct OpenAICompatibleSettingsView: View {
    let provider: OpenAICompatibleProvider

    @State private var apiKey = ""

    var body: some View {
        Form {
            Section("API Configuration") {
                OpenAIConfigFields(provider: provider, apiKey: $apiKey)
            }

            Section("System Prompt") {
                TextEditor(text: Defaults.binding(provider.systemPromptKey))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                Text("Use {targetLang} as a placeholder for the target language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Defaults Binding Helper

private extension Defaults {
    static func binding(_ key: Defaults.Key<String>) -> Binding<String> {
        Binding(
            get: { Defaults[key] },
            set: { Defaults[key] = $0 }
        )
    }
}
