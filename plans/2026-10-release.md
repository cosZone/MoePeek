# 2026-10 修复与发布安排

基线：`main f12d421`（v0.20.0）。工作分支：`fix/translation-quality-and-integrations`。
本记录初次验证日期为 2026-10-16，2026-10-19 继续验证；历史测试不能替代最终候选版本的验证。

## 本轮候选：v0.21.0

范围是 OpenClip 集成（#113）、外部 URL 入口集成测试、HTML 富文本冷启动超时修复，以及 PR / 发布工作流的完整测试门禁。新增集成按仓库约定提升 minor 版本。

- [x] OpenClip 扩展 manifest、双语安装说明、Release 扩展包打包步骤。
- [x] OpenClip v1.8.2 实际安装成功，安装后的 manifest 与待发布文件一致。
- [x] URL 入口定向测试：2 个参数化测试，7 个输入场景通过。
- [x] 最终 v0.21.0 候选完整套件：96 个测试、16 个套件通过；xcresult 记录零失败、零跳过。
- [x] OpenClip 原生界面确认扩展启用；发现并修复 `symbol:` 导致的空白图标，改为上游支持的 `symbol(...)`，界面已显示正确图标。
- [x] 直接运行 OpenClip 1.8.2 原版图标解析和 URL 编码实现：图标有效，3 组特殊字符输入完整往返。
- [ ] OpenClip 实际菜单动作到 MoePeek 呈现结果的完整验收（保留验证缺口，按 10 月 19 日用户指示继续推进代码审查）。
- [x] 最终版本 Release archive 成功，版本号 0.21.0，包含 arm64 / x86_64；扩展 ZIP 中的 manifest 与源文件一致。
- [x] 最终 diff、JSON、Release YAML 静态检查通过。
- [x] 提交并推送 feature branch，创建 [draft PR #117](https://github.com/cosZone/MoePeek/pull/117)。
- [x] 远端完整测试通过：[运行 39258012918](https://github.com/cosZone/MoePeek/actions/runs/39258012918)，提交 `167a167`，96 个测试、16 个套件成功。首轮测试宿主启动超时；仅补入公开测试公钥后，本地和远端均成功，正式发布仍使用 Prod 公钥。
- [x] HTML 超时调整后的本地完整套件通过，96 个测试成功。文档提交后的运行 39258728005 复现已有 `importsHTMLFormatting` 在 2.013 秒退回纯文本的问题；当前只将 HTML 导入超时从 2 秒延长至 5 秒，保持原有格式断言和失败回退。
- [x] HTML 修复的远端回归通过：[运行 39260098603](https://github.com/cosZone/MoePeek/actions/runs/39260098603)，提交 `6c16a7c`，96 个测试、16 个套件成功；HTML 格式断言在冷启动耗时 2.570 秒后通过。合并前仍检查 PR #117 最新提交的状态。
- [x] HTML 修复后的 Release 归档重新验证：10 月 19 日生成版本 0.21.0，包含 arm64 / x86_64；本地未签名 ZIP 完整性校验通过。10 月 16 日归档不包含此修复。
- [ ] 展示剩余验证缺口和发布命令，确认正式发版。
- [ ] 远端测试、正式签名、ZIP/DMG、扩展包、appcast 与 tag/commit 一致性核验。

自动化测试必须成功才进入发布流程。10 月 19 日用户要求直接尝试并继续推进，因此不再把人工快捷键操作作为代码审查的前置条件；正式发布前仍须明确披露原生完整调用的验证缺口。测试报告保存在 `.build/quality-20261016/` 与 `.build/quality-20261019/`，不提交构建产物或本地 HANDOFF.md。

### 本地证据与尚缺条件

- `final.xcresult` / `final-summary.json`：最终候选 96 / 96 通过，失败 0、跳过 0；参数化场景共计 134 次测试执行。
- `archive.log` / `MoePeek-v0.21.0.xcarchive`：Release 通用二进制归档成功。本地使用 `CODE_SIGNING_ALLOWED=NO`，不能代替正式签名验证。
- `MoePeek.openclipext.zip`：通过 ZIP 内容校验及 manifest 字节一致性校验。
- `apple-matrix.log`：使用真实 Apple 翻译 API，指定英语和自动识别两种模式下分别执行简体→繁体→简体，共 6 次成功；仅证明本机该输入正常。
- `quality-20261019/verification.xcresult` / `verification-summary.json`：当天完整套件 96 / 96 通过，失败 0、跳过 0。
- `quality-20261019/openclip-contract.log`：直接使用上游 v1.8.2 源码验证图标解析和 3 组 URL 特殊字符输入；上下文仅用最小数据结构承载，不替代 OpenClip 的菜单执行验收。
- `quality-20261019/key-fixed.xcresult` / `ci-39258012918.log`：带公开测试公钥的本地完整套件与 GitHub macOS 26.6.2 / Xcode 26.6 完整套件均通过。
- `quality-20261019/html-fixed.xcresult` / `ci-39260098603.log`：HTML 修复后的本地与远端完整套件均为 96 / 96 通过；远端 HTML 用例耗时超过原有 2 秒限制，仍保留粗体与列表格式。
- `quality-20261019/archive.log` / `MoePeek-v0.21.0-local-unsigned.zip`：包含 HTML 修复的通用 Release 归档和 ZIP 校验成功；仍待正式签名与分发验证。
- OpenClip 1.8.2 的原生安装、启用和图标显示已确认。系统权限开关已开启，重启后权限恢复提示消失；窗口级快捷键未唤起面板，System Events 明确拒绝 `osascript` 发送按键。没有绕过或修改系统权限数据库。
- 正式签名、Release Actions、Sparkle 更新及安装包下载仍需在远端发布流程中验证。

## 问题与后续顺序

**新优先项 #116（10 月 17 日新增）**：macOS 27 OCR 报错及 TikTok 选字失败。10 月 19 日在 macOS 27.2 用同一张中英文合成图片对照：当前 OCR 路径在 Vision / TextRecognition 内等待，默认 revision 3 和 CPU-only revision 3 均超过 30 秒未返回，revision 2 成功识别中英文。尚未复现报告中的 `CRImageReaderError 1`，不能等同原始故障；revision 2 也不支持现有日语、韩语，因此不能全局降级。该问题列为本轮之后的首要修复，需验证有限回退及语言兼容性。TikTok 部分需要实际页面复现，当前仅确认剪贴板回退会发送带 Command 修饰的 C；没有修改或关闭 issue。

1. **#112 简体结果混入繁体字**：直接运行当前 AppleTranslationProvider 并使用原始文本，显式英语与自动识别下的简体、繁体输出均正确；原生窗口也显示正确简体结果。本机为 macOS 27.2 / Xcode 27。尚未复现，不添加推测性转换逻辑，不在本轮发布说明中声称修复，不关闭 issue。后续需要报告者的 macOS / MoePeek 版本，以及同一原文在当前版本中的复测结果。
2. **#106 OCR 长文本无响应**：已有布局回归测试通过，覆盖 12 组尺寸/字体组合、流式结果中的手动缩放及关闭后重开。原始截图与原始环境的持续卡死场景仍未复测；本轮不把通过合成场景视为该场景已解决。若原场景仍可复现，优先于功能扩展处理。
3. **PR #114 / #115**：两者分别提供 API Route / Opper 预设。纳入后续版本前，需要针对最终提交确认构建、模型列表、连接测试与流式翻译。#114 的公开验证运行实际完成了 94 个测试，唯一失败项是 HTML 富文本格式导入；该问题已在不含服务预设的本分支 CI 复现并修复，不能归因于 API Route。两个服务预设的实际 API 验证仍待完成。
4. **#76 / #13**：智能翻译和浮窗自动增高已有实现；整理已完成主诉求与剩余细节，不重复开发。是否关闭或拆分 issue 另行确认。
5. **#62 换行处理**：先获得真实 PDF/网页文本样本，明确保留段落与合并硬换行的规则。
6. **#77 自定义 TTS**：作为独立功能设计，覆盖服务配置、播放取消和失败反馈。
7. **#66 自动纠错**：先明确纠错提示交互，避免静默修改用户原文。

## 发布与回退

- 发布说明草案：`docs/releases/v0.21.0.md`。
- 先提交并推送 feature branch，通过审查后再合入 main；若最终提交包含额外改动，重新验证。正式发布 tag 必须指向完整测试通过、验证证据与剩余缺口已经确认的提交。
- 新增 `Tests` workflow，在 PR、main 推送及手动触发时运行；采用示例 xcconfig 且关闭签名，不访问 Prod secrets。tag 推送后，Release workflow 的完整测试门禁仍须成功，才会继续正式签名归档和创建 Release。
- 推送 `v0.21.0` 会触发正式 Release，并通过 `releases/latest` 向 Sparkle 用户提供更新，因此需要最终确认。
- 若发布流程测试或签名失败，停止并保留日志，不移动 tag、不改为临时签名发布。
- 若正式发布后确认回归，撤下错误的 latest 更新入口并准备新 patch；不覆盖已有安装包或重用版本号。
