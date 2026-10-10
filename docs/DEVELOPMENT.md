# 개발 환경: 평소용과 개발용

Waypoint로 다른 저장소의 세션을 늘 추적하면서 Waypoint 자체도 고친다. 개발하느라 앱을 껐다 켜거나 가짜 데이터로 실측하면 추적이 끊기고 실제 기록이 섞이므로, 인스턴스를 둘로 나눈다.

| | 평소용 Waypoint | 개발용 Waypoint Dev |
|---|---|---|
| 빌드 | Release → `/Applications/Waypoint.app` | Debug(`.build/xcode/.../Debug/Waypoint.app`, Xcode 실행) |
| 번들 ID | `dev.antaeho.waypoint` | `dev.antaeho.waypoint.dev` |
| 표시 | 메뉴 막대 `signpost.right` | 메뉴 막대 `hammer`, 「Waypoint Dev 열기」, 사이드바 맨 위 「Dev」 |
| 포트 | 47821 | 47822 |
| 저장 폴더 | `~/Library/Application Support/Waypoint/` | `~/Library/Application Support/Waypoint-Dev/` |
| 켜짐 | 로그인 항목(앱이 `SMAppService`로 등록), 늘 | 개발할 때만(로그인 항목에 등록하지 않는다) |
| 훅·MCP | 전역 설정(`~/.claude/settings.json`, `~/.claude.json` 사용자 범위) | 실측 폴더의 프로젝트 설정만 |
| CloudKit 컨테이너 | `iCloud.dev.antaeho.waypoint` | `iCloud.dev.antaeho.waypoint.dev` |
| iPhone 앱 | 「Waypoint」(Release) | 「Waypoint Dev」(Debug) |
| 앱 아이콘 | 이정표, 클레이 바탕(`AppIcon`) | 이정표, 검은 바탕(`AppIconDev`) |

- 인스턴스는 번들 ID로 가른다(`Shared/Instance/AppInstance.swift`, 끝이 `.dev`면 개발용). 번들 ID가 없는 명령행 도구·테스트는 평소용으로 본다.
- 환경 변수 `WAYPOINT_PORT`·`WAYPOINT_SUPPORT_DIR`가 있으면 기본값보다 먼저다(훅 스크립트와 같은 이름).
- 앱 메뉴 이름은 두 빌드 모두 「Waypoint」다(`PRODUCT_NAME`을 그대로 둬 빌드 경로가 같다). 가려 보는 것은 메뉴 막대 아이콘과 사이드바 「Dev」.
- 사용량 게이지와 세션 이름 · 컨텍스트 사용률은 상태줄 중계가 평소용 폴더에만 `usage.json`·`session-status.json`을 쓰므로 Dev에서는 비어 있다. 채워 보려면 중계를 Dev 저장 폴더로 직접 돌린다: `WAYPOINT_SUPPORT_DIR=<Dev 저장 폴더> bash integration/statusline/waypoint-statusline-tap.sh cat < 가짜입력.json`.

## 규칙

- 평소용은 개발 중 건드리지 않는다. 종료·교체·실측 금지.
- 평소용 새 버전은 `scripts/install-local.sh`로만 올린다.
- 개발·실측은 Dev에서, 실측 폴더(`dev-probe-setup.sh`로 이은 폴더)에서만.

## 평소용 설치·갱신

```sh
scripts/install-local.sh
```

Release 빌드(`.build/release`, 팀 서명, `-allowProvisioningUpdates`, 빌드 번호 = 커밋 수) → 서명과 컨테이너 엔타이틀먼트 확인 → 떠 있는 평소용 정상 종료(번들 ID로 `quit`, 10초 대기, 안 꺼지면 멈춤, 강제 종료 없음) → `ditto`로 `/Applications/Waypoint.app` 교체 → 뒤에서 실행(`open -g`, 쓰던 창의 초점을 뺏지 않는다) → 47821을 설치한 앱이 여는지 확인. 실행 전에 옛 방식(System Events) 로그인 항목이 있으면 지우고 `defaults`에 `WaypointLoginItemLegacyRemoved`를 남긴다. 로그인 항목 등록은 앱이 첫 실행 때 `SMAppService`로 한다(TRK-55). 끝에 한 줄로 결과를 보인다. 어느 단계든 실패하면 이유를 출력하고 exit 1. 여러 번 돌려도 된다.

