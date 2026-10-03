#!/bin/bash
# SSH 원격 서버의 Claude Code(·Codex)를 이 Mac의 Waypoint에 잇는다(TRK-53, docs/REMOTE.md).
#   1) 원격의 ~/.claude/settings.json·~/.claude/waypoint/·tracker 스킬(~/.codex/가 있으면 Codex 설정도)을 임시 홈에 받는다
#   2) 앱 안 설치기(Shared/Integration/Installer/)를 명령행(waypoint-integration)으로 돌려 임시 홈에 계획·적용한다
#   3) 바뀐 파일의 원격 원본을 ~/.waypoint-backups/<시각>.tgz로 먼저 묶어 두고, 바뀐 파일만 원격에 되돌려 놓는다
#   4) 원격에 `claude`가 있으면 MCP를 사용자 범위로 등록한다(http://127.0.0.1:<포트>/mcp — SSH 터널 경유). 없으면 명령만 보인다
#   5) 사용자 ~/.ssh/config에 넣을 RemoteForward 한 줄을 출력한다(이 스크립트는 ~/.ssh를 고치지 않는다)
#
# 사용: scripts/remote-setup.sh [--dev] [--dry-run] <ssh 대상> [-- <ssh 옵션>...]
#   --dev      Waypoint Dev(47822)에 잇는다(실측용). 기본은 평소용 47821
#   --dry-run  받아서 계획만 보이고 원격에 아무것도 쓰지 않는다
# 원격 요구: bash, curl 7.84+(응답 머리 읽기), tar. jq가 있으면 앱이 꺼진 동안의 기록을 줄여 둔다(없어도 동작).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
port=47821 instance=stable dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dev) port=47822 instance=dev; shift ;;
    --dry-run) dry=1; shift ;;
    -*) echo "모르는 옵션: $1" >&2; exit 1 ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || { echo "사용: $0 [--dev] [--dry-run] <ssh 대상> [-- <ssh 옵션>...]" >&2; exit 1; }
target="$1"; shift
[ "${1:-}" = "--" ] && shift
SSH=(ssh -o BatchMode=yes "$@" "$target")

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
home="$work/home" orig="$work/orig"
mkdir -p "$home" "$orig" "$work/backups"

step() { printf '· %s\n' "$*"; }

# 원격 확인: 홈, curl 버전, jq·claude·codex 유무
info="$("${SSH[@]}" 'printf "home=%s\n" "$HOME"
  printf "curl=%s\n" "$(curl --version 2>/dev/null | head -n 1 | cut -d" " -f2)"
  command -v jq >/dev/null 2>&1 && echo jq=1
  [ -d "$HOME/.codex" ] && echo codex=1
  bash -lc "command -v claude" >/dev/null 2>&1 && echo claude=1
  true')" || { echo "ssh 접속 실패: $target" >&2; exit 1; }
