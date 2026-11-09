import Defaults
import Foundation
import SwiftUI

/// Google Translate provider using the free GTX API (no API key required).
struct GoogleTranslateProvider: TranslationProvider {
    let id = "google"
    let displayName = "Google Translate"
    let iconSystemName = "g.circle.fill"
    let iconAssetName: String? = "Google"
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
        AnyView(GoogleTranslateSettingsView())
    }

    // MARK: - Translation

    func translate(_ text: String, from sourceLang: String?, to targetLang: String) async throws -> String {
        let sl = LanguageCodeMapping.resolve(sourceLang, using: LanguageCodeMapping.google) ?? "auto"
        let tl = LanguageCodeMapping.resolveTarget(targetLang, using: LanguageCodeMapping.google)

        guard var components = URLComponents(string: "https://translate.google.com/translate_a/single") else {
            throw TranslationError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: sl),
            URLQueryItem(name: "tl", value: tl),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "dj", value: "1"),
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "q", value: text),
        ]

        guard let url = components.url else {
            throw TranslationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let session = try await GoogleTranslateProxySession.shared.session(for: Self.proxySettings)
            ?? translationURLSession
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }

        let json = try JSONDecoder().decode(GTXResponse.self, from: data)
        let translated = json.sentences.compactMap(\.trans).joined()

        guard !translated.isEmpty else {
            throw TranslationError.emptyResult
        }
        return translated
    }

    @MainActor
    static var proxySettings: GoogleTranslateProxySettings {
        GoogleTranslateProxySettings(
            enabled: Defaults[.googleProxyEnabled],
            host: Defaults[.googleProxyHost],
            port: Defaults[.googleProxyPort]
        )
    }
}

// MARK: - Response Model

private struct GTXResponse: Decodable {
    let sentences: [Sentence]

    struct Sentence: Decodable {
        let trans: String?
    }
}

// MARK: - Settings View

private struct GoogleTranslateSettingsView: View {
    @Default(.googleProxyEnabled) private var proxyEnabled
    @Default(.googleProxyHost) private var proxyHost
    @Default(.googleProxyPort) private var proxyPort

    @State private var testID: UUID?
    @State private var testMessage: String?
    @State private var testSucceeded = false

    private var proxyError: String? {
        do {
            _ = try GoogleTranslateProvider.proxySettings.configuration()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        Form {
            Section("Status") {
                Label("Free, no API key needed.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                Text("Uses unofficial Google Translate API, may be rate-limited.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("HTTP Proxy") {
                Toggle("Use a custom HTTP proxy", isOn: $proxyEnabled)
                if proxyEnabled {
                    TextField("Proxy Host", text: $proxyHost)
                    TextField("Proxy Port", text: $proxyPort)
                    Text("For a local proxy, use 127.0.0.1 and its HTTP or mixed port. Authentication is not supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let proxyError {
                        Label(proxyError, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Text("Applies only to Google Translate. When disabled, existing system and per-app proxy routing is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button {
                        testMessage = nil
                        testID = UUID()
                    } label: {
                        Label("Test Connection", systemImage: "bolt.horizontal")
                    }
                    .disabled(testID != nil || proxyError != nil)
                    if testID != nil {
                        ProgressView().controlSize(.small)
                    }
                }
                if let testMessage {
                    Label(testMessage, systemImage: testSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(testSucceeded ? .green : .red)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .task(id: testID) {
            guard let currentTestID = testID else { return }
            do {
                _ = try await GoogleTranslateProvider().translate("Hello", from: "en", to: "zh-Hans")
                guard !Task.isCancelled, testID == currentTestID else { return }
                testSucceeded = true
                testMessage = String(localized: "Connection successful")
            } catch {
                guard !Task.isCancelled, testID == currentTestID else { return }
                testSucceeded = false
                testMessage = error.localizedDescription
            }
            testID = nil
        }
        .onChange(of: proxyEnabled) { resetTest() }
        .onChange(of: proxyHost) { resetTest() }
        .onChange(of: proxyPort) { resetTest() }
        .onDisappear { resetTest() }
    }

    private func resetTest() {
        testID = nil
        testMessage = nil
    }
}
