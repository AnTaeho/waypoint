#!/bin/bash
# 외부 베타용 macOS 앱을 만든다: 사전 점검 → archive → Developer ID export → 서명 검증 → 공증(Xcode 계정) → Gatekeeper 확인
# → dist/Waypoint-<버전>-<빌드>.zip, .sha256, -summary.txt. 절차와 사람이 할 준비는 docs/RELEASE.md.
#
# 사용: scripts/release-mac.sh [--check] [--icloud] [--skip-notarize] [--allow-dirty] [--version X.Y.Z]
#                              [--poll-interval 초] [--notarize-timeout 분] [--notary-profile 이름]
#       scripts/release-mac.sh --resume-notarize <xcarchive>
#   --check                준비가 됐는지만 본다(빌드 안 함). 없는 것과 할 일을 한 줄씩 출력한다.
#   --icloud               iCloud 동기화를 켜고 빌드한다. 기본은 끔(WAYPOINT_ICLOUD=NO, 기록은 그 Mac에만).
#                          CloudKit Production 스키마를 배포한 뒤에만 쓴다.
#   --skip-notarize        공증 전까지만(내부 확인용). 산출물 이름 끝에 -unnotarized.
#   --allow-dirty          커밋 안 된 변경이 있어도 진행(개발용). 산출물 이름에 -dirty.
#   --version X.Y.Z        마케팅 버전을 이 값으로(project.yml은 고치지 않음).
#   --poll-interval 초      공증 결과를 확인하는 간격(기본 300).
#   --notarize-timeout 분   공증 결과를 기다리는 최대 시간(기본 180).
#   --notary-profile 이름   Xcode 계정 대신 notarytool 키체인 프로필(앱 암호)로 공증한다.
#   --resume-notarize 경로  이미 제출한 xcarchive의 공증 결과 대기부터 이어 한다(중간에 끊겼을 때).
#
# 만든 앱은 실행하지 않는다. 번들 ID가 평소용과 같아 평소용 포트(47821)·저장소를 건드린다. 검증은 정적 검사만.
set -uo pipefail

TEAM_ID="2FCXA77MC5"
BUNDLE_ID="dev.antaeho.waypoint"
CONTAINER="iCloud.dev.antaeho.waypoint"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/build-failure-report.sh"
source "$ROOT/scripts/build-version.sh"
WORK="$ROOT/.build/release-mac"
DIST="$ROOT/dist"

usage_error() { echo "release-mac: $*" >&2; exit 2; }
is_positive_int() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }

check_only=0; skip_notarize=0; allow_dirty=0; version_arg=""; icloud=0
notary_profile=""; poll_interval=300; notarize_timeout=180; resume_archive=""; resume=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) check_only=1 ;;
    --icloud) icloud=1 ;;
    --skip-notarize) skip_notarize=1 ;;
    --allow-dirty) allow_dirty=1 ;;
    --version|--poll-interval|--notarize-timeout|--notary-profile|--resume-notarize)
      [ $# -ge 2 ] && [ -n "$2" ] || usage_error "$1 뒤에 값이 필요함"
      case "$1" in
        --version) version_arg="$2" ;;
        --poll-interval) poll_interval="$2" ;;
        --notarize-timeout) notarize_timeout="$2" ;;
        --notary-profile) notary_profile="$2" ;;
        --resume-notarize) resume_archive="$2"; resume=1 ;;
      esac
      shift ;;
    --version=*) version_arg="${1#--version=}" ;;
    --poll-interval=*) poll_interval="${1#--poll-interval=}" ;;
    --notarize-timeout=*) notarize_timeout="${1#--notarize-timeout=}" ;;
    --notary-profile=*) notary_profile="${1#--notary-profile=}" ;;
    --resume-notarize=*) resume_archive="${1#--resume-notarize=}"; resume=1 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) usage_error "모르는 인자: $1 (--help)" ;;
  esac
  shift
done

