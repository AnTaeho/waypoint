#!/bin/bash
# Waypoint 훅 브리지. Claude Code 훅 입력(JSON, stdin)을 로컬 앱으로 전달한다.
# 원칙: 절대 세션을 막지 않는다. 항상 exit 0. stdout은 SessionStart, 그리고 블록을 받지 못한 세션의
# UserPromptSubmit에서만(앱이 200 + 본문을 돌려줄 때. 둘 다 평문 stdout이 대화 컨텍스트에 들어간다).
# 본문을 stdout에 출력한 뒤에만 응답 ID(X-Waypoint-Context-ID)를 /hooks/ack로 돌려보낸다. 앱은 이 확인을 받아야
# 블록을 받은 것으로 적고, 확인이 없으면(시간 초과 등) 다음 UserPromptSubmit에 블록을 다시 준다(TRK-35).
# 설치: ~/.claude/waypoint/waypoint-hook.sh 에 두고 chmod +x
#
# 사용: waypoint-hook.sh <EventName>   (stdin: 훅 입력 JSON)
# 환경 변수:
#   WAYPOINT_PORT      앱 포트(기본 47821)
#   WAYPOINT_AGENT     claude(기본) / codex. 경로·PID·outbox의 도구를 구분한다.
#   WAYPOINT_HOOK_LOG  1이면 받은 입력을 그대로 hook-log/<날짜>.jsonl 에도 남긴다(실제 필드 확인용, 원본 그대로)
#   WAYPOINT_SUPPORT_DIR  저장 폴더(기본 ~/Library/Application Support/Waypoint, 테스트용)
#   WAYPOINT_JQ        outbox를 줄일 jq(기본 /usr/bin/jq, 테스트용)

# 훅을 부른 도구 PID. 셸 래퍼를 포함해 조상을 8단계까지 확인한다.
# (인자로 비교하지 않는다: 이 스크립트 경로 `~/.claude/...`가 셸 인자에 들어 있다.)
# Claude 네이티브 설치는 실행 파일명이 버전 번호다. 정해진 versions 경로도 검사한다.
agent_pid() {
  local pid="$PPID" ppid comm i
  for i in 1 2 3 4 5 6 7 8; do
    case "$pid" in ''|0|1|*[!0-9]*) return 0 ;; esac
    read -r ppid comm <<< "$(ps -o ppid=,comm= -p "$pid")"
    [ -z "$comm" ] && return 0
    local native_claude=0
    if [ "${WAYPOINT_AGENT:-claude}" = "claude" ]; then
      case "$comm" in
        */.local/share/claude/versions/*)
          [[ "${comm##*/}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][a-zA-Z0-9.-]+)?$ ]] && native_claude=1
          ;;
      esac
    fi
    if [ "${comm##*/}" = "${WAYPOINT_AGENT:-claude}" ] || [ "$native_claude" = "1" ]; then
      printf '%s' "$pid"
      return 0
    fi
    pid="$ppid"
  done
  return 0
}

# outbox에는 앱이 읽는 필드만 남긴다(SPEC 6장). 파일 내용·명령·출력·diff 원문은 쓰지 않는다.
# 앱이 세는 값(줄 수, 커밋 줄, 카드 ID)은 같은 결과가 나오는 자리표시로 바꿔 둔다 → 앱 코드는 그대로 읽는다.
# 실시간 POST는 원본을 그대로 보낸다. 이 필터는 앱이 꺼져 있을 때만 쓴다.
OUTBOX_FILTER='
def keep($ks): with_entries(select(.key as $k | $ks | index($k)));
# HookParsing.lineCount와 같은 줄 수. Swift는 "\r\n"을 한 글자로 봐서 줄바꿈으로 세지 않는다.
def lines_of: if . == "" then 0 else gsub("\r\n"; "x") as $s
  | ($s | split("\n") | length) - (if $s | endswith("\n") then 1 else 0 end) end;
