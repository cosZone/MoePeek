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
  <a href="https://github.com/cosZone/MoePeek/releases/latest"><img src="https://img.shields.io/github/v/release/cosZone/MoePeek" alt="GitHub Release" /></a>
  <a href="https://github.com/cosZone/MoePeek/releases"><img src="https://img.shields.io/github/downloads/cosZone/MoePeek/total" alt="Downloads" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/swift-6.0-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License" /></a>
</p>


<p align="center">
  <img src="Resources/MoePeek-promo.webp" alt="MoePeek 预览" />
</p>

## 功能

**翻译方式**

- **划词翻译**：在任意应用中选中文字，浮窗即时展示翻译结果
- **OCR 截图翻译**：框选屏幕区域，识别并翻译其中的文字
- **剪贴板翻译**：一键翻译剪贴板中的内容
- **手动输入**：输入或粘贴文字进行翻译

**内置翻译服务**

| 免费 | API | LLM | 系统 |
|------|-----|-----|------|
| Google 翻译 | DeepL | OpenAI | Apple 翻译 |
| Bing 翻译 | 百度翻译 | DeepSeek | *（macOS 15+，离线可用）* |
| 有道翻译 | 小牛翻译 | 智谱 GLM | |
| | 彩云小译 | Ollama（本地） | |

**更多特性**

- 智能语言检测，支持 14 种语言，自动切换翻译方向
- 非激活浮窗，永远不会抢走当前应用焦点
- 三层文本抓取：Accessibility API → AppleScript → 剪贴板逐级回退
- 所有快捷键均可自定义
- 内置 Sparkle 自动更新

## 为什么选择 MoePeek

- **约 5 MB 安装体积**：纯 Swift 6 构建，仅 3 个依赖。没有 Electron，没有 WebView。
- **约 50 MB 后台内存**：系统性防控内存泄漏，长时间挂后台也稳定。
- **注重隐私**：Apple 翻译完全在设备端运行。
- **开源项目**：AGPL-3.0 协议，欢迎提 Issue 和反馈。

## 安装

从 [GitHub Releases](https://github.com/cosZone/MoePeek/releases) 下载最新的 `.dmg` 或 `.zip`，将 `MoePeek.app` 拖入 `/Applications`。

## 使用

首次启动时，MoePeek 会引导你完成权限设置：

- **辅助功能**：用于通过 Accessibility API 获取选中文本
- **屏幕录制**：用于 OCR 截图翻译

### 默认快捷键

| 操作 | 快捷键 |
|------|--------|
| 划词翻译 | `⌥ D` |
| OCR 截图 | `⌥ S` |
| 手动输入 | `⌥ A` |
| 剪贴板翻译 | `⌥ V` |

所有快捷键均可在**设置 → 通用**中自定义。

### PopClip 集成

如果你使用 [PopClip](https://www.popclip.app/)，可以直接从 PopClip 菜单栏一键触发 MoePeek 翻译。

**安装扩展：**

1. 确保 MoePeek 已安装并正在运行。
2. 从最新 Release 下载 [`MoePeek.popclipext.zip`](https://github.com/cosZone/MoePeek/releases/latest/download/MoePeek.popclipext.zip) 并解压。
3. 双击 `MoePeek.popclipext`，PopClip 会自动完成安装。
4. 在任意应用中选中文字 → 点击 PopClip 栏中的 **MoePeek** 图标即可翻译。

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

## 参与贡献

欢迎提 Issue 和 PR！有几点说明：

- 平时上班较忙，可能无法及时回复，通常会集中在周末统一处理 Issue 和 PR。
- 欢迎 Fork 进行二次开发。根据 AGPL-3.0 协议，衍生项目**必须同样开源**。

## 致谢

MoePeek 的诞生受到了 [Easydict](https://github.com/tisfeng/Easydict) 和 [Bob](https://github.com/ripperhe/Bob) 的启发，感谢这些项目的开拓与贡献。

依赖库：

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)：Sindre Sorhus
- [Defaults](https://github.com/sindresorhus/Defaults)：Sindre Sorhus
- [Sparkle](https://sparkle-project.org/)：自动更新

## 赞助

<a href="https://afdian.com/a/cosyu"><img width="20%" src="https://pic1.afdiancdn.com/static/img/welcome/button-sponsorme.jpg" alt="在爱发电上赞助"></a>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=cosZone/MoePeek&type=date&legend=top-left)](https://www.star-history.com/#cosZone/MoePeek&type=date&legend=top-left)

## 许可证

[AGPL-3.0](LICENSE)
