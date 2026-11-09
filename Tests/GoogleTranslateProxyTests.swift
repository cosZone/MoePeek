import Foundation
import Network
import Testing
@testable import MoePeek

@Suite struct GoogleTranslateProxyTests {
    @Test func disabledProxyIgnoresUnfinishedFieldsAndPreservesSystemRouting() throws {
        let config = try GoogleTranslateProxySettings(enabled: false, host: "", port: "").configuration()
        #expect(config.proxyConfigurations.isEmpty)
        #expect(config.connectionProxyDictionary == nil)
        #expect(config.urlCache == nil)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test(arguments: ["127.0.0.1", "localhost", "proxy.example.com", "::1", "[::1]", " 127.0.0.1 \n"])
    func acceptsProxyHosts(host: String) throws {
        let config = try GoogleTranslateProxySettings(enabled: true, host: host, port: " 7890 ").configuration()
        #expect(config.proxyConfigurations.count == 1)
        #expect(config.proxyConfigurations.first?.allowFailover == false)
        #expect(config.urlCache == nil)
    }

    @Test(arguments: ["", " ", "http://127.0.0.1", "127.0.0.1:7890", "proxy/path", "user@proxy", "proxy host"])
    func rejectsInvalidHosts(host: String) {
        #expect(throws: GoogleTranslateProxySettings.ValidationError.invalidHost) {
            try GoogleTranslateProxySettings(enabled: true, host: host, port: "7890").configuration()
        }
    }

    @Test(arguments: ["", "0", "65536", "-1", "abc", "7890.0"])
    func rejectsInvalidPorts(port: String) {
        #expect(throws: GoogleTranslateProxySettings.ValidationError.invalidPort) {
            try GoogleTranslateProxySettings(enabled: true, host: "127.0.0.1", port: port).configuration()
        }
    }

    @Test(arguments: ["1", "65535"])
    func acceptsPortBoundaries(port: String) throws {
        _ = try GoogleTranslateProxySettings(enabled: true, host: "127.0.0.1", port: port).configuration()
    }

    @Test @MainActor func reusesConnectionsAndAppliesChangedSettingsWithoutRestart() throws {
        let store = GoogleTranslateProxySession()
        var settings = GoogleTranslateProxySettings(enabled: true, host: "127.0.0.1", port: "7890")
        let first = try #require(try store.session(for: settings))
        #expect(try store.session(for: settings) === first)

        settings.port = "7891"
        let changed = try #require(try store.session(for: settings))
        #expect(changed !== first)

        settings.enabled = false
        #expect(try store.session(for: settings) == nil)
        settings.enabled = true
        #expect(try store.session(for: settings) !== changed)
    }

    @Test @MainActor func invalidProxyDoesNotReusePreviousProxyOrFallBackToSystem() throws {
        let store = GoogleTranslateProxySession()
        var settings = GoogleTranslateProxySettings(enabled: true, host: "127.0.0.1", port: "7890")
        _ = try store.session(for: settings)
        settings.port = "0"
        #expect(throws: GoogleTranslateProxySettings.ValidationError.invalidPort) {
            try store.session(for: settings)
        }
    }
}
