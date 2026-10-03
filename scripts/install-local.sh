#!/bin/bash
# 평소용 Waypoint를 새 버전으로 바꾼다: Release 빌드(팀 서명) → 서명 확인 → 떠 있는 평소용 정상 종료 → /Applications 교체 → 옛 로그인 항목 정리 → 실행 → 포트 확인.
# 로그인 항목은 앱이 `SMAppService`로 등록한다(TRK-55). 스크립트는 옛 방식(System Events) 항목만 지운다.
# 여러 번 돌려도 안전하다. 어느 단계든 실패하면 이유를 출력하고 exit 1. 강제 종료는 하지 않는다.
#
# 사용: scripts/install-local.sh
# 환경 변수(확인용):
#   WAYPOINT_INSTALL_DIR  설치 위치(기본 /Applications)
#   WAYPOINT_SKIP_BUILD   1이면 빌드를 건너뛰고 이미 있는 .build/release 결과를 쓴다
set -uo pipefail

BUNDLE_ID="dev.antaeho.waypoint"
PORT=47821
CONTAINER="iCloud.dev.antaeho.waypoint"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/build-failure-report.sh"
source "$ROOT/scripts/build-version.sh"
DERIVED="$ROOT/.build/release"
BUILT="$DERIVED/Build/Products/Release/Waypoint.app"
DEST_DIR="${WAYPOINT_INSTALL_DIR:-/Applications}"
DEST="$DEST_DIR/Waypoint.app"
WAIT=10

fail() { echo "install-local: $*" >&2; exit 1; }
step() { echo "· $*"; }

is_running() {
  # `is running`은 앱을 띄우지 않는다(`tell application id … to quit`는 꺼져 있으면 띄운다).
  [ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null)" = "true" ]
}

listen_pid() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1; }

# 1. 빌드. CloudKit·푸시 엔타이틀먼트는 프로파일이 있어야 해서 팀 서명(project.yml)으로 빌드한다.
#    `-allowProvisioningUpdates`: 프로파일이 없거나 만료됐으면 Xcode 계정으로 새로 받는다.
#    빌드 번호는 커밋 수(build-version.sh). 번호가 바뀌어야 새 앱이 첫 실행 때 저장소를 백업한다.
if [ "${WAYPOINT_SKIP_BUILD:-0}" != "1" ]; then
  build_number="$(waypoint_build_number "$ROOT")" || fail "빌드 번호를 정하지 못함"
  step "Release 빌드(빌드 번호 $build_number)"
  log="$DERIVED/install-build.log"
  mkdir -p "$DERIVED"
  if ! xcodebuild -project "$ROOT/Waypoint.xcodeproj" -scheme Waypoint -configuration Release \
      -destination 'platform=macOS' -derivedDataPath "$DERIVED" -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$build_number" build > "$log" 2>&1; then
    report_build_failure "$log"
    fail "빌드 실패(전체 로그: $log)"
  fi
fi
[ -d "$BUILT" ] || fail "빌드 결과가 없음: $BUILT"
id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$BUILT/Contents/Info.plist" 2>/dev/null)"
[ "$id" = "$BUNDLE_ID" ] || fail "빌드 결과의 번들 ID가 $BUNDLE_ID 가 아님: $id"
# 서명·엔타이틀먼트가 없으면 앱이 CloudKit 없이 뜨거나 실행이 거부된다. 평소용을 끄기 전에 확인한다.
codesign --verify --strict "$BUILT" 2>/dev/null || fail "서명 확인 실패: $BUILT"
codesign -d --entitlements :- "$BUILT" 2>/dev/null | grep -q "<string>$CONTAINER</string>" \
  || fail "빌드 결과에 CloudKit 컨테이너 $CONTAINER 엔타이틀먼트가 없음"