외부 베타용 배포 빌드(Developer ID·공증)는 [`docs/RELEASE.md`](RELEASE.md), `scripts/release-mac.sh`.

앱이 꺼져 있는 동안 온 훅은 `outbox.jsonl`에 쌓였다가 새 앱이 켜질 때 흡수된다.

빌드 실패 시 마지막 직접 오류 최대 12개를 표시한다. 접근 거부가 포함되면 실행 환경의 sandbox·경로 권한과 설치 명령 승인 여부를 확인한다. 전체 로그는 `.build/release/install-build.log`에 있으며, 직접 오류 문구가 없으면 마지막 12줄을 표시한다. 실패 진단과 앱 교체 전 중단은 `python3 scripts/test_build_failure_report.py`로 실제 앱을 건드리지 않고 검증한다.

## 개발용 실행

Xcode에서 Waypoint 스킴을 Debug로 실행하거나:

```sh
xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -destination 'platform=macOS' \
  -derivedDataPath .build/xcode -allowProvisioningUpdates build
open .build/xcode/Build/Products/Debug/Waypoint.app
lsof -nP -iTCP:47822 -sTCP:LISTEN
```

가짜 데이터만 볼 때는 `-WaypointSampleData`(메모리 저장소, 서버 안 엶). 끌 때는 메뉴 막대 망치 → 종료.

## 서명과 CloudKit

- 팀 `2FCXA77MC5`(Taeho An) 자동 서명. Xcode 설정 > Accounts에 이 팀 계정이 있어야 한다. CloudKit·푸시 엔타이틀먼트는 프로파일이 있어야 들어가서 애드혹 서명(`CODE_SIGN_IDENTITY=-`)으로는 빌드하지 않는다.
- 명령행 빌드에는 `-allowProvisioningUpdates`(기기 빌드는 `-allowProvisioningDeviceRegistration`도)를 붙인다. App ID·iCloud 컨테이너·프로파일을 Xcode가 만들고 갱신한다. 2026-09-28 이렇게 생겼다:
  - App ID `dev.antaeho.waypoint`(「XC dev antaeho waypoint」), `dev.antaeho.waypoint.dev`(「XC dev antaeho waypoint dev」)
  - 컨테이너 `iCloud.dev.antaeho.waypoint`, `iCloud.dev.antaeho.waypoint.dev`
  - 프로파일 「Mac Team Provisioning Profile: …」, 「iOS Team Provisioning Profile: …」(번들 ID마다)
- 새로 만든 컨테이너는 서버에 퍼지기까지 몇 분 걸린다. 그사이 앱을 켜면 `CKError 5`(내부 1014, 「Error fetching database URL」)로 미러링이 멈추고 다시 시도하지 않는다. 몇 분 뒤 앱을 다시 켜면 된다.
- 환경은 둘 다 Development. 대시보드: https://icloud.developer.apple.com (팀 → 컨테이너 → Development → Records, 영역 `com.apple.coredata.cloudkit.zone`).
- CloudKit을 끄고 띄우기: `open --env WAYPOINT_CLOUDKIT=0 …/Waypoint.app`(셸 변수는 `open`으로 넘어가지 않는다). `WAYPOINT_SUPPORT_DIR`를 준 실행은 저절로 꺼진다.
- 개발 인증서·프로파일은 1년마다 만료된다. 만료 전에 `scripts/install-local.sh`를 다시 돌려 평소용을 새 프로파일로 서명한다(iPhone 앱은 아래 「iPhone 설치」를 다시).
- 로그: `/usr/bin/log show --last 5m --info --debug --predicate 'process == "Waypoint" AND subsystem == "com.apple.coredata"'`(zsh의 `log`는 내장 명령이라 경로를 적는다). 「Successfully set up CloudKit integration」, 「Found N objects needing export」, 「Modify records finished」를 본다.

## iPhone 설치

기기(「안태호의 iPhone」, UDID `00008150-000A50C01E20401C`)를 USB나 같은 네트워크로 잇고 잠금을 푼다.

