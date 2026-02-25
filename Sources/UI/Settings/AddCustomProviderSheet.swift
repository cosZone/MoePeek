import Defaults
import SwiftUI

struct AddCustomProviderSheet: View {
    let registry: TranslationProviderRegistry
    @Binding var selectedProviderID: String?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var baseURL = ""
    @State private var defaultModel = ""
    @State private var apiKey = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") == true
            && !defaultModel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Custom Provider")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 4)

            Form {
                TextField("Name:", text: $name, prompt: Text(verbatim: "My API"))
                TextField("Base URL:", text: $baseURL, prompt: Text(verbatim: "https://api.example.com/v1"))
                TextField("Default Model:", text: $defaultModel, prompt: Text(verbatim: "gpt-4o-mini"))
                SecureField("API Key:", text: $apiKey, prompt: Text(verbatim: "sk-... (Optional)"))
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { addProvider() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 380)
    }

    private func addProvider() {
        let def = CustomProviderDefinition(
            name: name.trimmingCharacters(in: .whitespaces),
            defaultBaseURL: baseURL.trimmingCharacters(in: .whitespaces),
            defaultModel: defaultModel.trimmingCharacters(in: .whitespaces)
        )
        registry.addCustomProvider(def)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        if !trimmedKey.isEmpty,
           let oai = registry.provider(withID: def.id) as? OpenAICompatibleProvider {
            Defaults[oai.apiKeyKey] = trimmedKey
        }
        selectedProviderID = def.id
        dismiss()
    }
}
