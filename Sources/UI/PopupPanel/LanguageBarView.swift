import Defaults
import SwiftUI

/// Language selection bar with source (auto-detect) + swap + target picker.
struct LanguageBarView: View {
    let detectedLanguage: String?
    var detectionConfidence: Double?
    @Binding var targetLanguage: String
    let onSwap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Source language display
            HStack(spacing: 4) {
                Image(systemName: "text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sourceDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onSwap) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            // Target language picker
            Picker("", selection: $targetLanguage) {
                ForEach(SupportedLanguages.all, id: \.code) { code, name in
                    Text(name).tag(code)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    /// Shows a "?" when confidence is above the detection threshold (so a language is returned)
    /// but below this display threshold. Derived from the user's detection threshold to stay in sync.
    private var uncertainDisplayThreshold: Double {
        min(Defaults[.detectionConfidenceThreshold] + 0.3, 0.8)
    }

    private var sourceDisplayName: String {
        if let lang = detectedLanguage {
            let name = Locale.current.localizedString(forIdentifier: lang) ?? lang
            if let conf = detectionConfidence, conf < uncertainDisplayThreshold {
                return "\(name) ?"
            }
            return name
        }
        return "Auto Detect"
    }
}
