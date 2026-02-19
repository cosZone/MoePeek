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

    func applicationDidFinishLaunching(_: Notification) {
        // Migrate old settings to new namespaced keys (one-time)
        migrateDefaults()

        permissionManager = PermissionManager()
        coordinator = TranslationCoordinator(permissionManager: permissionManager, registry: registry)
        panelController = PopupPanelController(coordinator: coordinator)
        onboardingController = OnboardingWindowController(permissionManager: permissionManager)
        selectionMonitor = SelectionMonitor()
        triggerIconController = TriggerIconController()

        // Apply dock visibility — only switch to .regular when needed;
        // LSUIElement=YES already provides .accessory by default.
        if Defaults[.showInDock] {
            NSApp.setActivationPolicy(.regular)
        }

        setupShortcuts()
        setupSelectionMonitor()

        // Wire onComplete once so every path (first launch + menu bar re-open) behaves consistently.
        onboardingController.onComplete = { [weak self] in
            self?.openSettings()
        }

        // Show onboarding on first launch; skip if permissions already granted.
        if permissionManager.allPermissionsGranted {
            Defaults[.hasCompletedOnboarding] = true
            openSettings()
        } else if !Defaults[.hasCompletedOnboarding] {
            DispatchQueue.main.async {
                self.onboardingController.showWindow()
            }
        } else {
            openSettings()
        }
        if !permissionManager.allPermissionsGranted {
            permissionManager.startPolling()
        }
    }

    func openSettings() {
        // Workaround: SettingsLink is only available inside SwiftUI views.
        // showSettingsWindow: is a private AppKit selector; monitor compatibility on macOS upgrades.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                NSLog("[MoePeek] showSettingsWindow: selector failed — macOS version may have removed it")
            }
        }
    }

    // MARK: - Migration

    private func migrateDefaults() {
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

        // Migrate Keychain API key
        if let oldApiKey = KeychainHelper.load(key: "openai_api_key"), !oldApiKey.isEmpty {
            KeychainHelper.save(key: "provider.openai.apiKey", value: oldApiKey)
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
