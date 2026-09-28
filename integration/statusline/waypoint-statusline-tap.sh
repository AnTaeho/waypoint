#!/bin/bash
# Waypoint 상태줄 중계. Claude Code가 상태줄 명령에 넘기는 JSON(stdin)에서 사용량(rate_limits)만
# usage.json으로 남기고, 같은 입력을 원래 상태줄 명령에 넘겨 그 출력을 그대로 내보낸다.
# 원칙: 원래 상태줄 출력은 어떤 경우에도 나온다. 쓰기 실패·jq 없음은 조용히 넘어간다.
# 설치: ~/.claude/waypoint/waypoint-statusline-tap.sh 에 두고 chmod +x
#
# 사용(settings.json statusLine.command):
#   bash ~/.claude/waypoint/waypoint-statusline-tap.sh bash ~/.claude/awesome-statusline.sh
# 인자가 원래 상태줄 명령이다. 인자가 없으면 환경 변수 WAYPOINT_STATUSLINE_NEXT(셸 명령 문자열)를 쓴다.
# 환경 변수:
#   WAYPOINT_SUPPORT_DIR  저장 폴더(기본 ~/Library/Application Support/Waypoint, 테스트용)
#
# usage.json 형식: {"capturedAt":<unix 초>,"rateLimits":<입력의 rate_limits 그대로>}

# stdin 전체(끝 줄바꿈까지 그대로)
input="$(cat; printf x)"
input="${input%x}"

# 사용량 기록(jq·mv 두 프로세스, 수 ms). 서브셸 안에서만 실패를 삼켜 아래 원래 상태줄로 이어진다.
(
  command -v jq >/dev/null 2>&1 || exit 0
  dir="${WAYPOINT_SUPPORT_DIR:-$HOME/Library/Application Support/Waypoint}"
  json="$(printf '%s' "$input" | jq -c \
    'if (.rate_limits | type) == "object" then {capturedAt: (now | floor), rateLimits: .rate_limits} else empty end')" || exit 0
  [ -n "$json" ] || exit 0
  [ -d "$dir" ] || mkdir -p "$dir" || exit 0
  tmp="$dir/.usage.json.tmp.$$"
  if printf '%s\n' "$json" > "$tmp"; then
    mv -f "$tmp" "$dir/usage.json" || rm -f "$tmp"
  else
    rm -f "$tmp"
  fi
) </dev/null >/dev/null 2>&1

# 원래 상태줄 명령
if [ "$#" -gt 0 ]; then
  printf '%s' "$input" | "$@"
elif [ -n "${WAYPOINT_STATUSLINE_NEXT:-}" ]; then
  printf '%s' "$input" | bash -c "$WAYPOINT_STATUSLINE_NEXT"
fi
