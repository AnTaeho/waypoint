# Waypoint — Claude Code 핸드오프 패키지

Claude Code 세션을 프로젝트 단위로 추적하는 개인용 Apple 앱(macOS + iOS)의 구현 인수인계 자료.

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

## 핵심 원칙 (한 줄 요약)

- 세션이 아니라 **프로젝트** 기준으로 "작업중"을 보여준다.
- 기록은 사용자가 이미 쓰는 Claude Code 세션 안에서 훅과 스킬이 남긴다. **앱은 Anthropic API를 호출하지 않는다** (크레딧 사용 없음).
- 지침 문서(CLAUDE.md 등)는 앱과 로컬 파일이 양방향 동기화된다. Claude가 수정을 제안하는 기능은 없다.
