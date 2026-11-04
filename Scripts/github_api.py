"""发布脚本共享的 GitHub CLI 调用与错误处理。"""
import json
import re
import subprocess


class GitHubError(RuntimeError):
    def __init__(self, message, status=None):
        super().__init__(message)
        self.status = status


def run_gh(*arguments, input_text=None):
    result = subprocess.run(['gh', *arguments], input=input_text, text=True, capture_output=True)
    if result.returncode:
        match = re.search(r'HTTP (\d{3})', result.stderr)
        raise GitHubError(result.stderr.strip(), int(match[1]) if match else None)
    return result.stdout


def github_api(endpoint, method='GET', payload=None):
    arguments = ['api', '--method', method, endpoint]
    if payload is not None:
        arguments += ['--input', '-']
    return json.loads(run_gh(*arguments, input_text=json.dumps(payload) if payload is not None else None))
