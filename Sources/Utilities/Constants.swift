import AppKit
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

    /// English full names for language codes, used when interpolating into LLM prompts.
    ///
    /// Small models (≤2B params) often fail to recognize BCP-47 codes like `zh-Hans`,
    /// so we expand to a stable English name. We hardcode the mapping rather than
    /// using `Locale.localizedString(forIdentifier:)` to avoid locale-dependent
    /// variations like "Chinese, Simplified" vs "Simplified Chinese".
    private static let englishNames: [String: String] = [
        "en": "English",
        "zh-Hans": "Simplified Chinese",
        "zh-Hant": "Traditional Chinese",
        "ja": "Japanese",
        "ko": "Korean",
        "fr": "French",
        "de": "German",
        "es": "Spanish",
        "pt-BR": "Brazilian Portuguese",
        "ru": "Russian",
        "ar": "Arabic",
        "it": "Italian",
        "th": "Thai",
        "vi": "Vietnamese",
    ]

    /// Returns the English full name for a language code (e.g. `zh-Hans` → `Simplified Chinese`).
    /// Falls back to the code itself for unknown identifiers.
    static func englishName(for code: String) -> String {
        englishNames[code] ?? code
    }
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

// MARK: - Text Detection Mode

enum TextDetectionMode: String, CaseIterable, Defaults.Serializable {
    case conservative  // Tier 1 only (AX API)
    case standard      // Tier 1 + Tier 2 (AX + AppleScript)
    case full          // Tier 1 + Tier 2 + Tier 3 (AX + AppleScript + ⌘C simulation)
}

// MARK: - Menu Bar Icon Style

enum MenuBarIconStyle: String, CaseIterable, Defaults.Serializable {
    case filled
    case custom
}

enum MenuBarCustomIconSource: String, CaseIterable, Defaults.Serializable {
    case symbol
    case image
}

/// Constants describing the SF Symbols catalog used by the menu bar icon UI.
enum MenuBarIconCatalog {
    /// Default SF Symbol surfaced when the user first picks a custom symbol icon.
    /// Kept in sync with the `filled` style so switching to custom is non-disruptive.
    static let defaultSymbol = "character.bubble.fill"

    /// Curated SF Symbol presets exposed in Settings. Names must exist on macOS 14.
    static let presets: [String] = [
        "character.bubble.fill",
        "text.bubble.fill",
        "bubble.left.fill",
        "globe",
        "globe.americas.fill",
        "character.book.closed.fill",
        "text.viewfinder",
        "sparkles",
        "abc",
        "textformat",
        "character",
        "command",
    ]
}

// MARK: - Trigger Icon Activation Mode

enum TriggerActivationMode: String, CaseIterable, Defaults.Serializable {
    case hover  // Hover over the trigger icon (default behavior)
    case click  // Click the trigger icon
}

// MARK: - Settings Tab

enum SettingsTab: String, Defaults.Serializable {
    case general
    case excludedApps
    case services
    case providerOrder
    case audio
    case about
}

// MARK: - Keyboard Shortcuts

extension KeyboardShortcuts.Name {
    static let translateSelection = Self("translateSelection", default: .init(.d, modifiers: .option))
    static let ocrScreenshot = Self("ocrScreenshot", default: .init(.s, modifiers: .option))
    static let inputTranslation = Self("inputTranslation", default: .init(.a, modifiers: .option))
    static let clipboardTranslation = Self("clipboardTranslation", default: .init(.v, modifiers: .option))
    static let swapLanguages: Self = {
        let name = Self("swapLanguages", default: .init(.t, modifiers: .option))
        // Clear legacy or default bindings that conflict with popup or global actions.
        if let current = KeyboardShortcuts.getShortcut(for: name),
           SwapLanguagesShortcut.isReserved(current) {
            KeyboardShortcuts.setShortcut(nil, for: name)
        }
        KeyboardShortcuts.disable(name)
        SwapLanguagesShortcut.restoreGlobalRegistrations()
        return name
    }()
}

