import AppKit
import Defaults
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @Default(.targetLanguage) private var targetLanguage
    @Default(.isAutoDetectEnabled) private var isAutoDetectEnabled
    @Default(.textDetectionMode) private var textDetectionMode
    @Default(.triggerActivationMode) private var triggerActivationMode
    @Default(.showInDock) private var showInDock
    @Default(.popupDefaultWidth) private var popupDefaultWidth
    @Default(.popupDefaultHeight) private var popupDefaultHeight
    @Default(.popupFontSize) private var popupFontSize
    @Default(.popupFontName) private var popupFontName
    @Default(.popupRememberPosition) private var popupRememberPosition
    @Default(.sourceLanguage) private var sourceLanguage
    @Default(.detectionConfidenceThreshold) private var confidenceThreshold
    @Default(.appLanguage) private var appLanguage
    @Default(.menuBarIconStyle) private var menuBarIconStyle
    @Default(.menuBarCustomIconSource) private var menuBarCustomIconSource
    @Default(.menuBarCustomSymbolName) private var menuBarCustomSymbolName
    @Default(.menuBarCustomIconIsTemplate) private var menuBarCustomIconIsTemplate
    @Default(.menuBarCustomIconRevision) private var menuBarCustomIconRevision

    @State private var iconImportError: String?
    @State private var showingIconResetConfirm = false

    private var textDetectionModeDescription: String {
        switch textDetectionMode {
        case .conservative:
            String(localized: "Uses Accessibility API only. Most compatible with remote desktops and virtual machines, but may not detect text in some apps.")
        case .standard:
            String(localized: "Uses Accessibility API + AppleScript (Safari). Covers most apps without simulating keystrokes.")
        case .full:
            String(localized: "Uses all detection methods including ⌘C simulation. Best coverage, but may interfere with remote desktop apps and keyboard shortcut recording.")
        }
    }

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showRestartAlert = false
    @State private var availableFonts = NSFontManager.shared.availableFontFamilies

    var body: some View {
        Form {
            Section("Keyboard Shortcuts") {
                GlobalShortcutRecorder("Selection Translation:", name: .translateSelection)
                GlobalShortcutRecorder("Screenshot OCR:", name: .ocrScreenshot)
                GlobalShortcutRecorder("Manual Translation:", name: .inputTranslation)
                GlobalShortcutRecorder("Clipboard Translation:", name: .clipboardTranslation)

                LocalShortcutRecorder()
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
                            NSApp.activate()
                        }
                    }
            }

            Section("Menu Bar Icon") {
                Picker("Style:", selection: $menuBarIconStyle) {
                    Text("Filled").tag(MenuBarIconStyle.filled)
                    Text("Custom").tag(MenuBarIconStyle.custom)
                }
                .pickerStyle(.segmented)

                if menuBarIconStyle == .custom {
                    Picker("Source:", selection: $menuBarCustomIconSource) {
                        Text("SF Symbol").tag(MenuBarCustomIconSource.symbol)
                        Text("Upload").tag(MenuBarCustomIconSource.image)
                    }
                    .pickerStyle(.segmented)

                    switch menuBarCustomIconSource {
                    case .symbol:
                        menuBarSymbolControls
                    case .image:
                        menuBarCustomIconControls
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

                if isAutoDetectEnabled {
                    Picker("Floating Icon Activation:", selection: $triggerActivationMode) {
                        Text("Hover").tag(TriggerActivationMode.hover)
                        Text("Click").tag(TriggerActivationMode.click)
                    }

                    Picker("Text Detection Mode:", selection: $textDetectionMode) {
                        Text("Conservative").tag(TextDetectionMode.conservative)
                        Text("Standard").tag(TextDetectionMode.standard)
                        Text("Full").tag(TextDetectionMode.full)
                    }

                    Text(textDetectionModeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                Toggle("Remember Last Popup Position", isOn: $popupRememberPosition)

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

                LabeledContent("Font Size: \(popupFontSize)") {
                    Slider(
                        value: Binding(
                            get: { Double(popupFontSize) },
                            set: { popupFontSize = Int($0) }
                        ),
                        in: 12...24,
                        step: 1
                    )
                }

                Picker("Font:", selection: $popupFontName) {
                    Text("System Default")
                        .tag("")
                    Divider()
                    ForEach(availableFonts, id: \.self) { family in
                        Text(family)
                            .font(.custom(family, size: 13))
                            .tag(family)
                    }
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
        .alert(
            "Could not load icon",
            isPresented: Binding(
                get: { iconImportError != nil },
                set: { if !$0 { iconImportError = nil } }
            ),
            actions: { Button("OK", role: .cancel) { iconImportError = nil } },
            message: { Text(iconImportError ?? "") }
        )
        .confirmationDialog(
            "Remove custom menu bar icon?",
            isPresented: $showingIconResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                MenuBarIconStore.removeCustomIcon()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The uploaded image will be deleted. You can choose another image any time.")
        }
    }

    @ViewBuilder
    private var menuBarSymbolControls: some View {
        let isValid = isValidSymbol(menuBarCustomSymbolName)
        let previewName = isValid ? menuBarCustomSymbolName : MenuBarIconCatalog.defaultSymbol

        // Preview + free-form name input in a single row so the user sees them together.
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
                Image(systemName: previewName)
                    .font(.system(size: 16))
            }
            .frame(width: 32, height: 32)

            TextField(
                text: $menuBarCustomSymbolName,
                prompt: Text(verbatim: MenuBarIconCatalog.defaultSymbol)
            ) {
                EmptyView()
            }
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .frame(maxWidth: .infinity)

            Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isValid ? .green : .orange)
                .help(isValid
                    ? String(localized: "Symbol exists on this system.")
                    : String(localized: "Symbol not found. Falling back to default."))
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Presets")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                spacing: 8
            ) {
                ForEach(MenuBarIconCatalog.presets, id: \.self) { name in
                    Button {
                        menuBarCustomSymbolName = name
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(menuBarCustomSymbolName == name
                                        ? Color.accentColor.opacity(0.25)
                                        : Color.secondary.opacity(0.10))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        menuBarCustomSymbolName == name
                                            ? Color.accentColor
                                            : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(name)
                    .accessibilityLabel(Text(verbatim: name))
                }
            }
        }

        Text("Tip: open the SF Symbols app from Apple to browse all available names, then paste one above. Names are case-sensitive.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func isValidSymbol(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    @ViewBuilder
    private var menuBarCustomIconControls: some View {
        let customIcon = MenuBarIconStore.loadCustomIcon(isTemplate: menuBarCustomIconIsTemplate)
        let hasCustomIcon = customIcon != nil

        LabeledContent("Image:") {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                    if let customIcon {
                        Image(nsImage: customIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 36, height: 36)

                Button("Choose Image…") { chooseCustomIcon() }
                if hasCustomIcon {
                    Button("Reset", role: .destructive) {
                        showingIconResetConfirm = true
                    }
                }
                Spacer(minLength: 0)
            }
        }

        Toggle("Render as template (monochrome)", isOn: $menuBarCustomIconIsTemplate)

        Text("Template mode masks the image to the menu bar tint — recommended for monochrome icons so they adapt to light and dark menu bars. Turn it off only for full-color logos.")
            .font(.caption)
            .foregroundStyle(.secondary)

        Text("Requirements: PNG, JPG, SVG, PDF, TIFF, or ICNS, up to 2 MB. Recommended 36×36 px (18 pt @2x) with transparent background. For template mode, ship a monochrome image — black on transparent, alpha controls visibility.")
            .font(.caption)
            .foregroundStyle(.secondary)

        Text("Need inspiration? Browse free icons on [Iconify](https://icon-sets.iconify.design/?query=translate) — download an SVG or PNG and upload it here.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .tint(.accentColor)
    }

    private func chooseCustomIcon() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .png, .jpeg, .svg, .pdf, .tiff, .icns, UTType.image,
        ]
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MenuBarIconStore.importIcon(from: url)
        } catch {
            iconImportError = error.localizedDescription
        }
    }
}
