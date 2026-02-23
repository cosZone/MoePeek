<p align="center">
  <img src="Resources/AppIcon.icon/Assets/MoePeek.png" width="128" height="128" alt="MoePeek Icon" />
</p>

<h1 align="center">MoePeek</h1>

<p align="center">
  A lightweight, native macOS menu bar translator. Select text, get translation.
</p>

<p align="center">
  English | <a href="README_zh.md">中文</a>
</p>

<p align="center">
  <a href="https://github.com/cosZone/MoePeek/releases/latest"><img src="https://img.shields.io/github/v/release/cosZone/MoePeek" alt="GitHub Release" /></a>
  <a href="https://github.com/cosZone/MoePeek/releases"><img src="https://img.shields.io/github/downloads/cosZone/MoePeek/total" alt="Downloads" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/swift-6.0-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License" /></a>
</p>

<p align="center">
  <img src="Resources/MoePeek-promo.webp" alt="MoePeek Preview" />
</p>

## Features

**Translation Modes**

- **Select & Translate**: Select text in any app, get instant translation in a floating panel
- **OCR Screenshot**: Capture a screen region and translate the recognized text
- **Clipboard Translation**: Translate whatever's on your clipboard
- **Manual Input**: Type or paste text to translate on demand

**Built-in Translation Services**

| Free | API | LLM | System |
|------|-----|-----|--------|
| Google Translate | DeepL | OpenAI | Apple Translation |
| Bing Translate | Baidu | DeepSeek | *(macOS 15+, on-device)* |
| Youdao Translate | NiuTrans | 智谱 GLM | |
| | Caiyun | Ollama (local) | |

**And More**

- Smart language detection across 14 languages, auto-flips translation direction
- Non-activating floating panels that never steal focus from your current app
- 3-tier text grabbing: Accessibility API → AppleScript → Clipboard fallback
- Fully customizable keyboard shortcuts
- Built-in auto-updater via Sparkle

## Why MoePeek

- **~5 MB app size**: Pure Swift 6, only 3 dependencies. No Electron, no WebView.
- **~50 MB background memory**: Systematic memory leak prevention for long-running sessions.
- **Privacy-friendly**: Apple Translation runs entirely on-device.
- **Open source**: AGPL-3.0 licensed. Issues and feedback welcome.

## Installation

Download the latest `.dmg` or `.zip` from [GitHub Releases](https://github.com/cosZone/MoePeek/releases) and drag `MoePeek.app` into `/Applications`.

## Usage

On first launch, MoePeek walks you through an onboarding flow to grant the required permissions:

- **Accessibility**: Needed to grab selected text via the Accessibility API
- **Screen Recording**: Needed for OCR screenshot translation

### Default Shortcuts

| Action | Shortcut |
|--------|----------|
| Translate Selection | `⌥ D` |
| OCR Screenshot | `⌥ S` |
| Manual Input | `⌥ A` |
| Clipboard Translation | `⌥ V` |

All shortcuts can be customized in **Settings → General**.

### PopClip Integration

If you use [PopClip](https://www.popclip.app/), you can translate selected text with a single click from the PopClip bar.

**Install the extension:**

1. Make sure MoePeek is installed and running.
2. Download [`MoePeek.popclipext.zip`](https://github.com/cosZone/MoePeek/releases/latest/download/MoePeek.popclipext.zip) from the latest release and unzip it.
3. Double-click `MoePeek.popclipext` — PopClip will install it automatically.
4. Select any text in any app → click the **MoePeek** icon in the PopClip bar.

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

## Contributing

Issues and PRs are welcome! A few things to know:

- I work a day job, so I may not respond immediately — I typically batch-process issues and PRs on weekends.
- Feel free to fork and build your own version. Per the AGPL-3.0 license, derivative works **must also be open source**.

## Acknowledgements

MoePeek was inspired by [Easydict](https://github.com/tisfeng/Easydict) and [Bob](https://github.com/ripperhe/Bob). Thank you for paving the way.

Built with:

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus
- [Defaults](https://github.com/sindresorhus/Defaults) by Sindre Sorhus
- [Sparkle](https://sparkle-project.org/) for auto-updates

## Sponsor

<a href="https://afdian.com/a/cosyu"><img width="20%" src="https://pic1.afdiancdn.com/static/img/welcome/button-sponsorme.jpg" alt="Sponsor on Afdian"></a>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=cosZone/MoePeek&type=date&legend=top-left)](https://www.star-history.com/#cosZone/MoePeek&type=date&legend=top-left)

## License

[AGPL-3.0](LICENSE)
