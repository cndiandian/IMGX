#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# 与参考项目使用相同的环境变量；不读取或保存私钥内容。
: "${CODE_SIGN_IDENTITY:=${IMGX_SIGN_IDENTITY:-}}"
: "${CODE_SIGN_IDENTITY:?请设置 CODE_SIGN_IDENTITY 为 Developer ID 证书名称或 SHA-1}"
export CODE_SIGN_IDENTITY
bash Scripts/build-app.sh release --notarize --dmg "$@"
