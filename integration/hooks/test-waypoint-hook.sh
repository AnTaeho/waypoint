#!/bin/bash
# waypoint-hook.sh 동작 확인. 임시 폴더만 쓰고 실제 Application Support는 건드리지 않는다.
# 사용: bash integration/hooks/test-waypoint-hook.sh   (python3 필요)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/waypoint-hook.sh"
FIX="$HERE/../../Tests/Fixtures/hooks"
TMP="$(mktemp -d)"
trap 'kill $SERVER 2>/dev/null; rm -rf "$TMP"' EXIT
export WAYPOINT_SUPPORT_DIR="$TMP/support"
FAIL=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAIL=1; fi; }

# 1) 앱 없음(빈 포트): outbox 적재, stdout 없음, exit 0, 1초 안팎
export WAYPOINT_PORT=47999
start=$(date +%s)
out="$(bash "$HOOK" SessionStart < "$FIX/doc-SessionStart.json")"; code=$?
elapsed=$(( $(date +%s) - start ))
check "앱 없음: exit 0" '[ $code -eq 0 ]'
check "앱 없음: stdout 없음" '[ -z "$out" ]'
check "앱 없음: 2초 안에 끝남" '[ $elapsed -le 2 ]'
check "outbox 한 줄" '[ "$(wc -l < "$WAYPOINT_SUPPORT_DIR/outbox.jsonl")" -eq 1 ]'
check "outbox 형식" 'python3 -c "import json,sys; l=json.loads(open(sys.argv[1]).readline()); assert l[\"event\"]==\"SessionStart\" and isinstance(l[\"receivedAt\"],int) and l[\"payload\"][\"source\"]==\"startup\" and l[\"trimmed\"] is True" "$WAYPOINT_SUPPORT_DIR/outbox.jsonl"'

# 2) 빈 입력: 아무것도 안 함
rm -f "$WAYPOINT_SUPPORT_DIR/outbox.jsonl"
bash "$HOOK" Stop < /dev/null; code=$?
check "빈 입력: exit 0, outbox 없음" '[ $code -eq 0 ] && [ ! -e "$WAYPOINT_SUPPORT_DIR/outbox.jsonl" ]'

# 3) 로깅 모드: hook-log에도 남김
WAYPOINT_HOOK_LOG=1 bash "$HOOK" Stop < "$FIX/doc-Stop.json"
check "로깅 모드: hook-log 파일" '[ "$(cat "$WAYPOINT_SUPPORT_DIR"/hook-log/*.jsonl | wc -l)" -eq 1 ]'
rm -rf "$WAYPOINT_SUPPORT_DIR"
WAYPOINT_HOOK_LOG=1 bash "$HOOK" PostToolUse < "$FIX/real-PostToolUse-Edit.json"
check "로깅 모드: hook-log는 원본 그대로, outbox는 줄인 것" 'python3 - "$WAYPOINT_SUPPORT_DIR" "$FIX/real-PostToolUse-Edit.json" <<"PY"
import glob, json, sys
original = json.load(open(sys.argv[2]))
log = json.loads(open(glob.glob(sys.argv[1] + "/hook-log/*.jsonl")[0]).readline())
box = json.loads(open(sys.argv[1] + "/outbox.jsonl").readline())
assert log["payload"] == original and "trimmed" not in log
assert "originalFile" not in box["payload"]["tool_response"] and box["trimmed"] is True
PY'

