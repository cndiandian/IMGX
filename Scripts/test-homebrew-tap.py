#!/usr/bin/env python3
"""离线验证 tap 更新和并发保护，不访问 GitHub。"""
import base64
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location('tap', Path(__file__).with_name('update-homebrew-tap.py'))
tap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tap)
CHECKSUM = 'a' * 64


def existing(version, checksum=CHECKSUM, sha='previous-sha'):
    return {'sha': sha, 'content': base64.b64encode(tap.render_cask(version, checksum).encode()).decode()}


class HomebrewTapTests(unittest.TestCase):
    def test_creates_cask_with_exact_checksum_and_requirements(self):
        api = Mock(side_effect=[tap.GitHubError('not found', 404), {}])
        tap.update_tap('0.1.0', CHECKSUM, api)
        payload = api.call_args_list[1].args[1]
        cask = base64.b64decode(payload['content']).decode()
        self.assertNotIn('sha', payload)
        self.assertIn(f'sha256 "{CHECKSUM}"', cask)
        self.assertIn('depends_on arch: :arm64', cask)
        self.assertIn('depends_on macos: :tahoe', cask)
        self.assertIn('IMGX-v#{version}.dmg', cask)
        self.assertIn('app "IMGX.app"', cask)

    def test_updates_using_current_blob_sha(self):
        api = Mock(side_effect=[existing('0.9.0'), {}])
        tap.update_tap('0.10.0', CHECKSUM, api)
        self.assertEqual(api.call_args_list[1].args[1]['sha'], 'previous-sha')

    def test_unchanged_and_older_versions_never_write(self):
        for previous in ['0.1.0', '0.10.0']:
            with self.subTest(previous=previous):
                api = Mock(return_value=existing(previous))
                tap.update_tap('0.1.0', CHECKSUM, api)
                api.assert_called_once_with('GET')

    def test_conflict_reloads_and_preserves_newer_version(self):
        api = Mock(side_effect=[existing('0.1.0'), tap.GitHubError('conflict', 409), existing('0.3.0')])
        tap.update_tap('0.2.0', CHECKSUM, api)
        self.assertEqual([call.args[0] for call in api.call_args_list], ['GET', 'PUT', 'GET'])

    def test_conflict_retries_with_fresh_sha(self):
        api = Mock(side_effect=[existing('0.1.0'), tap.GitHubError('conflict', 409),
                                existing('0.1.1', sha='fresh-sha'), {}])
        tap.update_tap('0.2.0', CHECKSUM, api)
        self.assertEqual(api.call_args_list[-1].args[1]['sha'], 'fresh-sha')

    def test_permission_failure_does_not_create_or_retry(self):
        api = Mock(side_effect=tap.GitHubError('forbidden', 403))
        with self.assertRaises(tap.GitHubError):
            tap.update_tap('0.1.0', CHECKSUM, api)
        api.assert_called_once_with('GET')

    def test_unrecognized_existing_cask_is_preserved(self):
        api = Mock(return_value={'sha': 'x', 'content': base64.b64encode(b'version :latest').decode()})
        with self.assertRaises(ValueError):
            tap.update_tap('0.1.0', CHECKSUM, api)
        api.assert_called_once_with('GET')

    def test_invalid_version_and_checksum_are_rejected(self):
        for version, checksum in [('1.0', CHECKSUM), ('0.1.0-beta', CHECKSUM), ('0.1.0', 'invalid')]:
            with self.subTest(version=version, checksum=checksum):
                with self.assertRaises(ValueError):
                    tap.render_cask(version, checksum)


if __name__ == '__main__':
    unittest.main()
