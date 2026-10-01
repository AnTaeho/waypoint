# Waypoint

Claude Code·Codex 세션을 프로젝트 단위로 추적하는 개인용 Apple 앱(macOS + iOS).

## 사용법

1. 새 저장소를 만들고 이 폴더 내용을 루트에 복사한다 (`CLAUDE.md`가 루트에 오도록).
2. 저장소 폴더에서 `claude` 실행 후 이렇게 시작한다:

   > `docs/SPEC.md`와 `docs/MILESTONES.md`를 읽고 M0부터 진행해줘. 각 마일스톤 끝나면 멈추고 확인받아.

3. 디자인 시안 원본(캔버스): https://claude.ai/artifact/G9JsAmHhuKb1ZLeRdoroGM

## 구성

| 경로 | 내용 |
|---|---|
| `CLAUDE.md` | 이 저장소에서 Claude Code가 따를 작업 지침 |
| `docs/SPEC.md` | 제품 정의, 아키텍처, 데이터 모델, 로컬 API·MCP 도구 명세 |
| `docs/MILESTONES.md` | 구현 순서와 각 단계의 완료 조건 |
| [docs/PRODUCT_ROADMAP.md](docs/PRODUCT_ROADMAP.md) | 현재 제품 로드맵: 우선순위·선행 작업·사용자 검증·유료화 기준 |
| [docs/PRODUCT_ROADMAP_CARDS.json](docs/PRODUCT_ROADMAP_CARDS.json) | TRK-9 하위 카드 ID·선행 관계·등록 데이터 |
| `docs/DESIGN.md` | 디자인 토큰, 화면 목록, 시안 파일 읽는 법 |
| `design/*.dc.html` | 시안 화면 마크업 (레이아웃·색·문구 참고용, 단독 렌더링 안 됨) |
| `integration/skills/tracker/SKILL.md` | 사용자의 모든 프로젝트에서 쓸 tracker 스킬 |
| `integration/hooks/` | Claude Code 훅 설정 예시와 훅 스크립트 |
| `integration/statusline/` | 상태줄 입력의 사용량을 `usage.json`으로 남기는 중계 스크립트와 테스트 |
| `docs/DEVELOPMENT.md` | 평소용·개발용 인스턴스, 설치·실측 절차, 되돌리는 방법 |
| `scripts/install-local.sh` | 평소용을 Release로 빌드해 `/Applications/Waypoint.app`에 설치·실행 |
| `scripts/dev-probe-setup.sh` | 실측 폴더를 개발용 Waypoint Dev(47822)에 잇는 프로젝트 설정 |

## 설치 (앱)

```sh
scripts/install-local.sh   # Release 빌드(팀 서명) → /Applications/Waypoint.app 교체·실행 → 로그인 항목
```

Xcode 설정 > Accounts에 개발 팀(`2FCXA77MC5`)이 로그인돼 있어야 한다. 빌드가 App ID·iCloud 컨테이너·프로파일을 자동으로 받는다. Mac과 iPhone은 같은 Apple 계정의 iCloud로 기록을 나눈다(CloudKit 개인 DB, `iCloud.dev.antaeho.waypoint`).

iPhone 앱은 기기를 잇고 잠금을 푼 뒤 Release로 빌드해 설치한다.

```sh
xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -configuration Release \
  -destination 'platform=iOS,id=<기기 UDID>' -derivedDataPath .build/ios \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device <기기 UDID> .build/ios/Build/Products/Release-iphoneos/Waypoint.app
```

평소 쓰는 것은 이 평소용 하나다. Xcode에서 돌리는 Debug 빌드는 개발용 **Waypoint Dev**(포트 47822, 저장소 `Waypoint-Dev/`)라 평소용 기록과 섞이지 않는다. 자세한 것은 `docs/DEVELOPMENT.md`.

## 설치 (MCP·스킬)

평소용 앱이 켜져 있으면 `http://127.0.0.1:47821/mcp`에 MCP 서버가 열린다. 한 번만 등록한다.

```sh
# MCP 서버(사용자 범위, ~/.claude.json에 적힌다)
claude mcp add --transport http --scope user waypoint http://127.0.0.1:47821/mcp
claude mcp get waypoint      # Status: ✔ Connected (앱이 켜져 있을 때)

# tracker 스킬
mkdir -p ~/.claude/skills/tracker
cp integration/skills/tracker/SKILL.md ~/.claude/skills/tracker/
```

훅 설치는 `integration/hooks/settings.example.json`. 도구 이름은 `mcp__waypoint__card_start` 꼴이라, 권한을 미리 주려면 `mcp__waypoint__*`.
되돌리기: `claude mcp remove waypoint -s user`, `rm -r ~/.claude/skills/tracker`.

## 프로젝트 등록 (`/tracker init`)

등록할 폴더에서 Claude Code를 열고 `/tracker init`. Claude가 README·CLAUDE.md·docs·최근 커밋·TODO를 훑어 `project_init`을 부르면 앱에 「새 프로젝트 등록」 창이 뜬다. 이름·키·개요·스택을 고치고 지침 문서와 초기 카드를 골라 「등록」하면 그 폴더의 세션이 다음 훅부터 기록된다(지난 대화는 가져오지 않는다).