# 4) 앱 있음: SessionStart·UserPromptSubmit(200일 때)은 본문을 stdout으로, 나머지는 stdout 없음, outbox 안 씀
export WAYPOINT_PORT=47998
cat > "$TMP/server.py" <<'PY'
import http.server, os, sys, time
ups = 0
tmp = os.path.dirname(sys.argv[2])
def flag(name):
    try:
        return open(os.path.join(tmp, name)).read().strip()
    except OSError:
        return None
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        data = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        # 블록 수신 확인: 본문을 acks.txt에 남긴다. ackdelay 파일이 있으면 그만큼 늦게 답한다
        if self.path == '/hooks/ack':
            with open(os.path.join(tmp, 'acks.txt'), 'a') as f:
                f.write(data.decode() + '\n')
            if flag('ackdelay'):
                time.sleep(float(flag('ackdelay')))
            try:
                self.send_response(204); self.end_headers()
            except BrokenPipeError:
                pass
            return
        with open(sys.argv[2], 'a') as f:
            f.write('%s %s\n' % (self.path, self.headers.get('X-Waypoint-Claude-PID', '-')))
        with open(os.path.join(tmp, 'capability.txt'), 'a') as f:
            f.write('%s %s\n' % (self.path, self.headers.get('X-Waypoint-Context-Ack', '-')))
        # SessionStart가 늦게 답하는 경우(시간 초과): startdelay 파일
        if self.path == '/hooks/SessionStart' and flag('startdelay'):
            time.sleep(float(flag('startdelay')))
        # UserPromptSubmit: 늦은 주입 흉내 — 첫 번째만 200 + 본문, 다음부터 204
        # PostToolUse: 200 + 본문을 줘도 스크립트가 찍지 않아야 한다
        global ups
        if self.path == '/hooks/UserPromptSubmit':
            ups += 1
        if self.path == '/hooks/SessionStart':
            body = 'Waypoint: LDG 가계부 앱'.encode()
        elif self.path == '/hooks/UserPromptSubmit' and ups == 1:
            body = 'Waypoint: LDG 늦은 주입'.encode()
        elif self.path == '/hooks/PostToolUse':
            body = '찍히면 안 됨'.encode()
        else:
            body = None
        try:
            if body is not None:
                self.send_response(200); self.send_header('Content-Type', 'text/plain; charset=utf-8')
                # 응답 ID: ctxid 파일 내용(없으면 머리를 싣지 않는다 — 옛 앱). 다른 이벤트에 실려도 스크립트는 쓰지 않는다
                if flag('ctxid'):
                    self.send_header('X-Waypoint-Context-ID', flag('ctxid'))
                self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
            else:
                self.send_response(204); self.end_headers()
        except BrokenPipeError:
            pass
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
python3 "$TMP/server.py" "$WAYPOINT_PORT" "$TMP/headers.txt" & SERVER=$!
sleep 1
rm -f "$WAYPOINT_SUPPORT_DIR/outbox.jsonl"
out="$(bash "$HOOK" SessionStart < "$FIX/doc-SessionStart.json")"
check "앱 있음: SessionStart 본문 출력" '[ "$out" = "Waypoint: LDG 가계부 앱" ]'
out="$(bash "$HOOK" PostToolUse < "$FIX/doc-PostToolUse-Edit.json")"
check "앱 있음: 다른 이벤트는 200 본문이어도 stdout 없음" '[ -z "$out" ]'
out="$(bash "$HOOK" UserPromptSubmit < "$FIX/doc-UserPromptSubmit.json")"; code=$?
check "앱 있음: UserPromptSubmit 200 본문 출력" '[ $code -eq 0 ] && [ "$out" = "Waypoint: LDG 늦은 주입" ]'
out="$(bash "$HOOK" UserPromptSubmit < "$FIX/doc-UserPromptSubmit.json")"; code=$?
check "앱 있음: UserPromptSubmit 204는 stdout 없음" '[ $code -eq 0 ] && [ -z "$out" ]'
check "앱 있음: outbox 안 씀" '[ ! -e "$WAYPOINT_SUPPORT_DIR/outbox.jsonl" ]'
check "앱 있음: 응답 ID가 없으면(옛 앱) 확인 안 보냄" '[ ! -e "$TMP/acks.txt" ]'
check "확인 머리: SessionStart·UserPromptSubmit에만" '[ "$(cat "$TMP/capability.txt")" = "$(printf "/hooks/SessionStart 1\n/hooks/PostToolUse -\n/hooks/UserPromptSubmit 1\n/hooks/UserPromptSubmit 1")" ]'

