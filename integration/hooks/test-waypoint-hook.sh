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
check "outbox 형식" 'python3 -c "import json,sys; l=json.loads(open(sys.argv[1]).readline()); assert l[\"event\"]==\"SessionStart\" and isinstance(l[\"receivedAt\"],int) and l[\"payload\"][\"source\"]==\"startup\"" "$WAYPOINT_SUPPORT_DIR/outbox.jsonl"'

# 2) 빈 입력: 아무것도 안 함
rm -f "$WAYPOINT_SUPPORT_DIR/outbox.jsonl"
bash "$HOOK" Stop < /dev/null; code=$?
check "빈 입력: exit 0, outbox 없음" '[ $code -eq 0 ] && [ ! -e "$WAYPOINT_SUPPORT_DIR/outbox.jsonl" ]'

# 3) 로깅 모드: hook-log에도 남김
WAYPOINT_HOOK_LOG=1 bash "$HOOK" Stop < "$FIX/doc-Stop.json"
check "로깅 모드: hook-log 파일" '[ "$(cat "$WAYPOINT_SUPPORT_DIR"/hook-log/*.jsonl | wc -l)" -eq 1 ]'

# 4) 앱 있음: SessionStart는 본문을 stdout으로, 나머지는 stdout 없음, outbox 안 씀
export WAYPOINT_PORT=47998
cat > "$TMP/server.py" <<'PY'
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        if self.path == '/hooks/SessionStart':
            body = 'Waypoint: LDG 가계부 앱'.encode()
            self.send_response(200); self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
        else:
            self.send_response(204); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
python3 "$TMP/server.py" "$WAYPOINT_PORT" & SERVER=$!
sleep 1
rm -f "$WAYPOINT_SUPPORT_DIR/outbox.jsonl"
out="$(bash "$HOOK" SessionStart < "$FIX/doc-SessionStart.json")"
check "앱 있음: SessionStart 본문 출력" '[ "$out" = "Waypoint: LDG 가계부 앱" ]'
out="$(bash "$HOOK" PostToolUse < "$FIX/doc-PostToolUse-Edit.json")"
check "앱 있음: 다른 이벤트는 stdout 없음" '[ -z "$out" ]'
check "앱 있음: outbox 안 씀" '[ ! -e "$WAYPOINT_SUPPORT_DIR/outbox.jsonl" ]'

exit $FAIL
