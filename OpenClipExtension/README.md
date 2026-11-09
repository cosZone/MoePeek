# MoePeek for OpenClip

Select text in [OpenClip](https://github.com/ganeshmshetty/openclip), then choose **MoePeek** to open the translation popup. Translation uses the services and target language configured in MoePeek.

## Install

1. Install MoePeek and OpenClip, and complete MoePeek's initial setup.
2. Download `MoePeek.openclipext.zip` from the [latest MoePeek release](https://github.com/cosZone/MoePeek/releases/latest) and unzip it.
3. Open `MoePeek.openclipext` with OpenClip and confirm the extension installation.
4. Select text and choose **MoePeek** from OpenClip's actions.

For a source checkout, open `OpenClipExtension/MoePeek.openclipext` with OpenClip.

The extension uses MoePeek's existing `mopeek://translate?text=…` URL entry point. OpenClip percent-encodes the selected text, including newlines and URL punctuation. It opens MoePeek's translation window; it does not replace the selected text or return the translation to OpenClip.
