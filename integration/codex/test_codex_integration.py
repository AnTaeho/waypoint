#!/usr/bin/env python3
"""임시 홈·임시 서버만 사용해 설치와 Codex 브리지를 검증한다."""
import contextlib
import http.server
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('installer', ROOT / 'scripts/install-codex.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='waypoint codex ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        (self.home / '.codex').mkdir()
        self.config = self.home / '.codex/config.toml'
        self.hooks = self.home / '.codex/hooks.json'
        self.config.write_text('model = "test-model"\n[mcp_servers.other]\nurl = "http://localhost:9999"\n')
        self.other_hook = {'hooks': [{'type': 'command', 'command': 'echo other'}]}
        self.hooks.write_text(json.dumps({'description': 'keep', 'hooks': {'Stop': [self.other_hook]}}))

    def test_install_repeat_dev_and_remove_preserve_other_settings(self):
        original = tomllib.loads(self.config.read_text())
        installer.setup(self.home)
        installer.setup(self.home)
        data = json.loads(self.hooks.read_text())
        self.assertEqual(data['description'], 'keep')
        self.assertEqual(len(data['hooks']['Stop']), 2)
        self.assertIn('PermissionRequest', data['hooks'])
        self.assertNotIn('matcher', data['hooks']['PreToolUse'][-1])
        self.assertEqual(data['hooks']['Stop'][0], self.other_hook)
        self.assertEqual(tomllib.loads(self.config.read_text())['mcp_servers']['waypoint']['url'], 'http://127.0.0.1:47821/mcp')
        installer.setup(self.home, dev=True)
        self.assertEqual(tomllib.loads(self.config.read_text())['mcp_servers']['waypoint']['url'], 'http://127.0.0.1:47822/mcp')
        for groups in json.loads(self.hooks.read_text())['hooks'].values():
            for group in groups:
                for hook in group['hooks']:
                    if 'waypoint-codex-hook' in hook['command']:
                        self.assertIn('WAYPOINT_PORT=47822', hook['command'])
                        self.assertNotIn('bypass-hook-trust', hook['command'])
        installer.setup(self.home, remove=True)
        self.assertEqual(tomllib.loads(self.config.read_text()), original)
        self.assertEqual(json.loads(self.hooks.read_text())['hooks'], {'Stop': [self.other_hook]})
        self.assertFalse((self.home / '.agents/skills/waypoint-tracker/SKILL.md').exists())
        self.assertTrue(list((self.home / '.codex/waypoint/backups').iterdir()))

    def test_conflicting_mcp_is_not_overwritten(self):
        self.config.write_text('[mcp_servers.waypoint]\nurl = "https://example.com/private"\n')
        before = self.config.read_bytes(), self.hooks.read_bytes()
        with self.assertRaises(ValueError):
            installer.setup(self.home)
        self.assertEqual((self.config.read_bytes(), self.hooks.read_bytes()), before)
        self.assertFalse((self.home / '.codex/waypoint').exists())

    def test_existing_same_mcp_is_retained_on_remove(self):
        self.config.write_text('[mcp_servers.waypoint]\nurl = "http://127.0.0.1:47821/mcp"\n')
        before = self.config.read_text()
        installer.setup(self.home)
        installer.setup(self.home, remove=True)
        self.assertEqual(self.config.read_text(), before)

    def test_invalid_config_and_disabled_hooks_do_not_write(self):
        for content in ('not valid TOML', '[features]\nhooks = false\n'):
            self.config.write_text(content)
            before = self.config.read_bytes(), self.hooks.read_bytes()
            with self.assertRaises(ValueError):
                installer.setup(self.home)
            self.assertEqual((self.config.read_bytes(), self.hooks.read_bytes()), before)

    def test_edited_skill_is_retained(self):
        installer.setup(self.home)
        skill = self.home / '.agents/skills/waypoint-tracker/SKILL.md'
        skill.write_text(skill.read_text() + '\n사용자 메모\n')
        with self.assertRaises(ValueError):
            installer.setup(self.home)
        installer.setup(self.home, remove=True)
        self.assertIn('사용자 메모', skill.read_text())


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='waypoint codex ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = dict(os.environ, WAYPOINT_SUPPORT_DIR=str(self.home / 'support'))
        self.hook = ROOT / 'integration/codex/waypoint-codex-hook.sh'
        self.payload = {'session_id': 'thread-1', 'cwd': '/tmp/project', 'prompt': '작업 시작'}

    @contextlib.contextmanager
    def server(self, status=200, delay=0, context_id=None):
        requests = []
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(inner):
                data = inner.rfile.read(int(inner.headers.get('Content-Length', 0)))
                requests.append((inner.path, dict(inner.headers), json.loads(data)))
                if inner.path == '/hooks/ack':
                    inner.send_response(204)
                    inner.end_headers()
                    return
                time.sleep(delay)
                body = 'Waypoint: TST (테스트)\nsessionId: codex:thread-1'.encode()
                inner.send_response(status)
                if context_id and status == 200:
                    inner.send_header('X-Waypoint-Context-ID', context_id)
                inner.send_header('Content-Length', str(len(body)) if status != 204 else '0')
                inner.end_headers()
                if status != 204:
                    try:
                        inner.wfile.write(body)
                    except BrokenPipeError:
                        pass
            def log_message(self, *args):
                pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.env['WAYPOINT_PORT'] = str(server.server_port)
        try:
            yield requests
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def run_hook(self, event, payload=None):
        return subprocess.run(['bash', str(self.hook), event], input=json.dumps(payload or self.payload),
                              text=True, capture_output=True, env=self.env, timeout=4)

    def test_context_only_for_start_and_late_prompt(self):
        with self.server() as requests:
            for event in ('SessionStart', 'UserPromptSubmit', 'PostToolUse', 'Stop', 'SubagentStop', 'SessionEnd'):
                result = self.run_hook(event)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stderr, '')
                self.assertEqual(bool(result.stdout), event in ('SessionStart', 'UserPromptSubmit'))
            self.assertTrue(all(path.startswith('/hooks/codex/') for path, _, _ in requests))
            self.assertTrue(all(payload == self.payload for _, _, payload in requests))
        self.assertFalse((self.home / 'support/outbox.jsonl').exists())

    def test_204_has_no_context_or_outbox(self):
        with self.server(status=204):
            result = self.run_hook('UserPromptSubmit')
            self.assertEqual(result.stdout, '')
        self.assertFalse((self.home / 'support/outbox.jsonl').exists())

    def test_context_ack_after_output_only(self):
        context_id = '0f1e2d3c-4b5a-6978-8a9b-acbdcedf0123'
        with self.server(context_id=context_id) as requests:
            for event in ('SessionStart', 'UserPromptSubmit', 'Stop'):
                result = self.run_hook(event)
                self.assertEqual(result.returncode, 0)
            acks = [payload for path, _, payload in requests if path == '/hooks/ack']
            self.assertEqual(acks, [{'contextId': context_id}] * 2)
            hooks = {path: headers for path, headers, _ in requests if path != '/hooks/ack'}
            self.assertEqual(hooks['/hooks/codex/SessionStart'].get('X-Waypoint-Context-Ack'), '1')
            self.assertEqual(hooks['/hooks/codex/UserPromptSubmit'].get('X-Waypoint-Context-Ack'), '1')
            self.assertNotIn('X-Waypoint-Context-Ack', hooks['/hooks/codex/Stop'])
        self.assertFalse((self.home / 'support/outbox.jsonl').exists())

    def test_context_timeout_sends_no_ack(self):
        with self.server(delay=2, context_id='0f1e2d3c-4b5a-6978-8a9b-acbdcedf0123') as requests:
            result = self.run_hook('SessionStart')
            self.assertEqual((result.returncode, result.stdout), (0, ''))
            self.assertFalse([path for path, _, _ in requests if path == '/hooks/ack'])

    def test_failure_buffers_trimmed_with_provider(self):
        with self.server(status=503):
            result = self.run_hook('Stop')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        data = json.loads((self.home / 'support/outbox.jsonl').read_text())
        self.assertEqual(data['provider'], 'codex')
        self.assertEqual(data['payload'], self.payload)  # 세 필드 모두 앱이 읽는 필드라 그대로 남는다
        self.assertTrue(data['trimmed'])
        self.assertEqual(data['event'], 'Stop')
        self.assertNotIn('claudePid', data)

    def test_timeout_does_not_block_agent(self):
        with self.server(delay=2):
            start = time.monotonic()
            result = self.run_hook('Stop')
            self.assertLess(time.monotonic() - start, 2)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')
        self.assertTrue((self.home / 'support/outbox.jsonl').exists())

    def test_codex_ancestor_pid_header(self):
        fake = self.home / 'codex'
        fake.symlink_to('/bin/bash')
        with self.server() as requests:
            result = subprocess.run([str(fake), '-c', 'echo $$ > "$1"; bash "$2" Stop; true',
                                     '_', str(self.home / 'pid'), str(self.hook)],
                                    input=json.dumps(self.payload), text=True, capture_output=True,
                                    env=self.env, timeout=4)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(requests[0][1]['X-Waypoint-Process-PID'], (self.home / 'pid').read_text().strip())
            self.assertNotIn('X-Waypoint-Claude-PID', requests[0][1])

    def test_native_claude_version_ancestor_pid(self):
        native = self.home / '.local/share/claude/versions/2.1.285'
        native.parent.mkdir(parents=True)
        native.symlink_to('/bin/bash')
        hook = ROOT / 'integration/hooks/waypoint-hook.sh'
        env = dict(self.env, WAYPOINT_AGENT='claude')
        with self.server() as requests:
            env['WAYPOINT_PORT'] = self.env['WAYPOINT_PORT']
            result = subprocess.run([str(native), '-c', 'echo $$ > "$1"; bash "$2" Stop; true',
                                     '_', str(self.home / 'pid'), str(hook)],
                                    input=json.dumps(self.payload), text=True, capture_output=True,
                                    env=env, timeout=4)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(requests[0][0], '/hooks/Stop')
            self.assertEqual(requests[0][1]['X-Waypoint-Claude-PID'], (self.home / 'pid').read_text().strip())
        env['WAYPOINT_PORT'] = '1'
        subprocess.run([str(native), '-c', 'echo $$ > "$1"; bash "$2" Stop; true',
                        '_', str(self.home / 'pid'), str(hook)], input=json.dumps(self.payload),
                       text=True, capture_output=True, env=env, timeout=4, check=True)
        record = json.loads((self.home / 'support/outbox.jsonl').read_text())
        self.assertEqual(record['claudePid'], int((self.home / 'pid').read_text()))


if __name__ == '__main__':
    unittest.main()
