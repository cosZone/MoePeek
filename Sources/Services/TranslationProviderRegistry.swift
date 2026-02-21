import Defaults

/// Container for all registered translation providers.
@MainActor
final class TranslationProviderRegistry {
    /// All providers available on this system (filtered by `isAvailable`).
    let providers: [any TranslationProvider]

    init(providers: [any TranslationProvider]) {
        self.providers = providers.filter { $0.isAvailable }
    }

    /// Providers the user has enabled (via Defaults).
    var enabledProviders: [any TranslationProvider] {
        let ids = Defaults[.enabledProviders]
        return providers.filter { ids.contains($0.id) }
    }

    func provider(withID id: String) -> (any TranslationProvider)? {
        providers.first { $0.id == id }
    }

    /// Providers grouped by category, preserving registration order within each group.
    var groupedProviders: [(category: ProviderCategory, providers: [any TranslationProvider])] {
        var grouped: [ProviderCategory: [any TranslationProvider]] = [:]
        for provider in providers {
            grouped[provider.category, default: []].append(provider)
        }
        return ProviderCategory.allCases.compactMap { category in
            guard let list = grouped[category], !list.isEmpty else { return nil }
            return (category: category, providers: list)
        }
    }

    /// Factory method returning the built-in provider set.
    static func builtIn() -> TranslationProviderRegistry {
        var allProviders: [any TranslationProvider] = [
            // Free Translation
            GoogleTranslateProvider(),
            BingTranslateProvider(),

            // Translation APIs
            DeepLProvider(),
            BaiduTranslateProvider(),
            NiuTransProvider(),
            CaiyunProvider(),

            // LLM Services
            OpenAICompatibleProvider(
                id: "openai",
                displayName: "OpenAI",
                iconSystemName: "brain",
                defaultBaseURL: "https://api.openai.com/v1",
                defaultModel: "gpt-4o-mini",
                guideURL: "https://platform.openai.com/api-keys"
            ),
            OpenAICompatibleProvider(
                id: "deepseek",
                displayName: "DeepSeek",
                iconSystemName: "brain.head.profile",
                defaultBaseURL: "https://api.deepseek.com/v1",
                defaultModel: "deepseek-chat",
                guideURL: "https://platform.deepseek.com/api_keys"
            ),
            OpenAICompatibleProvider(
                id: "zhipu",
                displayName: "智谱 GLM",
                iconSystemName: "sparkles",
                defaultBaseURL: "https://open.bigmodel.cn/api/paas/v4",
                defaultModel: "glm-4-flash",
                guideURL: "https://open.bigmodel.cn/usercenter/apikeys"
            ),
            OllamaProvider(),
        ]

        // System
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            allProviders.append(AppleTranslationProvider())
        }
        #endif

        return TranslationProviderRegistry(providers: allProviders)
    }
}
