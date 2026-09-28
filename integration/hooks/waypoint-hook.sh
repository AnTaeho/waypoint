#!/bin/bash
# Waypoint 훅 브리지. Claude Code 훅 입력(JSON, stdin)을 로컬 앱으로 전달한다.
# 원칙: 절대 세션을 막지 않는다. 항상 exit 0. stdout은 SessionStart에서만.
# 설치: ~/.claude/waypoint/waypoint-hook.sh 에 두고 chmod +x
#
# 사용: waypoint-hook.sh <EventName>   (stdin: 훅 입력 JSON)
# 환경 변수:
#   WAYPOINT_PORT      앱 포트(기본 47821)
#   WAYPOINT_HOOK_LOG  1이면 받은 입력을 그대로 hook-log/<날짜>.jsonl 에도 남긴다(실제 필드 확인용)
#   WAYPOINT_SUPPORT_DIR  저장 폴더(기본 ~/Library/Application Support/Waypoint, 테스트용)

main() {
  local event="${1:-Unknown}"
  local port="${WAYPOINT_PORT:-47821}"
  local dir="${WAYPOINT_SUPPORT_DIR:-$HOME/Library/Application Support/Waypoint}"
  local payload now line response status body

  payload="$(cat)"
  [ -z "$payload" ] && return 0
  now="$(date +%s)"
  # 한 줄 JSON(문자열 안 줄바꿈은 이미 \n으로 이스케이프돼 있어 구조 사이 줄바꿈만 빠진다)
  line="$(printf '{"event":"%s","receivedAt":%s,"payload":%s}' "$event" "$now" "$(printf '%s' "$payload" | tr -d '\r\n')")"

  if [ "${WAYPOINT_HOOK_LOG:-0}" = "1" ]; then
    mkdir -p "$dir/hook-log" 2>/dev/null
    printf '%s\n' "$line" >> "$dir/hook-log/$(date +%Y-%m-%d).jsonl" 2>/dev/null
  fi

  response="$(printf '%s' "$payload" | curl -sS --noproxy '*' --max-time 1 --connect-timeout 1 \
    -X POST -H 'Content-Type: application/json' \
    --data-binary @- -w '\n%{http_code}' \
    "http://127.0.0.1:${port}/hooks/${event}" 2>/dev/null)"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [ "$status" = "200" ] || [ "$status" = "204" ]; then
    # SessionStart 응답 본문은 대화 컨텍스트로 주입된다
    if [ "$event" = "SessionStart" ] && [ -n "$body" ] && [ "$body" != "$status" ]; then
      printf '%s\n' "$body"
    fi
    return 0
  fi

  # 앱이 꺼져 있거나 응답 없음 → outbox 적재 (앱 실행 시 흡수)
  mkdir -p "$dir" 2>/dev/null
  printf '%s\n' "$line" >> "$dir/outbox.jsonl" 2>/dev/null
  return 0
}

main "$@" 2>/dev/null
exit 0