```sh
# 개발용(Waypoint Dev)
xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -configuration Debug \
  -destination 'platform=iOS,id=00008150-000A50C01E20401C' -derivedDataPath .build/ios \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device 00008150-000A50C01E20401C \
  .build/ios/Build/Products/Debug-iphoneos/Waypoint.app
# 콘솔을 붙여 실행: 작업중 줄이 바뀔 때·CloudKit 가져오기가 끝날 때 「[waypoint] …Z」 한 줄씩(Debug만)
xcrun devicectl device process launch --console --terminate-existing \
  --device 00008150-000A50C01E20401C dev.antaeho.waypoint.dev

# 평소용(Waypoint): -configuration Release, 결과는 .build/ios/Build/Products/Release-iphoneos/Waypoint.app
```

- 잠긴 기기에는 실행을 못 한다(「device was not, or could not be, unlocked」). 설치는 된다.
- Debug 실행 인자 `-- -WaypointMoveIdea PRB-2`: 그 아이디어 카드를 버튼과 같은 길(`PhoneIdeaAction.move`)로 「다음 할 일로」 옮긴다. 손 없이 동기화를 확인할 때만.
- `devicectl`에는 화면 캡처가 없다. 화면은 기기에서 직접 보거나 위 콘솔 줄로 확인한다.
- Release 앱은 콘솔 줄이 없다. 무엇이 동기화됐는지는 기기 저장소를 꺼내 본다(개발 서명이라 된다):
  `xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer --domain-identifier dev.antaeho.waypoint --source "Library/Application Support/Waypoint/Waypoint.store" --destination /tmp/phone.store`(`-shm`·`-wal`도 같이).

## 앱 아이콘

원본 SVG는 `design/icon/`(mac-·ios-, stable·dev). 에셋은 `App/Assets.xcassets`의 `AppIcon`(평소용)·`AppIconDev`(Debug 구성). 바꿀 때는 SVG를 1024 PNG로 그린 뒤 macOS용은 `sips -z`로 16–512 @1x/@2x를, iOS용은 1024 한 장(알파 없이)을 넣는다.

## 연동 설치

사용자 범위 연동(Claude 훅·상태줄 중계·MCP·tracker 스킬, Codex 훅·MCP·스킬)은 앱 안 설치기가 기준이다(`Shared/Integration/Installer/`, `docs/SPEC.md` 「앱 안 연동 설치기」). 화면은 온보딩(「연결 설정」, `docs/SPEC.md` 「온보딩」)이다.

- 앱 번들에 `integration/`의 훅 스크립트·상태줄 중계·Codex 브리지·tracker 스킬이 리소스로 들어간다(`project.yml`). 저장소 파일이 원본이므로 그 파일을 고치면 앱을 다시 빌드한다.
- 백업: 저장 폴더의 `integration-backups/<시각>-<8자>/`(`paths.json`에 원래 경로). 평소용은 `~/Library/Application Support/Waypoint/`, Dev는 `Waypoint-Dev/`.
- Dev 앱은 실제 홈에 설치·해제하지 않는다(온보딩 연결 단계가 「Waypoint Dev는 평소용 연결을 바꾸지 않음」으로 막힌다). 설치기로 Dev 47822에 잇는 일은 아래 확인용 홈에서만 한다. 평소 Dev 실측은 아래 실측 폴더를 쓴다.

### 확인용 홈과 온보딩 강제 표시 (Debug만)

`WAYPOINT_INTEGRATION_HOME=<폴더>`를 주면 Debug 빌드는 그 폴더를 홈으로 보고(설치기·연동 상태 진단 모두) 설치를 허용한다. Release는 무시한다. 확인용 저장 폴더(`WAYPOINT_SUPPORT_DIR`)와 함께 쓰면 프로젝트가 없어 온보딩이 저절로 뜬다.

```sh
P=/tmp/onboarding-probe; mkdir -p $P/home $P/support $P/app
APP=.build/xcode/Build/Products/Debug/Waypoint.app
open -g -j --env WAYPOINT_INTEGRATION_HOME=$P/home --env WAYPOINT_SUPPORT_DIR=$P/support $APP \
  --args -WaypointOnboarding apply            # tools | install | apply | project | receive
open -g -j --env WAYPOINT_INTEGRATION_HOME=$P/home --env WAYPOINT_SUPPORT_DIR=$P/support $APP \
  --args -WaypointOnboarding receive -WaypointOnboardingFolder $P/app
osascript -e 'quit app id "dev.antaeho.waypoint.dev"'
```

