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
    /// Images captured with rich source text, keyed by placeholder id. Released with the request.
    private(set) var sourceAttachments: [String: SourceImageAttachment] = [:]
    private(set) var detectedLanguage: String?
    private(set) var targetLanguage: String = ""
    private(set) var providerStates: [String: ProviderState] = [:]
    /// Setting a non-nil error also auto-unpins, so an error never appears in a frozen pinned panel.
    private(set) var globalError: String? {
        didSet {
            if globalError != nil { isPinned = false }
        }
    }
    private(set) var detectionResult: DetectionResult?
    /// Snapshot of expanded provider slots for the current translation session.
    /// PopupView reads this instead of `registry.enabledSlots` to avoid recomputation during streaming.
    private(set) var activeSlots: [any TranslationProvider] = []
    /// Monotonically increasing counter; increments each time `translate()` is called.
    /// Used by PopupView to reset `expandedProviders` for subsequent translations.
    private(set) var translationGeneration: Int = 0
    private(set) var copiedProviderID: String?
    private(set) var copyFeedbackGeneration: Int = 0
    /// Single source of truth for popup pin state. PopupView toggles, PopupPanelController reads.
    var isPinned: Bool = false

    let registry: TranslationProviderRegistry
    private let permissionManager: PermissionManager
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var copyFeedbackTask: Task<Void, Never>?

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

        guard let document = await TextSelectionManager.grabSelectedDocument() else {
            phase = .active
            sourceText = ""
            globalError = String(localized: "No text selected. Select some text and try again.")
            return
        }

        translate(document: document)
    }

    /// Triggered by the floating icon, which already holds the plain selection. With rich
    /// capture on, re-copy the still-active selection to pick up formatting and images.
    func translateTriggeredSelection(_ text: String) async {
        if TextSelectionManager.isRichCaptureEnabled,
           let document = await ClipboardGrabber.grabRichViaClipboard() {
            translate(document: document)
        } else {
            translate(text)
        }
    }

    /// Triggered by OCR shortcut: screen capture → OCR → translate.
    func ocrAndTranslate() async {
        guard permissionManager.isScreenRecordingGranted else {
            phase = .active
            sourceText = ""
            globalError = String(localized: "Screen recording permission not granted. Open Settings to enable it.")
            return
        }

        let previousPhase = phase
        phase = .grabbing

        do {
            let text = try await ScreenCaptureOCR.captureAndRecognize()
            translate(text)
        } catch OCRError.captureCancelled {
            phase = previousPhase
        } catch {
            phase = .active
            sourceText = ""
            globalError = String(localized: "OCR failed: \(error.localizedDescription)")
        }
    }

    /// Read clipboard text and translate directly.
    func translateClipboard() async {
        if Defaults[.captureRichText],
           let payload = RichTextImporter.payload(from: NSPasteboard.general),
           let document = await RichTextImporter.document(from: payload) {
            translate(document: document)
            return
        }
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
        clearCopyFeedback()
        globalError = nil
        sourceText = ""
        sourceAttachments = [:]
        detectedLanguage = nil
        targetLanguage = Defaults[.targetLanguage]
        providerStates = [:]
        detectionResult = nil
        activeSlots = []
        phase = .active
    }

    /// Translate text with all enabled providers in parallel.
    /// Launches provider tasks in the background and returns immediately.
    /// Attachments from the current session survive as long as the text still references them.
    func translate(_ text: String) {
        startTranslation(
            text,
            attachments: SourceAttachmentReference.retainedAttachments(sourceAttachments, referencedIn: text)
        )
    }

    func translate(document: RichSourceDocument) {
        startTranslation(document.markdown, attachments: document.attachments)
    }

    private func startTranslation(_ text: String, attachments: [String: SourceImageAttachment]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .active
            sourceText = ""
            globalError = String(localized: "Empty text")
            return
        }

        cancelAll()
        clearCopyFeedback()
        globalError = nil

        sourceText = trimmed
        sourceAttachments = attachments

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
        translationGeneration += 1
        guard !providers.isEmpty else {
            globalError = String(localized: "No providers enabled. Enable at least one in Settings.")
            return
        }

        // Initialize all provider states
        providerStates = [:]
        for provider in providers {
            providerStates[provider.id] = .waiting
        }

        for provider in providers {
            launchProvider(provider, text: trimmed, from: detectedLanguage, to: targetLanguage)
        }
    }

    /// Retry a single provider that previously errored.
    func retryProvider(_ provider: any TranslationProvider) {
        guard phase == .active, !sourceText.isEmpty else { return }
        activeTasks[provider.id]?.cancel()
        providerStates[provider.id] = .waiting
        launchProvider(provider, text: sourceText, from: detectedLanguage, to: targetLanguage)
    }

    @discardableResult
    func copyResult(atDisplayIndex index: Int) -> Bool {
        guard activeSlots.indices.contains(index) else { return false }
        return copyResult(forProviderID: activeSlots[index].id)
    }

    @discardableResult
    func copyResult(forProviderID providerID: String) -> Bool {
        guard let rawText = providerStates[providerID]?.copyableText else { return false }
        let resultText = MarkdownSupport.removingAttachmentPlaceholders(rawText)
        guard !resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(resultText, forType: .string) else { return false }
        showCopyFeedback(forProviderID: providerID)
        return true
    }

    func dismiss() {
        cancelAll()
        clearCopyFeedback()
        phase = .idle
        sourceText = ""
        sourceAttachments = [:]
        detectedLanguage = nil
        targetLanguage = ""
        providerStates = [:]
        globalError = nil
        detectionResult = nil
        activeSlots = []
        isPinned = false
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

    /// Markdown sources go to LLM providers verbatim with a preserve-formatting instruction;
    /// machine translation APIs get plain text because they cannot honor either.
    private func launchProvider(
        _ provider: any TranslationProvider,
        text: String,
        from sourceLang: String?,
        to targetLang: String
    ) {
        let isMarkdown = MarkdownSupport.looksLikeMarkdown(text)
        let sendsMarkdown = isMarkdown && provider.acceptsMarkdownInput
        let providerText = (isMarkdown && !provider.acceptsMarkdownInput) ? MarkdownSupport.plainText(from: text) : text
        guard !providerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            providerStates[provider.id] = .error(message: String(localized: "Nothing to translate after removing images."))
            return
        }
        let task = Task {
            await TranslationRequestContext.$sourceIsMarkdown.withValue(sendsMarkdown) {
                await runProvider(provider, text: providerText, from: sourceLang, to: targetLang)
            }
        }
        activeTasks[provider.id] = task
    }

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

    private func showCopyFeedback(forProviderID providerID: String) {
        copyFeedbackTask?.cancel()
        copiedProviderID = providerID
        copyFeedbackGeneration += 1

        copyFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            guard self?.copiedProviderID == providerID else { return }
            self?.copiedProviderID = nil
            self?.copyFeedbackTask = nil
        }
    }

    private func clearCopyFeedback() {
        copyFeedbackTask?.cancel()
        copyFeedbackTask = nil
        copiedProviderID = nil
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

private extension TranslationCoordinator.ProviderState {
    var copyableText: String? {
        switch self {
        case let .streaming(partial):
            partial
        case let .completed(text):
            text
        case .waiting, .translating, .error:
            nil
        }
    }
}