# 4-1) 블록 수신 확인(TRK-35): 본문을 출력한 뒤에만 응답 ID를 /hooks/ack로 돌려보낸다
ID=0f1e2d3c-4b5a-6978-8a9b-acbdcedf0123
acks() { [ -e "$TMP/acks.txt" ] && wc -l < "$TMP/acks.txt" | tr -d ' ' || echo 0; }
printf '%s' "$ID" > "$TMP/ctxid"
out="$(bash "$HOOK" SessionStart < "$FIX/doc-SessionStart.json")"; code=$?
check "확인: SessionStart 본문 출력, exit 0" '[ $code -eq 0 ] && [ "$out" = "Waypoint: LDG 가계부 앱" ]'
check "확인: 출력 뒤 응답 ID를 한 번 돌려보냄" '[ "$(cat "$TMP/acks.txt")" = "{\"contextId\":\"$ID\"}" ]'
out="$(bash "$HOOK" UserPromptSubmit < "$FIX/doc-UserPromptSubmit.json")"
check "확인: UserPromptSubmit 204면 확인 없음" '[ -z "$out" ] && [ "$(acks)" -eq 1 ]'
out="$(bash "$HOOK" PostToolUse < "$FIX/doc-PostToolUse-Edit.json")"
check "확인: 다른 이벤트는 ID가 와도 확인 없음" '[ -z "$out" ] && [ "$(acks)" -eq 1 ]'
bash "$HOOK" SessionStart < "$FIX/doc-SessionStart.json" >&-; code=$?
check "확인: stdout에 쓰지 못하면 확인 안 보냄, exit 0" '[ $code -eq 0 ] && [ "$(acks)" -eq 1 ]'
printf 'not-an-id' > "$TMP/ctxid"
out="$(bash "$HOOK" SessionStart < "$FIX/doc-SessionStart.json")"
check "확인: ID 꼴이 아니면 출력만" '[ "$out" = "Waypoint: LDG 가계부 앱" ] && [ "$(acks)" -eq 1 ]'
printf '%s' "$ID" > "$TMP/ctxid"
printf '1.5' > "$TMP/startdelay"
out="$(bash "$HOOK" SessionStart < "$FIX/doc-SessionStart.json")"; code=$?
check "확인: 시간 초과면 출력·확인 없음, exit 0" '[ $code -eq 0 ] && [ -z "$out" ] && [ "$(acks)" -eq 1 ]'
check "확인: 시간 초과는 outbox로" '[ "$(wc -l < "$WAYPOINT_SUPPORT_DIR/outbox.jsonl")" -eq 1 ]'
rm -f "$TMP/startdelay" "$WAYPOINT_SUPPORT_DIR/outbox.jsonl"
sleep 1  # 늦게 답하던 SessionStart 처리가 끝나게
printf '3' > "$TMP/ackdelay"
start=$(python3 -c 'import time; print(time.time())')
out="$(bash "$HOOK" SessionStart < "$FIX/doc-SessionStart.json")"; code=$?
elapsed=$(python3 -c "import time; print(time.time() - $start)")
check "확인: 확인 응답이 늦어도 출력 유지, exit 0" '[ $code -eq 0 ] && [ "$out" = "Waypoint: LDG 가계부 앱" ] && [ "$(acks)" -eq 2 ]'
check "확인: 확인은 1초에서 끊는다(전체 2.5초 안)" 'python3 -c "import sys; sys.exit(0 if $elapsed < 2.5 else 1)"'
check "확인: 확인 실패는 outbox에 쓰지 않음" '[ ! -e "$WAYPOINT_SUPPORT_DIR/outbox.jsonl" ]'
rm -f "$TMP/ackdelay" "$TMP/ctxid"
sleep 2  # 늦게 답하던 확인 처리가 끝나게

