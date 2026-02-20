# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This project uses **Tuist** as its build system with SPM for dependency management.

```bash
# Initial setup (install deps + generate Xcode project)
tuist install && tuist generate

# Regenerate after changing Project.swift or Package.swift
tuist generate

# Build from command line
xcodebuild -workspace MoePeek.xcworkspace -scheme MoePeek -configuration Debug build

# Open in Xcode
open MoePeek.xcworkspace
```

No tests, linting, or CI/CD are currently configured.

## Tech Stack

- **Swift 6.0+** with `SWIFT_STRICT_CONCURRENCY: complete`
- **macOS 14.0+** deployment target, LSUIElement (menu bar app, no Dock icon)
- **SwiftUI + AppKit hybrid**: SwiftUI for views, AppKit NSPanel for non-activating floating windows
- **Dependencies**: KeyboardShortcuts (sindresorhus), Defaults (sindresorhus)
- **License**: AGPL-3.0

## Architecture

### Core Data Flow

```
User Action (shortcut / mouse selection / OCR)
  → TranslationCoordinator (state machine: idle → grabbing → translating → streaming → completed/error)
    → Text Grabbing: TextSelectionManager (3-tier fallback: AX API → AppleScript → Clipboard)
    → Language Detection: LanguageDetector (NLLanguageRecognizer, auto-flips target if same as detected)
    → Translation: TranslationService protocol (OpenAI streaming API or Apple Translation on macOS 15+)
  → PopupPanelController (floating result panel at cursor)
```

### Key Patterns

- **@MainActor everywhere**: All UI controllers and coordinators are `@MainActor`-isolated. `@Observable` macro for state observation.
- **Non-activating NSPanels**: `PopupPanel` and `TriggerIconPanel` are borderless floating panels that never steal focus from the user's active app.
- **Coordinator pattern**: `TranslationCoordinator` owns all translation logic and exposes a single `State` enum consumed by views.
- **Callback wiring in AppDelegate**: `AppDelegate.setupSelectionMonitor()` wires together SelectionMonitor → TriggerIconController → TranslationCoordinator → PopupPanelController via closures.
- **3-tier text grabbing**: `AccessibilityGrabber` (AX API) → `AppleScriptGrabber` (Safari-specific) → `ClipboardGrabber` (⌘+C simulation). Each tier tried in order.

### Source Layout

| Directory | Purpose |
|-----------|---------|
| `Sources/App/` | SwiftUI app entry + AppDelegate lifecycle & wiring |
| `Sources/Core/` | Text grabbing, OCR, permissions, TranslationCoordinator |
| `Sources/Services/` | TranslationService protocol + OpenAI/Apple implementations |
| `Sources/UI/` | PopupPanel, TriggerIcon, MenuBar, Settings, Onboarding |
| `Sources/Utilities/` | Constants (Defaults keys, keyboard shortcuts), KeychainHelper, positioning |

### Internationalization (i18n)

The app supports **English** (development language) and **Simplified Chinese** (zh-Hans) via Xcode String Catalogs.

- **`Resources/Localizable.xcstrings`** — Single String Catalog containing all localized strings with en keys and zh-Hans translations.
- **SwiftUI views** use string literals as `LocalizedStringKey` (automatic lookup).
- **Non-UI code** (errors, coordinators) uses `String(localized:)` for runtime localization.
- **`SupportedLanguages`** in `Constants.swift` uses `Locale.current.localizedString(forIdentifier:)` for dynamic language names.
- Strings that should **NOT** be localized: API technical labels (`"Base URL:"`, `"API Key:"`, `"Model:"`), LLM system prompts, provider IDs, copyright/license text, brand name "MoePeek".

### Critical Files

- **`TranslationCoordinator.swift`** — Central orchestrator with state machine; all translation flows route through here
- **`AppDelegate.swift`** — Wires all components together; global shortcut registration and selection monitor setup
- **`Constants.swift`** — All `Defaults.Keys` and `KeyboardShortcuts.Name` definitions; single source of truth for user preferences
- **`TextSelectionManager.swift`** — 3-tier fallback logic for grabbing selected text
- **`PopupPanelController.swift`** — Manages floating panel lifecycle, positioning, and dismiss monitoring

### Permissions

The app requires **Accessibility** (for AX text grabbing) and **Screen Recording** (for OCR). `PermissionManager` polls every 1.5s since macOS has no permission-change callback. Onboarding flow shown on first launch guides users through granting both.

### Adding a New Translation Service

1. Implement `TranslationService` protocol (with `translateStream` returning `AsyncThrowingStream`)
2. Add selection option in `TranslationCoordinator.resolveService()`
3. Add UI controls in `ServiceSettingsView`

## Versioning & Release

- Follow [Semantic Versioning (SemVer)](https://semver.org), tag format `v<MAJOR>.<MINOR>.<PATCH>`
- **MAJOR**: incompatible breaking changes; **MINOR**: new features (backward-compatible); **PATCH**: bug fixes
- During the `0.x.x` phase, bump MINOR for each new feature (`v0.1.0` → `v0.2.0`)
- Pushing a `v*` tag triggers CI auto-build and release; see `docs/RELEASING.md`

## Code Review

Use the following specialized skills when reviewing code changes:

- **swift-concurrency** — async/await, Actor, Sendable, Swift 6 strict concurrency
- **swiftui-expert-skill** — SwiftUI state management, view composition, modern API usage
- **swiftui-performance-audit** — rendering performance, excessive view updates, memory/CPU issues
- **swiftui-view-refactor** — view structure, dependency injection, @Observable usage patterns
- **swiftui-ui-patterns** — UI pattern design, page structure, component composition

Note this project uses a SwiftUI + AppKit hybrid architecture: SwiftUI handles view content (Settings, Onboarding, PopupView), while AppKit NSPanel/NSWindow manages window lifecycle and non-activating floating panels. Reviews must consider the interaction boundary between both.

### Memory Leak Prevention

This is a long-running menu bar app — memory leaks accumulate over time. All code changes must be checked against these patterns:

**Closure Captures**
- Stored closures (callback properties, completion handlers) **must** use `[weak self]` with `guard let self` unwrapping
- SwiftUI `.onChange` / `Button` action closures are lifecycle-managed by the framework and do **not** need `[weak self]`
- System API callbacks like `KeyboardShortcuts.onKeyUp`, `Timer.scheduledTimer`, `NSEvent.addGlobalMonitorForEvents` **must** use `[weak self]`

**NSPanel / NSWindow Lifecycle**
- Windows with `isReleasedWhenClosed = false` must be manually cleaned up on dismiss: `panel.contentView = nil` → `panel = nil`
- Prevent NSHostingView's SwiftUI views from holding strong references back to window controllers

**Timer / Event Monitor Cleanup**
- All `Timer` instances must be `invalidate()`d and set to `nil` in the corresponding stop/dismiss method
- All monitors from `NSEvent.addGlobalMonitorForEvents` must be removed in both `stop()` and `deinit`
- `PermissionManager`'s polling timer must call `stopPolling()` once all permissions are granted

**AsyncThrowingStream**
- `continuation.onTermination` must cancel the associated `Task` to prevent task leaks when the stream is discarded

**Inter-Controller Callback Chains**
- The closure chain in `AppDelegate.setupSelectionMonitor()` (SelectionMonitor → TriggerIconController → TranslationCoordinator → PopupPanelController) uses `[weak self]` throughout; new callbacks must follow this pattern