is_positive_int "$poll_interval" || usage_error "--poll-interval은 1 이상의 초(정수): $poll_interval"
is_positive_int "$notarize_timeout" || usage_error "--notarize-timeout은 1 이상의 분(정수): $notarize_timeout"
if [ "$resume" = 1 ]; then
  [ -n "$resume_archive" ] || usage_error "--resume-notarize 뒤에 xcarchive 경로가 필요함"
  [ "$skip_notarize" = 0 ] || usage_error "--resume-notarize와 --skip-notarize는 같이 쓸 수 없음"
  [ -z "$notary_profile" ] || usage_error "--resume-notarize는 Xcode 계정 공증만 이어 한다(--notary-profile과 같이 쓸 수 없음)"
  [ -z "$version_arg" ] || usage_error "--resume-notarize는 버전을 아카이브에서 읽는다(--version과 같이 쓸 수 없음)"
  [ "$check_only" = 0 ] || usage_error "--resume-notarize와 --check는 같이 쓸 수 없음"
  [ "$icloud" = 0 ] || usage_error "--resume-notarize는 iCloud 설정을 아카이브에서 읽는다(--icloud와 같이 쓸 수 없음)"
fi
if [ "$skip_notarize" = 1 ] && [ -n "$notary_profile" ]; then
  usage_error "--skip-notarize와 --notary-profile은 같이 쓸 수 없음"
fi

# iCloud 빌드 스위치. 앱 Info.plist WaypointICloud로 들어가고, NO면 앱이 CloudKit을 열지 않는다(AppInstance.cloudKitContainer).
# 엔타이틀먼트(컨테이너·Production)는 켜든 끄든 그대로다.
icloud_setting() { [ "$1" = 1 ] && echo YES || echo NO; }
icloud_label() { [ "$1" = YES ] && echo 켬 || echo 끔; }
ICLOUD_SETTING="$(icloud_setting "$icloud")"
ICLOUD_EXPECTED="$ICLOUD_SETTING"   # 서명 검증이 앱 Info.plist에서 기대하는 원래 값(이어 하기는 아카이브 값, 비어 있을 수 있음)

