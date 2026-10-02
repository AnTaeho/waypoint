#!/bin/bash
# 외부 베타용 macOS 앱을 만든다: 사전 점검 → archive → Developer ID export → 서명 검증 → 공증 → staple → Gatekeeper 확인
# → dist/Waypoint-<버전>-<빌드>.zip, .sha256, -summary.txt. 절차와 사람이 할 준비는 docs/RELEASE.md.
#
# 사용: scripts/release-mac.sh [--check] [--skip-notarize] [--allow-dirty] [--version X.Y.Z]
#   --check          준비가 됐는지만 본다(빌드 안 함). 없는 것과 할 일을 한 줄씩 출력한다.
#   --skip-notarize  공증 전까지만(내부 확인용). 산출물 이름 끝에 -unnotarized.
#   --allow-dirty    커밋 안 된 변경이 있어도 진행(개발용). 산출물 이름에 -dirty.
#   --version X.Y.Z  마케팅 버전을 이 값으로(project.yml은 고치지 않음).
#
# 만든 앱은 실행하지 않는다. 번들 ID가 평소용과 같아 평소용 포트(47821)·저장소를 건드린다. 검증은 정적 검사만.
set -uo pipefail

TEAM_ID="2FCXA77MC5"
BUNDLE_ID="dev.antaeho.waypoint"
CONTAINER="iCloud.dev.antaeho.waypoint"
NOTARY_PROFILE="waypoint-notary"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/build-failure-report.sh"
source "$ROOT/scripts/build-version.sh"
WORK="$ROOT/.build/release-mac"
DIST="$ROOT/dist"

check_only=0; skip_notarize=0; allow_dirty=0; version_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) check_only=1 ;;
    --skip-notarize) skip_notarize=1 ;;
    --allow-dirty) allow_dirty=1 ;;
    --version)
      [ $# -ge 2 ] || { echo "release-mac: --version 뒤에 X.Y.Z가 필요함" >&2; exit 2; }
      version_arg="$2"; shift ;;
    --version=*) version_arg="${1#--version=}" ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "release-mac: 모르는 인자: $1 (--help)" >&2; exit 2 ;;
  esac
  shift
done

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
  if out="$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>&1)"; then
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
  if has_developer_id_cert; then
    echo "  ✓ Developer ID Application 인증서: 키체인에 있음"
  else
    echo "  ✗ Developer ID Application 인증서가 키체인에 없음"
    echo "    → Xcode > Settings… > Accounts > (팀 계정) > Manage Certificates… > 왼쪽 아래 + > Developer ID Application"
    echo "      (Xcode가 클라우드 관리 인증서로 서명할 수도 있다. 이 경우에도 export 단계가 되는지 scripts/release-mac.sh --skip-notarize로 확인)"
    missing=1
  fi
  state="$(notary_profile_state)"
  case "$state" in
    ok) echo "  ✓ 공증 자격 증명 프로필: $NOTARY_PROFILE" ;;
    missing)
      echo "  ✗ 공증 자격 증명 프로필 '$NOTARY_PROFILE' 이 없음"
      echo "    → https://account.apple.com > 로그인 및 보안 > 앱 암호 > 암호 생성(이름 예: waypoint-notary)"
      echo "    → xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <Apple ID 이메일> --team-id $TEAM_ID"
      echo "      (암호를 물으면 위에서 만든 앱 암호를 붙여 넣는다)"
      missing=1 ;;
    *)
      echo "  ✗ 공증 자격 증명 프로필을 확인하지 못함: ${state#error: }"
      echo "    → 네트워크를 확인하고 다시: xcrun notarytool history --keychain-profile $NOTARY_PROFILE"
      missing=1 ;;
  esac
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
  echo "  ? CloudKit Production 스키마: 이 스크립트로는 확인 못 함"
  echo "    → https://icloud.developer.apple.com > CloudKit Database > $CONTAINER > Production에 Record Type이 있는지 확인"
  echo "      (없으면 Development에서 Deploy Schema Changes…, docs/RELEASE.md 「CloudKit Production 스키마」)"
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