/// Keeps the swap shortcut popup-local even though the package recorder uses global names.
enum SwapLanguagesShortcut {
    static let didChangeNotification = Notification.Name("SwapLanguagesShortcutDidChange")

    private static let popupReservedNumberKeys: Set<KeyboardShortcuts.Key> = [
        .one, .two, .three, .four, .five, .six, .seven, .eight, .nine,
        .keypad1, .keypad2, .keypad3, .keypad4, .keypad5,
        .keypad6, .keypad7, .keypad8, .keypad9,
    ]

    /// `PopupPanel.sendEvent` runs before `NSTextView`, so preserve standard editing and navigation.
    private static let textEditingShortcuts: Set<KeyboardShortcuts.Shortcut> = [
        .init(.a, modifiers: .command),
        .init(.b, modifiers: .command),
        .init(.c, modifiers: .command),
        .init(.e, modifiers: .command),
        .init(.f, modifiers: .command),
        .init(.f, modifiers: [.command, .option]),
        .init(.g, modifiers: .command),
        .init(.g, modifiers: [.command, .shift]),
        .init(.j, modifiers: .command),
        .init(.i, modifiers: .command),
        .init(.u, modifiers: .command),
        .init(.v, modifiers: .command),
        .init(.v, modifiers: [.command, .option, .shift]),
        .init(.x, modifiers: .command),
        .init(.z, modifiers: .command),
        .init(.z, modifiers: [.command, .shift]),
        .init(.leftArrow, modifiers: .command),
        .init(.rightArrow, modifiers: .command),
        .init(.upArrow, modifiers: .command),
        .init(.downArrow, modifiers: .command),
        .init(.leftArrow, modifiers: [.command, .shift]),
        .init(.rightArrow, modifiers: [.command, .shift]),
        .init(.upArrow, modifiers: [.command, .shift]),
        .init(.downArrow, modifiers: [.command, .shift]),
        .init(.leftArrow, modifiers: .option),
        .init(.rightArrow, modifiers: .option),
        .init(.leftArrow, modifiers: [.option, .shift]),
        .init(.rightArrow, modifiers: [.option, .shift]),
        .init(.delete, modifiers: .option),
        .init(.deleteForward, modifiers: .option),
        .init(.delete, modifiers: [.option, .shift]),
        .init(.deleteForward, modifiers: [.option, .shift]),
        .init(.delete, modifiers: .command),
        .init(.deleteForward, modifiers: .command),
        .init(.delete, modifiers: [.command, .shift]),
        .init(.deleteForward, modifiers: [.command, .shift]),
    ]

    private static let globalShortcutNames: [KeyboardShortcuts.Name] = [
        .translateSelection,
        .ocrScreenshot,
        .inputTranslation,
        .clipboardTranslation,
    ]

    static var current: KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: .swapLanguages)
    }

    static func recorderDidChange() {
        reconcileRegistrations()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func reconcileRegistrations() {
        KeyboardShortcuts.disable(.swapLanguages)
        restoreGlobalRegistrations()
    }

    /// `KeyboardShortcuts` unregisters by key combination rather than by name. Re-enable
    /// the app-wide shortcuts after disabling or reverting this popup-local binding so a
    /// rejected collision cannot leave an existing global shortcut inactive.
    static func restoreGlobalRegistrations() {
        KeyboardShortcuts.enable(globalShortcutNames)
    }

    static func matches(_ event: NSEvent) -> Bool {
        guard let current, let eventShortcut = KeyboardShortcuts.Shortcut(event: event) else {
            return false
        }
        return eventShortcut == current
    }

    static func isReserved(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        if shortcut.key == .return || shortcut.key == .keypadEnter || shortcut.key == .escape {
            return true
        }

        if shortcut.modifiers == .command,
           let key = shortcut.key,
           popupReservedNumberKeys.contains(key) {
            return true
        }

        if textEditingShortcuts.contains(shortcut) {
            return true
        }

        return globalShortcutNames
            .compactMap { KeyboardShortcuts.getShortcut(for: $0) }
            .contains(shortcut)
    }
}

// MARK: - User Defaults Keys