# 5) Claude Code PID: 조상 중 실행 파일 이름이 claude인 프로세스를 찾아 헤더·outbox 필드로 보낸다
#    가짜 claude(= bash 심볼릭 링크. 실제 설치도 ~/.local/bin/claude 링크다)가 훅을 부른다. 명령이 둘이라 bash가 exec로 바꾸지 않는다.
ln -s /bin/bash "$TMP/claude"
run_as_claude() {  # $1 이벤트, $2 픽스처 → 가짜 claude PID를 $TMP/pid에
  "$TMP/claude" -c 'echo $$ > "$1"; bash "$2" "$3" < "$4"; true' _ "$TMP/pid" "$HOOK" "$1" "$FIX/$2.json"
}
: > "$TMP/headers.txt"
out="$(run_as_claude Stop doc-Stop)"; code=$?
check "PID 헤더: exit 0, stdout 없음" '[ $code -eq 0 ] && [ -z "$out" ]'
check "PID 헤더: X-Waypoint-Claude-PID = 가짜 claude PID" '[ "$(cat "$TMP/headers.txt")" = "/hooks/Stop $(cat "$TMP/pid")" ]'
out="$(run_as_claude SessionStart doc-SessionStart)"
check "PID 헤더: SessionStart 본문 출력 유지" '[ "$out" = "Waypoint: LDG 가계부 앱" ]'
kill $SERVER 2>/dev/null; wait $SERVER 2>/dev/null

export WAYPOINT_PORT=47999
rm -f "$WAYPOINT_SUPPORT_DIR/outbox.jsonl"
run_as_claude Stop doc-Stop; code=$?
check "PID outbox: exit 0" '[ $code -eq 0 ]'
check "PID outbox: 최상위 claudePid, payload는 허용 필드만" 'python3 -c "import json,sys; l=json.loads(open(sys.argv[1]).readline()); o=json.load(open(sys.argv[3])); keep={\"session_id\",\"cwd\",\"hook_event_name\"}; assert l[\"claudePid\"]==int(sys.argv[2]) and l[\"payload\"]=={k:v for k,v in o.items() if k in keep} and l[\"event\"]==\"Stop\"" "$WAYPOINT_SUPPORT_DIR/outbox.jsonl" "$(cat "$TMP/pid")" "$FIX/doc-Stop.json"'

# 6) 8단계 안에 claude가 없으면 PID를 보내지 않는다(셸 9겹으로 감싼다. 이 테스트를 Claude Code 안에서 돌려도 실제 claude가 범위 밖에 있게)
rm -f "$WAYPOINT_SUPPORT_DIR/outbox.jsonl"
nest_hook() {  # $1 남은 겹 수. `; true`로 bash가 exec로 바꾸지 않게 한다.
  if [ "$1" -eq 0 ]; then bash "$HOOK" Stop < "$FIX/doc-Stop.json"; true
  else bash -c 'nest_hook "$0"; true' "$(($1 - 1))"; true; fi
}
export -f nest_hook; export HOOK FIX
bash -c 'nest_hook 8; true'
check "PID 없음: outbox 줄에 claudePid 없음" 'python3 -c "import json,sys; l=json.loads(open(sys.argv[1]).readline()); assert \"claudePid\" not in l and l[\"event\"]==\"Stop\"" "$WAYPOINT_SUPPORT_DIR/outbox.jsonl"'

# 7) outbox 줄이기: 앱이 읽는 필드만 남고 파일 내용·명령·출력 원문은 없다(SPEC 6장)
export WAYPOINT_PORT=47999
outbox_of() {  # $1 이벤트, stdin 훅 입력 → outbox 줄을 $TMP/line에(없으면 빈 파일)
  rm -f "$WAYPOINT_SUPPORT_DIR/outbox.jsonl"
  bash "$HOOK" "$1"; local code=$?
  cat "$WAYPOINT_SUPPORT_DIR/outbox.jsonl" > "$TMP/line" 2>/dev/null || : > "$TMP/line"
  return $code
}
cat > "$TMP/read.py" <<'PY'
import json, sys
body = "\n".join("SECRET-LINE-%d 비밀 내용" % i for i in range(3000))
json.dump({"session_id": "s-read", "transcript_path": "/x/t.jsonl", "cwd": "/w", "permission_mode": "auto",
           "hook_event_name": "PostToolUse", "tool_name": "Read", "tool_use_id": "toolu_R",
           "tool_input": {"file_path": "/w/secret.txt", "limit": 9000},
           "tool_response": {"type": "text", "file": {"filePath": "/w/secret.txt", "content": body, "numLines": 3000}}},
          open(sys.argv[1], "w"))
