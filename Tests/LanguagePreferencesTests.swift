import Testing
@testable import MoePeek

@Suite struct LanguagePreferencesTests {
    @Test func preservesLegacyTargetDefaultsAndAddsPolishToCatalog() {
        #expect(SupportedLanguages.defaultTargetCodes == [
            "en", "zh-Hans", "zh-Hant", "ja", "ko",
            "fr", "de", "es", "pt-BR", "ru", "ar", "it", "th", "vi",
        ])
        #expect(SupportedLanguages.codes.contains("pl"))
        #expect(!SupportedLanguages.defaultTargetCodes.contains("pl"))
    }

    @Test func normalizesPersistedFavoritesWithoutChangingOrder() {
        #expect(SupportedLanguages.normalizedTargetCodes([
            "es", "unknown", "pl", "es", "en",
        ]) == ["es", "pl", "en"])
    }

    @Test func emptyOrInvalidFavoritesFallBackToLegacyDefaults() {
        #expect(SupportedLanguages.effectiveTargetCodes([]) == SupportedLanguages.defaultTargetCodes)
        #expect(SupportedLanguages.effectiveTargetCodes(["unknown"]) == SupportedLanguages.defaultTargetCodes)
    }

    @Test func preservesCatalogTargetsOutsideFavoritesAndResolvesUnknownValues() {
        #expect(SupportedLanguages.resolvedTarget("pl", favoriteCodes: ["es", "en"]) == "pl")
        #expect(SupportedLanguages.resolvedTarget("pl", favoriteCodes: ["es", "zh-Hans", "en"]) == "pl")
        #expect(SupportedLanguages.resolvedTarget("unknown", favoriteCodes: []) == "zh-Hans")
        #expect(SupportedLanguages.resolvedTarget("unknown", favoriteCodes: ["es", "en"]) == "es")
        #expect(SupportedLanguages.resolvedTarget("pl", favoriteCodes: ["en", "pl"]) == "pl")
    }

    @Test func swappedSourceRemainsVisibleWithoutBecomingFavorite() {
        #expect(SupportedLanguages.targetPickerCodes(
            ["en", "pl"],
            selectedTarget: "de"
        ) == ["en", "pl", "de"])
        #expect(SupportedLanguages.targetPickerCodes(
            ["en", "pl"],
            selectedTarget: "unknown"
        ) == ["en", "pl"])
    }

    @Test func autoFlipUsesFavoriteOrderAndHandlesSingleChoice() {
        #expect(SupportedLanguages.resolvedTarget(
            "pl",
            detectedLanguage: "pl",
            favoriteCodes: ["es", "en", "pl"]
        ) == "es")
        #expect(SupportedLanguages.resolvedTarget(
            "zh-Hans",
            detectedLanguage: "zh-Hant",
            favoriteCodes: SupportedLanguages.defaultTargetCodes
        ) == "zh-Hans")
        #expect(SupportedLanguages.resolvedTarget(
            "pl",
            detectedLanguage: "pl",
            favoriteCodes: ["pl"]
        ) == "pl")
    }

    @Test func autoFlipPrefersLegacyFallbackBeforeFavoriteOrder() {
        #expect(SupportedLanguages.resolvedTarget(
            "fr",
            detectedLanguage: "fr",
            favoriteCodes: SupportedLanguages.defaultTargetCodes
        ) == "zh-Hans")
        #expect(SupportedLanguages.resolvedTarget(
            "ja",
            detectedLanguage: "ja",
            favoriteCodes: SupportedLanguages.defaultTargetCodes
        ) == "zh-Hans")
        #expect(SupportedLanguages.resolvedTarget(
            "zh-Hant",
            detectedLanguage: "zh-Hans",
            favoriteCodes: SupportedLanguages.defaultTargetCodes
        ) == "zh-Hant")
        #expect(SupportedLanguages.resolvedTarget(
            "fr",
            detectedLanguage: "fr",
            favoriteCodes: ["pl", "es", "fr"]
        ) == "pl")
    }

    @Test func sameScriptChineseStillAutoFlipsToEnglish() {
        for target in ["zh-Hans", "zh-Hant"] {
            #expect(SupportedLanguages.resolvedTarget(
                target,
                detectedLanguage: target,
                favoriteCodes: SupportedLanguages.defaultTargetCodes
            ) == "en")
        }
    }

    @Test func explicitSwappedTargetOutsideFavoritesRemainsSelectableAndResolved() {
        let favorites = ["en", "pl"]
        let swappedTarget = "de"

        #expect(SupportedLanguages.targetPickerCodes(
            favorites,
            selectedTarget: swappedTarget
        ) == ["en", "pl", "de"])
        #expect(SupportedLanguages.resolvedTarget(
            swappedTarget,
            detectedLanguage: "pl",
            favoriteCodes: favorites
        ) == swappedTarget)
    }

    @Test func expandedLanguagesHaveProviderAndLLMNames() {
        #expect(SupportedLanguages.englishName(for: "pl") == "Polish")
        #expect(LanguageCodeMapping.resolveTarget("pl", using: LanguageCodeMapping.deepLTarget) == "PL")
        #expect(LanguageCodeMapping.resolveTarget("uk", using: LanguageCodeMapping.deepLSource) == "UK")
        #expect(!LanguageCodeMapping.caiyunSupported.contains("pl"))
    }

    @Test func detectsPolishFromTheFullCatalog() {
        let result = LanguageDetector.detectWithConfidence(
            "Zażółć gęślą jaźń. To jest dłuższe zdanie napisane po polsku.",
            threshold: 0.1
        )
        #expect(result.language == "pl")
    }
}