# ── 점검 항목. 각각 0(됨)/1(안 됨)을 돌려주고, 안 될 때 사람이 할 일을 FIX에 남긴다 ─────────────
FIX=""
has_xcode_team() {
  defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | grep -q "teamID = $TEAM_ID;"
}
has_developer_id_cert() {
  security find-identity -v -p codesigning 2>/dev/null | grep -q "\"Developer ID Application: .*($TEAM_ID)\""
}
notary_profile_state() {
  # 프로필이 있으면 history가 성공한다(제출하지 않는 조회). 없을 때와 다른 오류(네트워크 등)를 가른다.
  local out
  if out="$(xcrun notarytool history --keychain-profile "$notary_profile" 2>&1)"; then
    echo ok
  elif printf '%s' "$out" | grep -q "No Keychain password item found"; then
    echo missing
  else
    echo "error: $(printf '%s' "$out" | head -1)"
  fi
}
tree_dirty() { [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; }

run_check() {
  local missing=0 line state
  echo "Waypoint macOS 배포 준비 점검(팀 $TEAM_ID)"
  if line="$(xcodebuild -version 2>/dev/null | head -1)"; then
    echo "  ✓ Xcode: $line"
  else
    echo "  ✗ Xcode 명령행 도구가 없음"
    echo "    → Xcode를 설치하고 실행: sudo xcode-select -s /Applications/Xcode.app"
    missing=1
  fi
  if has_xcode_team; then
    echo "  ✓ Xcode 계정: 팀 $TEAM_ID 로그인됨"
  else
    echo "  ✗ Xcode 계정에 팀 $TEAM_ID 가 없음"
    echo "    → Xcode > Settings… > Accounts > + > Apple Account 로 팀 계정에 로그인"
    missing=1
  fi
  # 키체인에 없어도 막지 않는다: 자동 서명 export가 Xcode 클라우드 관리 Developer ID 인증서로 서명한다(2026-10-02 확인).
  if has_developer_id_cert; then
    echo "  ✓ Developer ID Application 인증서: 키체인에 있음"
  else
    echo "  ✓ Developer ID Application 인증서: 키체인에 없음 — export 때 Xcode 클라우드 관리 인증서로 서명"
    echo "    (export가 인증서 오류로 실패하면 Xcode > Settings… > Accounts > (팀) > Manage Certificates… > + > Developer ID Application)"
  fi
  if [ -z "$notary_profile" ]; then
    if has_xcode_team; then
      echo "  ✓ 공증: Xcode 계정 로그인(팀 $TEAM_ID)으로 제출"
    else
      echo "  ✗ 공증: Xcode 계정 로그인(팀 $TEAM_ID)이 필요함 — 위 Xcode 계정 항목"
      missing=1
    fi
  else
    state="$(notary_profile_state)"
    case "$state" in
      ok) echo "  ✓ 공증: notarytool 프로필 $notary_profile" ;;
      missing)
        echo "  ✗ 공증: notarytool 프로필 '$notary_profile' 이 없음"
        echo "    → xcrun notarytool store-credentials $notary_profile --apple-id <Apple ID 이메일> --team-id $TEAM_ID"
        echo "      (앱 암호가 필요하다. 프로필 없이 Xcode 계정으로 공증하려면 --notary-profile을 빼고 실행)"
        missing=1 ;;
      *)
        echo "  ✗ 공증: notarytool 프로필을 확인하지 못함: ${state#error: }"
        echo "    → 네트워크를 확인하고 다시: xcrun notarytool history --keychain-profile $notary_profile"
        missing=1 ;;
    esac
  fi
  if tree_dirty; then
    echo "  ✗ 커밋 안 된 변경이 있음(빌드 번호가 내용을 가리키지 못함)"
    echo "    → git status 로 보고 커밋하거나 치운다(개발 중 확인만이면 --allow-dirty)"
    missing=1
  else
    echo "  ✓ 작업 트리 깨끗함"
  fi
  local build version
  if build="$(waypoint_build_number "$ROOT" 2>/dev/null)" && version="$(waypoint_marketing_version "$ROOT" 2>/dev/null)"; then
    echo "  ✓ 다음 산출물: Waypoint-$version-$build (커밋 $(git -C "$ROOT" rev-parse --short HEAD))"
  else
    echo "  ✗ 버전·빌드 번호를 정하지 못함(project.yml MARKETING_VERSION, git 커밋 확인)"
    missing=1
  fi
  if [ "$icloud" = 1 ]; then
    echo "  ✓ iCloud: 켬(--icloud, WAYPOINT_ICLOUD=YES)"
    echo "  ? CloudKit Production 스키마: 이 스크립트로는 확인 못 함"
    echo "    → https://icloud.developer.apple.com > CloudKit Database > $CONTAINER > Production에 Record Type이 있는지 확인"
    echo "      (없으면 Development에서 Deploy Schema Changes…, docs/RELEASE.md 「CloudKit Production 스키마」)"
  else
    echo "  ✓ iCloud: 끔(베타 기본, WAYPOINT_ICLOUD=NO — 기록은 그 Mac에만. 켜려면 --icloud)"
  fi
  if [ "$missing" = 0 ]; then
    echo "준비됨: scripts/release-mac.sh"
  else
    echo "준비 안 됨: 위 ✗ 항목을 처리한 뒤 scripts/release-mac.sh --check"
  fi
  return "$missing"
}

if [ "$check_only" = 1 ]; then
  run_check
  exit $?
fi

