#!/bin/bash
# waypoint-statusline-tap.sh 동작 확인. 임시 폴더만 쓰고 실제 Application Support는 건드리지 않는다.
# 사용: bash integration/statusline/test-statusline-tap.sh   (jq·python3 필요)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TAP="$HERE/waypoint-statusline-tap.sh"
TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export WAYPOINT_SUPPORT_DIR="$TMP/support"
FAIL=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAIL=1; fi; }

WITH="$TMP/with.json"
WITHOUT="$TMP/without.json"
cat > "$WITH" <<'JSON'
{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp/한글 폴더"},"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1790000000},"seven_day":{"used_percentage":18,"resets_at":1790500000}}}
JSON
printf '{"model":{"display_name":"Opus"}}' > "$WITHOUT"

# 가짜 원래 상태줄: 받은 입력을 그대로 내보내고 끝에 표시 한 줄, 종료 코드 3
FAKE="$TMP/fake-statusline.sh"
cat > "$FAKE" <<'SH'
cat
printf '\n\033[38;2;255;135;175mfake 상태줄\033[0m\n'
exit 3
SH

# 1) 출력 동일: 인자로 받은 명령
bash "$FAKE" < "$WITH" > "$TMP/direct.out"; direct_code=$?
bash "$TAP" bash "$FAKE" < "$WITH" > "$TMP/tap.out"; tap_code=$?
check "인자: 출력 바이트 동일" 'cmp -s "$TMP/direct.out" "$TMP/tap.out"'
check "인자: 종료 코드 동일" '[ $direct_code -eq $tap_code ]'

# 2) 출력 동일: 환경 변수로 받은 명령
WAYPOINT_STATUSLINE_NEXT="bash '$FAKE'" bash "$TAP" < "$WITH" > "$TMP/tap-env.out"
check "환경 변수: 출력 바이트 동일" 'cmp -s "$TMP/direct.out" "$TMP/tap-env.out"'

