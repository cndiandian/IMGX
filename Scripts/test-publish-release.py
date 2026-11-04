#!/usr/bin/env python3
"""离线验证发布中断恢复和已发布附件保护。"""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import github_api

spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('publish-release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class FakeGitHub:
    def __init__(self, metadata=None):
        self.metadata = metadata
        self.calls = []
        self.interrupt_upload = False
        self.interrupt_publish = False

    def __call__(self, *args):
        self.calls.append(args)
        action = args[1]
        if action == 'view':
            if self.metadata is None:
                raise github_api.GitHubError('release not found')
            return json.dumps(self.metadata)
        if action == 'create':
            self.metadata = {'tagName': args[2], 'isDraft': True, 'assets': []}
        elif action == 'upload':
            if self.interrupt_upload:
                self.interrupt_upload = False
                raise github_api.GitHubError('network timeout')
            self.metadata['assets'] = [
                {'name': Path(value).name, 'state': 'uploaded',
                 'digest': 'sha256:' + release.checksum(Path(value))}
                for value in args[3:] if Path(value).is_file()
            ]
        elif action == 'edit':
            self.metadata['isDraft'] = False
            if self.interrupt_publish:
                self.interrupt_publish = False
                raise github_api.GitHubError('response lost after publishing')
        else:
            raise AssertionError(args)
        return ''


class PublishReleaseTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='imgx-publish-test-')
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        for extension in ('zip', 'dmg'):
            path = self.path / f'IMGX-v0.1.0.{extension}'
            path.write_bytes(f'test {extension} archive'.encode())
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            path.with_name(path.name + '.sha256').write_text(f'{digest}  {path.name}\n')

    def publish(self, command):
        return release.publish('0.1.0', self.path, 'cndiandian/IMGX', command)

    def published(self):
        fake = FakeGitHub()
        self.publish(fake)
        fake.calls.clear()
        return fake

    def test_create_upload_verify_and_publish_in_order(self):
        fake = FakeGitHub()
        self.publish(fake)
        self.assertEqual([call[1] for call in fake.calls], ['view', 'create', 'view', 'upload', 'view', 'edit'])
        self.assertIn('--draft', fake.calls[1])
        self.assertIn('--verify-tag', fake.calls[1])
        self.assertFalse(fake.metadata['isDraft'])
        self.assertEqual(len(fake.metadata['assets']), 4)

    def test_upload_interruption_can_resume_same_draft(self):
        fake = FakeGitHub()
        fake.interrupt_upload = True
        with self.assertRaises(github_api.GitHubError):
            self.publish(fake)
        self.assertTrue(fake.metadata['isDraft'])
        self.assertFalse(any(call[1] == 'edit' for call in fake.calls))
        self.publish(fake)
        self.assertEqual(sum(call[1] == 'create' for call in fake.calls), 1)
        self.assertFalse(fake.metadata['isDraft'])

    def test_lost_publish_response_is_idempotent(self):
        fake = FakeGitHub()
        fake.interrupt_publish = True
        with self.assertRaises(github_api.GitHubError):
            self.publish(fake)
        fake.calls.clear()
        self.publish(fake)
        self.assertEqual([call[1] for call in fake.calls], ['view'])

    def test_matching_published_release_is_read_only(self):
        fake = self.published()
        self.publish(fake)
        self.assertEqual([call[1] for call in fake.calls], ['view'])

    def test_mismatched_published_release_is_not_modified(self):
        fake = self.published()
        fake.metadata['assets'][0]['digest'] = 'sha256:' + '0' * 64
        with self.assertRaises(ValueError):
            self.publish(fake)
        self.assertEqual([call[1] for call in fake.calls], ['view'])

    def test_local_checksum_failure_makes_no_remote_changes(self):
        (self.path / 'IMGX-v0.1.0.dmg').write_bytes(b'corrupt')
        fake = FakeGitHub()
        with self.assertRaises(ValueError):
            self.publish(fake)
        self.assertEqual(fake.calls, [])

    def test_permission_error_is_not_treated_as_missing_release(self):
        calls = []
        def forbidden(*args):
            calls.append(args)
            raise github_api.GitHubError('forbidden', 403)
        with self.assertRaises(github_api.GitHubError):
            self.publish(forbidden)
        self.assertEqual(len(calls), 1)

    def test_incomplete_uploaded_assets_never_publish(self):
        fake = FakeGitHub({'tagName': 'v0.1.0', 'isDraft': True, 'assets': []})
        def incomplete(*args):
            if args[1] == 'upload':
                fake.calls.append(args)
                return ''
            return fake(*args)
        with self.assertRaises(ValueError):
            self.publish(incomplete)
        self.assertTrue(fake.metadata['isDraft'])
        self.assertFalse(any(call[1] == 'edit' for call in fake.calls))


class GitHubCLITests(unittest.TestCase):
    @patch('github_api.subprocess.run')
    def test_http_error_preserves_status(self, run):
        run.return_value = subprocess.CompletedProcess([], 1, '', 'gh: forbidden (HTTP 403)')
        with self.assertRaises(github_api.GitHubError) as result:
            github_api.run_gh('api', 'repos/example/repo')
        self.assertEqual(result.exception.status, 403)

    @patch('github_api.subprocess.run')
    def test_empty_json_payload_is_sent_as_json(self, run):
        run.return_value = subprocess.CompletedProcess([], 0, '{}', '')
        self.assertEqual(github_api.github_api('repos/example/repo', 'PUT', {}), {})
        self.assertEqual(run.call_args.kwargs['input'], '{}')
        self.assertEqual(run.call_args.args[0][-2:], ['--input', '-'])


if __name__ == '__main__':
    unittest.main()
