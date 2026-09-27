#!/bin/bash
# Waypoint 훅 브리지. Claude Code 훅 입력(JSON, stdin)을 로컬 앱으로 전달한다.
# 원칙: 절대 세션을 막지 않는다. 항상 exit 0. stdout은 SessionStart에서만.
# 설치: ~/.claude/waypoint/waypoint-hook.sh 에 두고 chmod +x

EVENT="${1:-Unknown}"
PORT="${WAYPOINT_PORT:-47821}"
OUTBOX_DIR="$HOME/Library/Application Support/Waypoint"
OUTBOX="$OUTBOX_DIR/outbox.jsonl"

PAYLOAD="$(cat)"
[ -z "$PAYLOAD" ] && exit 0

RESPONSE="$(printf '%s' "$PAYLOAD" | curl -sS --max-time 1 \
  -X POST -H 'Content-Type: application/json' \
  --data-binary @- -w '\n%{http_code}' \
  "http://127.0.0.1:${PORT}/hooks/${EVENT}" 2>/dev/null)"
STATUS="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "$STATUS" = "200" ] || [ "$STATUS" = "204" ]; then
  # SessionStart 응답 본문은 대화 컨텍스트로 주입된다
  if [ "$EVENT" = "SessionStart" ] && [ -n "$BODY" ] && [ "$BODY" != "$STATUS" ]; then
    printf '%s\n' "$BODY"
  fi
  exit 0
fi

# 앱이 꺼져 있거나 응답 없음 → outbox 적재 (앱 실행 시 흡수)
mkdir -p "$OUTBOX_DIR" 2>/dev/null
ONELINE="$(printf '%s' "$PAYLOAD" | tr -d '\n')"
printf '{"event":"%s","receivedAt":%s,"payload":%s}\n' "$EVENT" "$(date +%s)" "$ONELINE" >> "$OUTBOX" 2>/dev/null
exit 0