- `-WaypointOnboarding <단계>`: 그 단계로 연다. 앞 단계가 막혀 있으면 그 단계가 보인다. `apply`는 연결 계획을 바로 적용하며 `WAYPOINT_INTEGRATION_HOME`이 없으면 적용하지 않는다. `-WaypointOnboardingFolder`와 함께 주면 적용 뒤 첫 기록 단계로 넘어간다.
- `-WaypointOnboardingFolder <경로>`: 프로젝트 단계에서 그 폴더를 고른 것으로 본다. 등록 안 된 폴더면 확인 창 없이 등록한다(확인용 저장 폴더에서만 쓴다).
- 첫 기록 확인: 임시 홈 `.claude/settings.json`의 `SessionStart` 명령을 `HOME=$P/home`으로, `Tests/Fixtures/hooks/doc-SessionStart.json`의 `cwd`를 등록한 폴더로 바꿔 stdin에 넣어 돌린다.
- 화면은 `screencapture -x -o -l <창 번호>`로 시트 창 하나만 찍는다(창 번호는 `CGWindowListCopyWindowInfo`로, 폭 640인 창). `-j`로 숨긴 채 띄워도 찍힌다.
- 끝 화면의 「끝」을 누르면 Dev의 UserDefaults에 `onboarding.completed`가 남는다. 다시 보려면 `defaults delete dev.antaeho.waypoint.dev onboarding.completed`.
- 첫 연결 지표(`metrics.json`의 `onboarding`)는 `curl -s 127.0.0.1:47822/integration/status | jq .metrics.onboarding`으로 본다(파일은 10초 점검 때 쓴다).
- `scripts/install-codex.py`·`dev-probe-setup.sh`는 개발용으로 남는다. Codex 쪽은 앱 설치기와 같은 파일을 쓴다(`CodexInstallerTests`).
- 이 Mac의 실제 설치를 그대로 인식하는지는 `RealInstallStateTests`가 실제 설정을 임시 홈에 복사(읽기만)해 빈 계획인지 본다.

### 깨끗한 환경 첫 설정 (TRK-45)

설정이 하나도 없는 홈에서 첫 설정과 실제 수신을 잰다. 결과는 `docs/RELIABILITY.md` 같은 이름 절.

```sh
P=<스크래치>/clean; mkdir -p $P/home $P/support $P/app
open -g -j --env WAYPOINT_INTEGRATION_HOME=$P/home --env WAYPOINT_SUPPORT_DIR=$P/support $APP \
  --args -WaypointOnboarding apply -WaypointOnboardingFolder $P/app
curl -s 127.0.0.1:47822/integration/status | jq .metrics.onboarding   # installed·projectAt 확인
cd $P/app
env -i HOME=$P/home PATH=$HOME/.local/bin:/usr/bin:/bin:/opt/homebrew/bin TERM=xterm \
  claude -p "ok" --model haiku --debug                               # 한 번만
env -i HOME=$P/home CODEX_HOME=$P/home/.codex PATH=/opt/homebrew/bin:/usr/bin:/bin TERM=xterm \
  codex exec --skip-git-repo-check "ok" < /dev/null                  # 한 번만
curl -s 127.0.0.1:47822/integration/status | jq '.history.hooks, .metrics.onboarding'
osascript -e 'quit app id "dev.antaeho.waypoint.dev"'
```

- `env -i`로 띄운다. Claude Code 안에서 돌리면 `CLAUDECODE`·메시징 소켓 변수가 따라가 지금 세션으로 섞인다.
- 임시 홈에는 로그인 정보가 없어 Claude는 훅·MCP까지만 돌고 모델 호출에서 「Not logged in」, Codex는 `401`로 끝난다. 실제 대화까지 보려면 사람이 임시 홈에서 로그인하고, Codex는 대화형 `/hooks`에서 신뢰한다. 실제 홈의 인증 파일을 복사하지 않는다.
- 끝나면 실제 홈 설정(`~/.claude/settings.json`·`~/.codex/config.toml`·`hooks.json`·`~/.agents`)의 수정 시각·해시와 `~/.claude.json`의 `mcpServers`가 그대로인지 본다(`~/.claude.json` 전체는 돌고 있는 Claude Code가 늘 고쳐 쓴다).
- 설치된 훅의 outbox는 `$HOME/Library/Application Support/Waypoint-Dev`, 곧 임시 홈 안으로 간다. 앱이 `$P/support`를 쓰므로 앱이 꺼진 동안 온 기록은 흡수되지 않는다. 앱을 켠 채로 잰다.
- macOS에는 `timeout`이 없다. 시간 제한은 `perl -e 'alarm 150; exec @ARGV' …`.

