import AppKit
import Defaults
import KeyboardShortcuts

/// Handles app lifecycle, permission checks, and global shortcut registration.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // registry must be available before applicationDidFinishLaunching because
    // SwiftUI evaluates MoePeekApp.body (which reads registry) during app init.
    lazy var registry = TranslationProviderRegistry.builtIn()
    var coordinator: TranslationCoordinator!
    var panelController: PopupPanelController!
    var permissionManager: PermissionManager!
    var onboardingController: OnboardingWindowController!
    var selectionMonitor: SelectionMonitor!
    var triggerIconController: TriggerIconController!
    lazy var updaterController = UpdaterController()

    func applicationDidFinishLaunching(_: Notification) {
        applyLanguageOverride()

        // Migrate old settings to new namespaced keys (one-time)
        migrateDefaults()

        permissionManager = PermissionManager()
        coordinator = TranslationCoordinator(permissionManager: permissionManager, registry: registry)
        panelController = PopupPanelController(coordinator: coordinator)
        onboardingController = OnboardingWindowController(permissionManager: permissionManager, registry: registry)
        selectionMonitor = SelectionMonitor()
        triggerIconController = TriggerIconController()
        // Apply dock visibility — only switch to .regular when needed;
        // LSUIElement=YES already provides .accessory by default.
        if Defaults[.showInDock] {
            NSApp.setActivationPolicy(.regular)
        }

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
        guard !enabled.isDisjoint(with: removedIDs) else { return }
        enabled.subtract(removedIDs)
        if enabled.isEmpty {
            enabled = ["google"]
        }
        Defaults[.enabledProviders] = enabled
    }

    // MARK: - Shortcuts

    private func setupShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .translateSelection) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.coordinator.translateSelection()
                if case .idle = self.coordinator.phase { return }
                self.panelController.showAtCursor()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .ocrScreenshot) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.coordinator.ocrAndTranslate()
                if case .idle = self.coordinator.phase { return }
                self.panelController.showAtCursor()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .inputTranslation) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.coordinator.prepareInputMode()
                self.panelController.showAtScreenCenter()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .clipboardTranslation) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.coordinator.translateClipboard()
                self.panelController.showAtCursor()
            }
        }
    }

    // MARK: - Selection Monitor

    private func setupSelectionMonitor() {
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
                self.coordinator.translate(text)
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
