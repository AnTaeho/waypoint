#!/bin/bash
# Waypoint 상태줄 중계. Claude Code가 상태줄 명령에 넘기는 JSON(stdin)에서 사용량(rate_limits)을 usage.json으로,
# 세션 이름·컨텍스트 사용률을 session-status.json으로 남기고, 같은 입력을 원래 상태줄 명령에 넘겨 그 출력을 그대로 내보낸다.
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
# session-status.json 형식: {"<session_id>":{"at":<unix 초>,"name":"<session_name>","context":<context_window.used_percentage>},…}
#   자기 세션 항목만 바꾸고 at이 24시간 넘은 항목은 뺀다. name·context는 입력에 없으면 키도 없다.

# stdin 전체(끝 줄바꿈까지 그대로)
input="$(cat; printf x)"
input="${input%x}"

# 기록(jq 하나 + 파일마다 mv 하나, 수 ms). 서브셸 안에서만 실패를 삼켜 아래 원래 상태줄로 이어진다.
(
  command -v jq >/dev/null 2>&1 || exit 0
  dir="${WAYPOINT_SUPPORT_DIR:-$HOME/Library/Application Support/Waypoint}"
  prev="$dir/session-status.json"
  [ -f "$prev" ] && [ -r "$prev" ] || prev=/dev/null
  # 첫 줄 usage.json 내용, 둘째 줄 session-status.json 내용. 쓸 것이 없는 쪽은 null.
  out="$(printf '%s' "$input" | jq -c --rawfile prev "$prev" '
    (now | floor) as $t
    | (if (.rate_limits | type) == "object" then {capturedAt: $t, rateLimits: .rate_limits} else null end) as $usage
    | .session_id as $sid
    | (if ($sid | type) == "string" and $sid != "" then
        ((try ($prev | fromjson) catch null) | if type == "object" then . else {} end
          | with_entries(select((.value | type) == "object" and (.value.at | type) == "number" and .value.at > $t - 86400)))
        + {($sid): ({at: $t}
            + (.session_name | if type == "string" and . != "" then {name: .[0:200]} else {} end)
            + ((try .context_window.used_percentage catch null) | if type == "number" then {context: .} else {} end))}
      else null end) as $status
    | $usage, $status')" || exit 0
  nl='
'
  usage="${out%%"$nl"*}"
  status="${out#*"$nl"}"
  [ "$usage" != null ] || usage=""
  [ "$status" != null ] || status=""
  [ -n "$usage$status" ] || exit 0
  [ -d "$dir" ] || mkdir -p "$dir" || exit 0
  put() {
    [ -n "$2" ] || return 0
    tmp="$dir/.$1.tmp.$$"
    if printf '%s\n' "$2" > "$tmp"; then
      mv -f "$tmp" "$dir/$1" || rm -f "$tmp"
    else
      rm -f "$tmp"
    fi
  }
  put usage.json "$usage"
  put session-status.json "$status"
) </dev/null >/dev/null 2>&1

# 원래 상태줄 명령
if [ "$#" -gt 0 ]; then
  printf '%s' "$input" | "$@"
elif [ -n "${WAYPOINT_STATUSLINE_NEXT:-}" ]; then
  printf '%s' "$input" | bash -c "$WAYPOINT_STATUSLINE_NEXT"
fi