## 실측 폴더

```sh
scripts/dev-probe-setup.sh ~/workspace/projects/waypoint/waypoint-probe          # 잇기
scripts/dev-probe-setup.sh --remove ~/workspace/projects/waypoint/waypoint-probe # 되돌리기
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
- 평소용 로그인 항목: 설정(⌘,) → 「일반」 → 「로그인할 때 열기」를 끄거나 시스템 설정 > 일반 > 로그인 항목에서 Waypoint를 뺀다. 한 번 끈 뒤로 앱이 다시 켜지 않는다(UserDefaults `loginItem.userChoice`·`loginItem.autoApplied`).
- CloudKit: `WaypointApp.makeContainer`에서 `cloudKitContainer:`를 빼면 로컬만. 올라간 기록은 CloudKit 대시보드에서 영역 `com.apple.coredata.cloudkit.zone`을 지운다(Development 환경은 「Reset Environment」로 통째로 비울 수 있다). App ID·컨테이너는 개발자 계정에 남는다(컨테이너는 지울 수 없다).
- 서명: `project.yml`의 `DEVELOPMENT_TEAM`·`CODE_SIGN_IDENTITY`·`CODE_SIGN_ENTITLEMENTS…`를 빼고 `install-local.sh`에 `CODE_SIGN_IDENTITY=-`를 되돌리면 M6 전 애드혹 빌드. CloudKit은 함께 빼야 한다.
- iPhone 앱: 기기에서 앱을 길게 눌러 삭제.
- 인스턴스 분리 자체: `project.yml`의 `configs: Debug:` 블록을 지우고 `xcodegen generate`. Debug가 다시 `dev.antaeho.waypoint`가 되어 평소용과 같은 포트·저장소를 쓴다(둘을 동시에 켜지 않는다).

## 기록 탭 실측 (TRK-47)

실제 저장소는 열지 않는다. 평소용이 뜬 백업 폴더 하나를 스크래치 폴더로 복사해 쓴다.

```sh
P=<스크래치>/records-probe; mkdir -p $P/support $P/out
cp "$HOME/Library/Application Support/Waypoint/store-backups/<최근 폴더>/"Waypoint.store* $P/support/
APP=.build/xcode/Build/Products/Debug/Waypoint.app
ENV="--env WAYPOINT_SUPPORT_DIR=$P/support --env WAYPOINT_CLOUDKIT=0 --env WAYPOINT_RELAUNCH_HIDDEN=1"
open -g -j $ENV $APP --args -WaypointSettingsTab records -WaypointExport $P/out/all.json   # 창 + 전체 내보내기
open -g -j $ENV $APP --args -WaypointBackupNow 1 -WaypointExport $P/out/one.json -WaypointExportProject <키>
open -g -j $ENV $APP --args -WaypointRestore <백업 폴더 이름|latest>   # 예약 → 다시 시작
open -g -j $ENV $APP --args -WaypointWipe 1                            # 지우기 → 다시 시작
osascript -e 'quit app id "dev.antaeho.waypoint.dev"'
```

- 한 번에 하나씩, 앞 인스턴스를 끈 뒤 띄운다(꺼지는 중이면 `open`이 -600으로 실패한다).
- 설정 창은 `-WaypointSettingsTab records`로 메인 창이 뜰 때 열린다. 아래 구역은 `-WaypointSettingsScroll bottom`. 창 번호는 `CGWindowListCopyWindowInfo`(이름 「기록」), `screencapture -x -o -l <번호>`.
- 다시 시작은 `WAYPOINT_*` 변수를 넘기고 인자는 넘기지 않는다. `WAYPOINT_RELAUNCH_HIDDEN=1`이면 다시 뜬 앱도 숨긴 채(`-j`).
- 확인: 백업은 `$P/support/store-backups/*/info.json`, 복원은 `store-restore.json`과 `curl -s 127.0.0.1:47822/integration/status`의 `storeRestore`, 지우기는 `sqlite3 "file:$P/support/Waypoint.store?mode=ro"`의 `ZPROJECT`·`ZCARD`… 행 수.
- 복원이 실제로 되돌리는지 보려면 백업 뒤 `POST 127.0.0.1:47822/hooks/SessionStart`(등록된 폴더 `cwd`, 새 `session_id`)로 세션을 하나 더하고 복원 뒤 그 세션이 없는지 본다.

## 원격·컨테이너 실측 (TRK-53)

사용자 절차는 [`REMOTE.md`](REMOTE.md). 개발 중 실측은 실제 원격 서버 대신 Docker 컨테이너로 한다(Docker Desktop은 `open -g -j -a Docker`로 뒤에서 켜고, 끝나면 `osascript -e 'quit app "Docker"'`).

- 설치기 명령행: `swift build --product waypoint-integration` → `.build/debug/waypoint-integration <plan|install|remove> --home <임시 홈> --command-home <원격 $HOME> [--provider claude|codex] [--instance stable|dev] [--backup-root <폴더>]`. 앱 설치기와 같은 코드다. MCP 등록 명령은 돌리지 않고 `command …` 줄로 보인다.
- `scripts/remote-setup.sh --dev <대상> -- <ssh 옵션>`: Dev(47822)로 잇는다. 사용자 `~/.ssh`를 쓰지 않도록 `-F /dev/null -i <임시 키> -o UserKnownHostsFile=<임시 파일>`을 넘긴다.
- sshd 컨테이너를 원격으로 삼고 `ssh -N -R 47822:127.0.0.1:47822`로 터널을 연다. 실측 폴더(`~/workspace/projects/waypoint/waypoint-probe`)에 origin이 없으면 임시 bare 저장소를 origin으로 붙이고, 컨테이너 안 클론의 origin을 같은 문자열로 맞춘다(끝나면 실측 폴더의 origin을 지운다).
- 훅 스크립트 단위 확인: `bash integration/hooks/test-waypoint-hook.sh`(8번 묶음이 `WAYPOINT_URL`·원격 정보·replay).

## 뮤테이션 테스트 (TRK-69)

테스트가 실제로 버그를 잡는지 잰다. 코드를 한 군데씩 일부러 틀리게 바꾸고(`==`→`!=`, `&&`→`||`, `>`→`>=`, `true`→`false`, `!` 제거, `+`→`-`) 테스트가 실패하는지 본다.

```sh
scripts/mutation-test.py Shared/Rules/HandoffFreshness.swift      # 파일 하나
scripts/mutation-test.py Shared/Rules Shared/Hooks --jobs 3       # 폴더, 사본 셋으로 병렬
scripts/mutation-test.py Shared/Rules --list                      # 변형 목록만
```

- 결과: 죽음(테스트가 잡음) · 생존(테스트가 못 잡음) · 무효(컴파일 안 됨, 점수에서 뺌) · 시간 초과(죽음으로 셈). 점수는 죽음 ÷ (죽음 + 생존).
- 원본 작업 트리는 건드리지 않는다. 사본은 `.build/mutation/w<i>/`, 보고서는 `.build/mutation/report.json`(`--out`으로 바꿈). 중간에 끊어도 같은 명령으로 이어 간다.
- 변형 하나에 10~25초. 고친 파일만 돌린다. `Shared/Rules`+`Shared/Hooks` 전체는 세 시간쯤.
- 실제 홈 폴더를 읽는 `GuidanceRealFileTests`·`RealInstallStateTests`는 변형 실행에서 뺀다.
- 생존을 보면 그 줄의 동작을 확인하는 테스트를 더한다. 어떤 입력으로도 결과가 달라지지 않는 변형(동등 변형)은 `scripts/mutation-equivalents.txt`에 이유와 함께 적어 다음 실행에서 건너뛴다.
- 기성 도구 Muter 16은 Swift 6.4에서 변형 코드가 컴파일되지 않아 쓰지 않는다.
