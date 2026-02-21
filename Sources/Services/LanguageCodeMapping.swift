import Foundation

/// Maps BCP 47 language codes to provider-specific codes.
/// Each dictionary only lists codes that differ from BCP 47; unlisted codes pass through as-is.
enum LanguageCodeMapping {
    // MARK: - Google Translate

    static let google: [String: String] = [
        "zh-Hans": "zh-CN", "zh-Hant": "zh-TW", "pt-BR": "pt",
    ]

    // MARK: - DeepL

    /// DeepL target language codes (preserve variants, uppercase).
    static let deepLTarget: [String: String] = [
        "zh-Hans": "ZH-HANS", "zh-Hant": "ZH-HANT", "en": "EN",
        "ja": "JA", "ko": "KO", "fr": "FR", "de": "DE", "es": "ES",
        "pt-BR": "PT-BR", "ru": "RU", "ar": "AR", "it": "IT",
    ]

    /// DeepL source language codes (variants stripped, uppercase).
    static let deepLSource: [String: String] = [
        "zh-Hans": "ZH", "zh-Hant": "ZH", "en": "EN",
        "ja": "JA", "ko": "KO", "fr": "FR", "de": "DE", "es": "ES",
        "pt-BR": "PT", "ru": "RU", "ar": "AR", "it": "IT",
    ]

    // MARK: - Baidu

    static let baidu: [String: String] = [
        "zh-Hans": "zh", "zh-Hant": "cht", "ja": "jp", "ko": "kor",
        "fr": "fra", "es": "spa", "pt-BR": "pt", "ar": "ara", "vi": "vie",
    ]

    // MARK: - NiuTrans

    static let niuTrans: [String: String] = [
        "zh-Hans": "zh", "zh-Hant": "cht",
    ]

    // MARK: - Bing

    /// Bing natively uses BCP 47 for most codes; only map where they differ.
    static let bing: [String: String] = [
        "pt-BR": "pt",
    ]

    // MARK: - Caiyun

    static let caiyun: [String: String] = [
        "zh-Hans": "zh", "pt-BR": "pt",
    ]

    /// Supported language codes for Caiyun (used to check availability).
    static let caiyunSupported: Set<String> = [
        "zh", "zh-Hant", "en", "ja", "ko", "de", "es", "fr", "it", "pt", "ru", "tr", "vi",
    ]

    // MARK: - Resolve

    /// Resolve an optional BCP 47 code using the given mapping. Returns `nil` if input is `nil`.
    static func resolve(_ bcp47: String?, using mapping: [String: String]) -> String? {
        guard let code = bcp47 else { return nil }
        return mapping[code] ?? code
    }

    /// Resolve a BCP 47 target code using the given mapping.
    static func resolveTarget(_ bcp47: String, using mapping: [String: String]) -> String {
        mapping[bcp47] ?? bcp47
    }

}
