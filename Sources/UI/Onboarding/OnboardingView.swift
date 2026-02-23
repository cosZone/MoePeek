import Defaults
import SwiftUI

#if canImport(Translation)
@preconcurrency import Translation
#endif

/// Step-by-step onboarding view guiding users through required permissions and translation service setup.
struct OnboardingView: View {
    let permissionManager: PermissionManager
    let registry: TranslationProviderRegistry
    var onComplete: () -> Void

    @Default(.enabledProviders) private var enabledProviders
    @State private var currentPageIndex = 0
    @State private var hasRequestedScreenRecording = false

    private var openaiProvider: OpenAICompatibleProvider? {
        registry.providers.first { $0.id == "openai" } as? OpenAICompatibleProvider
    }

    private enum Page: Equatable {
        case welcome, accessibility, screenRecording
        case providerSelection, openaiSetup, appleTranslation
    }

    private var pages: [Page] {
        var result: [Page] = [.welcome, .accessibility, .screenRecording, .providerSelection]
        if enabledProviders.contains("openai"), openaiProvider != nil {
            result.append(.openaiSetup)
        }
        #if canImport(Translation)
        if #available(macOS 15.0, *),
           registry.providers.contains(where: { $0.id == "apple" }),
           enabledProviders.contains("apple") {
            result.append(.appleTranslation)
        }
        #endif
        return result
    }

    private var currentPage: Page {
        guard currentPageIndex < pages.count else { return pages.last ?? .welcome }
        return pages[currentPageIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            Group {
                switch currentPage {
                case .welcome:
                    welcomeStep
                case .accessibility:
                    accessibilityStep
                case .screenRecording:
                    screenRecordingStep
                case .providerSelection:
                    providerSelectionStep
                case .openaiSetup:
                    openaiSetupStep
                case .appleTranslation:
                    appleTranslationStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.push(from: currentPageIndex > 0 ? .trailing : .leading))

            Divider()

            // Navigation buttons
            HStack {
                if currentPageIndex > 0 {
                    Button("Previous") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPageIndex -= 1
                        }
                    }
                }

                Spacer()

                navigationButtons
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 380, height: 480)
    }

    // MARK: - Navigation Buttons

