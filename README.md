# IMGX

面向 Apple Silicon、macOS 26+ 的原生图片转换与压缩工具。使用 SwiftUI 与 AppKit，图片仅在本机处理。

## 使用

Apple Silicon、macOS 26+ 可以通过 Homebrew 安装：

```sh
brew install --cask cndiandian/tap/imgx
```

已安装后执行 `brew update && brew upgrade --cask imgx` 更新。
若 Homebrew 提示 Cask 来自未信任的 tap，先执行 `brew trust --cask cndiandian/tap/imgx`，再重试安装。

构建后打开 `dist/IMGX.app`。选择或拖入 JPG、JPEG、PNG、WebP、HEIC 静态图片，调整输出格式、质量及尺寸，通过滑杆或分屏检查真实编码结果，再选择文件夹导出全部图片。输出支持 WebP、JPEG、PNG；同名文件自动编号，保留原文件。

- ⌘O 添加图片，⌘Return 导出全部，⌘0 适应窗口。
- 侧栏上下键切图；非编辑状态下 Delete 移除选中。
- 画布滚轮/捏合缩放、拖动平移、双击复位；获得焦点后支持方向键、`+`/`-`、`0`、`[`/`]`。
- 100% 表示适应窗口的基准比例，不是像素一一对应。

在“IMGX → 关于 IMGX”中查看当前版本、打开项目主页或检测更新。发现 GitHub 新的正式版本后，会自动下载并校验 DMG，再打开安装镜像；将 IMGX 拖入 Applications 完成更新。安装镜像保存在“下载/IMGX”的独立目录中。检测和下载时按钮切换为“取消”。

## 开发与验证

需要 Xcode 26+ 与 Swift 6.2+。在项目目录执行：

```sh
swift build
swift test
bash Scripts/build-app.sh
open dist/IMGX.app
```

也可使用 Xcode 打开 `Package.swift`。WebP 1.6.0 和 libsharpyuv 已静态入库，运行和构建无需 Homebrew；库当前仅提供 arm64 架构。第三方许可位于 `Vendor/WebP`，打包时也复制至应用 Resources。

`bash Scripts/build-app.sh debug` 生成调试应用。仅 Debug 构建支持 `IMGX_DEV_APPEARANCE=dark/light`、`IMGX_DEV_SMALL_WINDOW=1` 和以换行分隔路径的 `IMGX_DEV_INPUTS`，用于应用内外观及文件导入验收，不修改系统设置。Release 构建不启用这些辅助入口。

## 正式签名与公证

需要 Apple Developer Program 账户、完整 Xcode，以及已安装到钥匙串的 **Developer ID Application** 证书和对应私钥。该流程用于 Mac App Store 之外分发。

先查看可用签名身份，并将公证凭据保存到钥匙串（一次即可）：

```sh
security find-identity -v -p codesigning
xcrun notarytool store-credentials IMGX --apple-id '你的 Apple ID' --team-id '你的 Team ID'
```

第二条命令会交互式提示输入 App 专用密码；不要使用 Apple ID 登录密码。也可使用 App Store Connect API Key 创建同名钥匙串凭据，详见 `xcrun notarytool store-credentials --help`。不需要把密码或私钥写入项目。

仅编译并正式签名：

```sh
bash Scripts/build-app.sh release --sign 'Developer ID Application: 你的姓名 (TEAMID)'
```

一键编译、签名、上传 Apple 公证、装订并验证票据：

```sh
bash Scripts/build-app.sh release \
  --sign 'Developer ID Application: 你的姓名 (TEAMID)' \
  --notarize --profile IMGX
```

`--sign` 也支持证书 SHA-1，以区分同名证书。可通过环境变量 `IMGX_SIGN_IDENTITY`（或参考项目使用的 `CODE_SIGN_IDENTITY`）、`IMGX_NOTARY_PROFILE` 提供默认值。没有签名配置时，原有命令继续使用本地临时签名；公证模式强制要求正式签名和 Release 构建。

签名后的应用位于 `dist/IMGX.app`。每次公证在 `dist/notarization.XXXXXX/` 中独立保存结果 `app-result.json` 和下载的日志 `app-log.json`；只有公证状态为 `Accepted` 且票据装订、签名、Gatekeeper 检查均通过后，才生成可分发的 **`IMGX-v0.1.0.zip`** 及 SHA-256 校验文件。`IMGX-upload.zip` 为提交给 Apple 的中间文件。

参照 PodLilt 项目增加 `Scripts/release.sh`：支持同名 API Key 环境变量，额外构建、签名、公证并装订 DMG（含 Applications 快捷方式）。版本使用 `APP_VERSION` 和 `BUILD_NUMBER`，默认 `0.1.0` / `1`。具体操作见 [发布步骤](docs/RELEASING.md)。

默认等待 30 分钟，可用 `--timeout 60m` 调整。超时或网络失败会返回失败状态，Apple 端可能仍继续处理；保留结果目录和提交 ID，可继续查询：

```sh
xcrun notarytool info '提交 ID' --keychain-profile IMGX
xcrun notarytool wait '提交 ID' --keychain-profile IMGX --timeout 60m
xcrun notarytool log '提交 ID' --keychain-profile IMGX '日志文件.json'
```

若稍后确认通过，可对**同一次构建且未被修改**的应用执行 `xcrun stapler staple dist/IMGX.app`、`xcrun stapler validate dist/IMGX.app` 和 `spctl --assess --type execute --verbose=2 dist/IMGX.app`，再重新打 ZIP；或重新执行完整脚本。流程依据 [Apple 公证文档](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)。

发布脚本的离线流程测试：`python3 Scripts/test-build-app.py`。测试模拟签名及 Apple 工具，覆盖默认临时签名、公证通过、API Key 与 DMG、版本号、公证拒绝/超时、装订失败和参数校验，不会读取凭据或上传应用。

## GitHub 自动发布

推送 `v0.1.0` 格式的 tag 后，GitHub Actions 自动运行测试、编译、正式签名、公证并创建带 ZIP / DMG 和校验文件的 Release。首次需在仓库配置五项 Secrets，详细步骤见 [GitHub 发布配置指南](docs/GITHUB_RELEASE.md)。

Release 成功后自动同步 `cndiandian/homebrew-tap` 中的 IMGX Cask，使用发布 DMG 的精确 SHA-256。需额外设置 `HOMEBREW_TAP_TOKEN`，仅授权 tap 仓库的 Contents 读写权限，配置步骤见同一指南。

## 验收与边界

当前 18 项 Swift 自动化测试覆盖编码、透明通道、EXIF 方向、尺寸规则、导入管理、异步预览、导出快照、失败继续、排他文件保护、画布无障碍操作，以及更新版本比较、Release 来源、校验文件、下载完整性和取消行为。Apple 人机交互检查见 [HIG 检查报告](docs/hig-audit/REPORT.md)。窗口实操及未覆盖事项见 [开发与验收记录](docs/IMPLEMENTATION.md)。

默认构建使用临时签名，仅面向本地开发。已完成本机 Developer ID 正式签名、应用与 DMG 的真实 Apple 公证、票据装订及 Gatekeeper 验证；尚未上架或在另一台 Mac 上验收。不支持动图保留，不承诺 EXIF、ICC、HDR 等信息完整保留。列表和设置不跨启动保存。

[原始 PRD](docs/PRD.md) 中的旧代码基线与已有验证属于历史描述；本仓库从空目录建立，完成情况以本仓库验收记录为准。
