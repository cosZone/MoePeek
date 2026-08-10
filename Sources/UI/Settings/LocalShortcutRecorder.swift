import AppKit
import KeyboardShortcuts
import SwiftUI

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
