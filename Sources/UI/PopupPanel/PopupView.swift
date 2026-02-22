import Defaults
import SwiftUI

/// The SwiftUI content displayed inside the popup translation panel.
struct PopupView: View {
    let coordinator: TranslationCoordinator
    var onOpenSettings: (() -> Void)?
    @Environment(\.openSettings) private var openSettings
    @State private var editableText: String = ""
    @State private var expandedProviders: Set<String> = []
    @State private var sourceLang: String = Defaults[.sourceLanguage]
    @State private var targetLang: String = Defaults[.targetLanguage]
    @State private var inputHeight: CGFloat = CGFloat(Defaults[.popupInputHeight])
    @State private var containerHeight: CGFloat = CGFloat(Defaults[.popupDefaultHeight])

    private let inputMinHeight: CGFloat = 36

    private var maxInputHeight: CGFloat {
        // Reserve 120pt for language bar + results; floor ensures drag range above inputMinHeight
        max(containerHeight - 120, inputMinHeight + 24)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch coordinator.phase {
            case .idle:
                EmptyView()

            case .grabbing:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Grabbing text…")
                        .foregroundStyle(.secondary)
                }
                .padding(14)

            case .active:
                activeContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in containerHeight = h }
            }
        )
        .onChange(of: containerHeight) { _, _ in
            let clamped = min(inputHeight, maxInputHeight)
            guard clamped != inputHeight else { return }
            inputHeight = clamped
        }
        .overlay(alignment: .bottomTrailing) {
            ResizeGripView()
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: coordinator.sourceText) { _, newValue in
            editableText = newValue
        }
        .onChange(of: coordinator.targetLanguage) { _, newValue in
            targetLang = newValue
        }
        .onAppear {
            editableText = coordinator.sourceText
            sourceLang = Defaults[.sourceLanguage]
            targetLang = coordinator.targetLanguage
            expandedProviders = Set(coordinator.activeSlots.map(\.id))
        }
    }

    // MARK: - Active Content

    @ViewBuilder
    private var activeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Global error (no providers, permissions, etc.)
            if let message = coordinator.globalError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                .padding(14)
            } else {
                // Source input
                SourceInputView(
                    text: $editableText,
                    onSubmit: {
                        coordinator.translate(editableText)
                    }
                )
                .frame(height: inputHeight)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

                DraggableDividerView(
                    inputHeight: $inputHeight,
                    minHeight: inputMinHeight,
                    maxHeight: maxInputHeight,
                    onDragEnd: { Defaults[.popupInputHeight] = Int(inputHeight) }
                )

                // Language bar + settings button
                HStack(spacing: 4) {
                    LanguageBarView(
                        sourceLanguage: $sourceLang,
                        detectedLanguage: coordinator.detectedLanguage,
                        detectionConfidence: coordinator.detectionResult?.confidence,
                        targetLanguage: $targetLang,
                        onSwap: {
                            let effectiveSource = sourceLang == "auto"
                                ? (coordinator.detectedLanguage ?? targetLang)
                                : sourceLang
                            // When auto-detect has no result yet, effectiveSource falls back
                            // to targetLang and swap becomes a no-op
                            guard effectiveSource != targetLang else { return }
                            sourceLang = targetLang
                            targetLang = effectiveSource
                        }
                    )

                    Button {
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                        onOpenSettings?()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open Settings")
                    .background { InteractiveMarker() }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .onChange(of: targetLang) { _, newValue in
                    Defaults[.targetLanguage] = newValue
                    // Skip retranslation when this change came from coordinator sync
                    guard newValue != coordinator.targetLanguage else { return }
                    if !editableText.isEmpty {
                        coordinator.translate(editableText)
                    }
                }
                .onChange(of: sourceLang) { _, newValue in
                    Defaults[.sourceLanguage] = newValue
                    if !editableText.isEmpty {
                        coordinator.translate(editableText)
                    }
                }

                Divider()
                    .padding(.horizontal, 10)

                // Provider results
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(coordinator.activeSlots, id: \.id) { provider in
                            if let state = coordinator.providerStates[provider.id] {
                                ProviderResultCard(
                                    provider: provider,
                                    state: state,
                                    isExpanded: expandedBinding(for: provider.id),
                                    onRetry: {
                                        coordinator.retryProvider(provider)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Helpers

    private func expandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedProviders.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedProviders.insert(id)
                } else {
                    expandedProviders.remove(id)
                }
            }
        )
    }
}

// MARK: - Resize Grip

/// A draggable grip in the bottom-right corner for resizing the popup panel.
/// Uses SwiftUI DragGesture with NSEvent.mouseLocation (screen coordinates) to avoid
/// EXC_BAD_ACCESS caused by overriding mouse events on NSPanel with NSHostingView.
private struct ResizeGripView: View {
    @Environment(\.popupPanel) private var panel
    @State private var dragStartMouse: NSPoint?
    @State private var dragStartFrame: NSRect?

    var body: some View {
        Canvas { context, size in
            let lineCount = 3
            let spacing: CGFloat = 3
            let lineWidth: CGFloat = 1
            let totalSize = CGFloat(lineCount - 1) * spacing

            for i in 0..<lineCount {
                let offset = CGFloat(i) * spacing
                let start = CGPoint(x: size.width - totalSize + offset, y: size.height)
                let end = CGPoint(x: size.width, y: size.height - totalSize + offset)
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: lineWidth)
            }
        }
        .frame(width: 12, height: 12)
        .padding(4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    let mouse = NSEvent.mouseLocation
                    if dragStartMouse == nil {
                        dragStartMouse = mouse
                        dragStartFrame = panel?.frame
                    }
                    guard let start = dragStartMouse,
                          let initial = dragStartFrame,
                          let panel else { return }

                    let deltaX = mouse.x - start.x
                    let deltaY = mouse.y - start.y

                    let newW = min(max(initial.width + deltaX, panel.minSize.width), panel.maxSize.width)
                    let newH = min(max(initial.height - deltaY, panel.minSize.height), panel.maxSize.height)

                    // Keep top-left corner fixed
                    let newY = initial.maxY - newH
                    panel.setFrame(
                        NSRect(x: initial.origin.x, y: newY, width: newW, height: newH),
                        display: true
                    )
                }
                .onEnded { _ in
                    if let panel {
                        Defaults[.popupDefaultWidth] = Int(panel.frame.width)
                        Defaults[.popupDefaultHeight] = Int(panel.frame.height)
                    }
                    dragStartMouse = nil
                    dragStartFrame = nil
                }
        )
        .onHover { hovering in
            if hovering {
                if #available(macOS 15.0, *) {
                    NSCursor.frameResize(position: .bottomRight, directions: .all).set()
                } else {
                    NSCursor.crosshair.set()
                }
            } else {
                NSCursor.arrow.set()
            }
        }
        .background { InteractiveMarker() }
    }
}

