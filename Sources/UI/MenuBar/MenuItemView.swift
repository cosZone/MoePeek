import Defaults
import KeyboardShortcuts
import SwiftUI

/// Content for the menu bar dropdown.
struct MenuItemView: View {
    let appDelegate: AppDelegate
    @Environment(\.openSettings) private var openSettings

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        Text("MoePeek \(appVersion)")
            .font(.headline)

        Divider()

        Button {
            guard let coordinator = appDelegate.coordinator,
                  let panelController = appDelegate.panelController else { return }
            coordinator.prepareInputMode()
            panelController.showAtScreenCenter()
        } label: {
            Label("Manual Translation", systemImage: "keyboard")
        }
        .keyboardShortcut("a", modifiers: .option)

        Button {
            guard let coordinator = appDelegate.coordinator,
                  let panelController = appDelegate.panelController else { return }
            Task {
                await coordinator.ocrAndTranslate()
                if case .idle = coordinator.phase { return }
                panelController.showAtCursor()
            }
        } label: {
            Label("Screenshot OCR", systemImage: "text.viewfinder")
        }
        .keyboardShortcut("s", modifiers: .option)

        Button {
            guard let coordinator = appDelegate.coordinator,
                  let panelController = appDelegate.panelController else { return }
            Task {
                await coordinator.translateSelection()
                panelController.showAtCursor()
            }
        } label: {
            Label("Selection Translation", systemImage: "text.cursor")
        }
        .keyboardShortcut("d", modifiers: .option)

        Button {
            guard let coordinator = appDelegate.coordinator,
                  let panelController = appDelegate.panelController else { return }
            coordinator.translateClipboard()
            panelController.showAtCursor()
        } label: {
            Label("Clipboard Translation", systemImage: "doc.on.clipboard")
        }
        .keyboardShortcut("v", modifiers: .option)

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
            SettingsWindowActivation.openOrBringToFront {
                openSettings()
            }
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
