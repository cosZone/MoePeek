import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

/// Content for the menu bar dropdown.
struct MenuItemView: View {
    let appDelegate: AppDelegate

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        Text("MoePeek \(appVersion)")
            .font(.headline)

        Divider()

        Button {
            appDelegate.performSmartTranslation()
        } label: {
            Label("Smart Translation", systemImage: "wand.and.stars")
        }
        .globalKeyboardShortcut(.smartTranslation)

        Button {
            guard let coordinator = appDelegate.coordinator,
                  let panelController = appDelegate.panelController else { return }
            appDelegate.cancelSmartTranslation()
            coordinator.prepareInputMode()
            panelController.showAtScreenCenter()
        } label: {
            Label("Manual Translation", systemImage: "keyboard")
        }
        .globalKeyboardShortcut(.inputTranslation)

        Button {
            guard let coordinator = appDelegate.coordinator,
                  let panelController = appDelegate.panelController else { return }
            appDelegate.cancelSmartTranslation()
            Task {
                let outcome = await coordinator.ocrAndTranslate()
                if outcome.shouldPresent {
                    panelController.showAtCursor()
                }
            }
        } label: {
            Label("Screenshot OCR", systemImage: "text.viewfinder")
        }
        .globalKeyboardShortcut(.ocrScreenshot)

        Button {
            appDelegate.performSilentOCR()
        } label: {
            Label("Silent OCR", systemImage: "doc.text.viewfinder")
        }
        .globalKeyboardShortcut(.silentOCR)

        Button {
            guard let coordinator = appDelegate.coordinator,
                  let panelController = appDelegate.panelController else { return }
            Task { @MainActor in
                await appDelegate.cancelSmartTranslationAndWait()
                let outcome = await coordinator.translateSelection()
                if outcome.shouldPresent {
                    panelController.showAtCursor()
                }
            }
        } label: {
            Label("Selection Translation", systemImage: "text.cursor")
        }
        .globalKeyboardShortcut(.translateSelection)

        Button {
            guard let coordinator = appDelegate.coordinator,
                  let panelController = appDelegate.panelController else { return }
            Task { @MainActor in
                await appDelegate.cancelSmartTranslationAndWait()
                await coordinator.translateClipboard()
                panelController.showAtCursor()
            }
        } label: {
            Label("Clipboard Translation", systemImage: "doc.on.clipboard")
        }
        .globalKeyboardShortcut(.clipboardTranslation)

        Divider()

        Button {
            appDelegate.onboardingController.showWindow()
        } label: {
            Label("Onboarding Guide...", systemImage: "questionmark.circle")
        }

        Button {
            appDelegate.updaterController.checkForUpdates()
        } label: {
            Label("Check for Updates...", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!appDelegate.updaterController.canCheckForUpdates)

        Button {
            appDelegate.settingsController.showWindow()
        } label: {
            Label("Settings...", systemImage: "gearshape")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit MoePeek") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
