# 发版指南

## 前置条件

### GitHub Secrets

需要在仓库的 **Prod** 环境中配置以下 Secrets（`Settings > Environments > Prod`）：

| Secret | 说明 |
|--------|------|
| `SPARKLE_ED_PUBLIC_KEY` | Sparkle 更新验证用的 Ed25519 公钥 |
| `SPARKLE_ED_PRIVATE_KEY` | 签名 appcast 条目用的 Ed25519 私钥 |

使用 Sparkle 的 `generate_keys` 工具生成密钥对：

```bash
# 从 Sparkle release 压缩包中执行
./bin/generate_keys
```

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
1. 构建 Release archive
2. 生成 ZIP 和 DMG
3. 下载 Sparkle CLI 工具（版本自动匹配 `Package.resolved`）
4. 生成 `appcast.xml`（保留历史版本记录）
5. 创建 **已发布** 的 GitHub Release，包含 ZIP、DMG 和 `appcast.xml`

## 手动触发（测试用）

通过 Actions 页面的 `workflow_dispatch` 进行测试构建：

1. 前往 **Actions > Release > Run workflow**
2. 可选填版本号（默认为 `0.0.0-dev`）
3. 点击 **Run workflow**

手动触发会创建 **draft** release。Draft release 不会影响 `releases/latest` URL，因此现有用户不会通过 Sparkle 自动更新收到测试版本。

## Sparkle 自动更新原理

1. 应用的 `Info.plist` 中 `SUFeedURL` 指向：
   ```
   https://github.com/yusixian/MoePeek/releases/latest/download/appcast.xml
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
