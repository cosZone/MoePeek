# MoePeek PopClip Extension

Translate selected text instantly with [MoePeek](https://github.com/cosZone/MoePeek) via PopClip.

## Requirements

- [MoePeek](https://github.com/cosZone/MoePeek) v0.8.0 or later
- [PopClip](https://www.popclip.app/) (Mac App Store)
- macOS 14.0+

## Installation

1. Make sure MoePeek is installed and running.
2. Double-click `MoePeek.popclipext` to install the extension into PopClip.
3. Select any text — click the MoePeek icon in the PopClip bar to translate.

## Icon

Place your app icon (512×512 PNG) at `MoePeek.popclipext/icon.png`.
You can export it from `Assets.xcassets` in the Xcode project.

## How it works

The extension uses PopClip's URL action to call `mopeek://translate?text=<selected text>`.
MoePeek handles the URL scheme and shows the translation panel at the cursor.