# ── 아카이브의 공증 제출 기록(Info.plist Distributions[]) ─────────────────────────────────
# 마지막 destination=upload 항목의 번호. 없으면 실패.
last_upload_index() {
  local plist="$1/Info.plist" i=0 found="" dest
  while dest="$(/usr/libexec/PlistBuddy -c "Print :Distributions:$i:destination" "$plist" 2>/dev/null)"; do
    [ "$dest" = upload ] && found="$i"
    i=$((i + 1))
  done
  [ -n "$found" ] && echo "$found"
}
# UTC ISO(2026-10-02T06:18:36Z) → 에포크 초
iso_epoch() { TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" '+%s' 2>/dev/null; }

# ── 배포 빌드 ────────────────────────────────────────────────────────────────────────
STEPS=()
NAME=""
FAILED=""
COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"
record() { STEPS+=("$1"); echo "· $1"; }
write_summary() {
  [ -n "$NAME" ] || return 0
  mkdir -p "$DIST"
  {
    echo "Waypoint macOS 배포 빌드 — $NAME"
    echo "시각: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "커밋: $COMMIT$( [ "$dirty" = 1 ] && echo ' (커밋 안 된 변경 포함)')"
    echo "버전: $VERSION  빌드: $BUILD  팀: $TEAM_ID"
    echo "iCloud: $(icloud_label "$ICLOUD_SETTING")(WaypointICloud=$ICLOUD_SETTING)"
    echo "Xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
    echo
    for s in ${STEPS[@]+"${STEPS[@]}"}; do echo "- $s"; done
    echo
    if [ -n "$FAILED" ]; then echo "결과: 실패 — $FAILED"; else echo "결과: 성공 — dist/$NAME.zip"; fi
  } > "$DIST/$NAME-summary.txt"
}
fail() {
  FAILED="$*"
  STEPS+=("실패: $*")
  echo "release-mac: $*" >&2
  write_summary
  [ -n "$NAME" ] && echo "요약: $DIST/$NAME-summary.txt" >&2
  exit 1
}

# 서명 검증(정적 검사만, 앱은 실행하지 않는다). $1 = 앱, 결과 요약은 SIGN_SUMMARY.
verify_signature() {
  local app="$1" info authority containers environment aps
  info="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' -c 'Print CFBundleShortVersionString' -c 'Print CFBundleVersion' "$app/Contents/Info.plist" 2>/dev/null | tr '\n' ' ')"
  [ "$info" = "$BUNDLE_ID $VERSION $BUILD " ] || fail "Info.plist가 예상과 다름: '$info'(예상 '$BUNDLE_ID $VERSION $BUILD', $app)"
  local icloud_value
  icloud_value="$(/usr/libexec/PlistBuddy -c 'Print :WaypointICloud' "$app/Contents/Info.plist" 2>/dev/null)"
  echo "  Info.plist WaypointICloud: ${icloud_value:-(없음)}"
  [ "$icloud_value" = "$ICLOUD_EXPECTED" ] || fail "Info.plist WaypointICloud가 ${icloud_value:-(없음)}(예상 ${ICLOUD_EXPECTED:-(없음)}, $app)"
  codesign --verify --deep --strict --verbose=2 "$app" > "$WORK/codesign-verify.txt" 2>&1 \
    || fail "codesign --verify 실패($app): $(tail -3 "$WORK/codesign-verify.txt" | tr '\n' ' ')"
  codesign -dv --verbose=4 "$app" > "$WORK/codesign-info.txt" 2>&1
  authority="$(grep -m1 '^Authority=' "$WORK/codesign-info.txt" | cut -d= -f2-)"
  case "$authority" in
    "Developer ID Application: "*"($TEAM_ID)") ;;
    *) fail "Developer ID 서명이 아님($app): Authority=$authority" ;;
  esac
  grep -q '^TeamIdentifier='"$TEAM_ID"'$' "$WORK/codesign-info.txt" || fail "TeamIdentifier가 $TEAM_ID 가 아님($app)"
  grep -q '^CodeDirectory .*(runtime)' "$WORK/codesign-info.txt" || fail "하드닝 런타임이 꺼져 있음(공증 불가, $app)"
  grep '^Authority=' "$WORK/codesign-info.txt" | sed 's/^/  /'
  ENT="$WORK/entitlements.plist"
  codesign -d --entitlements - --xml "$app" > "$ENT" 2>/dev/null || fail "엔타이틀먼트를 읽지 못함($app)"
  containers="$(ent_get com.apple.developer.icloud-container-identifiers)"
  environment="$(ent_get com.apple.developer.icloud-container-environment)"
  aps="$(ent_get com.apple.developer.aps-environment)"
  echo "  icloud-container-identifiers: $containers"
  echo "  icloud-container-environment: ${environment:-(없음)}"
  echo "  aps-environment: ${aps:-(없음)}"
  printf '%s' "$containers" | grep -q "$CONTAINER" || fail "엔타이틀먼트에 컨테이너 $CONTAINER 가 없음($app)"
  [ "$environment" = "Production" ] || fail "CloudKit 환경이 Production이 아님: ${environment:-(없음)}($app)"
  if grep -q 'com.apple.security.cs\.' "$ENT"; then
    echo "  주의: 하드닝 런타임 예외 엔타이틀먼트가 있음: $(grep -o 'com.apple.security.cs\.[a-z.-]*' "$ENT" | tr '\n' ' ')"
  fi
  SIGN_SUMMARY="$authority, 하드닝 런타임, $CONTAINER $environment, aps $aps, WaypointICloud=$icloud_value"
}
# 배열은 PlistBuddy가 「Array { … }」로 찍는다. 값만 남긴다.
ent_get() { /usr/libexec/PlistBuddy -c "Print :$1" "$ENT" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//;s/^Array { //;s/ }$//'; }

# Xcode 계정으로 제출한 아카이브에서 공증·staple된 앱을 받을 때까지 기다린다. 성공하면 APP을 그 앱으로 바꾼다.
wait_notarized_app() {
  local out_dir="$WORK/notarized" log="$WORK/notarized.log" started now waited submitted elapsed
  started="$(date +%s)"
  submitted="${SUBMIT_EPOCH:-$started}"
  trap 'echo; echo "release-mac: 대기를 멈춤. 이어 하려면: scripts/release-mac.sh --resume-notarize \"$ARCHIVE\"" >&2; exit 130' INT TERM
  echo "· 공증 결과 대기(${poll_interval}초마다 확인, 최대 ${notarize_timeout}분)"
  while :; do
    rm -rf "$out_dir"
    if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$out_dir" > "$log" 2>&1; then
      break
    fi
    if ! grep -q 'is processing and not ready for distribution' "$log"; then
      cp "$log" "$DIST/$NAME-notarize.log" 2>/dev/null
      echo "---- xcodebuild -exportNotarizedApp 출력 ----" >&2
      cat "$log" >&2
      echo "----" >&2
      trap - INT TERM
      fail "공증된 앱을 받지 못함(로그: dist/$NAME-notarize.log). 거절이면 Xcode Organizer의 이 아카이브에서 공증 로그를 본다"
    fi
    now="$(date +%s)"; waited=$(( now - started )); elapsed=$(( (now - submitted) / 60 ))
    if [ "$waited" -ge $(( notarize_timeout * 60 )) ]; then
      trap - INT TERM
      fail "공증 대기 ${notarize_timeout}분 초과(아직 처리 중). 이어 하려면: scripts/release-mac.sh --resume-notarize \"$ARCHIVE\""
    fi
    echo "  $(date '+%H:%M') 처리 중 — 제출 뒤 ${elapsed}분, ${poll_interval}초 뒤 다시 확인"
    sleep "$poll_interval"
  done
  trap - INT TERM
  cp "$log" "$DIST/$NAME-notarize.log" 2>/dev/null
  [ -d "$out_dir/Waypoint.app" ] || fail "공증된 앱이 없음: $out_dir/Waypoint.app"
  now="$(date +%s)"
  NOTARIZED_MINUTES=$(( (now - submitted) / 60 ))
  APP="$out_dir/Waypoint.app"
}

SUBMIT_EPOCH=""
if [ "$resume" = 1 ]; then
  # 이어 하기: archive·export·제출은 건너뛰고 아카이브의 버전·제출 기록에서 시작한다.
  [ -d "$resume_archive" ] || usage_error "--resume-notarize: 아카이브가 없음: $resume_archive"
  ARCHIVE="$(cd "$resume_archive" && pwd)"
  props="$ARCHIVE/Info.plist"
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$props" 2>/dev/null)"
  BUILD="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$props" 2>/dev/null)"
  [ -n "$VERSION" ] && [ -n "$BUILD" ] || usage_error "--resume-notarize: 아카이브 Info.plist에서 버전·빌드를 읽지 못함: $props"
  # iCloud 스위치는 아카이브 안 앱의 Info.plist에서. 키가 없으면(이 스위치 전 아카이브) 앱이 켬으로 돈다.
  ICLOUD_EXPECTED="$(/usr/libexec/PlistBuddy -c 'Print :WaypointICloud' "$ARCHIVE/Products/Applications/Waypoint.app/Contents/Info.plist" 2>/dev/null)"
  ICLOUD_SETTING=YES
  [ "$ICLOUD_EXPECTED" = NO ] && ICLOUD_SETTING=NO
  idx="$(last_upload_index "$ARCHIVE")" || usage_error "--resume-notarize: 이 아카이브에 공증 제출(upload) 기록이 없음: $ARCHIVE"
  submitted_iso="$(/usr/libexec/PlistBuddy -c "Print :Distributions:$idx:uploadEvent:date" "$props" 2>/dev/null)"
  SUBMIT_EPOCH="$(iso_epoch "$submitted_iso")"
  # 처음 실행이 남긴 이름·커밋(같은 빌드일 때만 쓴다)
  dirty=0; NAME="Waypoint-$VERSION-$BUILD"; COMMIT="(알 수 없음 — 이어 하기, 빌드 $BUILD)"
  state_file="$(dirname "$ARCHIVE")/release-state.txt"
  if [ -f "$state_file" ] && [ "$(sed -n 's/^build=//p' "$state_file")" = "$BUILD" ]; then
    NAME="$(sed -n 's/^name=//p' "$state_file")"
    COMMIT="$(sed -n 's/^commit=//p' "$state_file")"
    [ "$(sed -n 's/^dirty=//p' "$state_file")" = 1 ] && dirty=1
  fi
  echo "Waypoint $VERSION ($BUILD) 공증 이어 하기 → dist/$NAME.zip (iCloud $(icloud_label "$ICLOUD_SETTING"))"
  mkdir -p "$WORK" "$DIST"
  if [ -n "$SUBMIT_EPOCH" ]; then
    record "이어 하기: $ARCHIVE (제출 $(date -r "$SUBMIT_EPOCH" '+%Y-%m-%d %H:%M:%S %z'))"
  else
    record "이어 하기: $ARCHIVE (제출 시각 모름)"
  fi
