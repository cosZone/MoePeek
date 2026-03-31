import SwiftUI

@main
struct MoePeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu bar icon + dropdown
        MenuBarExtra("MoePeek", systemImage: "character.bubble") {
            MenuItemView(appDelegate: appDelegate)
        }
    }
}
