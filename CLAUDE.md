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

- 遵循 [语义化版本（SemVer）](https://semver.org)，tag 格式 `v<MAJOR>.<MINOR>.<PATCH>`
- **MAJOR**：不兼容的破坏性变更；**MINOR**：新增功能（向后兼容）；**PATCH**：Bug 修复
- `0.x.x` 阶段每次新功能递增 MINOR（`v0.1.0` → `v0.2.0`）
- 推送 `v*` tag 触发 CI 自动构建发布，详见 `docs/RELEASING.md`

## Code Review

审查代码变更时，使用以下专项 skill：

- **swift-concurrency** — async/await、Actor、Sendable、Swift 6 严格并发
- **swiftui-expert-skill** — SwiftUI 状态管理、视图组合、现代 API 用法
- **swiftui-performance-audit** — 渲染性能、过度视图更新、内存/CPU 问题
- **swiftui-view-refactor** — 视图结构、依赖注入、@Observable 使用模式
- **swiftui-ui-patterns** — UI 模式设计、页面结构、组件组合

注意本项目是 SwiftUI + AppKit 混合架构：SwiftUI 负责视图内容（Settings、Onboarding、PopupView），AppKit NSPanel/NSWindow 负责窗口管理和非激活浮动面板。审查时需兼顾两者的交互边界。