remote_home="$(printf '%s\n' "$info" | sed -n 's/^home=//p')"
curl_version="$(printf '%s\n' "$info" | sed -n 's/^curl=//p')"
case "$remote_home" in /*) ;; *) echo "원격 홈을 읽지 못함" >&2; exit 1 ;; esac
step "원격 $target (홈 $remote_home, curl ${curl_version:-없음})"
if [ -z "$curl_version" ]; then echo "원격에 curl이 없음 — 훅이 앱에 보내지 못한다" >&2; exit 1; fi
if [ "$(printf '%s\n7.84.0\n' "$curl_version" | sort -V | head -n 1)" != "7.84.0" ]; then
  echo "주의: 원격 curl $curl_version — 7.84 미만은 시작 블록 수신 확인을 보내지 못한다(블록이 다음 요청에 한 번 더 붙을 수 있음)" >&2
fi
printf '%s\n' "$info" | grep -q '^jq=1' || echo "참고: 원격에 jq가 없음 — 앱에 못 닿는 동안의 기록은 세션·폴더만 남는다" >&2
has_codex=0; printf '%s\n' "$info" | grep -q '^codex=1' && has_codex=1
has_claude=0; printf '%s\n' "$info" | grep -q '^claude=1' && has_claude=1

# 1) 원격 설정을 임시 홈으로(있는 것만)
files=(.claude/settings.json .claude/waypoint/waypoint-hook.sh .claude/waypoint/waypoint-statusline-tap.sh
       .claude/skills/tracker/SKILL.md)
[ "$has_codex" = 1 ] && files+=(.codex/hooks.json .codex/config.toml .codex/waypoint/install.json
       .codex/waypoint/waypoint-codex-hook.sh .codex/waypoint/waypoint-hook.sh .agents/skills/waypoint-tracker/SKILL.md)
"${SSH[@]}" "cd ~ && list=\$(for f in ${files[*]}; do [ -f \"\$f\" ] && printf '%s ' \"\$f\"; done); \
  if [ -n \"\$list\" ]; then tar cf - \$list; fi" > "$work/fetch.tar"
[ -s "$work/fetch.tar" ] && tar xf "$work/fetch.tar" -C "$home"
cp -R "$home/." "$orig/"
step "받은 파일 $(cd "$home" && find . -type f | wc -l | tr -d ' ')개"

# 2) 설치기(앱과 같은 코드)로 계획·적용
swift build --package-path "$ROOT" --product waypoint-integration >/dev/null 2>&1 \
  || { echo "설치기 빌드 실패: swift build --package-path $ROOT --product waypoint-integration" >&2; exit 1; }
cli="$(swift build --package-path "$ROOT" --product waypoint-integration --show-bin-path)/waypoint-integration"
verb=install; [ "$dry" = 1 ] && verb=plan
providers=(claude); [ "$has_codex" = 1 ] && providers+=(codex)
commands=()
for provider in "${providers[@]}"; do
  out="$("$cli" "$verb" --home "$home" --command-home "$remote_home" --provider "$provider" --instance "$instance" \
         --repo "$ROOT" --backup-root "$work/backups")"
  printf '%s\n' "$out" | sed -n "s/^file /  $provider: /p; s/^note /  $provider 참고: /p"
  while IFS= read -r line; do commands+=("$line"); done < <(printf '%s\n' "$out" | sed -n 's/^command //p')
done

changed=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  cmp -s "$home/$f" "$orig/$f" 2>/dev/null || changed+=("$f")
done < <(cd "$home" && find . -type f | sed 's|^\./||' | sort)

if [ "$dry" = 1 ]; then
  step "계획만 봤다(원격에 쓰지 않음)"
  exit 0
fi

# 3) 원격 백업 뒤 바뀐 파일만 되돌려 놓기
if [ ${#changed[@]} -gt 0 ]; then
  stamp="$(date +%Y%m%dT%H%M%S)"
  "${SSH[@]}" "cd ~ && mkdir -p .waypoint-backups && existing=\$(for f in ${changed[*]}; do [ -e \"\$f\" ] && printf '%s ' \"\$f\"; done); \
    if [ -n \"\$existing\" ]; then tar czf .waypoint-backups/$stamp.tgz \$existing; fi"
  step "원격 백업 ~/.waypoint-backups/$stamp.tgz(바뀌기 전 파일)"
  # macOS tar의 확장 속성(provenance 등)은 싣지 않는다
  (cd "$home" && COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs -cf - "${changed[@]}") | "${SSH[@]}" 'cd ~ && tar xf -'
  step "원격에 쓴 파일 ${#changed[@]}개"
else
  step "원격 설정이 이미 맞음"
fi

# 4) MCP 등록(Claude는 원격의 claude 명령으로. Codex MCP는 config.toml에 이미 들어갔다)
[ ${#commands[@]} -gt 0 ] && for command in "${commands[@]}"; do
  case "$command" in
    "claude mcp add "*)
      if [ "$has_claude" = 1 ]; then
        if "${SSH[@]}" "bash -lc 'claude mcp remove waypoint -s user >/dev/null 2>&1; $command'" >/dev/null 2>&1; then
          step "원격 MCP 등록: waypoint → http://127.0.0.1:$port/mcp"
        else
          echo "원격 MCP 등록 실패 — 원격에서 직접: $command" >&2
        fi
      else
        step "원격에 claude가 없음 — 설치 뒤 원격에서: $command"
      fi ;;
    *) step "원격에서: $command" ;;
  esac
done

# 5) 터널
cat <<EOF

다음 한 줄을 이 Mac의 ~/.ssh/config 「Host ${target#*@}」 아래에 넣는다(이 스크립트는 고치지 않음):
    RemoteForward $port 127.0.0.1:$port
또는 접속할 때: ssh -R $port:127.0.0.1:$port ${target}
터널이 없을 때의 기록은 원격 outbox에 쌓였다가 다음에 닿을 때 들어온다.
EOF
