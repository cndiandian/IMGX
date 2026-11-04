#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    cat <<'HELP'
用法：bash Scripts/build-app.sh [release|debug] [选项]

默认：Release 构建及本地临时签名。
  --sign IDENTITY       使用 Developer ID Application 证书名称或 SHA-1 签名
  --notarize            提交 Apple 公证，装订票据并生成分发 ZIP（仅 Release）
  --profile NAME        notarytool 钥匙串凭据名称
  --timeout DURATION    等待公证的时限，默认 30m
  --dmg                 公证通过后额外生成并公证 DMG 安装镜像
  -h, --help            显示帮助

环境变量：IMGX_SIGN_IDENTITY（或 CODE_SIGN_IDENTITY）、IMGX_NOTARY_PROFILE。
也支持参考项目的 APP_STORE_CONNECT_API_KEY_PATH / KEY_ID / ISSUER_ID，
以及 APP_VERSION、BUILD_NUMBER；API Key 与钥匙串凭据二选一。
示例：
  bash Scripts/build-app.sh debug
  bash Scripts/build-app.sh --sign 'Developer ID Application: 姓名 (TEAMID)'
  bash Scripts/build-app.sh --sign '证书名称或 SHA-1' --notarize --profile IMGX
HELP
}
fail() { echo "错误：$*" >&2; exit 1; }
configuration=release
identity="${IMGX_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
profile="${IMGX_NOTARY_PROFILE:-}"
notarize=false
dmg=false
app_version="${APP_VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
timeout=30m
configuration_set=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        release|debug)
            [[ "$configuration_set" == false ]] || fail "只能指定一个构建配置。"
            configuration="$1"; configuration_set=true; shift ;;
        --sign|--profile|--timeout)
            [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail "$1 缺少参数。"
            case "$1" in
                --sign) identity="$2" ;;
                --profile) profile="$2" ;;
                --timeout) timeout="$2" ;;
            esac
            shift 2 ;;
        --notarize) notarize=true; shift ;;
        --dmg) dmg=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "未知参数：$1；使用 --help 查看用法。" ;;
    esac
