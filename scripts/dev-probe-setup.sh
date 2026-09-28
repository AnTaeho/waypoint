#!/bin/bash
# 실측 폴더 하나를 개발용 Waypoint Dev(47822)에 잇는다. 그 폴더 안의 프로젝트 설정만 쓴다(전역 설정은 건드리지 않는다).
#   <폴더>/.claude/settings.local.json  전역 Waypoint 훅과 같은 이벤트·matcher로, 포트·저장 폴더만 Dev로 바꾼 훅
#                                       + enabledMcpjsonServers: ["waypoint"](대화형에서 승인 묻지 않게)
#   <폴더>/.mcp.json                    이름 `waypoint` → http://127.0.0.1:47822/mcp
#                                       (같은 이름이면 프로젝트 범위가 사용자 범위보다 먼저라 도구 이름 mcp__waypoint__*가 Dev로 간다)
# 전역 훅도 함께 불리므로 이 폴더는 평소용 Waypoint에 등록하지 않는다(평소용은 미등록 폴더의 기록을 버린다).
#
# 사용: scripts/dev-probe-setup.sh <폴더>           설정을 쓴다(여러 번 돌려도 같은 결과)
#       scripts/dev-probe-setup.sh --remove <폴더>  이 스크립트가 쓴 항목만 지운다
# 환경 변수: WAYPOINT_USER_SETTINGS  훅을 베낄 사용자 설정(기본 ~/.claude/settings.json)
set -euo pipefail

mode=setup
if [ "${1:-}" = "--remove" ]; then mode=remove; shift; fi
[ $# -eq 1 ] || { echo "사용: $0 [--remove] <폴더>" >&2; exit 1; }
dir="$(cd "$1" 2>/dev/null && pwd)" || { echo "폴더가 없음: $1" >&2; exit 1; }
case "$dir" in
  "$HOME"|"$HOME/.claude"|/) echo "이 폴더에는 쓰지 않음: $dir" >&2; exit 1 ;;
esac

/usr/bin/python3 - "$mode" "$dir" "${WAYPOINT_USER_SETTINGS:-$HOME/.claude/settings.json}" <<'PY'
import json, os, sys

mode, root, user_settings = sys.argv[1], sys.argv[2], sys.argv[3]
PORT = 47822
ENV = 'WAYPOINT_PORT=%d WAYPOINT_SUPPORT_DIR="$HOME/Library/Application Support/Waypoint-Dev" ' % PORT
HOOK = "waypoint-hook.sh"
MARK = "WAYPOINT_PORT=%d" % PORT
URL = "http://127.0.0.1:%d/mcp" % PORT

def load(path):
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)

def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)

def strip_ours(hooks):
    """이 스크립트가 넣은 훅(명령에 WAYPOINT_PORT=47822)을 뺀다. 빈 그룹·이벤트도 지운다."""
    out = {}
    for event, groups in hooks.items():
        kept = []
        for g in groups:
            hs = [h for h in g.get("hooks", []) if MARK not in h.get("command", "")]
            if hs:
                kept.append(dict(g, hooks=hs))
        if kept:
            out[event] = kept
    return out

settings_path = os.path.join(root, ".claude", "settings.local.json")
mcp_path = os.path.join(root, ".mcp.json")
settings = load(settings_path)
mcp = load(mcp_path)

hooks = strip_ours(settings.get("hooks", {}))
servers = dict(mcp.get("mcpServers", {}))
enabled = [s for s in settings.get("enabledMcpjsonServers", []) if s != "waypoint"]

if mode == "setup":
    src = load(user_settings).get("hooks", {})
    count = 0
    for event, groups in src.items():
        for g in groups:
            ours = []
            for h in g.get("hooks", []):
                cmd = h.get("command", "")
                if HOOK in cmd and MARK not in cmd:
                    ours.append(dict(h, command=ENV + cmd))
            if ours:
                group = {k: v for k, v in g.items() if k != "hooks"}
                group["hooks"] = ours
                hooks.setdefault(event, []).append(group)
                count += 1
    if count == 0:
        sys.exit("사용자 설정에 %s 훅이 없음: %s" % (HOOK, user_settings))
    servers["waypoint"] = {"type": "http", "url": URL}
    enabled.append("waypoint")
    print("훅 %d개(이벤트 %d) → 127.0.0.1:%d, MCP waypoint → %s" % (count, len(hooks), PORT, URL))
else:
    if servers.get("waypoint", {}).get("url") == URL:
        del servers["waypoint"]
    print("Dev 훅·MCP 항목을 지움")

if hooks:
    settings["hooks"] = hooks
else:
    settings.pop("hooks", None)
if enabled:
    settings["enabledMcpjsonServers"] = enabled
else:
    settings.pop("enabledMcpjsonServers", None)
if servers:
    mcp["mcpServers"] = servers
else:
    mcp.pop("mcpServers", None)

for path, data in ((settings_path, settings), (mcp_path, mcp)):
    if data:
        save(path, data)
    elif os.path.exists(path):
        os.remove(path)
claude_dir = os.path.join(root, ".claude")
if os.path.isdir(claude_dir) and not os.listdir(claude_dir):
    os.rmdir(claude_dir)
print(root)
PY