PY
python3 "$TMP/read.py" "$TMP/read.json"
# 사례별 기대값. 사용: python3 expect.py <사례> <outbox 줄 파일> [원본 픽스처]
cat > "$TMP/expect.py" <<'PY'
import json, sys
case, raw = sys.argv[1], open(sys.argv[2]).read()
line = json.loads(raw)
p = line["payload"]
assert line["trimmed"] is True
probe = "/Users/antaeho/workspace/waypoint-probe"
if case == "read":
    assert "SECRET" not in raw and len(raw) < 400, len(raw)
    assert p == {"session_id": "s-read", "cwd": "/w", "hook_event_name": "PostToolUse", "tool_name": "Read",
                 "tool_use_id": "toolu_R", "tool_input": {"file_path": "/w/secret.txt"}, "tool_response": {}}, p
elif case == "edit":
    assert "B1" not in raw
    assert p["tool_input"] == {"file_path": probe + "/notes.txt", "old_string": "\n", "new_string": "\n\n"}, p
    assert p["tool_response"] == {"structuredPatch": [{"lines": ["-", "+", "+"]}]}, p
elif case == "write":
    content = json.load(open(sys.argv[3]))["tool_input"]["content"]
    assert p["tool_input"] == {"file_path": probe + "/notes.txt", "content": "\n" * len(content.rstrip("\n").split("\n"))}, p
    assert p["tool_response"] == {"structuredPatch": []}, p
elif case == "commit":
    assert p["tool_input"] == {"command": "git commit"}, p
    r = p["tool_response"]
    assert r["stdout"] == "[master c5a688e] probe", r
    assert r["gitOperation"] == {"commit": {"sha": "c5a688e", "branch": "master"}}, r
    assert r["bashEditDiff"] == {"files": [{"filePath": probe + "/hello.txt", "hunks": [{"lines": ["+"]}]}],
                                 "changedFiles": [probe + "/hello.txt"]}, r
elif case == "agent":
    assert p["tool_input"] == {"prompt": "[PRB-1]", "subagent_type": "general-purpose"}, p
elif case == "patch":
    assert line["provider"] == "codex"
    assert p["tool_input"]["command"] == "*** Begin Patch\n*** Add File: new.swift\n+\n+\n*** Update File: old.swift\n-\n+\n*** End Patch", p
    assert p["tool_response"] == {"stdout": "Success. Updated the following files:\nA new.swift\nM old.swift"}, p
elif case == "verify":
    # 검증 명령은 원문, 출력은 없음, 종료 표시 필드는 유지
    assert "SECRET" not in raw
    assert p["tool_input"] == {"command": "cd /w && swift test 2>&1", "run_in_background": False}, p
    assert p["tool_response"] == {"stdout": "", "interrupted": False}, p
elif case == "other":
    assert "SECRET" not in raw and "rm -rf" not in raw
    assert "command" not in p["tool_input"], p
elif case == "failure":
    assert "SECRET" not in raw
    assert p["error"] == "Exit code 3" and p["is_interrupt"] is False, p
    assert p["tool_input"] == {"command": "bash test-fail.sh"}, p
elif case == "ids":
    # 재수신 중복 판정 열쇠(SPEC 5장): tool_use_id·prompt_id(Claude)·turn_id(Codex)는 남는다
    original = json.load(open(sys.argv[3]))
    for key in ("tool_use_id", "prompt_id", "turn_id"):
        if key in original:
            assert p[key] == original[key], (key, p)
elif case == "minimal":
    assert "SECRET" not in raw
    assert p == {"session_id": sys.argv[3], "cwd": "/w", "hook_event_name": "PostToolUse"}, p