# 3) usage.json 형식
check "usage.json 생김" '[ -f "$WAYPOINT_SUPPORT_DIR/usage.json" ]'
check "usage.json 형식" 'python3 -c "
import json,sys,time
d=json.load(open(sys.argv[1]))
assert isinstance(d[\"capturedAt\"], int) and abs(d[\"capturedAt\"]-time.time()) < 60
r=d[\"rateLimits\"]
assert r[\"five_hour\"]=={\"used_percentage\":42.5,\"resets_at\":1790000000}
assert r[\"seven_day\"][\"used_percentage\"]==18
" "$WAYPOINT_SUPPORT_DIR/usage.json"'
check "임시 파일 안 남음" '[ -z "$(ls -A "$WAYPOINT_SUPPORT_DIR" | grep -v "^usage.json$")" ]'
check "session_id 없음: session-status.json 안 씀" '[ ! -e "$WAYPOINT_SUPPORT_DIR/session-status.json" ]'

# 4) rate_limits 없음: 파일 안 씀, 출력 동일
rm -f "$WAYPOINT_SUPPORT_DIR/usage.json"
bash "$FAKE" < "$WITHOUT" > "$TMP/direct2.out"
bash "$TAP" bash "$FAKE" < "$WITHOUT" > "$TMP/tap2.out"
check "rate_limits 없음: 출력 동일" 'cmp -s "$TMP/direct2.out" "$TMP/tap2.out"'
check "rate_limits 없음: 파일 안 씀" '[ ! -e "$WAYPOINT_SUPPORT_DIR/usage.json" ]'

# 5) 깨진 JSON: 파일 안 씀, 출력 동일
printf 'not json' | bash "$FAKE" > "$TMP/direct3.out"
printf 'not json' | bash "$TAP" bash "$FAKE" > "$TMP/tap3.out" 2> "$TMP/tap3.err"
check "깨진 입력: 출력 동일" 'cmp -s "$TMP/direct3.out" "$TMP/tap3.out"'
check "깨진 입력: stderr 없음" '[ ! -s "$TMP/tap3.err" ]'
check "깨진 입력: 파일 안 씀" '[ ! -e "$WAYPOINT_SUPPORT_DIR/usage.json" ]'

# 6) 쓰기 불가 폴더: 출력 동일, stderr 없음
mkdir -p "$TMP/locked"; chmod 555 "$TMP/locked"
WAYPOINT_SUPPORT_DIR="$TMP/locked" bash "$TAP" bash "$FAKE" < "$WITH" > "$TMP/tap4.out" 2> "$TMP/tap4.err"
check "쓰기 불가: 출력 동일" 'cmp -s "$TMP/direct.out" "$TMP/tap4.out"'
check "쓰기 불가: stderr 없음" '[ ! -s "$TMP/tap4.err" ]'
WAYPOINT_SUPPORT_DIR="$TMP/locked/sub" bash "$TAP" bash "$FAKE" < "$WITH" > "$TMP/tap5.out" 2> "$TMP/tap5.err"
check "만들 수 없는 폴더: 출력 동일" 'cmp -s "$TMP/direct.out" "$TMP/tap5.out" && [ ! -s "$TMP/tap5.err" ]'

# 7) jq 없음: 출력 동일, 파일 안 씀
mkdir -p "$TMP/nojq"
for tool in bash cat mkdir mv rm printf; do p="$(command -v "$tool")"; [ -x "$p" ] && ln -s "$p" "$TMP/nojq/$tool"; done
rm -f "$WAYPOINT_SUPPORT_DIR/usage.json"
PATH="$TMP/nojq" "$TMP/nojq/bash" "$TAP" "$TMP/nojq/bash" "$FAKE" < "$WITH" > "$TMP/tap6.out" 2> "$TMP/tap6.err"
check "jq 없음: 출력 동일" 'cmp -s "$TMP/direct.out" "$TMP/tap6.out" && [ ! -s "$TMP/tap6.err" ]'
check "jq 없음: 파일 안 씀" '[ ! -e "$WAYPOINT_SUPPORT_DIR/usage.json" ]'

# 8) 다음 명령 없음: 출력 없음, exit 0
out="$(bash "$TAP" < "$WITH")"; code=$?
check "다음 명령 없음: 출력 없음, exit 0" '[ -z "$out" ] && [ $code -eq 0 ]'

# 9) 세션 이름·컨텍스트 사용률(session-status.json)
STATUS="$WAYPOINT_SUPPORT_DIR/session-status.json"
rm -rf "$WAYPOINT_SUPPORT_DIR"
py() { python3 -c "import json,sys,time
d=json.load(open(sys.argv[1])); now=time.time()
$1" "$STATUS"; }
NAMED="$TMP/named.json"
cat > "$NAMED" <<'JSON'
{"session_id":"aaaa-1111","session_name":"결제 \"영수증\" 고치기","context_window":{"used_percentage":62.5},"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1790000000}}}
JSON
bash "$FAKE" < "$NAMED" > "$TMP/direct9.out"; direct_code=$?
bash "$TAP" bash "$FAKE" < "$NAMED" > "$TMP/tap9.out" 2> "$TMP/tap9.err"; tap_code=$?
check "세션: 출력 바이트·종료 코드 동일, stderr 없음" 'cmp -s "$TMP/direct9.out" "$TMP/tap9.out" && [ $direct_code -eq $tap_code ] && [ ! -s "$TMP/tap9.err" ]'
check "세션: 항목 생김" 'py "
e=d[\"aaaa-1111\"]
assert e[\"name\"]==\"결제 \\\"영수증\\\" 고치기\" and e[\"context\"]==62.5
assert isinstance(e[\"at\"], int) and abs(e[\"at\"]-now) < 60
assert len(d)==1"'
check "세션: usage.json도 그대로 씀" 'python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
assert d[\"rateLimits\"]=={\"five_hour\":{\"used_percentage\":42.5,\"resets_at\":1790000000}} and set(d)=={\"capturedAt\",\"rateLimits\"}
" "$WAYPOINT_SUPPORT_DIR/usage.json"'

# 다른 세션(이름 없음·rate_limits 없음)이 더해지고 앞 항목은 남는다
rm -f "$WAYPOINT_SUPPORT_DIR/usage.json"
printf '{"session_id":"bbbb-2222","context_window":{"used_percentage":91}}' | bash "$TAP" bash "$FAKE" > /dev/null
check "세션: 이름 없는 입력은 name 키 없음, 앞 항목 유지" 'py "
assert d[\"bbbb-2222\"][\"context\"]==91 and \"name\" not in d[\"bbbb-2222\"]
assert d[\"aaaa-1111\"][\"name\"].startswith(\"결제\") and len(d)==2"'
check "세션: rate_limits 없으면 usage.json 안 씀" '[ ! -e "$WAYPOINT_SUPPORT_DIR/usage.json" ]'

# 같은 세션이 다시 오면 자기 항목만 바뀐다
printf '{"session_id":"aaaa-1111","session_name":"새 이름","context_window":{"used_percentage":70}}' | bash "$TAP" > /dev/null
check "세션: 자기 항목만 갱신" 'py "
assert d[\"aaaa-1111\"][\"name\"]==\"새 이름\" and d[\"aaaa-1111\"][\"context\"]==70
assert d[\"bbbb-2222\"][\"context\"]==91 and len(d)==2"'

# 사용률이 null·없음, 이름이 빈 글이면 키가 없다
printf '{"session_id":"cccc-3333","session_name":"","context_window":{"used_percentage":null}}' | bash "$TAP" > /dev/null
printf '{"session_id":"dddd-4444","context_window":"x"}' | bash "$TAP" > /dev/null
check "세션: null 사용률·빈 이름은 at만" 'py "
assert set(d[\"cccc-3333\"])=={\"at\"} and set(d[\"dddd-4444\"])=={\"at\"} and len(d)==4"'

# session_id가 없거나 글자가 아니면 그대로 둔다
cp "$STATUS" "$TMP/status-before.json"
printf '{"session_name":"이름만","context_window":{"used_percentage":5}}' | bash "$TAP" bash "$FAKE" > "$TMP/tap10.out" 2> "$TMP/tap10.err"
printf '{"session_id":7,"session_name":"숫자 ID"}' | bash "$TAP" > /dev/null
printf '{"session_id":""}' | bash "$TAP" > /dev/null
check "세션: session_id 없는 입력은 파일 그대로, stderr 없음" 'cmp -s "$STATUS" "$TMP/status-before.json" && [ ! -s "$TMP/tap10.err" ]'

# 24시간 넘은 항목·모양이 다른 항목은 다음에 쓸 때 빠진다
now=$(python3 -c 'import time;print(int(time.time()))')
printf '{"old":{"at":%s,"name":"어제"},"recent":{"at":%s,"context":12},"bad":"x","noat":{"name":"시각 없음"}}\n' "$((now - 90000))" "$((now - 80000))" > "$STATUS"
printf '{"session_id":"eeee-5555","session_name":"오늘"}' | bash "$TAP" > /dev/null
check "세션: 24시간 넘은 항목 제거" 'py "
assert set(d)=={\"recent\",\"eeee-5555\"}, set(d)
assert d[\"recent\"]=={\"at\":$((now - 80000)),\"context\":12} and d[\"eeee-5555\"][\"name\"]==\"오늘\""'

# 깨진 기존 파일은 새로 쓴다
printf 'not json' > "$STATUS"
printf '{"session_id":"ffff-6666","session_name":"다시"}' | bash "$TAP" > /dev/null 2> "$TMP/tap11.err"
check "세션: 깨진 기존 파일은 새로 씀" 'py "assert set(d)=={\"ffff-6666\"}" && [ ! -s "$TMP/tap11.err" ]'
check "세션: 임시 파일 안 남음" '[ -z "$(ls -A "$WAYPOINT_SUPPORT_DIR" | grep -v "^session-status.json$")" ]'

# 쓰기 불가 폴더·jq 없음: 출력 동일, 파일 안 씀
WAYPOINT_SUPPORT_DIR="$TMP/locked" bash "$TAP" bash "$FAKE" < "$NAMED" > "$TMP/tap12.out" 2> "$TMP/tap12.err"
check "세션: 쓰기 불가 폴더도 출력 동일" 'cmp -s "$TMP/direct9.out" "$TMP/tap12.out" && [ ! -s "$TMP/tap12.err" ] && [ -z "$(ls -A "$TMP/locked")" ]'
rm -f "$STATUS"
PATH="$TMP/nojq" "$TMP/nojq/bash" "$TAP" "$TMP/nojq/bash" "$FAKE" < "$NAMED" > "$TMP/tap13.out" 2> "$TMP/tap13.err"
check "세션: jq 없음도 출력 동일, 파일 안 씀" 'cmp -s "$TMP/direct9.out" "$TMP/tap13.out" && [ ! -s "$TMP/tap13.err" ] && [ ! -e "$STATUS" ]'

# 10) 추가 시간: 가짜 명령 직접 vs 중계 경유, 각 30회
t() { python3 -c 'import time;print(time.perf_counter())'; }
start=$(t); for i in $(seq 30); do bash "$FAKE" < "$NAMED" >/dev/null; done; mid=$(t)
for i in $(seq 30); do bash "$TAP" bash "$FAKE" < "$NAMED" >/dev/null; done; end=$(t)
python3 -c "import sys;a,b,c=map(float,sys.argv[1:]);d=(b-a)/30*1000;v=(c-b)/30*1000;print('info 직접 %.1f ms, 중계 %.1f ms, 추가 %.1f ms (30회 평균)'%(d,v,v-d))" "$start" "$mid" "$end"

[ $FAIL -eq 0 ] && echo "모두 통과" || echo "실패 있음"
exit $FAIL
