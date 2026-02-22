import Foundation

/// Fetches and caches model capability metadata from models.dev.
/// Data is fetched once per app session and silently ignored on network failure.
@MainActor @Observable
final class ModelMetadataService {
    static let shared = ModelMetadataService()

    /// Keyed by full model id as it appears in models.dev (e.g. "kimi-k2.5", "moonshotai/Kimi-K2.5").
    /// Stores all candidates from different providers sharing the same model id.
    private var modelIndex: [String: [ModelMeta]] = [:]
    /// Keyed by lowercased short name (last path component after "/").
    /// Stores all candidates sharing the same short name to detect ambiguous matches.
    private var shortIndex: [String: [ModelMeta]] = [:]
    private var isFetching = false
    private(set) var hasFetched = false

    struct ModelMeta: Sendable {
        let toolCall: Bool
        let reasoning: Bool
        let contextWindow: Int?     // limit.context (tokens)
    }

    enum MatchKind: Sendable { case exact, approximate }

    struct MetaMatch: Sendable {
        let meta: ModelMeta
        let matchKind: MatchKind
    }

    private init() {}

    /// Fetches models.dev data if not already fetched. Safe to call multiple times.
    func fetchIfNeeded() async {
        guard !hasFetched, !isFetching else { return }
        isFetching = true
        defer {
            isFetching = false
            hasFetched = true  // Once per session, even on failure
        }

        guard let url = URL(string: "https://models.dev/api.json") else { return }
        guard let (data, response) = try? await translationURLSession.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }

        // Parse and build indexes off the main thread to avoid blocking UI.
        let result = await Task.detached(priority: .utility) { () -> (index: [String: [ModelMeta]], short: [String: [ModelMeta]])? in
            // api.json top-level is { "provider-id": { "models": { "model-id": {...}, ... } } }
            guard let providers = try? JSONDecoder().decode([String: RawProvider].self, from: data) else { return nil }
            var index: [String: [ModelMeta]] = [:]
            var short: [String: [ModelMeta]] = [:]
            for provider in providers.values {
                for (modelID, model) in provider.models ?? [:] {
                    let meta = ModelMeta(
                        toolCall: model.toolCall ?? false,
                        reasoning: model.reasoning ?? false,
                        contextWindow: model.limit?.context
                    )
                    index[modelID, default: []].append(meta)
                    let bare = (modelID.components(separatedBy: "/").last ?? modelID).lowercased()
                    short[bare, default: []].append(meta)
                }
            }
            return (index, short)
        }.value

        guard let result else { return }
        modelIndex = result.index
        shortIndex = result.short
    }

    /// Returns metadata for the given model ID with match confidence.
    ///
    /// Three matching paths, tried in order:
    /// 1. **Exact full ID** — `modelIndex[modelID]` → `.exact`
    /// 2. **Exact bare name** — strip provider prefix, lookup in `shortIndex` → `.exact`
    /// 3. **Fuzzy substring** — find the best `shortIndex` key where query contains key
    ///    or key contains query → `.approximate` (shown with orange question mark in UI)
    ///
    /// Returns `nil` when no match is found at any level.
    func meta(for modelID: String) -> MetaMatch? {
        // 1. Exact model ID match (across all providers)
        if let candidates = modelIndex[modelID] {
            return merge(candidates, matchKind: .exact)
        }

        // 2. Short-name exact match (bare name after stripping provider prefix)
        let bare = (modelID.components(separatedBy: "/").last ?? modelID).lowercased()
        if let candidates = shortIndex[bare] {
            return merge(candidates, matchKind: .exact)
        }

        // 3. Fuzzy substring match against known bare names
        return fuzzyMatch(bare)
    }

    /// Finds the best candidate where the query contains a known bare name or vice versa.
    ///
    /// Among all matching keys, the longest one is chosen to maximize specificity
    /// (e.g. for query "gpt-4o-2024-08-06", prefer key "gpt-4o" over "gpt-4").
    /// Returns `.approximate` to signal uncertainty — UI shows an orange question mark.
    private func fuzzyMatch(_ query: String) -> MetaMatch? {
        var bestKey: String?
        var bestLength = 0

        for key in shortIndex.keys {
            guard query.contains(key) || key.contains(query) else { continue }
            if key.count > bestLength {
                bestLength = key.count
                bestKey = key
            }
        }

        guard let bestKey, let candidates = shortIndex[bestKey] else { return nil }
        return merge(candidates, matchKind: .approximate)
    }

    /// Merges multiple candidate metadata entries into a single `MetaMatch`.
    /// Uses conservative merge (capabilities must be unanimous) when candidates conflict,
    /// but `matchKind` is determined by the caller based on how the match was found,
    /// not by whether the data sources agree on capabilities.
    private func merge(_ candidates: [ModelMeta], matchKind: MatchKind = .exact) -> MetaMatch? {
        guard !candidates.isEmpty else { return nil }

        if candidates.count == 1 {
            return MetaMatch(meta: candidates[0], matchKind: matchKind)
        }

        let allSame = candidates.allSatisfy {
            $0.toolCall == candidates[0].toolCall &&
            $0.reasoning == candidates[0].reasoning
        }

        if allSame {
            let merged = ModelMeta(
                toolCall: candidates[0].toolCall,
                reasoning: candidates[0].reasoning,
                contextWindow: candidates.compactMap(\.contextWindow).max()
            )
            return MetaMatch(meta: merged, matchKind: matchKind)
        }

        // Capabilities conflict — conservative: only mark supported if ALL agree
        let merged = ModelMeta(
            toolCall: candidates.allSatisfy(\.toolCall),
            reasoning: candidates.allSatisfy(\.reasoning),
            contextWindow: candidates.compactMap(\.contextWindow).max()
        )
        return MetaMatch(meta: merged, matchKind: matchKind)
    }
}

// MARK: - Private JSON types

private extension ModelMetadataService {
    struct RawProvider: Decodable {
        // models is keyed by model id
        let models: [String: RawModel]?
    }

    struct RawModel: Decodable {
        let toolCall: Bool?
        let reasoning: Bool?
        let limit: Limit?

        enum CodingKeys: String, CodingKey {
            case toolCall = "tool_call"
            case reasoning, limit
        }

        struct Limit: Decodable { let context: Int? }
    }
}
