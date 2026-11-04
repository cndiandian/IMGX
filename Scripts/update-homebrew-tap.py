#!/usr/bin/env python3
"""将已发布 DMG 的精确校验和同步至 Homebrew tap。"""
import base64
import hashlib
import os
from pathlib import Path
import re
import sys
from github_api import GitHubError, github_api

ENDPOINT = 'repos/cndiandian/homebrew-tap/contents/Casks/imgx.rb'


def gh_api(method, payload=None):
    return github_api(ENDPOINT, method, payload)


def version_tuple(version):
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('版本必须为三段数字，如 0.1.0')
    return tuple(map(int, version.split('.')))


def render_cask(version, checksum):
    version_tuple(version)
    if not re.fullmatch(r'[0-9a-f]{64}', checksum):
        raise ValueError('SHA-256 格式不正确')
    return f'''cask "imgx" do
  version "{version}"
  sha256 "{checksum}"

  url "https://github.com/cndiandian/IMGX/releases/download/v#{{version}}/IMGX-v#{{version}}.dmg"
  name "IMGX"
  desc "Local image compression and format conversion"
  homepage "https://github.com/cndiandian/IMGX"

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "IMGX.app"
end
'''


def update_tap(version, checksum, api=gh_api):
    cask = render_cask(version, checksum)
    for attempt in range(3):
        try:
            existing = api('GET')
        except GitHubError as error:
            if error.status != 404:
                raise
            existing = None
        if existing:
            previous_cask = base64.b64decode(existing['content']).decode('utf-8')
            if previous_cask == cask:
                return 'Homebrew Cask 已是当前版本，无需重复提交。'
            match = re.search(r'^\s*version "([0-9]+\.[0-9]+\.[0-9]+)"', previous_cask, re.M)
            if not match:
                raise ValueError('现有 Cask 版本无法识别，停止以免覆盖手动配置。')
            if version_tuple(match[1]) > version_tuple(version):
                return f'跳过旧版本 {version}，Homebrew 已为 {match[1]}。'
        payload = {
            'message': f'chore(cask): 更新 IMGX 至 {version}',
            'content': base64.b64encode(cask.encode()).decode(),
        }
        if existing:
            payload['sha'] = existing['sha']
        try:
            api('PUT', payload)
            return f'已更新 cndiandian/homebrew-tap 的 IMGX 至 {version}。'
        except GitHubError as error:
            if error.status != 409 or attempt == 2:
                raise
            # 内容在读取后被更新，重新读取并检查版本，避免覆盖新发布。
    raise RuntimeError('Homebrew 更新未完成')


def main():
    if len(sys.argv) != 3:
        raise ValueError('用法：python3 Scripts/update-homebrew-tap.py VERSION DMG_PATH')
    version, filename = sys.argv[1:]
    version_tuple(version)
    path = Path(filename)
    if not path.is_file() or path.name != f'IMGX-v{version}.dmg':
        raise ValueError('需要指定该版本的 IMGX-v版本号.dmg 文件')
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    if os.environ.get('TAP_DRY_RUN') == '1':
        print(render_cask(version, digest.hexdigest()), end='')
        return
    if not os.environ.get('GH_TOKEN'):
        raise ValueError('缺少 GH_TOKEN，请配置具有 tap Contents 写权限的 HOMEBREW_TAP_TOKEN')
    print(update_tap(version, digest.hexdigest()))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, RuntimeError, KeyError) as error:
        sys.exit(f'Homebrew 更新失败：{error}')
