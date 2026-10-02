#!/usr/bin/env python3
"""Codex의 Waypoint 훅·MCP·스킬을 설치/해제한다. 신뢰 상태는 바꾸지 않는다.

개발용. 기준은 앱 안 설치기(Shared/Integration/Installer/CodexInstallPlanner.swift)이고,
CodexInstallerTests가 같은 입력에서 두 구현의 결과 파일이 같은지 비교한다. 한쪽을 고치면 다른 쪽도 고친다.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time
import tomllib

ROOT = Path(__file__).resolve().parent.parent
BEGIN = '# BEGIN WAYPOINT MCP (managed by install-codex.py)'
END = '# END WAYPOINT MCP'
BLOCK = re.compile(r'^' + re.escape(BEGIN) + r'\n.*?^' + re.escape(END) + r'\n?', re.M | re.S)
EVENTS = ('SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PermissionRequest',
          'SubagentStart', 'SubagentStop', 'Stop', 'Interrupt', 'SessionEnd')


def atomic_write(path, content, mode=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.waypoint-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
        os.chmod(temporary, mode or (path.stat().st_mode & 0o777 if path.exists() else 0o600))
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def json_text(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + '\n'


def is_ours(handler, bridge):
    # 다른 훅이나 임의의 유사 명령을 건드리지 않고 우리가 생성한 명령만 식별한다.
    return handler.get('type') == 'command' and handler.get('command', '').startswith(
        'WAYPOINT_PORT=') and '"' + str(bridge) + '" ' in handler.get('command', '')


def without_ours(hooks, bridge):
    result = {}
    for event, groups in hooks.items():
        kept = []
        for group in groups:
            handlers = [h for h in group.get('hooks', []) if not is_ours(h, bridge)]
            if handlers:
                kept.append(dict(group, hooks=handlers))
        if kept:
            result[event] = kept
    return result


def setup(home, dev=False, remove=False):
    codex_dir = home / '.codex'
    hooks_path = codex_dir / 'hooks.json'
    config_path = codex_dir / 'config.toml'
    integration_dir = codex_dir / 'waypoint'
    bridge = integration_dir / 'waypoint-codex-hook.sh'
    skill_path = home / '.agents' / 'skills' / 'waypoint-tracker' / 'SKILL.md'
    manifest_path = integration_dir / 'install.json'
    # 셸 이중 따옴표 안에 경로를 넣는다. 셸 확장 문자가 있는 홈은 안전하게 처리할 수 있을 때까지 거절한다.
    if any(c in str(home) for c in ('"', '$', '`', '\\', '\n', '\r')):
        raise ValueError('홈 경로에 셸 확장 문자가 있어 설정할 수 없습니다')
    original_hooks = hooks_path.read_text() if hooks_path.exists() else None
    original_config = config_path.read_text() if config_path.exists() else None
    hooks = json.loads(original_hooks or '{}')
    config = tomllib.loads(original_config or '')
    if not isinstance(hooks, dict) or not isinstance(hooks.get('hooks', {}), dict):
        raise ValueError('기존 hooks.json 구조를 확인하세요')
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    skill = (ROOT / 'integration/skills/tracker/SKILL.md').read_text().replace(
        'name: tracker\n', 'name: waypoint-tracker\n', 1)
    old_skill = skill_path.read_text() if skill_path.exists() else None
    old_hash = hashlib.sha256(old_skill.encode()).hexdigest() if old_skill is not None else None
    if not remove and old_skill is not None and old_skill != skill and old_hash != manifest.get('skillHash'):
        raise ValueError('waypoint-tracker 스킬이 이미 있고 직접 수정됨. 기존 파일을 보존합니다')
    port = 47822 if dev else 47821
    url = f'http://127.0.0.1:{port}/mcp'
    cleaned_config = BLOCK.sub('', original_config or '')
    remaining = tomllib.loads(cleaned_config)
    existing = remaining.get('mcp_servers', {}).get('waypoint')
    if not remove and existing is not None and existing != {'url': url}:
        raise ValueError('기존 waypoint MCP 설정이 다릅니다. 기존 설정을 보존합니다')
    installed_hooks = without_ours(hooks.get('hooks', {}), bridge)
    if not remove:
        for event in EVENTS:
            support = 'Waypoint-Dev' if dev else 'Waypoint'
            command = (f'WAYPOINT_PORT={port} '
                       f'WAYPOINT_SUPPORT_DIR="{home}/Library/Application Support/{support}" '
                       f'bash "{bridge}" {event}')
            handler = {'type': 'command', 'command': command, 'timeout': 2}
            if event in ('SessionStart', 'UserPromptSubmit'):
                handler['additionalContextLimit'] = 1500
            group = {'hooks': [handler]}
            installed_hooks.setdefault(event, []).append(group)
        if existing is None:
            cleaned_config = cleaned_config.rstrip() + (
                f'\n\n{BEGIN}\n[mcp_servers.waypoint]\nurl = "{url}"\n{END}\n')
    if installed_hooks:
        hooks['hooks'] = installed_hooks
    else:
        hooks.pop('hooks', None)
    # Validate both final documents before writing anything.
    json.loads(json_text(hooks))
    tomllib.loads(cleaned_config)
    if config.get('features', {}).get('hooks') is False and not remove:
        raise ValueError('Codex 설정에서 features.hooks=false입니다. 훅 사용 설정을 먼저 확인하세요')
    backup = integration_dir / 'backups' / str(time.time_ns())
    backup.mkdir(parents=True, exist_ok=True, mode=0o700)
    for path in (hooks_path, config_path, skill_path, manifest_path,
                 bridge, integration_dir / 'waypoint-hook.sh'):
        if path.exists():
            destination = backup / (path.name + ('.skill' if path == skill_path else ''))
            shutil.copy2(path, destination)
            destination.chmod(0o600)
    try:
        if remove:
            if hooks:
                atomic_write(hooks_path, json_text(hooks))
            elif hooks_path.exists():
                hooks_path.unlink()
            if original_config is not None:
                atomic_write(config_path, cleaned_config)
            if old_hash == manifest.get('skillHash') and skill_path.exists():
                skill_path.unlink()
            # 훅 스크립트와 백업은 남겨 진행 중인 세션이 파일 누락으로 실패하지 않게 한다.
        else:
            atomic_write(integration_dir / 'waypoint-hook.sh',
                         (ROOT / 'integration/hooks/waypoint-hook.sh').read_text(), 0o700)
            atomic_write(bridge, (ROOT / 'integration/codex/waypoint-codex-hook.sh').read_text(), 0o700)
            atomic_write(skill_path, skill)
            atomic_write(config_path, cleaned_config)
            atomic_write(hooks_path, json_text(hooks))
            atomic_write(manifest_path, json_text({'skillHash': hashlib.sha256(skill.encode()).hexdigest(),
                                                 'port': port, 'backup': str(backup)}))
    except Exception:
        # 설정 파일은 설치 전 상태로 되돌려 다음 시작 때 부분 설정이 로드되지 않게 한다.
        for path, original in ((hooks_path, original_hooks), (config_path, original_config), (skill_path, old_skill)):
            if original is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write(path, original)
        raise
    print('Waypoint Codex 연결 해제' if remove else f'Waypoint Codex 연결 준비 → {url}')
    print(f'설정 백업: {backup}')
    if not remove:
        print('Codex를 새로 열고 /hooks에서 Waypoint 훅을 검토·신뢰하세요. /mcp로 연결을 확인하세요.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dev', action='store_true', help='Waypoint Dev(47822)에 연결')
    parser.add_argument('--remove', action='store_true', help='Waypoint가 추가한 설정만 제거')
    parser.add_argument('--home', type=Path, default=Path.home(), help='설정할 사용자 홈(격리 테스트용)')
    args = parser.parse_args()
    try:
        setup(args.home.expanduser().resolve(), dev=args.dev, remove=args.remove)
    except (OSError, ValueError) as error:
        print(f'설치 중단: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
