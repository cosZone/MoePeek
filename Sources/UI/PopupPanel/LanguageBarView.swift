import Defaults
import SwiftUI

/// Language selection bar with source picker + swap + target picker.
struct LanguageBarView: View {
    @Binding var sourceLanguage: String
    let detectedLanguage: String?
    var detectionConfidence: Double?
    @Binding var targetLanguage: String
    let onSwap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Source language picker
            Picker("", selection: $sourceLanguage) {
                Text(autoDetectDisplayName).tag("auto")
                ForEach(SupportedLanguages.all, id: \.code) { code, name in
                    Text(name).tag(code)
                }
            }
            .labelsHidden()
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
        .background { InteractiveMarker() }
    }

    /// Shows a "?" when confidence is above the detection threshold (so a language is returned)
    /// but below this display threshold. Derived from the user's detection threshold to stay in sync.
    private var uncertainDisplayThreshold: Double {
        min(Defaults[.detectionConfidenceThreshold] + 0.3, 0.8)
    }

    private var autoDetectDisplayName: String {
        if sourceLanguage == "auto", let lang = detectedLanguage {
            let name = Locale.current.localizedString(forIdentifier: lang) ?? lang
            if let conf = detectionConfidence, conf < uncertainDisplayThreshold {
                return "\(String(localized: "Auto Detect")) (\(name) ?)"
            }
            return "\(String(localized: "Auto Detect")) (\(name))"
        }
        return String(localized: "Auto Detect")
    }
}
