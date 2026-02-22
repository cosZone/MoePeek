import AppKit
import Defaults

/// Central coordinator that orchestrates: text grabbing → language detection → multi-provider translation.
@MainActor
@Observable
final class TranslationCoordinator {
    /// Overall translation phase.
    enum Phase: Sendable {
        case idle
        case grabbing
        case active
    }

    /// Per-provider translation state.
    enum ProviderState: Sendable, Equatable {
        case waiting
        case translating
        case streaming(partial: String)
        case completed(text: String)
        case error(message: String)
    }

    private(set) var phase: Phase = .idle
    private(set) var sourceText: String = ""
    private(set) var detectedLanguage: String?
    private(set) var targetLanguage: String = ""
    private(set) var providerStates: [String: ProviderState] = [:]
    private(set) var globalError: String?
    private(set) var detectionResult: DetectionResult?
    /// Snapshot of expanded provider slots for the current translation session.
    /// PopupView reads this instead of `registry.enabledSlots` to avoid recomputation during streaming.
    private(set) var activeSlots: [any TranslationProvider] = []

    let registry: TranslationProviderRegistry
    private let permissionManager: PermissionManager
    private var activeTasks: [String: Task<Void, Never>] = [:]

    init(permissionManager: PermissionManager, registry: TranslationProviderRegistry) {
        self.permissionManager = permissionManager
        self.registry = registry
    }

    // MARK: - Public Actions

    /// Triggered by keyboard shortcut: grab selected text → translate.
    func translateSelection() async {
        guard permissionManager.isAccessibilityGranted else {
            phase = .active
            sourceText = ""
            globalError = String(localized: "Accessibility permission not granted. Open Settings to enable it.")
            return
        }

        phase = .grabbing

        guard let text = await TextSelectionManager.grabSelectedText() else {
            phase = .active
            sourceText = ""
            globalError = String(localized: "No text selected. Select some text and try again.")
            return
        }

        translate(text)
    }

    /// Triggered by OCR shortcut: screen capture → OCR → translate.
    func ocrAndTranslate() async {
        phase = .grabbing

        do {
            let text = try await ScreenCaptureOCR.captureAndRecognize()
            translate(text)
        } catch is OCRError {
            phase = .idle
        } catch {
            phase = .active
            sourceText = ""
            globalError = String(localized: "OCR failed: \(error.localizedDescription)")
        }
    }

