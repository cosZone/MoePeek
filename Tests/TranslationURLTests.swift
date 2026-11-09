import AppKit
import SwiftUI
import Testing
@testable import MoePeek

@MainActor
@Suite(.serialized)
struct TranslationURLTests {
    @Test(arguments: [
        "Hello & goodbye? 100% + # = 中文🙂\nSecond line",
        "https://example.test/?a=1&b=2#section",
        "Keep the literal %20 and %26 sequences",
    ])
    func externalURLPreservesSelectedText(_ text: String) throws {
        let delegate = makeDelegate()
        defer { delegate.panelController.dismiss() }
        var components = URLComponents(string: "mopeek://translate")!
        components.queryItems = [URLQueryItem(name: "text", value: text)]

        delegate.application(NSApplication.shared, open: [try #require(components.url)])

        #expect(delegate.coordinator.sourceText == text)
        #expect(delegate.coordinator.activeSlots.map(\.id) == ["url-test"])
        #expect(delegate.panelController.isVisible)
    }

    @Test(arguments: [
        "https://translate?text=hello",
        "mopeek://settings?text=hello",
        "mopeek://translate",
        "mopeek://translate?text=",
    ])
    func unrelatedOrEmptyURLsLeaveTheCurrentTranslationAlone(_ rawURL: String) throws {
        let delegate = makeDelegate()
        defer { delegate.panelController.dismiss() }
        delegate.coordinator.translate("Existing translation")
        let generation = delegate.coordinator.translationGeneration

        delegate.application(NSApplication.shared, open: [try #require(URL(string: rawURL))])

        #expect(delegate.coordinator.sourceText == "Existing translation")
        #expect(delegate.coordinator.translationGeneration == generation)
        #expect(!delegate.panelController.isVisible)
    }

    private func makeDelegate() -> AppDelegate {
        let registry = TranslationProviderRegistry(
            providers: [URLTestProvider()],
            enabledProviderIDs: { ["url-test"] },
            providerOrder: { [] },
            onDemandProviderIDs: { [] }
        )
        let delegate = AppDelegate()
        delegate.coordinator = TranslationCoordinator(permissionManager: URLTestPermissions(), registry: registry)
        delegate.panelController = PopupPanelController(coordinator: delegate.coordinator)
        return delegate
    }
}

private struct URLTestProvider: TranslationProvider {
    let id = "url-test"
    let displayName = "URL Test"
    let iconSystemName = "character.bubble"
    let supportsStreaming = false
    let isAvailable = true
    @MainActor var isConfigured: Bool { true }

    func translateStream(_ text: String, from sourceLang: String?, to targetLang: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(text)
            continuation.finish()
        }
    }

    @MainActor func makeSettingsView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
private final class URLTestPermissions: PermissionChecking {
    let isAccessibilityGranted = true
    let isScreenRecordingGranted = true
}
