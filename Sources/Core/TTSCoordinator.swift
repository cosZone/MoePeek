import Defaults
import Foundation
import Observation

@MainActor @Observable
final class TTSCoordinator {
    enum PlaybackState: Equatable {
        case idle
        case loading
        case playing(providerID: String)
        case error(String)
    }

    private(set) var playbackState: PlaybackState = .idle
    /// The text currently being spoken, used to scope UI state per-button.
    private(set) var currentText: String?
    private var speakTask: Task<Void, Never>?
    private var activePlaybackProvider: (any TTSProvider)?

    private let registry: TTSProviderRegistry

    init(registry: TTSProviderRegistry) {
        self.registry = registry
    }

    func speak(_ text: String, language: String) {
        stop()
        currentText = text

        speakTask = Task { [weak self] in
            guard let self else { return }
            let provider = registry.activeProvider
            activePlaybackProvider = provider
            playbackState = .loading

            do {
                try await performSpeak(provider, text: text, language: language)
            } catch {
                guard !Task.isCancelled else { return }

                // Fallback to Apple TTS if the current provider isn't Apple
                if provider.id != AppleTTSProvider.providerID,
                   let apple = registry.provider(withID: AppleTTSProvider.providerID)
                {
                    print("[TTS] \(provider.displayName) failed: \(error.localizedDescription), falling back to Apple TTS")
                    do {
                        try await performSpeak(apple, text: text, language: language)
                    } catch {
                        if !Task.isCancelled {
                            playbackState = .error(error.localizedDescription)
                        }
                    }
                } else {
                    playbackState = .error(error.localizedDescription)
                }
            }

            self.speakTask = nil
        }
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        activePlaybackProvider?.stop()
        activePlaybackProvider = nil
        currentText = nil
        playbackState = .idle
    }

    var isPlaying: Bool {
        if case .playing = playbackState { return true }
        if case .loading = playbackState { return true }
        return false
    }

    func isPlaying(_ text: String) -> Bool {
        isPlaying && currentText == text
    }

    private func performSpeak(_ provider: any TTSProvider, text: String, language: String) async throws {
        playbackState = .playing(providerID: provider.id)
        let rate = effectiveRate(for: language)
        try await provider.speak(text, language: language, accent: Defaults[.ttsAccent], rate: rate)
        if !Task.isCancelled {
            playbackState = .idle
        }
    }

    private func effectiveRate(for language: String) -> Float {
        if let override = Defaults[.ttsLanguageRates][language] {
            return Float(override)
        }
        return Float(Defaults[.ttsSpeechRate])
    }
}
