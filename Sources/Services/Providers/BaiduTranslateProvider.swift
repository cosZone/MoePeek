import CryptoKit
import Defaults
import Foundation
import SwiftUI

/// Baidu Translate (百度翻译) API provider with MD5 signature authentication.
struct BaiduTranslateProvider: TranslationProvider {
    let id = "baidu"
    let displayName = "Baidu"
    let iconSystemName = "pawprint.fill"
    let iconAssetName: String? = "Baidu"
    let category: ProviderCategory = .traditional
    let supportsStreaming = false
    let isAvailable = true

    let appIdKey = Defaults.Key<String>("provider_baidu_appId", default: "")
    let secretKeyKey = Defaults.Key<String>("provider_baidu_secretKey", default: "")

    @MainActor
    var isConfigured: Bool {
        !Defaults[appIdKey].isEmpty && !Defaults[secretKeyKey].isEmpty
    }

    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String
    ) -> AsyncThrowingStream<String, Error> {
        singleResultStream { [self] in try await translate(text, from: sourceLang, to: targetLang) }
    }

    @MainActor
    func makeSettingsView() -> AnyView {
        AnyView(BaiduSettingsView(provider: self))
    }

    // MARK: - Private

    private func translate(_ text: String, from sourceLang: String?, to targetLang: String) async throws -> String {
        let appId = Defaults[appIdKey]
        let secretKey = Defaults[secretKeyKey]
        guard !appId.isEmpty, !secretKey.isEmpty else { throw TranslationError.missingAPIKey }

        guard let url = URL(string: "https://fanyi-api.baidu.com/api/trans/vip/translate") else {
            throw TranslationError.invalidURL
        }

        let fromCode = LanguageCodeMapping.resolve(sourceLang, using: LanguageCodeMapping.baidu) ?? "auto"
        let toCode = LanguageCodeMapping.resolveTarget(targetLang, using: LanguageCodeMapping.baidu)

        let salt = String(Int.random(in: 100000...999999))
        let signString = appId + text + salt + secretKey
        let sign = md5Hex(signString)

        let formParts = [
            "q=\(URLFormEncoding.encode(text))",
            "from=\(URLFormEncoding.encode(fromCode))",
            "to=\(URLFormEncoding.encode(toCode))",
            "appid=\(URLFormEncoding.encode(appId))",
            "salt=\(URLFormEncoding.encode(salt))",
            "sign=\(URLFormEncoding.encode(sign))",
        ]

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formParts.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await translationURLSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw TranslationError.apiError(
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8) ?? ""
            )
        }

        let decoded = try JSONDecoder().decode(BaiduResponse.self, from: data)

        if let errorCode = decoded.error_code {
            throw TranslationError.apiError(
                statusCode: 0,
                message: "Baidu error \(errorCode): \(decoded.error_msg ?? String(localized: "Unknown error"))"
            )
        }

        guard let results = decoded.trans_result, !results.isEmpty else {
            throw TranslationError.emptyResult
        }

        return results.map(\.dst).joined(separator: "\n")
    }

    private func md5Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Response Model

private struct BaiduResponse: Decodable {
    let trans_result: [TransResult]?
    let error_code: String?
    let error_msg: String?

    struct TransResult: Decodable {
        let dst: String
    }
}

// MARK: - Settings View

private struct BaiduSettingsView: View {
    let provider: BaiduTranslateProvider

    private var appId: Binding<String> { Defaults.binding(provider.appIdKey) }
    private var secretKey: Binding<String> { Defaults.binding(provider.secretKeyKey) }

    var body: some View {
        Form {
            Section("API Configuration") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App ID")
                        .font(.subheadline.bold())
                    TextField("Enter Baidu App ID", text: appId)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Secret Key")
                        .font(.subheadline.bold())
                    SecureField("Enter Baidu Secret Key", text: secretKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                Link(destination: URL(string: "https://api.fanyi.baidu.com")!) {
                    Label("Get credentials at api.fanyi.baidu.com", systemImage: "arrow.up.right.square")
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}
