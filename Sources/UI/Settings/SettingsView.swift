import Defaults
import SwiftUI

struct SettingsView: View {
    let registry: TranslationProviderRegistry
    let ttsRegistry: TTSProviderRegistry
    let ttsCoordinator: TTSCoordinator
    let updaterController: UpdaterController?

    @Default(.selectedSettingsTab) private var selectedTab

    private var tabHeight: CGFloat {
        switch selectedTab {
        case .general: return 680
        case .excludedApps: return 480
        case .services: return 580
        case .providerOrder: return 520
        case .audio: return 520
        case .about: return 420
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)

            ExcludedAppsSettingsView()
                .tabItem {
                    Label("Excluded Apps", systemImage: "xmark.app")
                }
                .tag(SettingsTab.excludedApps)

            ServiceSettingsView(registry: registry)
                .tabItem {
                    Label("Services", systemImage: "globe")
                }
                .tag(SettingsTab.services)

            ProviderOrderSettingsView(registry: registry)
                .tabItem {
                    Label("Order", systemImage: "list.number")
                }
                .tag(SettingsTab.providerOrder)

            TTSSettingsView(registry: ttsRegistry, translationRegistry: registry, coordinator: ttsCoordinator)
                .tabItem {
                    Label("Audio", systemImage: "speaker.wave.2")
                }
                .tag(SettingsTab.audio)

            AboutSettingsView(updaterController: updaterController)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 720, idealWidth: 720, minHeight: tabHeight, idealHeight: tabHeight)
        .onDisappear {
            // Restore .accessory policy when the Settings window closes,
            // reversing the temporary .regular switch from the popup gear button.
            // Idempotent: no-op when policy is already .accessory or user has showInDock enabled.
            if !Defaults[.showInDock] {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
