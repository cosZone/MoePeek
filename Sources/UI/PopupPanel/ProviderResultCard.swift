import Defaults
import SwiftUI

/// A collapsible card showing a single provider's translation result.
struct ProviderResultCard: View {
    let provider: any TranslationProvider
    let state: TranslationCoordinator.ProviderState
    let targetLanguage: String
    @Binding var isExpanded: Bool
    let isCopyFeedbackActive: Bool
    let copyFeedbackGeneration: Int
    var onCopy: (() -> Void)?
    var onRetry: (() -> Void)?
    var attachments: [String: SourceImageAttachment] = [:]
    @State private var isCopyPulsing = false
    @State private var pulseTask: Task<Void, Never>?
    @Default(.popupFontSize) private var fontSize
    @Default(.popupFontName) private var fontName
    @Default(.ttsAccent) private var ttsAccent
    @Default(.renderMarkdownResults) private var renderMarkdownResults
    @Default(.resultViewMode) private var resultViewMode
    @Environment(\.ttsCoordinator) private var ttsCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: CGFloat(fontSize - 4)))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)

                    ProviderIconView(provider: provider, font: .system(size: CGFloat(fontSize - 2)), size: CGFloat(fontSize + 2))
                        .foregroundStyle(.secondary)

                    Text(provider.displayName)
                        .font(.popup(name: fontName, size: CGFloat(fontSize - 2)))
                        .fontWeight(.medium)

                    Spacer()

                    statusIndicator
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background { InteractiveMarker() }

            // Body — visible when expanded
            if isExpanded {
                Divider()
                    .padding(.horizontal, 8)

                bodyContent
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .onChange(of: copyFeedbackGeneration) { _, _ in
            guard isCopyFeedbackActive else { return }
            pulseTask?.cancel()
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                isCopyPulsing = true
            }
            pulseTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    isCopyPulsing = false
                }
            }
        }
        .onDisappear {
            pulseTask?.cancel()
            pulseTask = nil
        }
    }

    private func isSpeaking(_ text: String) -> Bool {
        ttsCoordinator?.isPlaying(text) ?? false
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        switch state {
        case .waiting:
            Circle()
                .fill(.tertiary)
                .frame(width: 6, height: 6)
        case .translating:
            ProgressView()
                .controlSize(.mini)
        case .streaming:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: CGFloat(fontSize - 2)))
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: CGFloat(fontSize - 2)))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Body Content

    @ViewBuilder
    private var bodyContent: some View {
        switch state {
        case .waiting:
            Text("Waiting…")
                .font(.popup(name: fontName, size: CGFloat(fontSize)))
                .foregroundStyle(.tertiary)
        case .translating:
            Text("Translating…")
                .font(.popup(name: fontName, size: CGFloat(fontSize)))
                .foregroundStyle(.secondary)
        case let .streaming(partial):
            resultContent(partial, isCompleted: false)
        case let .completed(text):
            resultContent(text, isCompleted: true)
        case let .error(message):
            VStack(alignment: .leading, spacing: 4) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.popup(name: fontName, size: CGFloat(fontSize)))
                    .foregroundStyle(.red)

                if let onRetry {
                    HStack {
                        Spacer()
                        Button(action: onRetry) {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.popup(name: fontName, size: CGFloat(fontSize - 2)))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
            .background { InteractiveMarker() }
        }
    }

    private func resultContent(_ text: String, isCompleted: Bool) -> some View {
        let canSpeak = isCompleted
        let offersMarkdown = isCompleted && renderMarkdownResults && MarkdownSupport.looksLikeMarkdown(text)
        let hasAttachments = offersMarkdown && attachments.keys.contains { SourceAttachmentReference.references($0, in: text) }
        let viewMode = (resultViewMode == .rich && !hasAttachments) ? .rendered : resultViewMode
        let font = Font.popup(name: fontName, size: CGFloat(fontSize))
        let spokenText = MarkdownSupport.speakableText(text)

        return VStack(alignment: .leading, spacing: 4) {
            if offersMarkdown && viewMode != .source {
                MarkdownResultView(text: text, font: font, attachments: attachments, showsAttachments: viewMode == .rich)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(font)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if offersMarkdown || (canSpeak && ttsCoordinator != nil) || onCopy != nil {
                HStack {
                    Spacer()

                    if offersMarkdown {
                        Picker("View", selection: Binding(get: { viewMode }, set: { resultViewMode = $0 })) {
                            Text("Source").tag(ResultViewMode.source)
                            Text("Markdown").tag(ResultViewMode.rendered)
                            if hasAttachments {
                                Text("Rich Text").tag(ResultViewMode.rich)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.mini)
                        .labelsHidden()
                        .fixedSize()
                        .help("Switch result view")
                    }

                    if canSpeak, let ttsCoordinator {
                        Button {
                            if isSpeaking(spokenText) {
                                ttsCoordinator.stop()
                            } else {
                                ttsCoordinator.speak(spokenText, language: targetLanguage)
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: isSpeaking(spokenText) ? "speaker.wave.3.fill" : "speaker.wave.2")
                                if targetLanguage.hasPrefix("en") {
                                    Text(ttsAccent.shortLabel)
                                }
                            }
                            .font(.popup(name: fontName, size: CGFloat(fontSize - 2)))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Speak")
                    }

                    if let onCopy {
                        Button(action: onCopy) {
                            Label(
                                isCopyFeedbackActive ? "Copied" : "Copy",
                                systemImage: isCopyFeedbackActive ? "checkmark" : "doc.on.doc"
                            )
                            .font(.popup(name: fontName, size: CGFloat(fontSize - 2)))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(isCopyFeedbackActive ? .green : nil)
                        .scaleEffect(isCopyPulsing ? 1.08 : 1)
                        .animation(.easeInOut(duration: 0.12), value: isCopyFeedbackActive)
                    }
                }
            }
        }
        .background { InteractiveMarker() }
    }
}
