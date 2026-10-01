#!/bin/bash
# Codex의 원본 훅을 공통 브리지로 보낸다. 항상 exit 0, 추적 때문에 Codex를 막지 않는다.
HERE="$(cd "$(dirname "$0")" && pwd)"
export WAYPOINT_AGENT=codex
BRIDGE="$HERE/waypoint-hook.sh"
[ -f "$BRIDGE" ] || BRIDGE="$HERE/../hooks/waypoint-hook.sh"
bash "$BRIDGE" "$@" 2>/dev/null
exit 0
