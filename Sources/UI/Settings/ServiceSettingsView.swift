import Defaults
import SwiftUI

/// Settings view for translation providers — left-right split layout.
struct ServiceSettingsView: View {
    let registry: TranslationProviderRegistry

    @Default(.enabledProviders) private var enabledProviders
    @State private var selectedProviderID: String?
    @State private var showingAddSheet = false
    @State private var providerToDelete: (any TranslationProvider)?

    var body: some View {
        HSplitView {
            // Left: Provider list
            providerList
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)

            // Right: Selected provider settings
            providerDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selectedProviderID == nil {
                selectedProviderID = registry.providers.first?.id
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddCustomProviderSheet(registry: registry, selectedProviderID: $selectedProviderID)
        }
        .alert(
            "Delete Provider",
            isPresented: Binding(
                get: { providerToDelete != nil },
                set: { if !$0 { providerToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { providerToDelete = nil }
            Button("Delete", role: .destructive) { deleteProvider() }
        } message: {
            if let provider = providerToDelete {
                Text("Are you sure you want to delete \"\(provider.displayName)\"? This will remove all its settings.")
            }
        }
    }

    // MARK: - Provider List

    @ViewBuilder
    private var providerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Providers")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            List(selection: $selectedProviderID) {
                ForEach(registry.groupedProviders, id: \.category) { group in
                    Section(group.category.displayName) {
                        ForEach(group.providers, id: \.id) { provider in
                            providerRow(provider)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Add Custom Provider"))

                Button {
                    if let id = selectedProviderID,
                       let provider = registry.provider(withID: id),
                       provider.isDeletable
                    {
                        providerToDelete = provider
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(!isSelectedProviderDeletable)
                .help(String(localized: "Delete Provider"))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: any TranslationProvider) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: providerEnabledBinding(for: provider.id))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

            Image(systemName: provider.iconSystemName)
                .font(.callout)
                .frame(width: 16)

            Text(provider.displayName)
                .font(.callout)

            Spacer()
        }
        .tag(provider.id)
        .contentShape(Rectangle())
        .contextMenu {
            if provider.isDeletable {
                Button("Delete", role: .destructive) {
                    providerToDelete = provider
                }
            }
        }
    }

    // MARK: - Provider Detail

    @ViewBuilder
    private var providerDetail: some View {
        if let id = selectedProviderID,
           let provider = registry.provider(withID: id)
        {
            ScrollView {
                provider.makeSettingsView()
                    .id(id)
            }
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView(
                "Select a provider",
                systemImage: "globe",
                description: Text("Choose a provider from the list to configure it.")
            )
        }
    }

    // MARK: - Helpers

    private var isSelectedProviderDeletable: Bool {
        guard let id = selectedProviderID,
              let provider = registry.provider(withID: id)
        else { return false }
        return provider.isDeletable
    }

    private func providerEnabledBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { enabledProviders.contains(id) },
            set: { isEnabled in
                if isEnabled {
                    enabledProviders.insert(id)
                } else {
                    enabledProviders.remove(id)
                }
            }
        )
    }

    private func deleteProvider() {
        guard let provider = providerToDelete else { return }
        let deletedID = provider.id
        providerToDelete = nil
        if selectedProviderID == deletedID {
            selectedProviderID = registry.providers.first { $0.id != deletedID }?.id
        }
        registry.removeCustomProvider(id: deletedID)
    }
}