else
  # 1. 사전 점검
  dirty=0
  if tree_dirty; then
    [ "$allow_dirty" = 1 ] || { echo "release-mac: 커밋 안 된 변경이 있음. 커밋하거나 --allow-dirty(개발용)" >&2; exit 1; }
    dirty=1
  fi
  BUILD="$(waypoint_build_number "$ROOT")" || exit 1
  if [ -n "$version_arg" ]; then
    waypoint_valid_version "$version_arg" || { echo "release-mac: --version은 X.Y.Z(숫자): $version_arg" >&2; exit 2; }
    VERSION="$version_arg"
  else
    VERSION="$(waypoint_marketing_version "$ROOT")" || exit 1
  fi
  NAME="Waypoint-$VERSION-$BUILD"
  [ "$dirty" = 1 ] && NAME="$NAME-dirty"
  [ "$skip_notarize" = 1 ] && NAME="$NAME-unnotarized"
  echo "Waypoint $VERSION ($BUILD) → dist/$NAME.zip (iCloud $(icloud_label "$ICLOUD_SETTING"))"

  has_xcode_team || fail "Xcode 계정에 팀 $TEAM_ID 가 없음(scripts/release-mac.sh --check)"
  if [ -n "$notary_profile" ]; then
    state="$(notary_profile_state)"
    [ "$state" = ok ] || fail "공증 프로필 '$notary_profile' 을 쓸 수 없음($state). 프로필 없이 Xcode 계정으로 하려면 --notary-profile을 뺀다"
  fi
  if has_developer_id_cert; then
    record "사전 점검: 통과(Developer ID 인증서 키체인에 있음)"
  else
    record "사전 점검: 통과(Developer ID 인증서가 키체인에 없음 — Xcode 클라우드 관리 서명을 시도)"
  fi

  rm -rf "$WORK"
  mkdir -p "$WORK" "$DIST"
  ARCHIVE="$WORK/Waypoint.xcarchive"
  EXPORT="$WORK/export"
  APP="$EXPORT/Waypoint.app"

  # 2. archive. 하드닝 런타임은 공증 필수라 여기서만 켠다(project.yml은 평소용 install-local.sh도 써서 그대로 둔다).
  #    iCloud는 기본 끔(WAYPOINT_ICLOUD=NO). project.yml 기본 YES는 평소용·개발용 몫.
  log="$WORK/archive.log"
  if ! xcodebuild -project "$ROOT/Waypoint.xcodeproj" -scheme Waypoint -configuration Release \
      -destination 'generic/platform=macOS' -derivedDataPath "$WORK/DerivedData" -archivePath "$ARCHIVE" \
      -allowProvisioningUpdates \
      MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" ENABLE_HARDENED_RUNTIME=YES \
      WAYPOINT_ICLOUD="$ICLOUD_SETTING" \
      archive > "$log" 2>&1; then
    report_build_failure "$log"
    fail "archive 실패(전체 로그: $log)"
  fi
  printf 'name=%s\nbuild=%s\ncommit=%s\ndirty=%s\n' "$NAME" "$BUILD" "$COMMIT" "$dirty" > "$WORK/release-state.txt"
  record "archive: 성공($ARCHIVE, WAYPOINT_ICLOUD=$ICLOUD_SETTING)"

  # 3. Developer ID export(자동 서명). ExportOptions는 여기서 만든다. destination: export(파일로) / upload(공증 제출)
  export_options() {
    cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>destination</key>
	<string>$1</string>
</dict>
</plist>
PLIST
  }
  OPTIONS="$WORK/ExportOptions.plist"
  export_options export > "$OPTIONS"
  log="$WORK/export.log"
  if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$OPTIONS" \
      -allowProvisioningUpdates > "$log" 2>&1; then
    report_build_failure "$log"
    fail "Developer ID export 실패(전체 로그: $log). scripts/release-mac.sh --check 의 인증서 항목 참고"
  fi
  [ -d "$APP" ] || fail "export 결과가 없음: $APP"
  record "export: 성공(developer-id, $APP)"

  # 4. 서명 검증. 제출 전에 한 번(45분 기다린 뒤 서명 문제를 알지 않게)
  verify_signature "$APP"
  record "서명 검증: 통과($SIGN_SUMMARY)"
