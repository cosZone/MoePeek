import AppKit
import Defaults
import KeyboardShortcuts

/// Handles app lifecycle, permission checks, and global shortcut registration.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // registry must be available before applicationDidFinishLaunching because
    // SwiftUI evaluates MoePeekApp.body (which reads registry) during app init.
    lazy var registry = TranslationProviderRegistry.builtIn()
    lazy var ttsRegistry = TTSProviderRegistry.builtIn()
    lazy var ttsCoordinator = TTSCoordinator(registry: ttsRegistry)
    var coordinator: TranslationCoordinator!
    var panelController: PopupPanelController!
    var permissionManager: PermissionManager!
    var onboardingController: OnboardingWindowController!
    var selectionMonitor: SelectionMonitor!
    var triggerIconController: TriggerIconController!
    lazy var copyToastController = CopyToastController()
    lazy var updaterController = UpdaterController()
    var settingsController: SettingsWindowController!
    private var smartTranslationTask: Task<Void, Never>?
    private var smartTranslationTaskID: UUID?

    func applicationDidFinishLaunching(_: Notification) {
        applyLanguageOverride()

        // Migrate old settings to new namespaced keys (one-time)
        migrateDefaults()

        permissionManager = PermissionManager()
        coordinator = TranslationCoordinator(permissionManager: permissionManager, registry: registry)
        settingsController = SettingsWindowController(
            registry: registry,
            ttsRegistry: ttsRegistry,
            ttsCoordinator: ttsCoordinator,
            updaterController: updaterController
        )
        panelController = PopupPanelController(
            coordinator: coordinator,
            ttsCoordinator: ttsCoordinator,
            settingsController: settingsController
        )
        onboardingController = OnboardingWindowController(permissionManager: permissionManager, registry: registry)
        selectionMonitor = SelectionMonitor()
        triggerIconController = TriggerIconController()
        // Apply dock visibility — always set explicitly because macOS may cache
        // .regular from a previous session, ignoring LSUIElement on relaunch.
        NSApp.setActivationPolicy(Defaults[.showInDock] ? .regular : .accessory)

        setupShortcuts()
        setupSelectionMonitor()

        // Show onboarding on first launch; returning users start silently as a menu bar app.
        if !Defaults[.hasCompletedOnboarding] {
            // Delay to let SwiftUI finish scene setup; async alone is insufficient.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.onboardingController.showWindow()
            }
        } else if !permissionManager.allPermissionsGranted {
            // Permissions lost after update — show a simplified recovery prompt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.onboardingController.showPermissionRecovery()
            }
        }
        if !permissionManager.allPermissionsGranted {
            permissionManager.startPolling()
        }
    }

    // MARK: - URL Scheme Handler

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "mopeek", url.host == "translate" else { continue }
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let text = components.queryItems?.first(where: { $0.name == "text" })?.value,
                  !text.isEmpty
            else { continue }

            cancelSmartTranslation()
            coordinator.translate(text)
            if case .idle = coordinator.phase { continue }
            panelController.showAtCursor()
        }
    }

    // MARK: - Language Override

    private func applyLanguageOverride() {
        let language = Defaults[.appLanguage]
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    // MARK: - Migration

    private func migrateDefaults() {
        migrateV1ProviderSettings()
        migrateV2KeychainToDefaults()
        migrateV3RemovedProviders()
        migrateV4PopupPositionKeys()
    }

    /// V4: Earlier builds of the remember-position feature stored the panel's bottom-left
    /// origin under `popupLastOriginX/Y`. We now persist the top-left corner under
    /// `popupLastTopLeftX/Y` so the visual position survives size changes. Convert any
    /// existing bottom-left value to top-left using the current default panel height as
    /// the best available approximation, then clear the legacy keys. If the saved flag is
    /// set but neither new nor old keys carry data, clear the flag so the panel falls back
    /// to cursor/center instead of opening at (0,0).
    private func migrateV4PopupPositionKeys() {
        let migrationKey = "hasMigratedPopupPositionToTopLeft"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let ud = UserDefaults.standard
        let oldX = ud.object(forKey: "popupLastOriginX") as? Double
        let oldY = ud.object(forKey: "popupLastOriginY") as? Double

        if let oldX, let oldY {
            let height = Double(Defaults[.popupDefaultHeight])
            Defaults[.popupLastTopLeftX] = oldX
            Defaults[.popupLastTopLeftY] = oldY + height
            ud.removeObject(forKey: "popupLastOriginX")
            ud.removeObject(forKey: "popupLastOriginY")
        } else if Defaults[.popupHasSavedPosition],
                  Defaults[.popupLastTopLeftX] == 0,
                  Defaults[.popupLastTopLeftY] == 0 {
            Defaults[.popupHasSavedPosition] = false
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// V1: Migrate old flat keys to namespaced provider keys.
    private func migrateV1ProviderSettings() {
        let migrationKey = "hasCompletedProviderMigration"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        // Migrate OpenAI settings to namespaced keys
        let oldBaseURL = Defaults.Key<String>("openAIBaseURL", default: "https://api.openai.com/v1")
        let oldModel = Defaults.Key<String>("openAIModel", default: "gpt-4o-mini")
        let oldPrompt = Defaults.Key<String>(
            "systemPromptTemplate",
            default: "Translate the following text to {targetLang}. Only output the translation, nothing else."
        )

        let newBaseURL = Defaults.Key<String>("provider_openai_baseURL", default: "https://api.openai.com/v1")
        let newModel = Defaults.Key<String>("provider_openai_model", default: "gpt-4o-mini")
        let newPrompt = Defaults.Key<String>(
            "provider_openai_systemPrompt",
            default: "Translate the following text to {targetLang}. Only output the translation, nothing else."
        )
        let newApiKey = Defaults.Key<String>("provider_openai_apiKey", default: "")

        // Only migrate if old keys have non-default values
        if UserDefaults.standard.object(forKey: "openAIBaseURL") != nil {
            Defaults[newBaseURL] = Defaults[oldBaseURL]
        }
        if UserDefaults.standard.object(forKey: "openAIModel") != nil {
            Defaults[newModel] = Defaults[oldModel]
        }
        if UserDefaults.standard.object(forKey: "systemPromptTemplate") != nil {
            Defaults[newPrompt] = Defaults[oldPrompt]
        }

        // Migrate Keychain API key directly to Defaults
        if let oldApiKey = KeychainHelper.load(key: "openai_api_key"), !oldApiKey.isEmpty {
            Defaults[newApiKey] = oldApiKey
        }

        // Migrate preferredService to enabledProviders
        if let preferred = UserDefaults.standard.string(forKey: "preferredService") {
            var enabled: Set<String> = []
            if preferred == "apple" {
                enabled = ["apple"]
            } else {
                enabled = ["openai"]
            }
            Defaults[.enabledProviders] = enabled
        }

        // Clean up old keys
        for oldKey in ["openAIBaseURL", "openAIModel", "systemPromptTemplate", "preferredService"] {
            UserDefaults.standard.removeObject(forKey: oldKey)
        }
        KeychainHelper.delete(key: "openai_api_key")

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// V2: Migrate API keys from Keychain to Defaults for users who already completed V1 migration.
    private func migrateV2KeychainToDefaults() {
        let migrationKey = "hasCompletedKeychainToDefaultsMigration"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let keychainKey = "provider.openai.apiKey"
        let defaultsKey = Defaults.Key<String>("provider_openai_apiKey", default: "")

        if let apiKey = KeychainHelper.load(key: keychainKey), !apiKey.isEmpty {
            Defaults[defaultsKey] = apiKey
            KeychainHelper.delete(key: keychainKey)
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// V3: Remove provider IDs that no longer exist; fall back to default if none remain.
    private func migrateV3RemovedProviders() {
        let removedIDs: Set<String> = ["groq", "github-models"]
        var enabled = Defaults[.enabledProviders]
        let needsMigration = !enabled.isDisjoint(with: removedIDs)
        if needsMigration {
            enabled.subtract(removedIDs)
            if enabled.isEmpty {
                enabled = ["google"]
            }
            Defaults[.enabledProviders] = enabled
        }

        // Clean up orphaned Defaults keys for removed providers
        let suffixes = ["baseURL", "model", "systemPrompt", "apiKey"]
        for id in removedIDs {
            for suffix in suffixes {
                UserDefaults.standard.removeObject(forKey: "provider_\(id)_\(suffix)")
            }
        }
    }

    // MARK: - Shortcuts

    func performSmartTranslation() {
        let previousTask = smartTranslationTask
        previousTask?.cancel()

        let taskID = UUID()
        smartTranslationTaskID = taskID
        smartTranslationTask = Task { @MainActor [weak self] in
            // ClipboardGrabber restores the pasteboard during cancellation cleanup, so the next
            // invocation must not capture its snapshot until that cleanup has fully completed.
            if let previousTask {
                await previousTask.value
            }

            guard let self else { return }
            defer {
                if self.smartTranslationTaskID == taskID {
                    self.smartTranslationTask = nil
                    self.smartTranslationTaskID = nil
                }
            }

            guard !Task.isCancelled else { return }
            let result = await self.coordinator.translateSmart()
            guard !Task.isCancelled else { return }
            switch result {
            case .selection, .clipboard:
                self.panelController.showAtCursor()
            case .manualInput:
                self.panelController.showAtScreenCenter()
            case .cancelled:
                break
            }
        }
    }

    func cancelSmartTranslation() {
        smartTranslationTask?.cancel()
    }

    /// Silent OCR: copy recognized text to the clipboard; confirm with a small toast.
    func performSilentOCR() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.cancelSmartTranslationAndWait()
            guard !Task.isCancelled else { return }
            switch await self.coordinator.ocrToClipboard() {
            case .copied:
                self.copyToastController.show(message: String(localized: "Copied"))
            case let .failed(message):
                self.copyToastController.show(message: message, isError: true)
            case .cancelled:
                break
            }
        }
    }

    @discardableResult
    func cancelSmartTranslationAndWait() async -> Bool {
        await SmartTranslationTaskCleanup.cancelAndWait(smartTranslationTask)
    }

    private func setupShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .smartTranslation) { [weak self] in
            self?.performSmartTranslation()
        }

        KeyboardShortcuts.onKeyUp(for: .translateSelection) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.cancelSmartTranslationAndWait()
                let outcome = await self.coordinator.translateSelection()
                if outcome.shouldPresent {
                    self.panelController.showAtCursor()
                }
            }
        }

        KeyboardShortcuts.onKeyUp(for: .ocrScreenshot) { [weak self] in
            guard let self else { return }
            self.cancelSmartTranslation()
            Task { @MainActor in
                let outcome = await self.coordinator.ocrAndTranslate()
                if outcome.shouldPresent {
                    self.panelController.showAtCursor()
                }
            }
        }

        KeyboardShortcuts.onKeyUp(for: .silentOCR) { [weak self] in
            self?.performSilentOCR()
        }

        KeyboardShortcuts.onKeyUp(for: .inputTranslation) { [weak self] in
            guard let self else { return }
            self.cancelSmartTranslation()
            Task { @MainActor in
                self.coordinator.prepareInputMode()
                self.panelController.showAtScreenCenter()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .clipboardTranslation) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.cancelSmartTranslationAndWait()
                await self.coordinator.translateClipboard()
                self.panelController.showAtCursor()
            }
        }
    }

    // MARK: - Selection Monitor

    private func setupSelectionMonitor() {
        selectionMonitor.shouldSkipClipboardAccess = { [weak self] in
            self?.smartTranslationTask != nil
        }

        selectionMonitor.onTextSelected = { [weak self] text, point in
            guard let self, !self.panelController.isVisible else { return }
            self.triggerIconController.show(text: text, near: point)
        }

        selectionMonitor.onMouseDown = { [weak self] _ in
            guard let self, self.triggerIconController.isVisible else { return }
            self.triggerIconController.dismissSilently()
        }

        triggerIconController.onTranslateRequested = { [weak self] text in
            guard let self else { return }
            Task { @MainActor in
                await self.cancelSmartTranslationAndWait()
                await self.coordinator.translateTriggeredSelection(text)
                if case .idle = self.coordinator.phase { return }
                self.panelController.showAtCursor()
            }
        }

        triggerIconController.onDismissed = { [weak self] in
            self?.selectionMonitor.suppressBriefly()
        }

        panelController.onDismiss = { [weak self] in
            self?.selectionMonitor.suppressBriefly()
            if self?.triggerIconController.isVisible == true {
                self?.triggerIconController.dismiss()
            }
        }

        selectionMonitor.start()
    }
}
