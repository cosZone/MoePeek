import AppKit

enum SettingsWindowActivation {
    @MainActor
    /// Bring Settings to front if it already exists; otherwise open it via fallback.
    ///
    /// We prefer `showPreferencesWindow:` because it reliably focuses an existing
    /// Settings window. Some contexts may not route that action, so we keep
    /// `openSettings()` as a fallback for creating/presenting the Settings scene.
    static func openOrBringToFront(fallbackOpenSettings: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let handled = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        if !handled {
            fallbackOpenSettings()
        }
    }
}
