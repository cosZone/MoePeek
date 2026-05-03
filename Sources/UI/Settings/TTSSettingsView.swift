import Defaults
import SwiftUI

/// Settings view for TTS configuration: service selection, preferences, and testing.
struct TTSSettingsView: View {
    let registry: TTSProviderRegistry
    let translationRegistry: TranslationProviderRegistry
    let coordinator: TTSCoordinator

    @Default(.ttsProvider) private var selectedProviderID
    @Default(.ttsAccent) private var accent
    @Default(.ttsSpeechRate) private var speechRate
    @Default(.ttsAutoPlaySource) private var autoPlaySource
    @Default(.ttsAutoPlayTarget) private var autoPlayTarget
    @Default(.ttsAutoPlayTargetProvider) private var autoPlayTargetProvider
    @Default(.ttsLanguageRates) private var languageRates

    @State private var isLanguageRatesExpanded = false
    @State private var testText = "Hello, 你好世界"
    @State private var testLanguage = "en"

    var body: some View {
        Form {
            // MARK: - Service Selection

            Section {
                Picker("TTS Service", selection: $selectedProviderID) {
                    ForEach(registry.providers, id: \.id) { provider in
                        HStack(spacing: 6) {
                            Image(systemName: provider.iconSystemName)
                                .frame(width: 16)
                            Text(provider.displayName)
                        }
                        .tag(provider.id)
                    }
                }

                registry.activeProvider.makeSettingsView()
            } header: {
                Text("Service")
            }

            // MARK: - Preferences

            Section {
                Picker("English Accent", selection: $accent) {
                    ForEach(TTSAccent.allCases, id: \.self) { accent in
                        Text(accent.displayName).tag(accent)
                    }
                }

                HStack {
                    Text("Default Speech Rate")
                    Slider(value: $speechRate, in: 0.1 ... 2.0, step: 0.05) {
                        Text("Default Speech Rate")
                    }
                    .labelsHidden()
                    HStack(spacing: 1) {
                        TextField("", value: $speechRate, format: .number.precision(.fractionLength(0...2)))
                            .monospacedDigit()
                            .frame(width: 48)
                            .multilineTextAlignment(.trailing)
                        Text("x")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Auto-play source text", isOn: $autoPlaySource)
                    .onChange(of: autoPlaySource) { _, on in
                        if on { autoPlayTarget = false }
                    }
                Toggle("Auto-play translation result", isOn: $autoPlayTarget)
                    .onChange(of: autoPlayTarget) { _, on in
                        if on { autoPlaySource = false }
                    }
                if autoPlayTarget {
                    Picker("Auto-play provider", selection: $autoPlayTargetProvider) {
                        Text("First completed").tag("first")
                        ForEach(translationRegistry.providers, id: \.id) { provider in
                            Text(provider.displayName).tag(provider.id)
                        }
                    }
                }

                DisclosureGroup(isExpanded: $isLanguageRatesExpanded) {
                    ForEach(SupportedLanguages.all, id: \.code) { lang in
                        let hasOverride = languageRates[lang.code] != nil
                        HStack {
                            Text(lang.name)
                                .frame(width: 80, alignment: .leading)
                            Slider(
                                value: languageRateBinding(for: lang.code),
                                in: 0.1 ... 2.0,
                                step: 0.05
                            )
                            HStack(spacing: 1) {
                                TextField("", value: languageRateBinding(for: lang.code), format: .number.precision(.fractionLength(0...2)))
                                    .monospacedDigit()
                                    .frame(width: 48)
                                    .multilineTextAlignment(.trailing)
                                Text("x")
                                    .foregroundStyle(.secondary)
                            }
                            if hasOverride {
                                Button {
                                    languageRates.removeValue(forKey: lang.code)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Reset to default rate")
                            }
                        }
                    }
                } label: {
                    Text("Per-Language Rate")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { isLanguageRatesExpanded.toggle() }
                }
            } header: {
                Text("Preferences")
            }

            // MARK: - Test

            Section {
                TextField("Test text", text: $testText, axis: .vertical)
                    .lineLimit(1 ... 3)

                Picker("Language", selection: $testLanguage) {
                    ForEach(SupportedLanguages.all, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }

                HStack(spacing: 12) {
                    if coordinator.isPlaying {
                        Button {
                            coordinator.stop()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .controlSize(.regular)

                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            coordinator.speak(testText, language: testLanguage)
                        } label: {
                            Label("Play Test", systemImage: "play.fill")
                        }
                        .controlSize(.regular)
                        .disabled(testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if case let .error(message) = coordinator.playbackState {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            } header: {
                Text("Test")
            }
        }
        .formStyle(.grouped)
    }

    private func languageRateBinding(for code: String) -> Binding<Double> {
        Binding(
            get: { languageRates[code] ?? speechRate },
            set: { languageRates[code] = $0 }
        )
    }
}
