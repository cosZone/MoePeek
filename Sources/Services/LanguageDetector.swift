import NaturalLanguage

struct DetectionResult: Sendable {
    let language: String?
    let confidence: Double
    let isReliable: Bool
}

enum LanguageDetector {
    // Detection always uses the complete catalog, independently of target favorites.
    private static let supportedNLLanguages = SupportedLanguages.codes.compactMap(bcp47ToNLLanguage)

    // Base language weight hints (inspired by Easydict, simplified)
    private static let baseHints: [NLLanguage: Double] = [
        .english: 2.0,
        .simplifiedChinese: 1.5,
        .traditionalChinese: 0.8,
        .japanese: 0.6,
        .korean: 0.5,
        .french: 0.4, .spanish: 0.4, .italian: 0.4,
        .portuguese: 0.3, .german: 0.3, .russian: 0.3,
        .arabic: 0.2, .thai: 0.2, .vietnamese: 0.2,
        NLLanguage(rawValue: "pl"): 0.2,
        NLLanguage(rawValue: "nl"): 0.2,
        NLLanguage(rawValue: "tr"): 0.2,
        NLLanguage(rawValue: "uk"): 0.2,
        NLLanguage(rawValue: "id"): 0.2,
        NLLanguage(rawValue: "sv"): 0.2,
        .hebrew: 0.2,
    ]

    /// Backward-compatible simple API.
    static func detect(_ text: String) -> String? {
        detectWithConfidence(text, threshold: 0.3).language
    }

    /// Full detection API with confidence and alternatives.
    /// `preferredSourceHints` uses BCP 47 codes as keys (e.g. "en", "zh-Hans").
    static func detectWithConfidence(
        _ text: String,
        threshold: Double = 0.3,
        preferredSourceHints: [String: Double]? = nil
    ) -> DetectionResult {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = supportedNLLanguages

        // Merge base hints + user preference hints
        var hints = baseHints
        if let extra = preferredSourceHints {
            for (code, weight) in extra {
                if let nlLang = bcp47ToNLLanguage(code) {
                    hints[nlLang, default: 0] += weight
                }
            }
        }
        recognizer.languageHints = hints

        recognizer.processString(text)

        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        let sorted = hypotheses
            .map { (language: mapToBCP47($0.key), confidence: $0.value) }
            .sorted { $0.confidence > $1.confidence }

        guard let best = sorted.first else {
            return DetectionResult(language: nil, confidence: 0, isReliable: false)
        }

        // Use higher threshold for very short text
        let effectiveThreshold = text.count <= 5
            ? max(threshold, 0.5)
            : threshold

        let isReliable = best.confidence >= effectiveThreshold

        return DetectionResult(
            language: isReliable ? best.language : nil,
            confidence: best.confidence,
            isReliable: isReliable
        )
    }

    private static func bcp47ToNLLanguage(_ code: String) -> NLLanguage? {
        switch code {
        case "zh-Hans": return .simplifiedChinese
        case "zh-Hant": return .traditionalChinese
        case "pt-BR": return .portuguese
        default: return NLLanguage(rawValue: code)
        }
    }

    private static func mapToBCP47(_ language: NLLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .portuguese: return "pt-BR"
        default: return language.rawValue
        }
    }
}
