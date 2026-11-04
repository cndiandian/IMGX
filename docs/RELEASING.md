# IMGX 发布步骤

参考项目：`2026-10-09-pod-mini-player/scripts/build.sh` 和 `scripts/release.sh`。沿用 `CODE_SIGN_IDENTITY`、`APP_STORE_CONNECT_API_KEY_PATH`、`APP_STORE_CONNECT_API_KEY_ID`、`APP_STORE_CONNECT_API_ISSUER_ID`、`APP_VERSION`、`BUILD_NUMBER` 配置。

2026-11-04 已在当前机器完成本地 `.release.env` 配置，真实执行应用及 DMG 公证成功，日志无问题，票据和 Gatekeeper 检查通过。当前机器可以直接从第 4 步开始；第 1～3 步供更换机器或凭据时参考。

## 1. 检查构建工具和证书

在项目根目录打开终端：

```sh
xcode-select -p
swift --version
security find-identity -v -p codesigning
```

应使用完整 Xcode，并有带私钥的 Developer ID Application 证书。当前本机已确认存在 Team ID 为 `8T4S63Q2KK` 的证书，且 IMGX 正式签名及时间戳验证通过，不需要重复申请证书。

## 2. 准备 API Key 配置

```sh
cp Scripts/release.env.example .release.env
```

编辑根目录 `.release.env`，填入实际证书名称、`.p8` 文件路径、Key ID、Issuer ID。使用本机已下载的 `AuthKey_KEYID.p8` 文件；文件只在本机由 Apple 工具读取，无需复制私钥到项目。若本机配置已完成，直接进入第 4 步，不要再次覆盖配置文件。

团队 API Key 的 Issuer ID 可在 [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api) 的“用户和访问 → 集成 → App Store Connect API → 团队密钥”查看。它是 UUID 格式的标识，不是括号里的 Team ID。个人 API Key 不使用 Issuer ID，应删除配置中对应的 export 行。

`.release.env`、`.p8` 和 `.p12` 已加入 Git 忽略规则。参考项目的 GitHub Secrets 仅能更新、不能读取原值，应从 Apple 页面取得标识及本机已有文件。

## 3. 先编译并正式签名

```sh
source .release.env
bash Scripts/build-app.sh release --sign "$CODE_SIGN_IDENTITY"
codesign --verify --deep --strict --verbose=2 dist/IMGX.app
```

此步骤不会上传公证。输出应用为 `dist/IMGX.app`。若 macOS 提示访问证书私钥，请确认是本次 `codesign` 操作，并在系统窗口自行完成授权。

## 4. 一键发布

```sh
source .release.env
bash Scripts/release.sh
```

依次执行：Release 编译 → 正式签名和时间戳 → 上传应用 ZIP 并等待 Apple 公证 → 装订和验证应用票据 → Gatekeeper 检查 → 生成 ZIP 及 SHA-256 → 生成 DMG → 签名、公证、装订和验证 DMG → 生成 DMG 的 SHA-256。

票据服务临时失败时最多尝试 4 次，最终未通过仍返回失败。默认每次公证最多等待 30 分钟，可用 `bash Scripts/release.sh --timeout 60m` 调整。脚本不发布到 GitHub，不更新 Homebrew，也不会创建新密钥或修改开发者账户。

## 5. 检查产物

脚本全部成功后，在它最后打印的 `dist/notarization.XXXXXX/` 目录中取得：

- `IMGX-v0.1.0.zip` 和 `IMGX-v0.1.0.zip.sha256`。
- `IMGX-v0.1.0.dmg` 和 `IMGX-v0.1.0.dmg.sha256`。
- `app-result.json`、`app-log.json`、`dmg-result.json`、`dmg-log.json`，用于查阅公证结果。

应用与镜像分别公证，只有两项都完成才视为整次发布成功。版本号随 `APP_VERSION` 变化。可进入产物目录执行 `shasum -a 256 -c IMGX-v0.1.0.zip.sha256` 和对应 DMG 命令验证下载文件完整性。

超时不代表 Apple 已取消处理。保存结果中的提交 ID，通过 `xcrun notarytool info` / `wait` / `log` 加上相同认证参数查询；不要把未通过整套流程的中间文件当成最终产物。详细命令及钥匙串替代方案见项目 README。
