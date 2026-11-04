#!/usr/bin/env python3
"""离线检查发布流程控制；不访问钥匙串、不上传 Apple、不代替真实签名验收。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['MOCK_LOG'], 'a') as stream:
    stream.write(json.dumps([name] + args) + '\n')
if name == 'swift' and '--show-bin-path' in args:
    print(os.environ['MOCK_BIN'])
elif name == 'iconutil':
    pathlib.Path(args[args.index('-o') + 1]).touch()
elif name == 'ditto':
    pathlib.Path(args[-1]).touch()
elif name == 'xcrun':
    if args[0] == '--find':
        print('/mock/' + args[1])
    elif args[:2] == ['notarytool', 'submit']:
        print(json.dumps({'id': 'test-submission', 'status': os.environ['MOCK_STATUS']}))
        sys.exit(int(os.environ.get('MOCK_SUBMIT_EXIT', '0')))
    elif args[:2] == ['notarytool', 'log']:
        pathlib.Path(args[-1]).write_text('{}')
    elif args[:2] == ['stapler', 'staple']:
        sys.exit(int(os.environ.get('MOCK_STAPLE_EXIT', '0')))
'''


class BuildScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='imgx-build-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'Scripts').mkdir()
        shutil.copy(Path(__file__).with_name('build-app.sh'), self.root / 'Scripts')
        shutil.copy(Path(__file__).with_name('Info.plist'), self.root / 'Scripts')
        license_path = self.root / 'Vendor/WebP/LICENSE'
        license_path.parent.mkdir(parents=True)
        license_path.write_text('test license')
        self.bin = self.root / 'tools'
        self.bin.mkdir()
        (self.bin / 'IMGX').write_text('test executable')
        stub = self.bin / 'stub'
        stub.write_text(STUB)
        stub.chmod(0o755)
        for name in ['swift', 'iconutil', 'codesign', 'ditto', 'xcrun', 'spctl']:
            (self.bin / name).symlink_to(stub)
        self.log = self.root / 'calls.jsonl'

    def run_build(self, args, **overrides):
        env = os.environ.copy()
        env.pop('IMGX_SIGN_IDENTITY', None)
        env.pop('IMGX_NOTARY_PROFILE', None)
        env.update(PATH=f'{self.bin}:{env["PATH"]}', MOCK_BIN=str(self.bin),
                   MOCK_LOG=str(self.log), MOCK_STATUS='Accepted')
        env.update(overrides)
        return subprocess.run(['bash', 'Scripts/build-app.sh', *args], cwd=self.root,
                              env=env, capture_output=True, text=True, errors='replace')

    def publish(self, **overrides):
        return self.run_build(['--sign', 'Developer ID Application: Test (TEAM)',
                               '--notarize', '--profile', 'Test Profile'], **overrides)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_default_is_adhoc_without_upload(self):
        result = self.run_build(['debug'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(['codesign', '--force', '--sign', '-', 'dist/IMGX.app'], self.calls())
        self.assertFalse(any(call[0] == 'xcrun' for call in self.calls()))

    def test_accepted_staples_validates_then_archives(self):
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        sign = next(c for c in calls if c[:3] == ['codesign', '--force', '--sign'])
        self.assertIn('runtime', sign)
        self.assertIn('--timestamp', sign)
        staple = next(i for i, c in enumerate(calls) if c[:3] == ['xcrun', 'stapler', 'staple'])
        validate = next(i for i, c in enumerate(calls) if c[:3] == ['xcrun', 'stapler', 'validate'])
        gatekeeper = next(i for i, c in enumerate(calls) if c[0] == 'spctl')
        self.assertLess(staple, validate)
        self.assertLess(validate, gatekeeper)
        self.assertEqual(calls[-1][0], 'ditto')
        self.assertEqual(len(list(self.root.glob('dist/notarization.*/IMGX.zip'))), 1)

    def test_rejected_or_timeout_never_creates_distribution(self):
        for status, code in [('Invalid', '0'), ('In Progress', '69')]:
            with self.subTest(status=status):
                result = self.publish(MOCK_STATUS=status, MOCK_SUBMIT_EXIT=code)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(list(self.root.glob('dist/notarization.*/IMGX.zip')))
        self.assertFalse(any(c[:2] == ['xcrun', 'stapler'] for c in self.calls()))

    def test_stapling_failure_never_creates_distribution(self):
        self.assertNotEqual(self.publish(MOCK_STAPLE_EXIT='1').returncode, 0)
        self.assertFalse(list(self.root.glob('dist/notarization.*/IMGX.zip')))

    def test_invalid_options_fail_before_build(self):
        for args in [['--notarize'], ['--sign'], ['--unknown'],
                     ['debug', 'release'], ['--timeout', '0m'],
                     ['debug', '--sign', 'Test', '--notarize', '--profile', 'Test']]:
            with self.subTest(args=args):
                self.assertNotEqual(self.run_build(args).returncode, 0)
                self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
