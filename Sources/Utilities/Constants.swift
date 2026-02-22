import Defaults
import Foundation
import KeyboardShortcuts

// MARK: - Supported Languages

/// Languages available for translation UI and provider checks.
enum SupportedLanguages {
    /// Ordered list of supported language codes.
    static let codes: [String] = [
        "en", "zh-Hans", "zh-Hant", "ja", "ko",
        "fr", "de", "es", "pt-BR", "ru", "ar", "it", "th", "vi",
    ]

    /// All supported language codes and their localized display names.
    static var all: [(code: String, name: String)] {
        codes.map { code in
            (code: code, name: Locale.current.localizedString(forIdentifier: code) ?? code)
        }
    }

    /// Set of all supported language codes.
    static let codeSet: Set<String> = Set(codes)
}

// MARK: - App Language

enum AppLanguage: String, CaseIterable, Defaults.Serializable {
    case system = ""
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var displayName: String {
        switch self {
        case .system: String(localized: "System Default")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, Defaults.Serializable {
    case general
    case services
    case about
}

// MARK: - Keyboard Shortcuts

extension KeyboardShortcuts.Name {
    static let translateSelection = Self("translateSelection", default: .init(.d, modifiers: .option))
    static let ocrScreenshot = Self("ocrScreenshot", default: .init(.s, modifiers: .option))
    static let inputTranslation = Self("inputTranslation", default: .init(.a, modifiers: .option))
    static let clipboardTranslation = Self("clipboardTranslation", default: .init(.v, modifiers: .option))
}

// MARK: - User Defaults Keys

extension Defaults.Keys {
    static let targetLanguage = Key<String>("targetLanguage", default: "zh-Hans")
    static let sourceLanguage = Key<String>("sourceLanguage", default: "auto")

    // Enabled translation providers
    static let enabledProviders = Key<Set<String>>("enabledProviders", default: ["openai"])

    // Language detection
    static let detectionConfidenceThreshold = Key<Double>("detectionConfidenceThreshold", default: 0.3)

    // Clipboard grabber timeout
    static let clipboardTimeout = Key<Int>("clipboardTimeout", default: 200)

    // Auto-detect text selection
    static let isAutoDetectEnabled = Key<Bool>("isAutoDetectEnabled", default: true)

    // Appearance
    static let showInDock = Key<Bool>("showInDock", default: true)

    // Onboarding
    static let hasCompletedOnboarding = Key<Bool>("hasCompletedOnboarding", default: false)

    // Popup panel default size
    static let popupDefaultWidth = Key<Int>("popupDefaultWidth", default: 450)
    static let popupDefaultHeight = Key<Int>("popupDefaultHeight", default: 350)
    static let popupInputHeight = Key<Int>("popupInputHeight", default: 48)

    // Settings tab selection
    static let selectedSettingsTab = Key<SettingsTab>("selectedSettingsTab", default: .general)

    // Custom providers
    static let customProviders = Key<[CustomProviderDefinition]>("customProviders", default: [])

    // App language override
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .system)
}