else:
    raise SystemExit("모르는 사례 " + case)
PY
expect() { python3 "$TMP/expect.py" "$@"; }

outbox_of PostToolUse < "$TMP/read.json"
check "Read: 파일 내용 없음, 허용 필드만" 'expect read "$TMP/line"'
outbox_of PostToolUse < "$FIX/real-PostToolUse-Edit.json"
check "Edit: 경로·diff 줄 수 유지, 문자열 원문 없음" 'expect edit "$TMP/line"'
outbox_of PostToolUse < "$FIX/real-PostToolUse-Write.json"
check "Write: content는 줄 수만" 'expect write "$TMP/line" "$FIX/real-PostToolUse-Write.json"'
outbox_of PostToolUse < "$FIX/real-PostToolUse-Bash-commit.json"
check "Bash 커밋: 커밋 줄·gitOperation·bashEditDiff 유지, 다른 출력 없음" 'expect commit "$TMP/line"'
outbox_of PreToolUse < "$FIX/real-PreToolUse-Agent.json"
check "Agent: 프롬프트는 카드 ID만" 'expect agent "$TMP/line"'
outbox_of UserPromptSubmit < "$FIX/real-UserPromptSubmit.json"
check "요청: prompt_id 유지" 'expect ids "$TMP/line" "$FIX/real-UserPromptSubmit.json" && grep -q prompt_id "$TMP/line"'
check "Edit: tool_use_id·prompt_id 유지" 'outbox_of PostToolUse < "$FIX/real-PostToolUse-Edit.json" && expect ids "$TMP/line" "$FIX/real-PostToolUse-Edit.json"'
WAYPOINT_AGENT=codex outbox_of UserPromptSubmit < "$FIX/doc-codex-UserPromptSubmit.json"
check "Codex 요청: turn_id 유지" 'expect ids "$TMP/line" "$FIX/doc-codex-UserPromptSubmit.json" && grep -q turn_id "$TMP/line"'
WAYPOINT_AGENT=codex outbox_of PostToolUse < "$FIX/doc-codex-PostToolUse-apply_patch.json"
check "Codex apply_patch: 머리 줄과 +/- 표시만" 'expect patch "$TMP/line"'

printf '%s' '{"session_id":"s","cwd":"/w","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"cd /w && swift test 2>&1","description":"SECRET","run_in_background":false},"tool_response":{"stdout":"SECRET out","stderr":"SECRET err","interrupted":false,"isImage":false}}' | outbox_of PostToolUse
check "검증 명령: 명령 원문 유지, 출력 없음" 'expect verify "$TMP/line"'
printf '%s' '{"session_id":"s","cwd":"/w","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf SECRET-dir"},"tool_response":{"stdout":"SECRET"}}' | outbox_of PostToolUse
check "다른 명령: 명령 빠짐" 'expect other "$TMP/line"'
printf '%s' '{"session_id":"s","cwd":"/w","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"bash test-fail.sh"},"error":"Exit code 3\nSECRET failing output","is_interrupt":false}' | outbox_of PostToolUseFailure
check "실패: error는 Exit code 줄만" 'expect failure "$TMP/line"'

# jq가 없거나 실패: session_id·cwd만. 그것도 못 뽑으면 줄을 쓰지 않는다. 원문은 어느 경우에도 쓰지 않는다.
WAYPOINT_JQ=/nonexistent/jq outbox_of PostToolUse < "$TMP/read.json"; code=$?
check "jq 없음: exit 0, 최소 정보만" '[ $code -eq 0 ] && expect minimal "$TMP/line" s-read'
printf '%s' '{"session_id":"s-bad","cwd":"/w","tool_response":{"stdout":"SECRET' | outbox_of PostToolUse
check "깨진 JSON: 최소 정보만" 'expect minimal "$TMP/line" s-bad'
printf '%s' 'not json SECRET' | outbox_of Stop; code=$?
check "session_id 없음: exit 0, 줄 안 씀" '[ $code -eq 0 ] && [ ! -s "$TMP/line" ]'

exit $FAIL
