import Foundation

extension SupportedLanguages {
    /// Removes unknown and duplicate values while preserving the user's order.
    static func normalizedTargetCodes(_ storedCodes: [String]) -> [String] {
        var seen: Set<String> = []
        return storedCodes.filter { codeSet.contains($0) && seen.insert($0).inserted }
    }

    /// An empty or invalid persisted list falls back to the pre-existing target list.
    static func effectiveTargetCodes(_ storedCodes: [String]) -> [String] {
        let normalized = normalizedTargetCodes(storedCodes)
        return normalized.isEmpty ? defaultTargetCodes : normalized
    }

    /// Favorites control picker visibility, not whether a catalog language can be used.
    /// Only an unknown persisted target falls back into the configured shortlist.
    static func resolvedTarget(_ target: String, favoriteCodes: [String]) -> String {
        if codeSet.contains(target) { return target }

        let normalized = normalizedTargetCodes(favoriteCodes)
        if normalized.isEmpty {
            return "zh-Hans"
        }
        return normalized[0]
    }

    /// Keeps a valid swapped source visible without silently adding it to favorites.
    static func targetPickerCodes(_ favoriteCodes: [String], selectedTarget: String) -> [String] {
        var available = effectiveTargetCodes(favoriteCodes)
        if codeSet.contains(selectedTarget), !available.contains(selectedTarget) {
            available.append(selectedTarget)
        }
        return available
    }

    /// Preserves the legacy English/Chinese fallback when it is a favorite, then
    /// uses the first favorite outside the detected language family.
    static func resolvedTarget(
        _ target: String,
        detectedLanguage: String?,
        favoriteCodes: [String]
    ) -> String {
        let available = effectiveTargetCodes(favoriteCodes)
        let preferred = resolvedTarget(target, favoriteCodes: favoriteCodes)
        if let detectedLanguage,
           detectedLanguage.hasPrefix("zh"),
           preferred.hasPrefix("zh"),
           detectedLanguage != preferred {
            return preferred
        }
        guard let detectedLanguage,
              sameLanguage(detectedLanguage, preferred)
        else { return preferred }

        let legacyFallback = detectedLanguage.hasPrefix("zh") ? "en" : "zh-Hans"
        if available.contains(legacyFallback) {
            return legacyFallback
        }

        return available.first { !sameLanguage($0, detectedLanguage) } ?? preferred
    }

    private static func sameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.hasPrefix("zh"), rhs.hasPrefix("zh") { return true }
        return lhs == rhs
    }
}