# 2. 떠 있는 평소용 정상 종료(같은 번들 ID면 옛 Debug 빌드도 여기서 꺼진다)
if is_running; then
  step "떠 있는 평소용 종료"
  osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
  for _ in $(seq 1 "$WAIT"); do
    is_running || break
    sleep 1
  done
  is_running && fail "평소용이 ${WAIT}초 안에 꺼지지 않음. 직접 종료한 뒤 다시 실행(강제 종료는 하지 않음)"
fi
# 포트가 아직 잡혀 있으면(다른 프로세스) 새 앱이 열지 못한다.
for _ in $(seq 1 "$WAIT"); do
  [ -z "$(listen_pid)" ] && break
  sleep 1
done
pid="$(listen_pid)"
[ -z "$pid" ] || fail "포트 $PORT 를 다른 프로세스가 쓰는 중: $(ps -o pid=,comm= -p "$pid")"

# 3. 교체
step "$DEST 교체"
mkdir -p "$DEST_DIR" || fail "$DEST_DIR 를 만들 수 없음"
tmp="$DEST_DIR/.Waypoint.app.installing"
rm -rf "$tmp"
ditto "$BUILT" "$tmp" || fail "복사 실패: $BUILT → $tmp"
rm -rf "$DEST" || fail "옛 앱을 지울 수 없음: $DEST"
mv "$tmp" "$DEST" || fail "옮기기 실패: $tmp → $DEST"

# 4. 옛 로그인 항목(System Events로 만든 것)이 있으면 지운다. 새 방식 등록은 앱이 한다(TRK-55).
#    지웠으면 앱이 첫 실행 때 알 수 있게 표시를 남긴다(앱이 읽고 지운다). 실행 전에 해야 앱이 첫 실행에서 본다.
login="앱이 관리"
if [ "$DEST_DIR" = "/Applications" ] && [ "$(defaults read "$BUNDLE_ID" loginItem.autoApplied 2>/dev/null)" = "1" ]; then
  # 앱이 이미 새 방식으로 등록했다. System Events 목록에 그 항목도 보이므로 지우지 않는다
  :
elif [ "$DEST_DIR" = "/Applications" ]; then
  removed="$(osascript -e 'tell application "System Events"
    if exists login item "Waypoint" then
      delete login item "Waypoint"
      return "removed"
    end if
  end tell' 2>/dev/null)"
  rc=$?
  if [ "$removed" = "removed" ]; then
    defaults write "$BUNDLE_ID" WaypointLoginItemLegacyRemoved -bool true
    login="앱이 관리(옛 항목 지움)"
  elif [ "$rc" -ne 0 ]; then
    # 자동화 권한이 없으면 옛 항목이 남아 두 줄이 될 수 있다
    login="앱이 관리(옛 항목 확인 못 함 — 시스템 설정 > 일반 > 로그인 항목에서 확인)"
  fi
else
  login="건너뜀(설치 위치가 /Applications 아님)"
fi

# 5. 실행(경로로 연다. 같은 번들 ID의 다른 빌드가 디스크에 남아 있을 수 있다). -g: 쓰던 앱의 초점을 뺏지 않게 뒤에서
step "실행"
open -g "$DEST" || fail "실행 실패: $DEST"
pid=""
for _ in $(seq 1 "$WAIT"); do
  pid="$(listen_pid)"
  [ -n "$pid" ] && break
  sleep 1
done
[ -n "$pid" ] || fail "${WAIT}초 안에 포트 $PORT 가 열리지 않음"
comm="$(ps -o comm= -p "$pid")"
case "$comm" in
  "$DEST"/*) ;;
  *) fail "포트 $PORT 를 연 것이 설치한 앱이 아님: $pid $comm" ;;
esac

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DEST/Contents/Info.plist" 2>/dev/null)"
build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$DEST/Contents/Info.plist" 2>/dev/null)"
echo "Waypoint $version ($build) 설치됨: $DEST · PID $pid · 127.0.0.1:$PORT LISTEN · 로그인 항목 $login"
