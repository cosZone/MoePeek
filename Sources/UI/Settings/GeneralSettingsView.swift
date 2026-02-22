import Defaults
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Default(.targetLanguage) private var targetLanguage
    @Default(.isAutoDetectEnabled) private var isAutoDetectEnabled
    @Default(.showInDock) private var showInDock
    @Default(.popupDefaultWidth) private var popupDefaultWidth
    @Default(.popupDefaultHeight) private var popupDefaultHeight
    @Default(.sourceLanguage) private var sourceLanguage
    @Default(.detectionConfidenceThreshold) private var confidenceThreshold
    @Default(.appLanguage) private var appLanguage

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showRestartAlert = false

    var body: some View {
        Form {
            Section("Keyboard Shortcuts") {
                KeyboardShortcuts.Recorder("Selection Translation:", name: .translateSelection)
                KeyboardShortcuts.Recorder("Screenshot OCR:", name: .ocrScreenshot)
                KeyboardShortcuts.Recorder("Manual Translation:", name: .inputTranslation)
                KeyboardShortcuts.Recorder("Clipboard Translation:", name: .clipboardTranslation)
            }

            Section("General") {
                Picker("App Language:", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .onChange(of: appLanguage) { _, newValue in
                    if newValue == .system {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
                    }
                    UserDefaults.standard.synchronize()
                    showRestartAlert = true
                }

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue // Revert on failure
                        }
                    }

                Toggle("Show Dock icon", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                        if !newValue {
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
            }

            Section("Translation") {
                Picker("Translate to:", selection: $targetLanguage) {
                    ForEach(SupportedLanguages.all, id: \.code) { code, name in
                        Text(name).tag(code)
                    }
                }

                Toggle("Show floating icon on text selection", isOn: $isAutoDetectEnabled)
            }

            Section("Language Detection") {
                Picker("Source Language:", selection: $sourceLanguage) {
                    Text("Auto Detect").tag("auto")
                    ForEach(SupportedLanguages.all, id: \.code) { code, name in
                        Text(name).tag(code)
                    }
                }

                if sourceLanguage == "auto" {
                    LabeledContent("Detection Sensitivity: \(confidenceThreshold, specifier: "%.1f")") {
                        Slider(value: $confidenceThreshold, in: 0.1...0.8, step: 0.1)
                    }
                    Text("Lower = more aggressive detection (may be inaccurate); Higher = more conservative (may return unknown)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Popup Panel") {
                LabeledContent("Default Width: \(popupDefaultWidth)") {
                    Slider(
                        value: Binding(
                            get: { Double(popupDefaultWidth) },
                            set: { popupDefaultWidth = Int($0) }
                        ),
                        in: 280...800,
                        step: 10
                    )
                }

                LabeledContent("Default Height: \(popupDefaultHeight)") {
                    Slider(
                        value: Binding(
                            get: { Double(popupDefaultHeight) },
                            set: { popupDefaultHeight = Int($0) }
                        ),
                        in: 200...800,
                        step: 10
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("App Language", isPresented: $showRestartAlert) {
            Button("Restart Now") { AppRelaunch.relaunch() }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Changing language requires restarting the app.")
        }
    }
}
