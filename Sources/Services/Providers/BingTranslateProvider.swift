import Foundation
import SwiftUI

/// Bing Translate provider using the free web API (no API key required).
struct BingTranslateProvider: TranslationProvider {
    let id = "bing"
    let displayName = "Bing Translate"
    let iconSystemName = "globe.americas.fill"
    let iconAssetName: String? = "Bing"
    let category: ProviderCategory = .freeTranslation
    let supportsStreaming = false
    let isAvailable = true

    @MainActor
    var isConfigured: Bool { true }

    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String
    ) -> AsyncThrowingStream<String, Error> {
        singleResultStream { [self] in try await translate(text, from: sourceLang, to: targetLang) }
    }

    @MainActor
    func makeSettingsView() -> AnyView {
        AnyView(BingTranslateSettingsView())
    }

    // MARK: - Private

    private func translate(_ text: String, from sourceLang: String?, to targetLang: String) async throws -> String {
        let sl = LanguageCodeMapping.resolve(sourceLang, using: LanguageCodeMapping.bing) ?? "auto-detect"
        let tl = LanguageCodeMapping.resolveTarget(targetLang, using: LanguageCodeMapping.bing)

        // Bing limits single requests to ~1000 characters
        let isTruncated = text.count > 1000
        let truncated = String(text.prefix(1000))

        let credentials = try await BingTokenManager.shared.getCredentials()

        guard var components = URLComponents(string: "https://www.bing.com/ttranslatev3") else {
            throw TranslationError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "isVertical", value: "1"),
            URLQueryItem(name: "IG", value: credentials.ig),
            URLQueryItem(name: "IID", value: credentials.iid),
        ]

        guard let url = components.url else {
            throw TranslationError.invalidURL
        }

        let formBody = [
            "fromLang=\(URLFormEncoding.encode(sl))",
            "to=\(URLFormEncoding.encode(tl))",
            "text=\(URLFormEncoding.encode(truncated))",
            "token=\(URLFormEncoding.encode(credentials.token))",
            "key=\(URLFormEncoding.encode(credentials.key))",
        ].joined(separator: "&")

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(BingTokenManager.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bing.com/translator", forHTTPHeaderField: "Referer")
        request.httpBody = formBody.data(using: .utf8)

        let (data, response) = try await translationURLSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        // 429 or auth failure → invalidate cached credentials so next call refreshes
        if httpResponse.statusCode == 429 || httpResponse.statusCode == 401 {
            await BingTokenManager.shared.invalidate()
            throw TranslationError.apiError(
                statusCode: httpResponse.statusCode,
                message: String(localized: "Rate limited by Bing. Please try again later.")
            )
        }

        guard httpResponse.statusCode == 200 else {
            throw TranslationError.apiError(
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8) ?? ""
            )
        }

        let decoded = try JSONDecoder().decode([BingTranslateResponse].self, from: data)
        guard let translated = decoded.first?.translations.first?.text, !translated.isEmpty else {
            throw TranslationError.emptyResult
        }
        if isTruncated {
            return translated + "\n\n" + String(localized: "[Bing Translate: text truncated to 1000 characters]")
        }
        return translated
    }
}

// MARK: - Response Model

private struct BingTranslateResponse: Decodable {
    let translations: [Translation]

    struct Translation: Decodable {
        let text: String
        let to: String
    }
}

// MARK: - Token Manager

/// Thread-safe manager for Bing Translate session credentials.
/// Fetches and caches IG, IID, key, and token from the Bing Translator page.
private actor BingTokenManager {
    static let shared = BingTokenManager()

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    private var credentials: Credentials?
    private var fetchedAt: Date?
    private var expiryInterval: TimeInterval = 1800 // default 30 min
    private var refreshTask: Task<Credentials, Error>?

    struct Credentials: Sendable {
        let ig: String
        let iid: String
        let key: String
        let token: String
    }

    func getCredentials() async throws -> Credentials {
        if let credentials, let fetchedAt, Date().timeIntervalSince(fetchedAt) < expiryInterval {
            return credentials
        }
        // Coalesce concurrent refresh requests into a single network call
        if let existing = refreshTask {
            return try await existing.value
        }
        let task = Task { try await refreshCredentials() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    func invalidate() {
        credentials = nil
        fetchedAt = nil
    }

    private func refreshCredentials() async throws -> Credentials {
        guard let url = URL(string: "https://www.bing.com/translator") else {
            throw TranslationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await translationURLSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TranslationError.apiError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: "Failed to fetch Bing Translator page"
            )
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw TranslationError.invalidResponse
        }

        // Extract IG
        guard let igMatch = html.firstMatch(of: /IG:"([^"]+)"/) else {
            throw BingTokenError.parseFailure("IG")
        }
        let ig = String(igMatch.1)

        // Extract IID
        guard let iidMatch = html.firstMatch(of: /data-iid="([^"]+)"/) else {
            throw BingTokenError.parseFailure("IID")
        }
        let iid = String(iidMatch.1)

        // Extract params_AbusePreventionHelper = [key, token, expiryInterval, ...]
        guard let paramsMatch = html.firstMatch(of: /params_AbusePreventionHelper\s*=\s*(\[[^\]]+\])/) else {
            throw BingTokenError.parseFailure("params_AbusePreventionHelper")
        }
        let paramsJSON = String(paramsMatch.1)

        guard let paramsData = paramsJSON.data(using: .utf8),
              let paramsArray = try? JSONSerialization.jsonObject(with: paramsData) as? [Any],
              paramsArray.count >= 3
        else {
            throw BingTokenError.parseFailure("params array")
        }

        guard let key = paramsArray[0] as? Int ?? (paramsArray[0] as? String).flatMap({ Int($0) }) else {
            throw BingTokenError.parseFailure("key")
        }
        guard let token = paramsArray[1] as? String else {
            throw BingTokenError.parseFailure("token")
        }

        let expiry: TimeInterval
        if let interval = paramsArray[2] as? Int {
            expiry = TimeInterval(interval) / 1000.0 // ms → seconds
        } else if let interval = paramsArray[2] as? Double {
            expiry = interval / 1000.0
        } else {
            expiry = 1800 // fallback 30 min
        }

        let creds = Credentials(ig: ig, iid: iid, key: String(key), token: token)
        self.credentials = creds
        self.fetchedAt = Date()
        self.expiryInterval = expiry

        return creds
    }
}

private enum BingTokenError: LocalizedError {
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case let .parseFailure(field):
            return String(localized: "Failed to parse Bing Translator page: \(field)")
        }
    }
}

// MARK: - Settings View

private struct BingTranslateSettingsView: View {
    var body: some View {
        Form {
            Section("Status") {
                Label("Free, no API key needed.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                Text("Uses Bing Translator, may be rate-limited.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