fi

# 5. 공증
if [ "$skip_notarize" = 1 ]; then
  record "공증: 건너뜀(--skip-notarize)"
elif [ -n "$notary_profile" ]; then
  # 대안: notarytool 키체인 프로필(앱 암호). zip 제출 → 기다림 → staple
  submit_zip="$WORK/Waypoint-notarize.zip"
  ditto -c -k --keepParent "$APP" "$submit_zip" || fail "공증용 zip 실패"
  echo "· 공증 제출(notarytool, 몇 분 걸린다)"
  out="$WORK/notary-submit.json"
  xcrun notarytool submit "$submit_zip" --keychain-profile "$notary_profile" --wait --output-format json > "$out" 2> "$WORK/notary-submit.err"
  status="$(plutil -extract status raw -o - "$out" 2>/dev/null)"
  sub_id="$(plutil -extract id raw -o - "$out" 2>/dev/null)"
  if [ -n "$sub_id" ]; then
    xcrun notarytool log "$sub_id" --keychain-profile "$notary_profile" "$DIST/$NAME-notary-log.json" > /dev/null 2>&1
  fi
  [ "$status" = "Accepted" ] || fail "공증 실패: 상태 '${status:-없음}' 제출 ${sub_id:-없음}. 로그: dist/$NAME-notary-log.json, $(head -2 "$WORK/notary-submit.err" | tr '\n' ' ')"
  record "공증: Accepted(notarytool 프로필 $notary_profile, 제출 $sub_id, 로그 dist/$NAME-notary-log.json)"
  xcrun stapler staple "$APP" > "$WORK/staple.txt" 2>&1 || fail "stapler staple 실패: $(tail -2 "$WORK/staple.txt" | tr '\n' ' ')"
  xcrun stapler validate "$APP" > "$WORK/staple-validate.txt" 2>&1 || fail "stapler validate 실패: $(tail -2 "$WORK/staple-validate.txt" | tr '\n' ' ')"
  record "staple: 성공"