# ── 배포 빌드 ────────────────────────────────────────────────────────────────────────
STEPS=()
NAME=""
FAILED=""
record() { STEPS+=("$1"); echo "· $1"; }
write_summary() {
  [ -n "$NAME" ] || return 0
  mkdir -p "$DIST"
  {
    echo "Waypoint macOS 배포 빌드 — $NAME"
    echo "시각: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "커밋: $(git -C "$ROOT" rev-parse HEAD 2>/dev/null)$( [ "$dirty" = 1 ] && echo ' (커밋 안 된 변경 포함)')"
    echo "버전: $VERSION  빌드: $BUILD  팀: $TEAM_ID"
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
echo "Waypoint $VERSION ($BUILD) → dist/$NAME.zip"

has_xcode_team || fail "Xcode 계정에 팀 $TEAM_ID 가 없음(scripts/release-mac.sh --check)"
if [ "$skip_notarize" = 0 ]; then
  state="$(notary_profile_state)"
  [ "$state" = ok ] || fail "공증 프로필 '$NOTARY_PROFILE' 을 쓸 수 없음($state). scripts/release-mac.sh --check 참고, 공증 없이 확인만 하려면 --skip-notarize"
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
log="$WORK/archive.log"
if ! xcodebuild -project "$ROOT/Waypoint.xcodeproj" -scheme Waypoint -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$WORK/DerivedData" -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" ENABLE_HARDENED_RUNTIME=YES \
    archive > "$log" 2>&1; then
  report_build_failure "$log"
  fail "archive 실패(전체 로그: $log)"
fi
record "archive: 성공($ARCHIVE)"

# 3. Developer ID export(자동 서명). ExportOptions는 여기서 만든다.
OPTIONS="$WORK/ExportOptions.plist"
cat > "$OPTIONS" <<PLIST
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
	<string>export</string>
</dict>
</plist>
PLIST
log="$WORK/export.log"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$OPTIONS" \
    -allowProvisioningUpdates > "$log" 2>&1; then
  report_build_failure "$log"
  fail "Developer ID export 실패(전체 로그: $log). scripts/release-mac.sh --check 의 인증서 항목 참고"
fi
[ -d "$APP" ] || fail "export 결과가 없음: $APP"
record "export: 성공(developer-id, $APP)"

# 4. 서명 검증(정적 검사만, 앱은 실행하지 않는다)
info="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' -c 'Print CFBundleShortVersionString' -c 'Print CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null | tr '\n' ' ')"
[ "$info" = "$BUNDLE_ID $VERSION $BUILD " ] || fail "Info.plist가 예상과 다름: '$info'(예상 '$BUNDLE_ID $VERSION $BUILD')"
codesign --verify --deep --strict --verbose=2 "$APP" > "$WORK/codesign-verify.txt" 2>&1 \
  || fail "codesign --verify 실패: $(tail -3 "$WORK/codesign-verify.txt" | tr '\n' ' ')"
codesign -dv --verbose=4 "$APP" > "$WORK/codesign-info.txt" 2>&1
authority="$(grep -m1 '^Authority=' "$WORK/codesign-info.txt" | cut -d= -f2-)"
case "$authority" in
  "Developer ID Application: "*"($TEAM_ID)") ;;
  *) fail "Developer ID 서명이 아님: Authority=$authority" ;;
esac
grep -q '^TeamIdentifier='"$TEAM_ID"'$' "$WORK/codesign-info.txt" || fail "TeamIdentifier가 $TEAM_ID 가 아님"
grep -q '^CodeDirectory .*(runtime)' "$WORK/codesign-info.txt" || fail "하드닝 런타임이 꺼져 있음(공증 불가)"
grep '^Authority=' "$WORK/codesign-info.txt" | sed 's/^/  /'
ENT="$WORK/entitlements.plist"
codesign -d --entitlements - --xml "$APP" > "$ENT" 2>/dev/null || fail "엔타이틀먼트를 읽지 못함"
ent_get() { /usr/libexec/PlistBuddy -c "Print :$1" "$ENT" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//'; }
containers="$(ent_get com.apple.developer.icloud-container-identifiers)"
environment="$(ent_get com.apple.developer.icloud-container-environment)"
aps="$(ent_get com.apple.developer.aps-environment)"
echo "  icloud-container-identifiers: $containers"
echo "  icloud-container-environment: ${environment:-(없음)}"
echo "  aps-environment: ${aps:-(없음)}"
printf '%s' "$containers" | grep -q "$CONTAINER" || fail "엔타이틀먼트에 컨테이너 $CONTAINER 가 없음"
[ "$environment" = "Production" ] || fail "CloudKit 환경이 Production이 아님: ${environment:-(없음)}"
if grep -q 'com.apple.security.cs\.' "$ENT"; then
  echo "  주의: 하드닝 런타임 예외 엔타이틀먼트가 있음: $(grep -o 'com.apple.security.cs\.[a-z.-]*' "$ENT" | tr '\n' ' ')"
fi
record "서명 검증: 통과($authority, 하드닝 런타임, $CONTAINER $environment, aps $aps)"

# 5. 공증 → staple
submit_zip="$WORK/Waypoint-notarize.zip"
ditto -c -k --keepParent "$APP" "$submit_zip" || fail "공증용 zip 실패"
if [ "$skip_notarize" = 1 ]; then
  record "공증: 건너뜀(--skip-notarize)"
else
  echo "· 공증 제출(몇 분 걸린다)"
  out="$WORK/notary-submit.json"
  xcrun notarytool submit "$submit_zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$out" 2> "$WORK/notary-submit.err"
  status="$(plutil -extract status raw -o - "$out" 2>/dev/null)"
  sub_id="$(plutil -extract id raw -o - "$out" 2>/dev/null)"
  if [ -n "$sub_id" ]; then
    xcrun notarytool log "$sub_id" --keychain-profile "$NOTARY_PROFILE" "$DIST/$NAME-notary-log.json" > /dev/null 2>&1
  fi
  [ "$status" = "Accepted" ] || fail "공증 실패: 상태 '${status:-없음}' 제출 ${sub_id:-없음}. 로그: dist/$NAME-notary-log.json, $(head -2 "$WORK/notary-submit.err" | tr '\n' ' ')"
  record "공증: Accepted(제출 $sub_id, 로그 dist/$NAME-notary-log.json)"
  xcrun stapler staple "$APP" > "$WORK/staple.txt" 2>&1 || fail "stapler staple 실패: $(tail -2 "$WORK/staple.txt" | tr '\n' ' ')"
  xcrun stapler validate "$APP" > "$WORK/staple-validate.txt" 2>&1 || fail "stapler validate 실패: $(tail -2 "$WORK/staple-validate.txt" | tr '\n' ' ')"
  record "staple: 성공"
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
