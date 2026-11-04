#!/usr/bin/env python3
"""校验全部产物后发布 Release；失败重跑时续传草稿，不改写已发布附件。"""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from github_api import GitHubError, run_gh


def checksum(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def artifacts(version, directory):
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('发布版本必须为三段数字')
    files = {}
    for extension in ('zip', 'dmg'):
        name = f'IMGX-v{version}.{extension}'
        archive = directory / name
        checksum_file = directory / f'{name}.sha256'
        if not archive.is_file() or archive.stat().st_size == 0:
            raise ValueError(f'缺少有效发布文件：{name}')
        digest = checksum(archive)
        fields = checksum_file.read_text().split()
        if fields != [digest, name]:
            raise ValueError(f'发布文件校验失败：{name}')
        files[name] = digest
        files[checksum_file.name] = checksum(checksum_file)
    return files


def release_info(tag, repository, command):
    try:
        output = command('release', 'view', tag, '--repo', repository,
                         '--json', 'tagName,isDraft,assets')
    except GitHubError as error:
        if error.status == 404 or str(error) == 'release not found':
            return None
        raise
    release = json.loads(output)
    if release['tagName'] != tag:
        raise ValueError('远程 Release 的 tag 与当前发布版本不一致')
    return release


def verify_remote(release, expected):
    assets = {asset['name']: asset for asset in release['assets']}
    for name, digest in expected.items():
        asset = assets.get(name)
        if not asset or asset.get('state') != 'uploaded' or asset.get('digest') != f'sha256:{digest}':
            raise ValueError(f'远程发布附件缺失或校验不一致：{name}；停止以免覆盖已发布文件')


def publish(version, directory, repository, command=run_gh):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('GH_REPO 必须为 owner/repo')
    expected = artifacts(version, directory)
    tag = f'v{version}'
    release = release_info(tag, repository, command)
    if release is None:
        command('release', 'create', tag, '--repo', repository, '--draft',
                '--verify-tag', '--generate-notes', '--title', f'IMGX {tag}')
        release = release_info(tag, repository, command)
        if release is None:
            raise ValueError('创建后未找到 Release 草稿，请稍后重试')
    if not release['isDraft']:
        verify_remote(release, expected)
        return f'{tag} 已发布且附件一致，无需重复发布。'
    paths = [str(directory / name) for name in expected]
    command('release', 'upload', tag, *paths, '--repo', repository, '--clobber')
    # 草稿完成全部附件上传、校验后才公开，避免更新检测读到半成品。
    release = release_info(tag, repository, command)
    if release is None:
        raise ValueError('上传后未找到 Release 草稿，请稍后重试')
    verify_remote(release, expected)
    command('release', 'edit', tag, '--repo', repository, '--draft=false')
    return f'已发布 {tag}，全部附件校验通过。'


if __name__ == '__main__':
    try:
        if len(sys.argv) != 3:
            raise ValueError('用法：python3 Scripts/publish-release.py VERSION ASSETS_DIRECTORY')
        repository = os.environ.get('GH_REPO', '')
        if not os.environ.get('GH_TOKEN'):
            raise ValueError('缺少 GH_TOKEN')
        print(publish(sys.argv[1], Path(sys.argv[2]), repository))
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        sys.exit(f'Release 发布失败：{error}')