else
  # 기본: Xcode 계정으로 제출(upload export) → 공증·staple된 앱을 받을 때까지 -exportNotarizedApp 재시도
  if [ "$resume" = 0 ]; then
    UPLOAD_OPTIONS="$WORK/ExportOptions-upload.plist"
    export_options upload > "$UPLOAD_OPTIONS"
    log="$WORK/upload.log"
    echo "· 공증 제출(Xcode 계정)"
    if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$WORK/upload" -exportOptionsPlist "$UPLOAD_OPTIONS" \
        -allowProvisioningUpdates > "$log" 2>&1; then
      report_build_failure "$log"
      fail "공증 제출 실패(전체 로그: $log). Xcode 계정 로그인 상태를 확인(scripts/release-mac.sh --check)"
    fi
    idx="$(last_upload_index "$ARCHIVE")" || fail "제출은 성공했는데 아카이브에 제출 기록이 없음($ARCHIVE/Info.plist)"
    SUBMIT_EPOCH="$(iso_epoch "$(/usr/libexec/PlistBuddy -c "Print :Distributions:$idx:uploadEvent:date" "$ARCHIVE/Info.plist" 2>/dev/null)")"
    [ -n "$SUBMIT_EPOCH" ] || SUBMIT_EPOCH="$(date +%s)"
    record "공증 제출: 성공(Xcode 계정, $(date -r "$SUBMIT_EPOCH" '+%Y-%m-%d %H:%M:%S %z'), 로그 $log)"
  fi
  wait_notarized_app
  record "공증: 수락(제출 뒤 ${NOTARIZED_MINUTES}분째 확인, 로그 dist/$NAME-notarize.log)"
  # 받은 앱은 따로 서명된 번들이라 다시 본다
  verify_signature "$APP"
  record "공증된 앱 서명 검증: 통과($SIGN_SUMMARY)"
  xcrun stapler validate "$APP" > "$WORK/staple-validate.txt" 2>&1 || fail "stapler validate 실패: $(tail -2 "$WORK/staple-validate.txt" | tr '\n' ' ')"
  record "staple: 확인($(tail -1 "$WORK/staple-validate.txt"))"
