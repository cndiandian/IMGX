# GitHub tag 自动发布

目标仓库：<https://github.com/cndiandian/IMGX>。工作流为 `.github/workflows/release.yml`。

推送 `v0.1.0` 这类 tag 后，自动使用 macOS 26 Apple Silicon runner 测试、Release 编译、Developer ID 签名、Apple 公证和装订，最后创建 GitHub Release，附上 ZIP、DMG 和两份 SHA-256 校验文件。普通分支推送不触发发布，单独在本地创建 tag 也不会触发，必须推送到 GitHub。

## 第一步：推送项目

当前项目已配置 origin 为 `git@github.com:cndiandian/IMGX.git`。在项目根目录执行：

```sh
git push -u origin main
```

当前机器已验证 `cndiandian` 的 SSH 身份，并仅为本仓库配置对应 Key，不影响其他项目。在新机器上需要先配置具有仓库写权限的 GitHub SSH Key。如果工作流已经由本次开发推送，可跳过这一步。

## 第二步：准备 Developer ID 的 P12 文件

GitHub runner 是新机器，不能直接访问本机钥匙串。参考项目的 Repository Secrets 无法读回或直接复制到另一个仓库，需要用原始文件重新配置一次。

1. 打开 macOS“钥匙串访问”，进入“我的证书”。
2. 找到 `Developer ID Application: Sichuan Guangnian Zhixu Technology Co., Ltd (8T4S63Q2KK)`，展开确认下面有私钥。
3. 选择该证书和对应私钥，选择“文件 → 导出项目”。
4. 格式选择“个人信息交换 (.p12)”，例如保存为下载目录的 `DeveloperID.p12`。如果已有参考项目使用的 P12 文件，可直接复用。
5. 设置 P12 导出密码，并自行完成系统授权。后续的 `APPLE_CERTIFICATE_PASSWORD` 必须与此密码一致。不要把密码发到聊天中。

只导出公开证书 `.cer` 不足以签名，必须包含私钥。

## 第三步：配置五个 Repository Secrets

