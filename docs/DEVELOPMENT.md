# 개발 환경: 평소용과 개발용

Waypoint로 다른 저장소의 세션을 늘 추적하면서 Waypoint 자체도 고친다. 개발하느라 앱을 껐다 켜거나 가짜 데이터로 실측하면 추적이 끊기고 실제 기록이 섞이므로, 인스턴스를 둘로 나눈다.

| | 평소용 Waypoint | 개발용 Waypoint Dev |
|---|---|---|
| 빌드 | Release → `/Applications/Waypoint.app` | Debug(`.build/xcode/.../Debug/Waypoint.app`, Xcode 실행) |
| 번들 ID | `dev.antaeho.waypoint` | `dev.antaeho.waypoint.dev` |
| 표시 | 메뉴 막대 `signpost.right` | 메뉴 막대 `hammer`, 「Waypoint Dev 열기」, 사이드바 맨 위 「Dev」 |
| 포트 | 47821 | 47822 |
| 저장 폴더 | `~/Library/Application Support/Waypoint/` | `~/Library/Application Support/Waypoint-Dev/` |
| 켜짐 | 로그인 항목, 늘 | 개발할 때만 |
| 훅·MCP | 전역 설정(`~/.claude/settings.json`, `~/.claude.json` 사용자 범위) | 실측 폴더의 프로젝트 설정만 |

- 인스턴스는 번들 ID로 가른다(`Shared/Instance/AppInstance.swift`, 끝이 `.dev`면 개발용). 번들 ID가 없는 명령행 도구·테스트는 평소용으로 본다.
- 환경 변수 `WAYPOINT_PORT`·`WAYPOINT_SUPPORT_DIR`가 있으면 기본값보다 먼저다(훅 스크립트와 같은 이름).
- 앱 메뉴 이름은 두 빌드 모두 「Waypoint」다(`PRODUCT_NAME`을 그대로 둬 빌드 경로가 같다). 가려 보는 것은 메뉴 막대 아이콘과 사이드바 「Dev」.
- 사용량 게이지는 상태줄 중계가 평소용 폴더에만 `usage.json`을 쓰므로 Dev에서는 비어 있다.

## 규칙

- 평소용은 개발 중 건드리지 않는다. 종료·교체·실측 금지.
- 평소용 새 버전은 `scripts/install-local.sh`로만 올린다.
- 개발·실측은 Dev에서, 실측 폴더(`dev-probe-setup.sh`로 이은 폴더)에서만.

## 평소용 설치·갱신

```sh
scripts/install-local.sh
```

Release 빌드(`.build/release`, 애드혹 서명) → 떠 있는 평소용 정상 종료(번들 ID로 `quit`, 10초 대기, 안 꺼지면 멈춤, 강제 종료 없음) → `ditto`로 `/Applications/Waypoint.app` 교체 → 실행 → 47821을 설치한 앱이 여는지 확인 → 로그인 항목이 없으면 System Events로 추가. 끝에 한 줄로 결과를 보인다. 어느 단계든 실패하면 이유를 출력하고 exit 1. 여러 번 돌려도 된다.

앱이 꺼져 있는 동안 온 훅은 `outbox.jsonl`에 쌓였다가 새 앱이 켜질 때 흡수된다.

## 개발용 실행

Xcode에서 Waypoint 스킴을 Debug로 실행하거나:

```sh
xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -destination 'platform=macOS' \
  -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- build
open .build/xcode/Build/Products/Debug/Waypoint.app
lsof -nP -iTCP:47822 -sTCP:LISTEN
```

가짜 데이터만 볼 때는 `-WaypointSampleData`(메모리 저장소, 서버 안 엶). 끌 때는 메뉴 막대 망치 → 종료.

## 실측 폴더

```sh
scripts/dev-probe-setup.sh ~/workspace/waypoint-probe          # 잇기
scripts/dev-probe-setup.sh --remove ~/workspace/waypoint-probe # 되돌리기
```

폴더 안에만 두 파일을 쓴다.

- `.claude/settings.local.json`: 전역 설정의 Waypoint 훅을 같은 이벤트·matcher로 베끼고 명령 앞에 `WAYPOINT_PORT=47822 WAYPOINT_SUPPORT_DIR="$HOME/Library/Application Support/Waypoint-Dev"`를 붙인다. `enabledMcpjsonServers: ["waypoint"]`도 넣어 대화형에서 승인을 묻지 않게 한다.
- `.mcp.json`: 이름 `waypoint` → `http://127.0.0.1:47822/mcp`.

그 뒤 Dev를 켠 채 폴더에서 `/tracker init`으로 Dev에 등록한다(등록 창이 Dev에 뜬다).

알아 둘 것:

- **훅은 합쳐진다.** 사용자·프로젝트 설정의 훅이 모두 불려 전역 훅(47821)도 간다. 평소용은 등록되지 않은 폴더의 기록을 버리므로, 실측 폴더는 평소용에 등록하지 않는다. 다만 평소용이 `SessionStart`에 「이 폴더는 Waypoint에 없음」 한 줄을 돌려줘 Dev 컨텍스트와 함께 들어간다.
- **MCP는 프로젝트 범위가 먼저다.** 같은 이름이면 로컬 > 프로젝트 > 사용자(https://code.claude.com/docs/en/mcp). 2026-09-28 Claude Code 2.1.283 실측: 실측 폴더의 `claude -p`에서 `mcp__waypoint__project_resolve`가 Dev(47822)로 갔다(이 저장소 경로를 물으면 평소용은 TRK, Dev는 null을 돌려준다). 다만 `claude mcp get/list`는 이 폴더에서도 사용자 범위(47821)를 보이고 「Conflicting scopes」 진단을 띄운다. 세션 동작과 표시가 다르니 확인은 도구 호출로 한다.
- 로컬 범위(`claude mcp add -s local`)는 `~/.claude.json`에 적히므로 쓰지 않는다.

## 되돌리기

- 실측 폴더: `scripts/dev-probe-setup.sh --remove <폴더>`.
- 개발용 데이터: Dev를 끄고 `~/Library/Application Support/Waypoint-Dev/`를 지운다.
- 평소용 로그인 항목: 시스템 설정 > 일반 > 로그인 항목에서 Waypoint를 빼거나 `osascript -e 'tell application "System Events" to delete login item "Waypoint"'`.
- 인스턴스 분리 자체: `project.yml`의 `configs: Debug:` 블록을 지우고 `xcodegen generate`. Debug가 다시 `dev.antaeho.waypoint`가 되어 평소용과 같은 포트·저장소를 쓴다(둘을 동시에 켜지 않는다).