- 키: 영문 대문자 2–5자, 보관된 것까지 포함해 다른 프로젝트와 겹치지 않게.
- 정리: 사이드바에서 프로젝트를 오른쪽 클릭 → 「보관」(숨기고 그 폴더의 기록을 멈춘다, 사이드바 맨 아래 「보관됨」에서 되돌린다) 또는 「삭제…」(카드·기록·지침 문서 등록을 지운다. 로컬 파일은 그대로).

## Codex 연결

로컬 Codex CLI의 훅·MCP·tracker 스킬을 연결한다. Python 3.11+가 필요하며 외부 Python 패키지는 쓰지 않는다. 개발 중에는 `--dev`로 Waypoint Dev에 연결하고, 평소용 앱을 갱신한 뒤 기본 설치로 전환한다.

```sh
python3 scripts/install-codex.py --dev  # 개발용(47822)
python3 scripts/install-codex.py        # 평소용(47821)
```

설치 후 **Codex를 새로 열고 `/hooks`에서 Waypoint 훅을 검토·신뢰**한다. `/mcp`에서 waypoint 연결을 확인한다. 스크립트는 신뢰 설정을 바꾸지 않는다. Codex에서 `$waypoint-tracker init`을 요청하면 프로젝트 등록 초안을 앱에 띄운다. 이미 등록한 Claude 프로젝트는 그대로 사용한다.

- 설치: `~/.codex/hooks.json`, `~/.codex/config.toml`, `~/.codex/waypoint/`, `~/.agents/skills/waypoint-tracker/`. 기존 훅·MCP는 보존하고 설정을 백업한다. 다른 waypoint MCP가 있거나 사용자가 직접 바꾼 스킬이 있으면 덮어쓰지 않고 멈춘다.
- 기록: 세션 시작·활동·마지막 요청·성공한 apply_patch 파일 변경·Bash 커밋·하위 에이전트·종료. Codex 카드의 만든 곳은 Codex, 세션 표시에도 Codex가 붙는다. 종료는 작업 전 상태로 돌리고 자동 완료하지 않는다.
- 프로젝트 화면의 「활동」 탭에서 날짜·세션별 요청, 변경 파일, 커밋, 완료와 인수인계 메모를 확인할 수 있다. 도구·카드·세션으로 좁혀 보며 카드 상세로 이동할 수 있고, 처음에는 최신 300건을 읽는다.
- 인수인계: 두 도구가 같은 카드의 메모를 공유한다. 훅 블록의 `sessionId: codex:…`를 MCP에 그대로 전달한다.
- 범위: 공식 훅 문서와 Codex CLI 0.159.2를 기준으로 검증한다. MCP 설정을 공유하는 다른 로컬 클라이언트도 있으나, 클라우드 실행의 로컬 훅·웹 채팅·모든 클라이언트의 이벤트 지원은 보장하지 않는다. 실제 Codex 세션은 훅 신뢰 후 확인한다.
- 되돌리기: `python3 scripts/install-codex.py --remove`. 이 설치기가 추가한 훅·MCP와 수정되지 않은 스킬만 제거한다. 백업과 브리지 파일은 남겨 열린 세션의 파일 누락을 피한다.

자세한 개발 검증·확인 목록은 [integration/codex/README.md](integration/codex/README.md).

## 핵심 원칙 (한 줄 요약)

- 세션이 아니라 **프로젝트** 기준으로 "작업중"을 보여준다.
- 기록은 사용자가 이미 쓰는 Claude Code 세션 안에서 훅과 스킬이 남긴다. **앱은 Anthropic API를 호출하지 않는다** (크레딧 사용 없음).
- 지침 문서(CLAUDE.md 등)는 앱과 로컬 파일이 양방향 동기화된다. Claude가 수정을 제안하는 기능은 없다.

### 작업 이어가기

카드 상세의 **작업 이어가기 → 재개 문맥 준비**에서 Claude Code 또는 Codex를 선택하고 미리보기 내용을 복사한다. Waypoint가 연결된 해당 도구의 새 대화에 붙여넣으면, 현재 대화의 실제 세션 ID로 프로젝트와 카드를 연결하도록 안내한다. 목표·마지막 메모·남은 완료 조건·최근 변경 파일·커밋이 포함된다. 복사만으로 카드 상태는 바뀌지 않으며, 새 세션이 `card_start`에 성공하면 작업중으로 표시된다. 완료·보관된 카드는 재개 전에 상태를 변경해야 한다.

### 연동 상태 점검

연동 상태 패널에서 실행 중인 앱의 버전·빌드와 개발용/일반용 구분을 확인할 수 있다. **진단 정보 복사**는 버전·운영체제·로컬 포트·설정 상태·수신 시각·미처리 기록 수를 클립보드에 복사한다. 프로젝트명·파일 경로·세션 ID·대화·자유 형식 오류 원문은 제외한다. 자동 전송은 하지 않는다.

Mac 대시보드의 **AI 연동** 또는 툴바의 **연동 상태**를 누르면 Claude·Codex의 사용자 훅 설정, 마지막 실제 수신, 연결 프로젝트, MCP 요청과 미처리 기록을 확인할 수 있다. 설치만 된 상태와 실제 수신 확인을 구분하며, 문제가 있으면 원인과 복구 안내를 표시한다. **다시 점검**으로 설정을 다시 읽고 실패한 로컬 서버를 재시도할 수 있다. 대화 내용은 진단 기록에 저장하지 않는다.