    /// Read clipboard text and translate directly.
    func translateClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .active
            sourceText = ""
            globalError = String(localized: "Clipboard is empty. Copy some text first.")
            return
        }
        translate(text)
    }

    /// Reset state and enter input mode (empty source input for manual typing).
    func prepareInputMode() {
        cancelAll()
        globalError = nil
        sourceText = ""
        detectedLanguage = nil
        targetLanguage = Defaults[.targetLanguage]
        providerStates = [:]
        detectionResult = nil
        activeSlots = []
        phase = .active
    }

    /// Translate text with all enabled providers in parallel.
    /// Launches provider tasks in the background and returns immediately.
    func translate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .active
            sourceText = ""
            globalError = String(localized: "Empty text")
            return
        }

        cancelAll()
        globalError = nil

        sourceText = trimmed

        // Language detection: check sourceLanguage setting
        let forcedSource = Defaults[.sourceLanguage]

        if forcedSource != "auto" {
            // User specified a source language in the panel or settings
            detectedLanguage = forcedSource
            detectionResult = nil
        } else {
            // Auto-detect with configurable threshold and hints
            let threshold = Defaults[.detectionConfidenceThreshold]
            let hints = buildLanguageHints()
            let result = LanguageDetector.detectWithConfidence(
                trimmed, threshold: threshold, preferredSourceHints: hints
            )
            detectionResult = result
            detectedLanguage = result.language
        }

        targetLanguage = resolveTargetLanguage(detected: detectedLanguage)
        phase = .active

        let providers = registry.enabledSlots
        activeSlots = providers
        guard !providers.isEmpty else {
            globalError = String(localized: "No providers enabled. Enable at least one in Settings.")
            return
        }

        // Initialize all provider states
        providerStates = [:]
        for provider in providers {
            providerStates[provider.id] = .waiting
        }

        // Launch parallel tasks
        for provider in providers {
            let task = Task {
                await runProvider(provider, text: trimmed, from: detectedLanguage, to: targetLanguage)
            }
            activeTasks[provider.id] = task
        }
    }

    /// Retry a single provider that previously errored.
    func retryProvider(_ provider: any TranslationProvider) {
        guard phase == .active, !sourceText.isEmpty else { return }
        activeTasks[provider.id]?.cancel()
        providerStates[provider.id] = .waiting
        let text = sourceText
        let target = targetLanguage
        let source = detectedLanguage
        let task = Task {
            await runProvider(provider, text: text, from: source, to: target)
        }
        activeTasks[provider.id] = task
    }

    func dismiss() {
        cancelAll()
        phase = .idle
        sourceText = ""
        detectedLanguage = nil
        targetLanguage = ""
        providerStates = [:]
        globalError = nil
        detectionResult = nil
        activeSlots = []
    }

    // MARK: - Computed Helpers

    /// Whether any provider has completed with a result.
    var hasAnyResult: Bool {
        providerStates.values.contains { state in
            if case .completed = state { return true }
            return false
        }
    }

    /// Whether all providers have finished (completed or error).
    var allFinished: Bool {
        guard !providerStates.isEmpty else { return true }
        return providerStates.values.allSatisfy { state in
            switch state {
            case .completed, .error: return true
            default: return false
            }
        }
    }

    // MARK: - Private

    private func runProvider(
        _ provider: any TranslationProvider,
        text: String,
        from sourceLang: String?,
        to targetLang: String
    ) async {
        defer {
            // Only clean up if not cancelled: when retryProvider() replaces a task,
            // the cancelled old task must not remove the new task's dictionary entry.
            if !Task.isCancelled {
                activeTasks.removeValue(forKey: provider.id)
            }
        }
        providerStates[provider.id] = .translating

        do {
            var accumulated = ""
            for try await chunk in provider.translateStream(text, from: sourceLang, to: targetLang) {
                guard !Task.isCancelled else { return }
                accumulated += chunk
                providerStates[provider.id] = .streaming(partial: accumulated)
            }

            guard !Task.isCancelled else { return }

            if accumulated.isEmpty {
                providerStates[provider.id] = .error(message: String(localized: "Translation returned empty result"))
            } else {
                providerStates[provider.id] = .completed(text: accumulated)
            }
        } catch {
            guard !Task.isCancelled else { return }
            providerStates[provider.id] = .error(message: error.localizedDescription)
        }
    }

    private func cancelAll() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
    }

    /// Build language hints (BCP 47 codes) based on user's target/source language preferences.
    /// Likely source languages are inferred from the target language for common translation pairs.
    private func buildLanguageHints() -> [String: Double]? {
        let target = Defaults[.targetLanguage]
        let source = Defaults[.sourceLanguage]

        var hints: [String: Double] = [:]

        // If user specified a preferred source language, give it a boost
        if source != "auto" {
            hints[source] = 0.5
        }

        // Infer likely source languages from target language
        switch target {
        case let t where t.hasPrefix("zh"):
            hints["en", default: 0] += 0.2
            hints["ja", default: 0] += 0.1
            hints["ko", default: 0] += 0.05
        case "en":
            hints["zh-Hans", default: 0] += 0.2
            hints["ja", default: 0] += 0.1
            hints["ko", default: 0] += 0.05
            hints["fr", default: 0] += 0.05
            hints["de", default: 0] += 0.05
            hints["es", default: 0] += 0.05
        case "ja":
            hints["en", default: 0] += 0.2
            hints["zh-Hans", default: 0] += 0.1
        case "ko":
            hints["en", default: 0] += 0.2
            hints["zh-Hans", default: 0] += 0.1
            hints["ja", default: 0] += 0.05
        case "fr", "de", "es", "it", "pt-BR":
            hints["en", default: 0] += 0.2
            hints["fr", default: 0] += 0.05
            hints["de", default: 0] += 0.05
            hints["es", default: 0] += 0.05
            hints["it", default: 0] += 0.05
            hints["pt-BR", default: 0] += 0.05
        case "ru":
            hints["en", default: 0] += 0.2
        case "ar":
            hints["en", default: 0] += 0.2
        default:
            break
        }

        // Don't hint the target language itself as a source
        hints.removeValue(forKey: target)

        return hints.isEmpty ? nil : hints
    }

    private func resolveTargetLanguage(detected: String?) -> String {
        let preferred = Defaults[.targetLanguage]

        guard let detected else { return preferred }

        if detected.hasPrefix("zh") && preferred.hasPrefix("zh") {
            return "en"
        }
        if detected == preferred {
            return detected.hasPrefix("zh") ? "en" : "zh-Hans"
        }

        return preferred
    }
}
