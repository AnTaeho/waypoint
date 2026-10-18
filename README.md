# Waypoint

Claude Code·Codex 세션을 프로젝트 단위로 추적하는 개인용 Apple 앱(macOS + iOS). 앱은 LLM API를 부르지 않는다. 기록은 사용자가 쓰는 세션 안에서 훅·MCP·tracker 스킬이 남긴다. 작업 지침은 `CLAUDE.md`, 다음 일은 `docs/PRODUCT_ROADMAP.md`와 Waypoint 보드의 TRK 카드에 있다.

## 구성

| 경로 | 내용 |
|---|---|
| `CLAUDE.md` | 이 저장소에서 Claude Code가 따를 작업 지침 |
| `docs/SPEC.md` | 제품 정의, 아키텍처, 데이터 모델, 로컬 API·MCP 도구 명세 |
| `docs/DESIGN.md` | 디자인 토큰, 화면 구조, 시안 파일 읽는 법 |
| `docs/PRODUCT_ROADMAP.md` | 제품 로드맵: 우선순위·사용자 검증·유료화 기준 |
| `docs/DECISIONS.md` | 설계 결정과 까닭 |
| `docs/DEVELOPMENT.md` | 평소용·개발용 인스턴스, 설치·실측 절차, 되돌리는 방법 |
| `docs/RELEASE.md` | 배포 빌드·공증·자동 업데이트 |
| `docs/RELIABILITY.md` | 기록 신뢰성 기준·측정 방법·기준값 |
| `docs/REMOTE.md` | 원격·컨테이너 세션 수집 |
| `docs/BETA_GUIDE.md`, `docs/BETA_EVALUATION.md` | 베타 참여자 안내문, 관찰 절차 |
| `design/` | 시안 마크업(`*.dc.html`, 단독 렌더링 안 됨), 앱 아이콘 원본 |
| `integration/skills/tracker/SKILL.md` | 사용자의 모든 프로젝트에서 쓸 tracker 스킬 |
| `integration/hooks/` | Claude Code 훅 설정 예시와 훅 스크립트 |
| `integration/statusline/` | 상태줄 입력의 사용량을 `usage.json`으로 남기는 중계 스크립트와 테스트 |
| `integration/codex/` | Codex 훅 스크립트, 연결 테스트, 확인 목록 |
| `scripts/install-local.sh` | 평소용을 Release로 빌드해 `/Applications/Waypoint.app`에 설치·실행 |
| `scripts/dev-probe-setup.sh` | 실측 폴더를 개발용 Waypoint Dev(47822)에 잇는 프로젝트 설정 |

## 설치 (앱)

```sh
scripts/install-local.sh   # Release 빌드(팀 서명) → /Applications/Waypoint.app 교체·실행(로그인 항목은 앱이 등록)
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

## 연결 (훅·MCP·스킬)

보통은 앱의 「Waypoint 연결」 창(첫 실행 때 뜬다. 다시 열려면 메뉴 막대 → 「연결 설정…」)에서 Claude Code·Codex를 연결한다. 설치기(`Shared/Integration/Installer/`, 동작은 `docs/SPEC.md` 「앱 안 연동 설치기」)는 쓰기 전 `~/Library/Application Support/Waypoint/integration-backups/`에 백업을 남기고, 기존 설정을 보존하며, 중간에 실패하면 되돌린다. 아래 수작업·스크립트 절차는 개발용이다.

평소용 앱이 켜져 있으면 `http://127.0.0.1:47821/mcp`에 MCP 서버가 열린다.

```sh
# MCP 서버(사용자 범위, ~/.claude.json에 적힌다)
claude mcp add --transport http --scope user waypoint http://127.0.0.1:47821/mcp
claude mcp get waypoint      # Status: ✔ Connected (앱이 켜져 있을 때)

# tracker 스킬
mkdir -p ~/.claude/skills/tracker
cp integration/skills/tracker/SKILL.md ~/.claude/skills/tracker/
```

훅 설치는 `integration/hooks/settings.example.json`. 도구 이름은 `mcp__waypoint__card_start` 꼴이라, 권한을 미리 주려면 `mcp__waypoint__*`. 도구 목록과 입력은 `docs/SPEC.md` 7장.
되돌리기: `claude mcp remove waypoint -s user`, `rm -r ~/.claude/skills/tracker`.

## 프로젝트 등록 (`/tracker init`)

등록할 폴더에서 Claude Code를 열고 `/tracker init`. Claude가 README·CLAUDE.md·docs·최근 커밋·TODO를 훑어 `project_init`을 부르면 앱에 「새 프로젝트 등록」 창이 뜬다. 이름·키·개요·스택을 고치고 지침 문서와 초기 카드를 골라 「등록」하면 그 폴더의 세션이 다음 훅부터 기록된다(지난 대화는 가져오지 않는다).

- 키: 영문 대문자 2–5자, 보관된 것까지 포함해 다른 프로젝트와 겹치지 않게.
- 정리: 사이드바에서 프로젝트를 오른쪽 클릭 → 「보관」(숨기고 그 폴더의 기록을 멈춘다, 사이드바 맨 아래 「보관됨」에서 되돌린다) 또는 「삭제…」(카드·기록·지침 문서 등록을 지운다. 로컬 파일은 그대로).

## Codex 연결

앱 안 설치기와 이 스크립트는 같은 결과 파일을 쓴다(테스트가 바이트 단위로 비교한다). 스크립트는 개발용이다. Python 3.11+, 외부 패키지 없음.

```sh
python3 scripts/install-codex.py --dev     # 개발용(47822)
python3 scripts/install-codex.py           # 평소용(47821)
python3 scripts/install-codex.py --remove  # 이 설치기가 추가한 훅·MCP와 수정되지 않은 스킬만 제거
```

- 설치 뒤 **Codex를 새로 열고 `/hooks`에서 Waypoint 훅을 검토·신뢰**한다. `/mcp`에서 waypoint 연결을 확인한다. 스크립트는 신뢰 설정을 바꾸지 않는다.
- 쓰는 곳: `~/.codex/hooks.json`, `~/.codex/config.toml`, `~/.codex/waypoint/`, `~/.agents/skills/waypoint-tracker/`. 기존 훅·MCP는 보존하고 설정을 백업한다. 다른 waypoint MCP가 있거나 사용자가 직접 바꾼 스킬이 있으면 덮어쓰지 않고 멈춘다.
- 새 폴더는 Codex에서 `$waypoint-tracker init`으로 등록한다. Claude Code로 등록한 프로젝트는 그대로 쓴다. 두 도구가 같은 카드의 메모를 나눈다.

지원 범위와 신뢰 후 확인 목록은 [integration/codex/README.md](integration/codex/README.md).

## 화면에서 쓰는 것

- **작업 이어가기**: 카드 상세 「재개 문맥 준비」에서 도구를 고르고 문맥을 복사해 새 대화에 붙인다. 실행 파일이 있으면 「Claude Code에서 열기」/「Codex에서 열기」로 터미널까지 연다. 규칙은 `docs/SPEC.md` 「카드 작업 이어가기」.
- **완료 근거**: 완료 조건 줄마다 통과·실패·미검증·변경 후 미검증과 출처(확인됨·보고)를 보인다. 체크 상자는 사용자 판단으로 따로 둔다.
- **연동 상태**: 툴바 「연동 상태」(Mac 대시보드 「AI 연동」)에서 도구별 설정·마지막 수신·미처리 기록을 보고 **다시 점검**한다. **진단 정보 복사**는 숫자와 상태만 담는다(프로젝트명·경로·세션 ID·대화 제외, 자동 전송 없음).
