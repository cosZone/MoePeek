import AppKit
import Defaults
import SwiftUI

@main
struct MoePeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Default(.menuBarIconStyle) private var menuBarIconStyle
    @Default(.menuBarCustomIconSource) private var customIconSource
    @Default(.menuBarCustomSymbolName) private var customSymbolName
    @Default(.menuBarCustomIconIsTemplate) private var customIconIsTemplate
    @Default(.menuBarCustomIconRevision) private var customIconRevision

    var body: some Scene {
        MenuBarExtra {
            MenuItemView(appDelegate: appDelegate)
        } label: {
            menuBarLabel
                // `.id` forces the label to rebuild when the user replaces the custom icon file.
                .id(customIconRevision)
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        switch menuBarIconStyle {
        case .filled:
            Image(systemName: MenuBarIconCatalog.defaultSymbol)
        case .custom:
            switch customIconSource {
            case .symbol:
                if NSImage(systemSymbolName: customSymbolName, accessibilityDescription: nil) != nil {
                    Image(systemName: customSymbolName)
                } else {
                    Image(systemName: MenuBarIconCatalog.defaultSymbol)
                }
            case .image:
                if let nsImage = MenuBarIconStore.loadCustomIcon(isTemplate: customIconIsTemplate) {
                    Image(nsImage: nsImage)
                } else {
                    Image(systemName: MenuBarIconCatalog.defaultSymbol)
                }
            }
        }
    }
}