// MARK: - Draggable Divider

/// A horizontal divider between the source input and translation results that can be
/// dragged vertically to resize the input area.
private struct DraggableDividerView: View {
    @Binding var inputHeight: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onDragEnd: () -> Void

    @State private var dragStartMouse: CGFloat?
    @State private var dragStartHeight: CGFloat?
    @State private var isHovering = false

    var body: some View {
        Divider()
            .padding(.horizontal, 10)
            .frame(height: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        let mouseY = NSEvent.mouseLocation.y
                        if dragStartMouse == nil {
                            dragStartMouse = mouseY
                            dragStartHeight = inputHeight
                        }
                        guard let startY = dragStartMouse, let startH = dragStartHeight else { return }
                        // Screen Y points up; dragging down decreases mouseY but should increase inputHeight
                        let delta = startY - mouseY
                        let newHeight = startH + delta
                        inputHeight = min(max(newHeight, minHeight), maxHeight)
                    }
                    .onEnded { _ in
                        dragStartMouse = nil
                        dragStartHeight = nil
                        onDragEnd()
                    }
            )
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                }
            }
            .background { InteractiveMarker() }
    }
}

// MARK: - Interactive Marker

/// NSView marker placed as `.background()` on SwiftUI gesture views.
/// `PopupPanel.sendEvent` checks for this marker to prevent window dragging
/// over areas that handle their own drag gestures (divider, resize grip).
final class InteractiveMarkerView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

struct InteractiveMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> InteractiveMarkerView { InteractiveMarkerView() }
    func updateNSView(_: InteractiveMarkerView, context: Context) {}
}