打开 [IMGX Actions Secrets 设置](https://github.com/cndiandian/IMGX/settings/secrets/actions)，依次点击 **New repository secret**，添加下表五项。Name 必须完全一致。

| Secret 名称 | Secret 内容 |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | 上一步 P12 文件的 Base64 内容 |
| `APPLE_CERTIFICATE_PASSWORD` | 导出 P12 时设置的密码 |
| `APP_STORE_CONNECT_API_KEY_BASE64` | 已下载的 App Store Connect `.p8` 文件的 Base64 内容 |
| `APP_STORE_CONNECT_API_KEY_ID` | 本机 `.release.env` 中的 Key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | 本机 `.release.env` 中的 Issuer ID |

证书和 API 私钥仅填写到 Secrets，不能放到代码、Actions Variables、Issue 或工作流 YAML 中。当前流程复用现有团队 API Key，不需要创建新 Key 或申请新证书。

按下面顺序复制内容到剪贴板并粘贴至 GitHub 对应 Secret 的 Value；这些命令不会把内容打印到终端。

**P12 Base64**（文件名不同请替换）：

```sh
base64 -i "$HOME/Downloads/DeveloperID.p12" | tr -d '\n' | pbcopy
```

添加 `APPLE_CERTIFICATE_P12_BASE64` 后，再手动填写导出密码对应的 Secret。

**API Key Base64**：在项目根目录执行：

```sh
source .release.env
base64 -i "$APP_STORE_CONNECT_API_KEY_PATH" | tr -d '\n' | pbcopy
```

添加 `APP_STORE_CONNECT_API_KEY_BASE64` 后，依次复制并添加剩余两项：

```sh
printf '%s' "$APP_STORE_CONNECT_API_KEY_ID" | pbcopy
```

```sh
printf '%s' "$APP_STORE_CONNECT_API_ISSUER_ID" | pbcopy
```

工作流仅在 tag 推送时使用凭据，不使用 PR 触发器。它在临时钥匙串导入证书，在结束或失败时清理证书、私钥文件和临时钥匙串；只有独立的 Release 发布 job 获得 `contents: write` 权限。

## 第四步：发布第一个 tag

五项 Secret 配置完成后，确保 tag 指向已包含工作流的提交：

```sh
git push origin main
git tag -a v0.1.0 -m '发布 IMGX 0.1.0'
git push origin v0.1.0
```

支持严格的 `v主版本.次版本.修订版本` 格式。版本自动从 tag 获取，写入应用 Info.plist，构建号使用 Actions 的 run number，无需为发布修改本机 `.release.env`。当前不接受 `v0.1.0-beta` 之类的预发布 tag。

不要删除或强制移动已经发布的 tag。后续版本使用 `v0.1.1`、`v0.2.0` 等新 tag。

## 第五步：检查发布结果

1. 打开 [Actions](https://github.com/cndiandian/IMGX/actions)，进入“发布 IMGX”，查看“编译、签名与公证”和“创建 GitHub Release”两个 job。
2. 全部成功后打开 [Releases](https://github.com/cndiandian/IMGX/releases)，下载 `IMGX-v0.1.0.zip` 或 `IMGX-v0.1.0.dmg`。校验文件同时发布。
3. 如失败，先查看报错步骤。公证结果及日志会保存为 `notarization-logs-*` Artifact，默认保留 14 天；已通过验证的分发产物也保存 14 天。不会把未通过公证检查的文件发布为 Release。

缺少 Secret 会在“检查发布凭据”步骤明确指出名称。证书导入失败通常是 P12 不包含私钥、密码不匹配或证书过期。公证认证失败需检查 `.p8`、Key ID、Issuer ID 是否属于同一 Key。

如果仅 Apple 网络/票据服务暂时失败，可在同一个 run 中选择 **Re-run failed jobs**。若 GitHub Release 已存在，不会自动覆盖；请检查已有 Release 后决定如何处理。

若 Actions 被仓库或组织禁用，到“Settings → Actions → General”启用 GitHub Actions，并允许工作流引用的 GitHub 官方 Actions。工作流已为发布 job 声明写入权限，通常不需要把所有工作流的默认权限改为可写，也不需要额外创建 PAT。

## 自动更新 Homebrew

Release 成功后会运行独立的“更新 Homebrew tap”job：从已经发布的 Release 下载 DMG 和校验文件，验证 SHA-256，随后更新 `cndiandian/homebrew-tap` 默认分支上的 `Casks/imgx.rb`。Cask 包含最低 macOS 26 和 arm64 架构约束。相同内容不会重复提交，旧版本不会覆盖新版本，并发冲突会重新读取版本后重试。

需在 **IMGX** 仓库增加第六项 Repository Secret：`HOMEBREW_TAP_TOKEN`。默认 `GITHUB_TOKEN` 仅能访问当前工作流仓库，不能据此写入另一个 tap 仓库。

1. 如果仍保留 PodLilt 使用的 `HOMEBREW_TAP_TOKEN` 原值，且它有该 tap 的写权限，可以在 IMGX Secrets 中复用。无法从 PodLilt Secrets 页面取回原值。
2. 否则打开 [Fine-grained token 创建页面](https://github.com/settings/personal-access-tokens/new)。Token name 可填 `IMGX Homebrew tap`，Resource owner 选择 `cndiandian`，设置合适的到期时间。
3. Repository access 选择 **Only select repositories**，仅选 `homebrew-tap`。
4. Repository permissions → **Contents** 设为 **Read and write**；Metadata 保留自动的 Read-only。无需授权 Actions、管理或其他仓库。
5. 生成后将 token 填入 [IMGX Secrets](https://github.com/cndiandian/IMGX/settings/secrets/actions)，Name 填 `HOMEBREW_TAP_TOKEN`。不要发到聊天或写进代码。

之后发布新 tag 即可自动更新 Homebrew。已存在的 `v0.1.0` tag 不会因为 main 上的工作流更新而重新触发；该版本的初始 Cask 单独从真实 Release 生成，后续 tag 才包含新的自动更新逻辑。

若只有 tap 更新失败，GitHub Release 仍然有效。配置或续期 token 后，在该次 run 中选择 **Re-run failed jobs**，无需重新编译、公证或重新创建 Release。若发布版本已经被更新版本取代，脚本会跳过该旧版本以避免降级。

安装及更新：

```sh
brew install --cask cndiandian/tap/imgx
brew update
brew upgrade --cask imgx
```

如果新版 Homebrew 提示 untrusted tap，先执行 `brew trust --cask cndiandian/tap/imgx`，仅信任该 Cask，再重试。

离线验证脚本：`python3 Scripts/test-homebrew-tap.py`。可用 `TAP_DRY_RUN=1 python3 Scripts/update-homebrew-tap.py 0.1.0 /路径/IMGX-v0.1.0.dmg` 预览 Cask，不写入 GitHub。

依据：[GITHUB_TOKEN 权限范围](https://docs.github.com/en/actions/concepts/security/github_token)、[细粒度 Token 权限](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens)。

## 当前验收边界

本地发布脚本已经完成真实 Developer ID 签名、应用与 DMG 公证、票据装订和 Gatekeeper 验证。云端 `v0.1.0` 发布已成功。新增 Homebrew 自动同步 job 的云端执行仍需 `HOMEBREW_TAP_TOKEN` 配置完成后，通过包含新工作流的下一版本 tag 验证。

依据：[GitHub macOS 26 runner](https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/)、[GitHub Apple 证书导入指南](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)。
