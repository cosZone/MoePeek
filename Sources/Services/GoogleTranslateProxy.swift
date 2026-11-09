import Foundation
import Network

/// An optional HTTP CONNECT proxy for Google Translate only.
struct GoogleTranslateProxySettings: Equatable, Sendable {
    var enabled: Bool
    var host: String
    var port: String

    func configuration() throws -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        guard enabled else { return config }

        var hostname = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if hostname.hasPrefix("["), hostname.hasSuffix("]") {
            hostname = String(hostname.dropFirst().dropLast())
        }
        let isIPv6 = IPv6Address(hostname) != nil
        let isHostname = !hostname.isEmpty && hostname.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0)
                || (48...57).contains($0) || $0 == 45 || $0 == 46
        } && hostname.contains(where: { $0.isLetter || $0.isNumber })
        guard isIPv6 || isHostname else { throw ValidationError.invalidHost }
        guard let number = UInt16(port.trimmingCharacters(in: .whitespacesAndNewlines)),
              number > 0, let proxyPort = NWEndpoint.Port(rawValue: number) else {
            throw ValidationError.invalidPort
        }

        var proxy = ProxyConfiguration(httpCONNECTProxy: .hostPort(
            host: NWEndpoint.Host(hostname), port: proxyPort
        ))
        // A failed explicit proxy must report an error instead of bypassing it.
        proxy.allowFailover = false
        config.proxyConfigurations = [proxy]
        return config
    }

    enum ValidationError: LocalizedError, Equatable {
        case invalidHost, invalidPort

        var errorDescription: String? {
            switch self {
            case .invalidHost:
                String(localized: "Enter a proxy hostname or IP address without a scheme, path, or port.")
            case .invalidPort:
                String(localized: "Enter a proxy port between 1 and 65535.")
            }
        }
    }
}

/// Reuse connections, but replace the session when proxy settings change.
/// Old sessions finish in-flight requests before releasing their resources.
@MainActor
final class GoogleTranslateProxySession {
    static let shared = GoogleTranslateProxySession()

    private var settings: GoogleTranslateProxySettings?
    private var cachedSession: URLSession?

    /// nil means the provider should use its existing shared system session.
    func session(for newSettings: GoogleTranslateProxySettings) throws -> URLSession? {
        guard newSettings.enabled else {
            cachedSession?.finishTasksAndInvalidate()
            cachedSession = nil
            settings = nil
            return nil
        }
        if newSettings == settings { return cachedSession }

        let config = try newSettings.configuration()
        let session = URLSession(configuration: config)
        cachedSession?.finishTasksAndInvalidate()
        cachedSession = session
        settings = newSettings
        return session
    }

    deinit {
        cachedSession?.finishTasksAndInvalidate()
    }
}