# 문자열 → 줄 수만큼의 "\n"(같은 lineCount). 문자열이 아니면 null(앱에서 빈 값과 같다).
def counted: if type == "string" then (lines_of as $n | if $n == 0 then "" else "\n" * $n end) else null end;
# diff 조각: 줄마다 첫 글자 +/-만 남긴다. 조각 개수는 그대로(빈 배열과 빈 조각은 앱에서 다르다).
def hunks: if type == "array" then map(select(type == "object")
  | {lines: ((.lines // []) | if type == "array" then map(strings | .[0:1] | select(. == "+" or . == "-")) else [] end)})
  else null end;
def card_refs: if type == "string" then [match("\\[[A-Z]{2,5}-[0-9]{1,6}\\]"; "g").string] | join(" ") else null end;
# 출력에서 커밋 줄 [브랜치 해시] 메시지(첫 줄만), Codex 종료 코드 줄(첫 줄만)과 apply_patch 결과 줄만.
def output_lines: if type == "string" then split("\n") as $ls
  | ([$ls[] | select(test("^\\[.+? (\\(root-commit\\) )?[0-9a-f]{7,40}\\] "))][0:1])
    + ([$ls[] | select(test("^(Process exited with code|Exit code:) -?[0-9]+$"))][0:1])
    + (if contains("Success. Updated the following files:")
       then [$ls[] | select(contains("Success. Updated the following files:") or test("^[AMD] ."))] else [] end)
  | join("\n") else null end;
# apply_patch: 머리 줄(*** …)은 그대로, +/- 줄은 첫 글자만.
def patch_shape: if type == "string" then split("\n")
  | map(if startswith("*** ") then . elif startswith("+") or startswith("-") then .[0:1] else empty end) | join("\n")
  else null end;
# 검증 명령 패턴. 앱의 VerificationCommand.pattern과 같은 문자열이어야 한다(OutboxTrimTests가 비교). 한 줄로 둔다.
def verify_pattern: "(^|[;&|(\\n])\\s*([A-Za-z_][A-Za-z0-9_]*=\\S*\\s+)*((time|env|nice|command|exec)\\s+|timeout\\s+\\S+\\s+)*((uv|poetry|pipenv|hatch)\\s+run\\s+)?(swift\\s+(test|build)\\b|xcodebuild\\b[^;&|\\n]*\\b(test|build|build-for-testing|test-without-building)\\b|(npm|pnpm|yarn|bun)\\s+(run\\s+)?test\\b|(npx\\s+|pnpm\\s+exec\\s+|yarn\\s+)?(jest|vitest|mocha)\\b|pytest\\b|python3?\\s+-m\\s+(pytest|unittest)\\b|python3?\\s+(\\S*/)?test[^\\s;&|]*\\.py\\b|go\\s+test\\b|cargo\\s+(test|nextest)\\b|(gradle|gradlew|\\./gradlew)\\b[^;&|\\n]*\\btest\\b|mvn\\b[^;&|\\n]*\\b(test|verify)\\b|make\\s+(test|check)\\b|(bash|sh|zsh)\\s+(\\S*/)?test[^\\s;&|]*\\.sh\\b|\\./(\\S*/)?test[^\\s;&|]*\\.sh\\b|deno\\s+test\\b)";
# 그 밖의 명령: 검증 명령(테스트·빌드)이면 원문을 남기고(앱이 근거로 쓴다), 아니면 git commit이 들어 있는지만.
def command_shape: if type == "array" then (if (map(strings) | join(" ") | test(verify_pattern)) then . else null end)
  elif type != "string" then null
  elif test(verify_pattern) then .
  elif contains("git commit") then "git commit"
  elif contains("git -c") and contains(" commit") then "git -c commit" else null end;
def object_or($key): if type == "object" then .
  elif type == "string" then ((try fromjson catch null) as $o | if ($o | type) == "object" then $o else {($key): .} end)
  else {} end;
if type != "object" then error("not an object") else . end
| .tool_name as $tool
| keep(["session_id", "cwd", "hook_event_name", "agent_id", "agent_type", "source", "reason",
        "prompt", "prompt_text", "prompt_id", "turn_id", "tool_name", "tool_use_id", "tool_input", "tool_response",
        "error", "is_interrupt"])
# PostToolUseFailure 설명: 앱은 첫 줄 `Exit code N`만 본다. 나머지(명령 출력)는 버린다.
| if has("error") then .error |= (if type == "string" then (split("\n")[0] | if test("^Exit code -?[0-9]+$") then . else null end) else null end) else . end
| if has("is_interrupt") then .is_interrupt |= (if type == "boolean" then . else null end) else . end
| with_entries(select(.value != null))
# 사용자 문장: 앱은 공백·붙여넣기 태그를 벗긴 뒤 앞 300자만 쓴다. 벗길 몫을 두고 600자(코드 포인트)까지.
| if (.prompt | type) == "string" then .prompt |= .[0:600] else . end
| if (.prompt_text | type) == "string" then .prompt_text |= .[0:600] else . end
| if has("tool_input") then .tool_input |= (
    (if $provider == "codex" then object_or("command") elif type == "object" then . else {} end)
    | keep(["file_path", "old_string", "new_string", "edits", "content", "command", "prompt", "message",
            "subagent_type", "agent_type", "workdir", "cwd", "run_in_background"])
    | if has("old_string") then .old_string |= counted else . end
    | if has("new_string") then .new_string |= counted else . end
    | if has("content") then .content |= counted else . end
    | if has("edits") then .edits |= (if type == "array"
        then map(if type == "object" then {old_string: (.old_string | counted), new_string: (.new_string | counted)} else {} end)
        else null end) else . end
    | if has("command") then .command |= (if $provider == "codex" and $tool == "apply_patch" then patch_shape else command_shape end) else . end
    # 백그라운드 실행 표시는 셸 명령만(앱의 HookParsing.shellTools). 결과를 모르는 실행을 통과로 보지 않게 남긴다.
    | if ($tool | IN("Bash", "shell", "exec_command", "local_shell")) then . else del(.run_in_background) end
    | if has("prompt") then .prompt |= card_refs else . end
    | if has("message") then .message |= card_refs else . end
    | with_entries(select(.value != null)))
  else . end
| if has("tool_response") then .tool_response |= (
    (if $provider == "codex" then object_or("stdout")
       | if has("stdout") then . else (((.output | strings) // (.text | strings)) as $o
           | if $o == null then . else .stdout = $o end) end
     elif type == "object" then . else {} end)
    | keep(["structuredPatch", "bashEditDiff", "gitOperation", "stdout", "metadata", "exit_code",
            "exitCode", "interrupted", "backgroundTaskId"])
    | if has("structuredPatch") then .structuredPatch |= hunks else . end
    | if has("bashEditDiff") then .bashEditDiff |= (if type == "object" then keep(["files", "changedFiles"])
        | if has("files") then .files |= (if type == "array"
            then map(if type == "object" then keep(["filePath", "hunks"]) | (if has("hunks") then .hunks |= hunks else . end) else {} end)
            else null end) else . end
        else null end) else . end
    | if has("gitOperation") then .gitOperation |= (if type == "object" and (.commit | type) == "object"
        then {commit: (.commit | keep(["sha", "branch"]))} else null end) else . end
    | if has("stdout") then .stdout |= output_lines else . end
    | if has("metadata") then .metadata |= (if type == "object" then keep(["exit_code"]) else null end) else . end
    | with_entries(select(.value != null)))
  else . end
'

# outbox용 payload. jq가 없거나 실패하면 session_id·cwd만(따옴표·역슬래시 없는 값일 때). 그것도 없으면 빈 값 → 줄을 쓰지 않는다.
outbox_payload() {
  local payload="$1" provider="$2" event="$3" trimmed sid cwd
  trimmed="$(printf '%s' "$payload" | "${WAYPOINT_JQ:-/usr/bin/jq}" -c --arg provider "$provider" "$OUTBOX_FILTER" 2>/dev/null)"
  if [ -n "$trimmed" ] && [ "${trimmed:0:1}" = "{" ]; then printf '%s' "$trimmed"; return 0; fi
  [[ "$payload" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"\\]+)\" ]] || return 0
  sid="${BASH_REMATCH[1]}"
  [[ "$payload" =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"\\]*)\" ]] && cwd="${BASH_REMATCH[1]}"
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"%s"}' "$sid" "$cwd" "$event"
}

# 블록 수신 확인. $1 포트, $2 응답 ID. ID 꼴(소문자 UUID)이 아니면 보내지 않는다(옛 앱은 머리가 없어 빈 값).
# 실패해도 아무것도 하지 않는다(outbox에 쓰지 않는다. 확인이 없으면 앱이 다음 프롬프트에 블록을 다시 준다).
send_ack() {
  [[ "$2" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || return 0
  curl -sS --noproxy '*' --max-time 1 --connect-timeout 1 -o /dev/null \
    -X POST -H 'Content-Type: application/json' --data-binary "{\"contextId\":\"$2\"}" \
    "http://127.0.0.1:$1/hooks/ack" >/dev/null 2>&1
  return 0
}

main() {
  local event="${1:-Unknown}"
  local port="${WAYPOINT_PORT:-47821}"
  local provider="${WAYPOINT_AGENT:-claude}" path="/hooks/$event" pidkey="claudePid" pidname="X-Waypoint-Claude-PID" providerfield=""
  case "$provider" in
    claude) ;;
    codex) path="/hooks/codex/$event"; pidkey="processPid"; pidname="X-Waypoint-Process-PID"; providerfield=',"provider":"codex"' ;;
    *) return 0 ;;
  esac
  local dir="${WAYPOINT_SUPPORT_DIR:-$HOME/Library/Application Support/Waypoint}"
  local payload now line response status rest body ctxid pid pidfield=""
  local -a pidheader=() ackheader=()
  # 블록을 줄 수 있는 이벤트: 이 스크립트는 출력 뒤 확인을 보낸다고 알린다(없으면 앱은 옛 스크립트로 보고 바로 확정).
  case "$event" in SessionStart|UserPromptSubmit) ackheader=(-H 'X-Waypoint-Context-Ack: 1') ;; esac

  payload="$(cat)"
  [ -z "$payload" ] && return 0
  now="$(date +%s)"
  pid="$(agent_pid)"
  if [ -n "$pid" ]; then
    pidfield=",\"$pidkey\":$pid"
    pidheader=(-H "$pidname: $pid")
  fi
  # 한 줄 JSON(문자열 안 줄바꿈은 이미 \n으로 이스케이프돼 있어 구조 사이 줄바꿈만 빠진다)
  line="$(printf '{"event":"%s","receivedAt":%s%s%s,"payload":%s}' "$event" "$now" "$providerfield" "$pidfield" "$(printf '%s' "$payload" | tr -d '\r\n')")"

  if [ "${WAYPOINT_HOOK_LOG:-0}" = "1" ]; then
    mkdir -p "$dir/hook-log" 2>/dev/null
    printf '%s\n' "$line" >> "$dir/hook-log/$(date +%Y-%m-%d).jsonl" 2>/dev/null
  fi

  response="$(printf '%s' "$payload" | curl -sS --noproxy '*' --max-time 1 --connect-timeout 1 \
    -X POST -H 'Content-Type: application/json' "${pidheader[@]}" "${ackheader[@]}" \
    --data-binary @- -w '\n%header{x-waypoint-context-id}\n%{http_code}' \
    "http://127.0.0.1:${port}${path}" 2>/dev/null)"
  # 응답 = 본문 \n 응답 ID(없으면 빈 줄) \n 상태 코드
  status="${response##*$'\n'}"
  rest="${response%$'\n'*}"
  ctxid="${rest##*$'\n'}"
  body="${rest%$'\n'*}"
  [ "$rest" = "$response" ] && body="" && ctxid=""

  if [ "$status" = "200" ] || [ "$status" = "204" ]; then
    # SessionStart·UserPromptSubmit 응답 본문은 대화 컨텍스트로 주입된다(UserPromptSubmit은 늦은 주입일 때만 200)
    case "$event" in
      SessionStart|UserPromptSubmit)
        if [ "$status" = "200" ] && [ -n "$body" ]; then
          # 출력에 실패하면(stdout이 닫힘 등) 확인을 보내지 않는다
          printf '%s\n' "$body" || return 0
          send_ack "$port" "$ctxid"
        fi
        ;;
    esac
    return 0
  fi

  # 앱이 꺼져 있거나 응답 없음 → 줄인 payload로 outbox 적재 (앱 실행 시 흡수)
  local trimmed
  trimmed="$(outbox_payload "$payload" "$provider" "$event")"
  [ -z "$trimmed" ] && return 0
  mkdir -p "$dir" 2>/dev/null
  printf '{"event":"%s","receivedAt":%s%s%s,"trimmed":true,"payload":%s}\n' \
    "$event" "$now" "$providerfield" "$pidfield" "$trimmed" >> "$dir/outbox.jsonl" 2>/dev/null
  return 0
}

main "$@" 2>/dev/null
exit 0