    @ViewBuilder
    private var navigationButtons: some View {
        let isLast = currentPageIndex >= pages.count - 1

        switch currentPage {
        case .welcome:
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPageIndex = 1
                }
            } label: {
                Text("Begin Setup")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .accessibility:
            nextStepButton(
                title: "Next",
                isHighlighted: permissionManager.isAccessibilityGranted,
                action: goNext
            )

        case .screenRecording:
            nextStepButton(
                title: "Next",
                isHighlighted: permissionManager.isScreenRecordingGranted,
                action: goNext
            )

        case .providerSelection:
            nextStepButton(
                title: "Next",
                isHighlighted: !enabledProviders.isEmpty,
                action: goNext
            )

        case .openaiSetup:
            HStack(spacing: 12) {
                Button("Skip") { goNext() }
                    .controlSize(.large)
                nextStepButton(
                    title: isLast ? "Get Started" : "Next",
                    isHighlighted: openaiProvider.map { !Defaults[$0.apiKeyKey].isEmpty } ?? false,
                    action: goNext
                )
            }

        case .appleTranslation:
            HStack(spacing: 12) {
                Button("Skip") { goNext() }
                    .controlSize(.large)
                nextStepButton(
                    title: "Get Started",
                    isHighlighted: true,
                    action: goNext
                )
            }
        }
    }

    private func goNext() {
        let nextIndex = currentPageIndex + 1
        if nextIndex < pages.count {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPageIndex = nextIndex
            }
        } else {
            Defaults[.hasCompletedOnboarding] = true
            onComplete()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("MoePeek")
                .font(.title.bold())

            Text("Menu Bar Translation Tool")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("The following permissions are required.\nWe'll guide you through the setup.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var accessibilityStep: some View {
        permissionStep(
            icon: "hand.raised",
            title: "Accessibility Permission",
            description: "MoePeek needs accessibility permission to read your selected text. This is essential for text selection translation.",
            isGranted: permissionManager.isAccessibilityGranted,
            onOpenSettings: { permissionManager.openAccessibilitySettings() }
        )
    }

    private var screenRecordingStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 40))
                .foregroundStyle(permissionManager.isScreenRecordingGranted ? .green : .secondary)

            Text("Screen Recording Permission")
                .font(.title2.bold())

            Text("MoePeek needs screen recording permission for OCR screenshot translation to recognize text on screen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if permissionManager.isScreenRecordingGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if !hasRequestedScreenRecording {
                Button("Request Permission") {
                    hasRequestedScreenRecording = true
                    permissionManager.requestScreenRecording()
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            } else {
                VStack(spacing: 8) {
                    Button("Open System Settings") {
                        permissionManager.openScreenRecordingSettings()
                    }
                    .controlSize(.large)

                    Text("MoePeek is now listed in Screen Recording settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Status updates automatically after granting")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: permissionManager.isScreenRecordingGranted)
        .animation(.easeInOut(duration: 0.3), value: hasRequestedScreenRecording)
    }

    // MARK: - Provider Selection Step

    /// Core providers shown during onboarding (subset of all available providers).
    private static let onboardingProviderIDs = ["openai", "google", "apple"]

    private var onboardingProviders: [any TranslationProvider] {
        Self.onboardingProviderIDs.compactMap { id in
            registry.providers.first { $0.id == id }
        }
    }

    private var providerSelectionStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "globe")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Select Translation Service")
                .font(.title2.bold())

            Text("Enable at least one translation service.\nYou can enable multiple services for comparison.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                ForEach(onboardingProviders, id: \.id) { provider in
                    providerToggleRow(provider)
                }
            }
            .padding(.horizontal, 24)

            if enabledProviders.isEmpty {
                Text("Please select at least one translation service")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("More translation services available in Settings")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }

    private func providerToggleRow(_ provider: any TranslationProvider) -> some View {
        let isEnabled = enabledProviders.contains(provider.id)
        return Button {
            var current = enabledProviders
            if current.contains(provider.id) {
                current.remove(provider.id)
            } else {
                current.insert(provider.id)
            }
            enabledProviders = current
        } label: {
            HStack(spacing: 12) {
                Image(systemName: provider.iconSystemName)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(isEnabled ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.headline)
                    Text(providerDescription(for: provider.id))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isEnabled ? .blue : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEnabled ? Color.blue.opacity(0.08) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isEnabled ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func providerDescription(for id: String) -> String {
        switch id {
        case "openai": String(localized: "OpenAI-compatible API, requires API Key")
        case "google": String(localized: "Free, no API key needed.")
        case "apple": String(localized: "Built-in system translation, no API Key needed (macOS 15+)")
        default: ""
        }
    }

    // MARK: - OpenAI Setup Step

    private var openaiSetupStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "key")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Configure OpenAI API")
                .font(.title2.bold())

            Text("Enter your API configuration to use the OpenAI translation service.\nYou can also configure this later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let provider = openaiProvider {
                OpenAIConfigFields(provider: provider, compact: true)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    // MARK: - Apple Translation Step

    @ViewBuilder
    private var appleTranslationStep: some View {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            appleTranslationContent
        } else {
            EmptyView()
        }
        #else
        EmptyView()
        #endif
    }

    #if canImport(Translation)
    @available(macOS 15.0, *)
    private var appleTranslationContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "apple.logo")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Apple Translation Language Packs")
                .font(.title2.bold())

            Text("Apple Translation requires language packs for offline translation.\nSelect a language pair and download, or do it later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            OnboardingLanguageDownloadView()
                .padding(.horizontal, 24)

            Spacer()
        }
    }
    #endif

    // MARK: - Helpers

    @ViewBuilder
    private func nextStepButton(
        title: LocalizedStringKey,
        isHighlighted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isHighlighted {
            Button(action: action) { Text(title) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else {
            Button(action: action) { Text(title) }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    // MARK: - Shared Permission Step Layout

    private func permissionStep(
        icon: String,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        isGranted: Bool,
        onOpenSettings: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(isGranted ? .green : .secondary)

            Text(title)
                .font(.title2.bold())

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("Open System Settings") {
                    onOpenSettings()
                }
                .controlSize(.large)
            }

            Text("Status updates automatically after granting")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: isGranted)
    }
}

// MARK: - Onboarding Language Download View

#if canImport(Translation)
@available(macOS 15.0, *)
private struct OnboardingLanguageDownloadView: View {
    private enum PairStatus {
        case checking, installed, needsDownload, unsupported, unknown

        var label: String {
            switch self {
            case .checking: String(localized: "Checking…")
            case .installed: String(localized: "Installed")
            case .needsDownload: String(localized: "Needs download")
            case .unsupported: String(localized: "Unsupported")
            case .unknown: String(localized: "Unknown")
            }
        }

        var color: Color {
            self == .installed ? .green : .secondary
        }
    }

    @State private var selectedSource = "en"
    @State private var selectedTarget = "zh-Hans"
    @State private var pairStatus: PairStatus?
    @State private var downloadConfiguration: TranslationSession.Configuration?

    private var selectionId: String { "\(selectedSource)-\(selectedTarget)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("Source Language", selection: $selectedSource) {
                    ForEach(SupportedLanguages.all, id: \.code) { code, name in
                        Text(name).tag(code)
                    }
                }
                .labelsHidden()

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                Picker("Target Language", selection: $selectedTarget) {
                    ForEach(SupportedLanguages.all, id: \.code) { code, name in
                        Text(name).tag(code)
                    }
                }
                .labelsHidden()
            }

            HStack(spacing: 8) {
                Button("Check & Download") {
                    downloadConfiguration = .init(
                        source: Locale.Language(identifier: selectedSource),
                        target: Locale.Language(identifier: selectedTarget)
                    )
                }
                .controlSize(.small)

                if let pairStatus {
                    Label(pairStatus.label, systemImage: pairStatus == .installed ? "checkmark.circle.fill" : "info.circle")
                        .font(.callout)
                        .foregroundStyle(pairStatus.color)
                }
            }
        }
        .task(id: selectionId) {
            pairStatus = .checking
            let availability = LanguageAvailability()
            let source = Locale.Language(identifier: selectedSource)
            let target = Locale.Language(identifier: selectedTarget)
            let status = await availability.status(from: source, to: target)
            pairStatus = switch status {
            case .installed: .installed
            case .supported: .needsDownload
            case .unsupported: .unsupported
            @unknown default: .unknown
            }
        }
        .translationTask(downloadConfiguration) { session in
            do {
                try await session.prepareTranslation()
                pairStatus = .installed
            } catch {
                let availability = LanguageAvailability()
                let source = Locale.Language(identifier: selectedSource)
                let target = Locale.Language(identifier: selectedTarget)
                let status = await availability.status(from: source, to: target)
                pairStatus = status == .installed ? .installed : .needsDownload
            }
        }
    }
}
#endif
