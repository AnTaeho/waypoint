#!/bin/bash
# Waypoint 훅 브리지. Claude Code 훅 입력(JSON, stdin)을 로컬 앱으로 전달한다.
# 원칙: 절대 세션을 막지 않는다. 항상 exit 0. stdout은 SessionStart, 그리고 블록을 받지 못한 세션의
# UserPromptSubmit에서 한 번만(앱이 200 + 본문을 돌려줄 때. 둘 다 평문 stdout이 대화 컨텍스트에 들어간다).
# 설치: ~/.claude/waypoint/waypoint-hook.sh 에 두고 chmod +x
#
# 사용: waypoint-hook.sh <EventName>   (stdin: 훅 입력 JSON)
# 환경 변수:
#   WAYPOINT_PORT      앱 포트(기본 47821)
#   WAYPOINT_HOOK_LOG  1이면 받은 입력을 그대로 hook-log/<날짜>.jsonl 에도 남긴다(실제 필드 확인용)
#   WAYPOINT_SUPPORT_DIR  저장 폴더(기본 ~/Library/Application Support/Waypoint, 테스트용)

# 이 훅을 부른 Claude Code 프로세스 PID. 조상을 4단계까지 올라가며 실행 파일 이름이 `claude`인 첫 프로세스.
# (인자로 비교하지 않는다: 이 스크립트 경로 `~/.claude/...`가 셸 인자에 들어 있다.)
# 실측(2.1.283)에서는 바로 위 부모가 claude라 `ps`를 한 번만 부른다. 못 찾으면 아무것도 출력하지 않는다.
claude_pid() {
  local pid="$PPID" ppid comm i
  for i in 1 2 3 4; do
    case "$pid" in ''|0|1|*[!0-9]*) return 0 ;; esac
    read -r ppid comm <<< "$(ps -o ppid=,comm= -p "$pid")"
    [ -z "$comm" ] && return 0
    if [ "${comm##*/}" = "claude" ]; then
      printf '%s' "$pid"
      return 0
    fi
    pid="$ppid"
  done
  return 0
}

main() {
  local event="${1:-Unknown}"
  local port="${WAYPOINT_PORT:-47821}"
  local dir="${WAYPOINT_SUPPORT_DIR:-$HOME/Library/Application Support/Waypoint}"
  local payload now line response status body pid pidfield=""
  local -a pidheader=()

  payload="$(cat)"
  [ -z "$payload" ] && return 0
  now="$(date +%s)"
  pid="$(claude_pid)"
  if [ -n "$pid" ]; then
    pidfield=",\"claudePid\":$pid"
    pidheader=(-H "X-Waypoint-Claude-PID: $pid")
  fi
  # 한 줄 JSON(문자열 안 줄바꿈은 이미 \n으로 이스케이프돼 있어 구조 사이 줄바꿈만 빠진다)
  line="$(printf '{"event":"%s","receivedAt":%s%s,"payload":%s}' "$event" "$now" "$pidfield" "$(printf '%s' "$payload" | tr -d '\r\n')")"

  if [ "${WAYPOINT_HOOK_LOG:-0}" = "1" ]; then
    mkdir -p "$dir/hook-log" 2>/dev/null
    printf '%s\n' "$line" >> "$dir/hook-log/$(date +%Y-%m-%d).jsonl" 2>/dev/null
  fi

  response="$(printf '%s' "$payload" | curl -sS --noproxy '*' --max-time 1 --connect-timeout 1 \
    -X POST -H 'Content-Type: application/json' "${pidheader[@]}" \
    --data-binary @- -w '\n%{http_code}' \
    "http://127.0.0.1:${port}/hooks/${event}" 2>/dev/null)"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [ "$status" = "200" ] || [ "$status" = "204" ]; then
    # SessionStart·UserPromptSubmit 응답 본문은 대화 컨텍스트로 주입된다(UserPromptSubmit은 늦은 주입일 때만 200)
    case "$event" in
      SessionStart|UserPromptSubmit)
        if [ "$status" = "200" ] && [ -n "$body" ] && [ "$body" != "$status" ]; then
          printf '%s\n' "$body"
        fi
        ;;
    esac
    return 0
  fi

  # 앱이 꺼져 있거나 응답 없음 → outbox 적재 (앱 실행 시 흡수)
  mkdir -p "$dir" 2>/dev/null
  printf '%s\n' "$line" >> "$dir/outbox.jsonl" 2>/dev/null
  return 0
}

main "$@" 2>/dev/null
exit 0