extension Defaults.Keys {
    static let targetLanguage = Key<String>("targetLanguage", default: "zh-Hans")
    static let sourceLanguage = Key<String>("sourceLanguage", default: "auto")

    // Enabled translation providers
    static let enabledProviders = Key<Set<String>>("enabledProviders", default: ["openai"])

    // User-defined display order for providers (ordered list of provider IDs)
    static let providerOrder = Key<[String]>("providerOrder", default: [])

    // Language detection
    static let detectionConfidenceThreshold = Key<Double>("detectionConfidenceThreshold", default: 0.3)

    // Clipboard grabber timeout
    static let clipboardTimeout = Key<Int>("clipboardTimeout", default: 200)

    // Auto-detect text selection
    static let isAutoDetectEnabled = Key<Bool>("isAutoDetectEnabled", default: true)
    static let textDetectionMode = Key<TextDetectionMode>("textDetectionMode", default: .full)
    static let triggerActivationMode = Key<TriggerActivationMode>("triggerActivationMode", default: .hover)
    static let excludedAppBundleIDs = Key<Set<String>>("excludedAppBundleIDs", default: [])

    // Appearance
    static let showInDock = Key<Bool>("showInDock", default: true)

    // Menu bar icon
    static let menuBarIconStyle = Key<MenuBarIconStyle>("menuBarIconStyle", default: .filled)
    static let menuBarCustomIconSource = Key<MenuBarCustomIconSource>("menuBarCustomIconSource", default: .symbol)
    static let menuBarCustomSymbolName = Key<String>("menuBarCustomSymbolName", default: MenuBarIconCatalog.defaultSymbol)
    static let menuBarCustomIconIsTemplate = Key<Bool>("menuBarCustomIconIsTemplate", default: true)
    // Bumped whenever the custom icon file is replaced so SwiftUI re-evaluates the cached image.
    static let menuBarCustomIconRevision = Key<Int>("menuBarCustomIconRevision", default: 0)

    // Onboarding
    static let hasCompletedOnboarding = Key<Bool>("hasCompletedOnboarding", default: false)

    // Popup panel default size
    static let popupDefaultWidth = Key<Int>("popupDefaultWidth", default: 450)
    static let popupDefaultHeight = Key<Int>("popupDefaultHeight", default: 350)
    static let popupInputHeight = Key<Int>("popupInputHeight", default: 48)
    static let popupFontSize = Key<Int>("popupFontSize", default: 12)
    static let popupFontName = Key<String>("popupFontName", default: "")

    // Popup panel last dragged position (used when popupRememberPosition is enabled).
    // We persist the top-left corner so the visual position stays anchored even when the
    // panel size differs between sessions (default size can change via Settings sliders or
    // the in-panel resize grip).
    static let popupRememberPosition = Key<Bool>("popupRememberPosition", default: true)
    static let popupHasSavedPosition = Key<Bool>("popupHasSavedPosition", default: false)
    static let popupLastTopLeftX = Key<Double>("popupLastTopLeftX", default: 0)
    static let popupLastTopLeftY = Key<Double>("popupLastTopLeftY", default: 0)

    // Settings tab selection
    static let selectedSettingsTab = Key<SettingsTab>("selectedSettingsTab", default: .general)

    // Custom providers
    static let customProviders = Key<[CustomProviderDefinition]>("customProviders", default: [])

    // App language override
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .system)

    // TTS (Text-to-Speech)
    static let ttsProvider = Key<String>("tts_provider", default: "apple")
    static let ttsAccent = Key<TTSAccent>("tts_accent", default: .american)
    static let ttsSpeechRate = Key<Double>("tts_speechRate", default: 1.0)
    static let ttsAutoPlaySource = Key<Bool>("tts_autoPlaySource", default: false)
    static let ttsAutoPlayTarget = Key<Bool>("tts_autoPlayTarget", default: false)
    // "first" = first provider to complete; otherwise a specific provider ID
    static let ttsAutoPlayTargetProvider = Key<String>("tts_autoPlayTargetProvider", default: "first")
    static let ttsLanguageRates = Key<[String: Double]>("tts_languageRates", default: [:])
}
