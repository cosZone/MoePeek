# 发版指南

## 前置条件

### GitHub Secrets

需要在仓库的 **Prod** 环境中配置以下 Secrets（`Settings > Environments > Prod`）：

| Secret | 说明 |
|--------|------|
| `SIGNING_CERTIFICATE_P12` | 签名证书 .p12 文件的 base64 编码（如 `Apple Development` 或 `Developer ID Application`） |
| `SIGNING_CERTIFICATE_PASSWORD` | 导出 .p12 时设置的密码 |
| `DEVELOPMENT_TEAM` | Apple Developer Team ID |
| `SPARKLE_ED_PUBLIC_KEY` | Sparkle 更新验证用的 Ed25519 公钥 |
| `SPARKLE_ED_PRIVATE_KEY` | 签名 appcast 条目用的 Ed25519 私钥 |

#### 导出签名证书（一次性操作）

1. 打开 **钥匙串访问**（Keychain Access）
2. 在 "login" 钥匙串中找到签名证书（如 `Apple Development: me@nahida.icu`）
3. 展开证书左边的三角，确认包含私钥
4. 右键证书 → **导出** → 格式选 `.p12` → 设置导出密码 → 保存
5. 转 base64 并复制到剪贴板：
   ```bash
   base64 -i ~/path/to/certificate.p12 | pbcopy
   ```
6. 粘贴到 GitHub Secret `SIGNING_CERTIFICATE_P12`
7. 导出密码填入 GitHub Secret `SIGNING_CERTIFICATE_PASSWORD`

导出前可用以下命令确认本机存在有效的代码签名 identity：

```bash
security find-identity -v -p codesigning
```

证书显示名末尾括号中的值不一定是 Team ID。Team ID 应以证书 Subject 的 `OU` 字段或 Apple Developer 账号中显示的 Team ID 为准，并填写到 `DEVELOPMENT_TEAM`。

> **为什么需要签名？** macOS TCC 数据库通过代码签名身份追踪辅助功能和屏幕录制等权限。使用固定证书签名可确保用户更新应用后无需重新授权。

#### 生成 Sparkle 密钥对

使用 Sparkle 的 `generate_keys` 工具生成密钥对：

```bash
# 从 Sparkle release 压缩包中执行
./bin/generate_keys
```

## 合并前验证

`Tests` workflow 在 PR 和 main 分支推送时运行完整 `MoePeekTests`，也支持手动触发。它使用示例签名配置并关闭代码签名，提供公开测试公钥供 Sparkle 测试宿主初始化，不读取 Prod secrets；xcresult 报告保留 14 天。

合并前检查最新提交的测试结果。Release workflow 会在正式签名归档前再次运行完整测试，失败时停止发布。

## 通过 Git Tag 发版（推荐）

推送 semver tag 即可触发 CI 自动构建、签名并发布。

```bash
# 1. 确保在 main 分支且代码最新
git checkout main && git pull

# 2. 创建并推送 tag
git tag v0.2.0
git push origin v0.2.0
```

CI 会自动完成以下步骤：
1. 导入签名证书，运行完整 `MoePeekTests`；失败则停止发布，并保留 xcresult 报告
2. 构建 Release archive，验证代码签名（确保 Authority 和 TeamIdentifier 正确）
3. 生成 ZIP、DMG、PopClip 和 OpenClip 扩展包
4. 下载 Sparkle CLI 工具（版本自动匹配 `Package.resolved`）
5. 生成 `appcast.xml`（保留历史版本记录）
6. 创建 **已发布** 的 GitHub Release，包含应用、扩展包和 `appcast.xml`

## 手动触发（测试用）

通过 Actions 页面的 `workflow_dispatch` 进行测试构建：

1. 前往 **Actions > Release > Run workflow**
2. 可选填版本号（默认为 `0.0.0-dev`）
3. 点击 **Run workflow**

手动触发会创建 **draft** release。Draft release 不会影响 `releases/latest` URL，因此现有用户不会通过 Sparkle 自动更新收到测试版本。

## Sparkle 自动更新原理

1. 应用的 `Info.plist` 中 `SUFeedURL` 指向：
   ```
   https://github.com/cosZone/MoePeek/releases/latest/download/appcast.xml
   ```
2. GitHub 的 `releases/latest/download/{asset}` 会重定向到最新 **非 draft** release 的资源文件
3. Sparkle 拉取 `appcast.xml`，比对版本号，如有更新则提示用户
4. 用户直接从 GitHub Releases 下载 ZIP 安装

## 常见问题

### Gatekeeper 阻止打开应用

由于应用未经公证（notarize），macOS Gatekeeper 可能在首次启动时阻止运行：

1. 右键点击应用 > **打开**（仅对该应用绕过 Gatekeeper）
2. 或前往 `系统设置 > 隐私与安全性` > 点击 **仍要打开**

### Release 中缺少 appcast.xml

- 检查 Prod 环境中是否已设置 `SPARKLE_ED_PRIVATE_KEY`
- 查看 Actions 日志中 "Generate appcast" 步骤是否有报错

### Sparkle 未检测到更新

- 确认 release 不是 draft（draft release 不包含在 `latest` 中）
- 检查 `Project.swift` 中 `SUFeedURL` 是否指向正确的 URL
- 确认最新 release 中包含 `appcast.xml` 资源文件

### 更新后辅助功能/屏幕录制权限丢失

- 检查 CI 日志中 "Verify code signature" 步骤，确认 `Authority` 包含签名身份且 `TeamIdentifier` 正确
- 如果签名验证失败，检查 Prod 环境中 `SIGNING_CERTIFICATE_P12`、`SIGNING_CERTIFICATE_PASSWORD`、`DEVELOPMENT_TEAM` 是否配置正确
- 证书过期后需要重新导出并更新 `SIGNING_CERTIFICATE_P12` secret
