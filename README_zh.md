<p align="center">
  <img src="Resources/AppIcon.icon/Assets/MoePeek.png" width="128" height="128" alt="MoePeek Icon" />
</p>

<h1 align="center">MoePeek</h1>

<p align="center">
  轻量原生的 macOS 菜单栏翻译工具，选中即译。
</p>

<p align="center">
  <a href="README.md">English</a> | 中文
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/swift-6.0-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License" /></a>
</p>

## 功能

- **划词翻译** — 在任意应用中选中文字，浮窗即时展示翻译结果
- **OCR 截图翻译** — 框选屏幕区域，识别并翻译其中的文字
- **剪贴板翻译** — 一键翻译剪贴板中的内容
- **手动输入** — 输入或粘贴文字进行翻译
- **多服务支持** — OpenAI 兼容 API 及 Apple 翻译（macOS 15+，离线可用）
- **智能语言检测** — 自动识别 14 种语言，智能切换翻译方向
- **非激活浮窗** — 翻译面板永远不会抢走你当前应用的焦点
- **三层文本抓取** — Accessibility API → AppleScript → 剪贴板逐级回退
- **自定义快捷键** — 每个操作都可自由配置快捷键
- **自动更新** — 内置 Sparkle 更新器，始终保持最新版本

## 为什么选择 MoePeek

- **纯原生开发** — Swift + SwiftUI + AppKit 构建，没有 Electron，没有 WebView，没有额外运行时开销。
- **轻量稳定** — 极小的内存占用，长时间运行依然稳定流畅。
- **注重隐私** — Apple 翻译完全在设备端运行，API Key 安全存储于 macOS 钥匙串。

## 安装

从 [GitHub Releases](https://github.com/yusixian/MoePeek/releases) 下载最新的 `.dmg` 或 `.zip`，将 `MoePeek.app` 拖入 `/Applications`。

## 使用

首次启动时，MoePeek 会引导你完成权限设置：

- **辅助功能** — 用于通过 Accessibility API 获取选中文本
- **屏幕录制** — 用于 OCR 截图翻译

### 默认快捷键

| 操作 | 快捷键 |
|------|--------|
| 划词翻译 | `⌥ D` |
| OCR 截图 | `⌥ S` |
| 手动输入 | `⌥ A` |
| 剪贴板翻译 | `⌥ V` |

所有快捷键均可在**设置 → 通用**中自定义。

## 常见问题

### macOS 提示"已损坏，无法打开"

由于应用未经 Apple 公证，macOS Gatekeeper 可能会拦截。这并非文件损坏，而是系统安全机制。解决方法：

1. 打开**终端**（Terminal）
2. 执行：

```bash
sudo xattr -r -d com.apple.quarantine /Applications/MoePeek.app
```

之后即可正常打开。

### 引导页未显示 / 想重新触发引导流程

重置所有用户偏好设置，恢复到首次启动状态：

```bash
defaults delete com.nahida.MoePeek
```

重新打开应用即可。

## 致谢

MoePeek 的诞生受到了 [Easydict](https://github.com/tisfeng/Easydict) 和 [Bob](https://github.com/ripperhe/Bob) 等优秀项目的启发，感谢这些项目的开拓与贡献。

依赖库：

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — Sindre Sorhus
- [Defaults](https://github.com/sindresorhus/Defaults) — Sindre Sorhus
- [Sparkle](https://sparkle-project.org/) — 自动更新

## 许可证

[AGPL-3.0](LICENSE)