fi

# 6. Gatekeeper. 공증 전이면 거부가 정상이라 기록만 한다.
spctl_out="$(spctl -a -vvv -t exec "$APP" 2>&1)"; spctl_rc=$?
echo "$spctl_out" | sed 's/^/  /'
spctl_line="$(printf '%s' "$spctl_out" | tr '\n' ' ' | sed 's/  */ /g')"
if [ "$skip_notarize" = 1 ]; then
  record "Gatekeeper: 공증 전이라 판정만 기록(rc=$spctl_rc): $spctl_line"
else
  [ "$spctl_rc" = 0 ] && printf '%s' "$spctl_out" | grep -q 'source=Notarized Developer ID' \
    || fail "Gatekeeper가 받지 않음(rc=$spctl_rc): $spctl_line"
  record "Gatekeeper: 통과($spctl_line)"
fi

# 7. 최종 zip(staple된 앱)과 SHA256
zip="$DIST/$NAME.zip"
rm -f "$zip" "$zip.sha256"
ditto -c -k --keepParent "$APP" "$zip" || fail "최종 zip 실패"
(cd "$DIST" && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256") || fail "SHA256 실패"
record "산출물: dist/$NAME.zip ($(du -h "$zip" | cut -f1 | tr -d ' ')), SHA256 $(cut -d' ' -f1 "$zip.sha256")"
write_summary
echo "완료: $zip"
echo "요약: $DIST/$NAME-summary.txt"
