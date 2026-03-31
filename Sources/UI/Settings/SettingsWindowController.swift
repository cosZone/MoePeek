import AppKit
import Defaults
import SwiftUI

/// Manages the Settings window lifecycle using AppKit NSWindow + NSHostingView,
/// avoiding SwiftUI's Settings scene which resets activation policy to .regular
/// on launch and causes the dock icon to appear despite LSUIElement=YES.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let registry: TranslationProviderRegistry
    private let ttsRegistry: TTSProviderRegistry
    private let ttsCoordinator: TTSCoordinator
    private let updaterController: UpdaterController?

    init(
        registry: TranslationProviderRegistry,
        ttsRegistry: TTSProviderRegistry,
        ttsCoordinator: TTSCoordinator,
        updaterController: UpdaterController?
    ) {
        self.registry = registry
        self.ttsRegistry = ttsRegistry
        self.ttsCoordinator = ttsCoordinator
        self.updaterController = updaterController
    }

    func showWindow() {
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView(
            registry: registry,
            ttsRegistry: ttsRegistry,
            ttsCoordinator: ttsCoordinator,
            updaterController: updaterController
        )
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 720, height: 680)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "MoePeek Settings")
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: 720, height: 420)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_: Notification) {
        MainActor.assumeIsolated {
            self.window?.contentView = nil
            self.window = nil
            if !Defaults[.showInDock] {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
