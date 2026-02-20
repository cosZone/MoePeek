<p align="center">
  <img src="Resources/AppIcon.icon/Assets/MoePeek.png" width="128" height="128" alt="MoePeek Icon" />
</p>

<h1 align="center">MoePeek</h1>

<p align="center">
  A lightweight, native macOS translation utility that lives in your menu bar.
</p>

<p align="center">
  English | <a href="README_zh.md">中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/swift-6.0-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License" /></a>
</p>

## Features

- **Select & Translate** — Select text in any app, get instant translation in a floating panel
- **OCR Translation** — Capture a screen region and translate the recognized text
- **Clipboard Translation** — Translate whatever's on your clipboard
- **Manual Input** — Type or paste text to translate on demand
- **Multiple Providers** — OpenAI-compatible APIs and Apple Translation (macOS 15+, offline)
- **Smart Language Detection** — Automatically detects source language across 14 languages
- **Non-activating Panels** — Floating windows that never steal focus from your current app
- **3-tier Text Grabbing** — Accessibility API → AppleScript → Clipboard fallback chain
- **Custom Shortcuts** — Fully configurable keyboard shortcuts for every action
- **Auto Updates** — Built-in Sparkle updater keeps you on the latest version

## Why MoePeek

- **Fully native** — Built with Swift, SwiftUI, and AppKit. No Electron, no WebView, no runtime overhead.
- **Stays light** — Minimal memory footprint, stable over long-running sessions.
- **Privacy-conscious** — Apple Translation runs entirely on-device. API keys are stored in macOS Keychain.

## Installation

Download the latest `.dmg` or `.zip` from [GitHub Releases](https://github.com/yusixian/MoePeek/releases) and drag `MoePeek.app` into `/Applications`.

## Usage

On first launch, MoePeek walks you through an onboarding flow to grant the required permissions:

- **Accessibility** — Needed to grab selected text via the Accessibility API
- **Screen Recording** — Needed for OCR screenshot translation

### Default Shortcuts

| Action | Shortcut |
|--------|----------|
| Translate Selection | `⌥ D` |
| OCR Screenshot | `⌥ S` |
| Manual Input | `⌥ A` |
| Clipboard Translation | `⌥ V` |

All shortcuts can be customized in **Settings → General**.

## FAQ

### "MoePeek.app is damaged and can't be opened"

The app is not notarized with Apple, so macOS Gatekeeper may block it. This does not mean the file is corrupted. To fix:

1. Open **Terminal**
2. Run:

```bash
sudo xattr -r -d com.apple.quarantine /Applications/MoePeek.app
```

Then launch the app as usual.

### Onboarding screen doesn't appear / want to re-trigger onboarding

Reset all user preferences to restore the first-launch state:

```bash
defaults delete com.nahida.MoePeek
```

Then relaunch the app.

## Acknowledgements

MoePeek was inspired by excellent projects in the macOS translation space, including [Easydict](https://github.com/tisfeng/Easydict) and [Bob](https://github.com/ripperhe/Bob). Thank you for paving the way.

Built with:

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus
- [Defaults](https://github.com/sindresorhus/Defaults) by Sindre Sorhus
- [Sparkle](https://sparkle-project.org/) for auto-updates

## License

[AGPL-3.0](LICENSE)