done
[[ -n "$identity" ]] || fail "签名身份不能为空。"
[[ "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "APP_VERSION 应为三段数字，如 0.1.0。"
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail "BUILD_NUMBER 应为正整数。"
[[ "$timeout" =~ ^[1-9][0-9]*[smh]?$ ]] || fail "等待时限应为正整数及可选单位 s、m、h。"
[[ "$dmg" == false || "$notarize" == true ]] || fail "--dmg 需要同时启用 --notarize。"
notary_auth=()
if [[ "$notarize" == true ]]; then
    [[ "$configuration" == release ]] || fail "公证必须使用 Release 构建。"
    [[ "$identity" != - ]] || fail "公证需要 --sign 指定 Developer ID Application 证书。"
    if [[ -n "$profile" ]]; then
        [[ -z "${APP_STORE_CONNECT_API_KEY_PATH:-}${APP_STORE_CONNECT_API_KEY_ID:-}${APP_STORE_CONNECT_API_ISSUER_ID:-}" ]] || fail "钥匙串凭据与 API Key 不能同时指定。"
        notary_auth=(--keychain-profile "$profile")
    else
        [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" && -n "${APP_STORE_CONNECT_API_KEY_ID:-}" ]] || fail "公证需要钥匙串凭据，或 API Key 文件路径及 Key ID。"
        [[ -s "$APP_STORE_CONNECT_API_KEY_PATH" ]] || fail "API Key 文件不存在或为空。"
        notary_auth=(--key "$APP_STORE_CONNECT_API_KEY_PATH" --key-id "$APP_STORE_CONNECT_API_KEY_ID")
        if [[ -n "${APP_STORE_CONNECT_API_ISSUER_ID:-}" ]]; then
            notary_auth+=(--issuer "$APP_STORE_CONNECT_API_ISSUER_ID")
        fi
    fi
    xcrun --find notarytool >/dev/null
    xcrun --find stapler >/dev/null
fi

swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="dist/IMGX.app"
# 每次重新创建应用，避免旧签名、公证票据及资源混入新构建。
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swift Scripts/generate-icon.swift dist/AppIcon.iconset
iconutil -c icns dist/AppIcon.iconset -o "$app/Contents/Resources/IMGX.icns"
cp Vendor/WebP/LICENSE "$app/Contents/Resources/WebP-LICENSE.txt"
cp "$binary_dir/IMGX" "$app/Contents/MacOS/IMGX"
cp Scripts/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$app_version" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
if [[ "$identity" == - ]]; then
    codesign --force --sign - "$app"
else
    codesign --force --sign "$identity" --options runtime --timestamp "$app"
fi
codesign --verify --deep --strict "$app"
echo "应用已生成：$PWD/$app"

submit_for_notarization() {
    local archive="$1" label="$2" submit_exit=0 submission_id status
    local result="$submission_dir/${label}-result.json"
    xcrun notarytool submit "$archive" "${notary_auth[@]}" \
        --wait --timeout "$timeout" --output-format json > "$result" || submit_exit=$?
    submission_id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
    if [[ -n "$submission_id" ]]; then
        echo "公证提交 ID：${submission_id}；状态：${status:-未知}"
        if ! xcrun notarytool log "$submission_id" "${notary_auth[@]}" "$submission_dir/${label}-log.json"; then
            echo "未能下载日志，可稍后使用 notarytool log 和上述提交 ID 重试。" >&2
        fi
    fi
    if [[ "$submit_exit" != 0 || "$status" != Accepted ]]; then
        echo "可通过 xcrun notarytool info / wait 查询或继续等待上述提交。" >&2
        fail "公证未确认通过，请检查 $result 和日志。Apple 端可能仍在处理。"
    fi
}

retry_ticket_operation() {
    local attempt exit_code
    for attempt in 1 2 3 4; do
        if "$@"; then return 0; else exit_code=$?; fi
        if [[ "$attempt" == 4 ]]; then return "$exit_code"; fi
        echo "票据服务暂未成功，$((attempt * 2)) 秒后重试。" >&2
        sleep "$((attempt * 2))"
    done
}

write_checksum() {
    local archive="$1"
    (cd "$(dirname "$archive")" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
}

if [[ "$notarize" == true ]]; then
    # 独立目录保留每次提交的结果，失败时不会将未公证 ZIP 当成分发产物。
    submission_dir="$(mktemp -d "$PWD/dist/notarization.XXXXXX")"
    upload_zip="$submission_dir/IMGX-upload.zip"
    ditto -c -k --keepParent --sequesterRsrc "$app" "$upload_zip"
    echo "提交 Apple 公证，结果目录：$submission_dir"
    submit_for_notarization "$upload_zip" app
    retry_ticket_operation xcrun stapler staple "$app"
    retry_ticket_operation xcrun stapler validate "$app"
    codesign --verify --deep --strict "$app"
    spctl --assess --type execute --verbose=2 "$app"
    # 重新压缩已经装订票据的应用，供离线校验和分发。
    release_zip="$submission_dir/IMGX-v${app_version}.zip"
    ditto -c -k --keepParent --sequesterRsrc "$app" "$release_zip"
    write_checksum "$release_zip"
    echo "签名、公证和装订检查通过，分发文件：$release_zip"
    if [[ "$dmg" == true ]]; then
        dmg_stage="$(mktemp -d "$PWD/dist/dmg-stage.XXXXXX")"
        trap 'rm -rf "$dmg_stage"' EXIT
        ditto "$app" "$dmg_stage/IMGX.app"
        ln -s /Applications "$dmg_stage/Applications"
        dmg_path="$submission_dir/IMGX-v${app_version}.dmg"
        hdiutil create -volname IMGX -srcfolder "$dmg_stage" -format UDZO "$dmg_path"
        codesign --force --sign "$identity" --timestamp "$dmg_path"
        submit_for_notarization "$dmg_path" dmg
        retry_ticket_operation xcrun stapler staple "$dmg_path"
        retry_ticket_operation xcrun stapler validate "$dmg_path"
        codesign --verify --strict "$dmg_path"
        spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
        write_checksum "$dmg_path"
        echo "DMG 签名、公证和装订检查通过：$dmg_path"
    fi
fi
