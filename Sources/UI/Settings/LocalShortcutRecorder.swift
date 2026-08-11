import AppKit
import KeyboardShortcuts
import SwiftUI

/// Prevents app-wide shortcuts from taking over the popup-local swap binding.
struct GlobalShortcutRecorder: View {
    private let title: LocalizedStringKey
    private let name: KeyboardShortcuts.Name
    @State private var lastAcceptedShortcut: KeyboardShortcuts.Shortcut?

    init(_ title: LocalizedStringKey, name: KeyboardShortcuts.Name) {
        self.title = title
        self.name = name
        _lastAcceptedShortcut = State(initialValue: KeyboardShortcuts.getShortcut(for: name))
    }

    var body: some View {
        KeyboardShortcuts.Recorder(title, name: name) { shortcut in
            if let shortcut, shortcut == SwapLanguagesShortcut.current {
                NSSound.beep()
                KeyboardShortcuts.setShortcut(lastAcceptedShortcut, for: name)
            } else {
                lastAcceptedShortcut = shortcut
            }

            SwapLanguagesShortcut.reconcileRegistrations()
        }
    }
}

/// Reuses the package recorder while keeping this shortcut local to the popup.
struct LocalShortcutRecorder: View {
    @State private var lastAcceptedShortcut = SwapLanguagesShortcut.current

    var body: some View {
        KeyboardShortcuts.Recorder("Swap Languages:", name: .swapLanguages) { shortcut in
            if let shortcut, SwapLanguagesShortcut.isReserved(shortcut) {
                NSSound.beep()
                KeyboardShortcuts.setShortcut(lastAcceptedShortcut, for: .swapLanguages)
            } else {
                lastAcceptedShortcut = shortcut
            }

            SwapLanguagesShortcut.recorderDidChange()
        }
    }
}
