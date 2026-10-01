# Waypoint 명세

## 1. 문제와 목표

여러 프로젝트를 Claude Code로 동시에 진행하다 보니 다음이 뒤섞인다.

- 지금 어떤 작업이 돌고 있는지 (세션·서브에이전트 여러 개)
- 이전에 무엇을 했는지 (히스토리)
- 나중에 하려던 것이 무엇인지 (아이디어, 다음 할 일)

Waypoint는 이것을 **프로젝트 단위의 카드 보드**로 보여주는 개인용 추적기다. 사용자가 직접 입력하는 게 아니라, Claude Code 세션 안의 **훅(결정적 기록)** 과 **스킬(판단이 필요한 기록)** 이 자동으로 채운다.

### 하지 않는 것

- Anthropic API 호출, LLM 기반 요약·추천. 앱은 순수 추적기다.
- 과거 히스토리 가져오기. 프로젝트는 init 시점부터 기록한다.
- 다중 사용자·팀 기능.

## 2. 용어

| 용어 | 뜻 |
|---|---|
| 프로젝트 | 로컬 폴더 하나(`rootPath`)에 대응. 카드 키(예: `LDG`)를 가진다 |
| 카드 | Jira 티켓에 해당. `LDG-14` 형식 ID |
| 세션 | Claude Code 세션 1개 (`session_id`). 서브에이전트는 부모 세션의 하위 세션으로 기록 |
| 작업중 | 카드에 살아있는(live) 세션이 붙어 있는 상태 |
| 활동 없음 | 응답 진행 또는 이전 버전 세션에서 15분간 새 활동을 확인하지 못한 상태. 실패를 의미하지 않음 |

## 3. 아키텍처

```
Claude Code 세션들 ──훅(command)──▶ waypoint-hook.sh ──HTTP──▶ ┐
        │                                                      │  Waypoint.app (macOS)
        └──스킬이 MCP 도구 호출──────────────────────────────▶ ┤  - 로컬 서버 127.0.0.1:47821
                                                               │    · /hooks/*  (훅 수신)
   앱이 꺼져 있으면 훅은 outbox.jsonl에 적재 ──(앱 실행 시 흡수)─▶ │    · /mcp      (MCP, Streamable HTTP)
                                                               │  - SwiftData 저장소
                                                               │  - 지침 파일 감시 (FSEvents)
                                                               └──▶ CloudKit ──▶ iOS 앱 (읽기 위주)
```

결정 사항:

- **Mac 앱이 서버를 겸한다.** 메뉴 막대 상주 모드를 두어 창을 닫아도 서버는 돈다.
- **훅은 curl만 쓴다.** 앱이 꺼져 있거나 응답이 없으면 `~/Library/Application Support/Waypoint/outbox.jsonl`에 한 줄씩 적재한다. 훅은 절대 Claude Code를 막거나 느리게 하면 안 된다 (타임아웃 1초, 항상 exit 0).
- **MCP 서버**는 앱 내장 Streamable HTTP 엔드포인트. 사용자 범위로 한 번 등록한다:
  `claude mcp add --transport http --scope user waypoint http://127.0.0.1:47821/mcp`
  (2026-09-28 Claude Code 2.1.283 `claude mcp add --help`로 확인. `~/.claude.json`의 사용자 범위에 적힌다)
- iOS는 CloudKit 동기화로 같은 데이터를 본다. 로컬 서버는 macOS에만 있다. Mac은 서버·훅·MCP·지침 동기화를 그대로 두고 저장소만 CloudKit에 미러링한다. iOS에서 쓰는 것은 아이디어 분류(다음 할 일로 / 보관)뿐이다.
- **인스턴스 두 개**: 평소용(Release, `dev.antaeho.waypoint`, 47821, `~/Library/Application Support/Waypoint/`)과 개발용 Waypoint Dev(Debug, `dev.antaeho.waypoint.dev`, 47822, `…/Waypoint-Dev/`). 번들 ID로 가르고(`AppInstance`), 환경 변수 `WAYPOINT_PORT`·`WAYPOINT_SUPPORT_DIR`가 있으면 그 값이 먼저다. 훅·MCP 전역 설정은 평소용만 가리키고, 실측 폴더만 프로젝트 설정으로 Dev에 잇는다(`docs/DEVELOPMENT.md`).

### CloudKit 구성 (M6)

- SwiftData `ModelConfiguration(cloudKitDatabase: .private(<컨테이너>))`. 개인 DB 하나, 공유 없음.
- 컨테이너는 인스턴스마다 따로: 평소용 `iCloud.dev.antaeho.waypoint`, 개발용 `iCloud.dev.antaeho.waypoint.dev`(`AppInstance.cloudKitContainerIdentifier`). 엔타이틀먼트(`Config/Waypoint-{macOS,iOS}.entitlements`)는 build setting `WAYPOINT_CONTAINER`로 같은 값을 받는다.
- 환경: 둘 다 CloudKit **Development**. 개발 서명(Apple Development) 빌드는 기본이 Development라 엔타이틀먼트에 환경을 적지 않는다. 개인 앱이라 Production 스키마 배포는 하지 않는다. Development 스키마는 앱이 처음 올린 레코드로 자동으로 생긴다.
- 끄기: 환경 변수 `WAYPOINT_CLOUDKIT=0`, 또는 `WAYPOINT_SUPPORT_DIR`로 저장 폴더를 옮긴 실행(확인용 임시 저장소가 실제 컨테이너와 섞이지 않게). 샘플 모드(메모리 저장소)와 테스트(`makeContainer` 기본값)는 늘 로컬.
- 서명: 팀 `2FCXA77MC5` 자동 서명. App ID·컨테이너·프로파일은 `xcodebuild -allowProvisioningUpdates`가 만든다. 푸시: iOS `aps-environment`, macOS `com.apple.developer.aps-environment`(development), iOS 백그라운드 모드 `remote-notification`.
- iOS는 앱이 원격 알림을 직접 등록한다(`PhoneAppDelegate`). 등록하지 않으면 Mac 변경이 앱을 다시 열 때까지 오지 않았다(2026-09-28 실측). macOS는 미러링이 알림 수신을 스스로 연다.
- iOS 화면은 CloudKit 가져오기가 끝날 때마다 새 `ModelContext`로 다시 읽는다. 메인 context는 새로 생긴 객체만 보이고 이미 읽은 객체(세션 `endedAt` 등)를 옛 값으로 둬, 끝난 세션이 작업중에 남았다(iOS 26 실측).
- Mac은 가져오기가 끝나면 새 context로 카드를 읽어 메인 context에 이미 올라온 같은 카드에 늦은 값을 옮겨 적는다(`RemoteCardMerge`). 그대로 두면 메인 context가 옛 상태를 들고 있다가 그 카드를 저장할 때 iPhone에서 옮긴 상태를 되돌린다(실측). iPhone이 고치는 것은 카드뿐이다.
- 세션 상태는 훅 이벤트와 활동 시각으로 판정하며 iPhone에는 해당 상태 필드가 동기화된다.
- 쓰기 양: 훅마다 이벤트·세션 갱신이 저장되고 미러링이 묶어서 올린다. 40초짜리 실측 세션 하나에 내보내기 5번(2026-09-28).

## 4. 데이터 모델 (SwiftData)

```swift
Project      id, key(String, unique, 2–5 대문자), name, summary, rootPath, stack:[String],
             nextCardNumber:Int, createdAt, archivedAt?

Card         id, project, number:Int, title, body(markdown),
             kind: task | idea | bug,
             status: idea | next | active | done | archived,
             parent: Card?, criteria:[Criterion], 
             origin: claude | manual, originSessionId?,
             nextSessionNote?, statusBeforeActive?, createdAt, updatedAt, doneAt?

Criterion    text, isDone

Session      id(= Claude Code session_id), project, kind: main | subagent,
             parent: Session?, agentName?, cwd, gitBranch?,
             startedAt, lastSeenAt, endedAt?, claudePid:Int?,   // claudePid: 메인 세션만, 훅 스크립트가 보낸 Claude Code PID
             contextProjectKey:String?,          // 대화에 Waypoint 블록을 준 프로젝트 키(5장 「늦은 주입」)
             lastPrompt:String?,                 // 메인 세션의 마지막 사용자 요청 문장, 300자까지(5장 「마지막 요청 문장」). 끝난 세션은 30일 뒤 비운다
             lastPromptAt:Date?,                 // lastPrompt를 적은 훅 시각, lastPrompt와 함께 바뀐다
             state: live | stalled | ended          // 파생값, 저장 캐시

CardSession  card, session, attachedAt, detachedAt?

Event        id, project, card?, session?, at,
             type: session.start | session.end | card.created | card.status |
                   card.attached | card.detached | file.changed | commit |
                   note | guide.synced | check,
             payload: JSON(Data)

GuideDoc     id, project, relPath, content, contentHash(SHA-256), lastSyncedAt,
             draft?, isMissing, conflictContent?     // 저장 안 한 편집, 파일 없음, 충돌 때 읽은 로컬 내용
GuideVersion doc, content, at, source: app | local
```

- **키**: 영문 대문자 2–5자(`^[A-Z]{2,5}$`), 보관된 것까지 포함해 다른 프로젝트 키와 겹치지 않는다. 같은 폴더(`rootPath`를 `~` 펼치고 표준화해 비교)를 쓰는 프로젝트는 보관 포함 하나뿐. 규칙은 `ProjectKey`·`ProjectRegistry`(M5).
- **추천 키**(`ProjectKey.suggest`, 키를 안 줬을 때·경고 문구의 예): 이름의 영문 단어가 둘 이상이면 머리글자 2–4자(`Waypoint Init Probe` → `WIP`), 그다음 첫 단어의 첫 글자 + 자음 둘(`ledger` → `LDG`), 첫 단어 앞 3자. 영문이 없으면 폴더 이름으로 같은 순서, 그래도 없으면 `PRJ`. 모두 쓰이면 후보 앞 4자 + `A`–`Z`.
- **보관**(`archivedAt`): 사이드바·대시보드·메뉴 막대·최근 기록에서 숨기고 사이드바 맨 아래 「보관됨」 접힘 구역에만 보인다. 그 폴더의 훅은 기록하지 않는다(5장). 카드·기록은 그대로 두고 「보관 해제」로 되돌린다.
- **삭제**: 확인 알림(이름, 카드 수) 뒤 프로젝트를 지우면 카드·세션·연결·이벤트·지침 문서(버전 포함)가 함께 지워진다(cascade). 로컬 파일은 건드리지 않는다.

CloudKit(M6) 호환을 위해 처음부터 다음을 지킨다: `@Attribute(.unique)`를 쓰지 않고 키·ID 중복은 코드에서 막는다. 모든 속성은 기본값이 있거나 옵셔널, 관계는 옵셔널이고 역관계를 둔다. enum은 원시 문자열로 저장한다.

### 검증 근거 (`check` 이벤트, TRK-10)

카드 완료 조건별로 실행한 검증 명령과 결과를 잇는다. 모델 필드는 늘리지 않고 이벤트로 남긴다(기존 데이터 마이그레이션 없음).

- payload(`CheckRecord`): `command`(변수 대입 값은 `…`로 가림, 300자), `outcome`(`pass`·`fail`·`skipped`·`unknown`), `source`(`hook` = 훅이 실행을 직접 봄, 화면 「확인됨」 / `agent` = 에이전트 보고, 화면 「보고」), `criterion`(0부터, 에이전트 보고만), `criterionText`(보고 때 조건 글), `detail`(200자), `exitCode`, `provider`(claude·codex), `toolUseId`(훅, 재수신 중복 방지). `text` 키는 두지 않는다 — 옛 앱은 모르는 이벤트 종류를 `note`로 읽고 `text` 없는 메모를 숨기므로 옛 앱·옛 iPhone 앱에 근거가 메모로 보이지 않는다.
- 이벤트는 카드와 실행한 세션에 붙는다. 근거를 남기는 것은 훅(5장 「검증 근거」)과 `card_evidence`(7장)뿐이다.

### 완료 조건 근거 상태 (`CardEvidence`, 순수 함수)

- 조건마다 통과·실패·건너뜀·미검증 + 출처·시각·명령. 근거가 없으면 미검증. 완료 조건이 없는 카드는 표시하지 않는다(기존 카드 그대로 동작).
- 기준은 그 조건에 직접 붙은 가장 최근 에이전트 보고다. 보고 때 조건 글(`criterionText`)이 지금 조건 글과 다르면(`card_update`로 조건을 바꿈) 그 보고는 그 조건의 근거가 아니다.
- 훅 기록과 짝짓기: 보고와 훅 기록의 명령을 검증 조각으로 다듬어(리다이렉션·앞 변수 대입 제거, 공백 정리 — `cd /x && swift test 2>&1`과 `swift test`는 같은 조각) 보고의 조각이 모두 훅 기록에 있고, 훅 기록 시각이 보고 15분 전 이후이며 결과가 `pass`·`fail`이면 짝이다. 짝 중 가장 최근 훅 기록이 조건 상태를 정하고 출처는 「확인됨」이다: 보고와 같으면 보고를 확인한 것, 다르면 훅 결과를 따르고(보고가 통과라도 훅이 실패를 봤으면 실패), 보고 뒤에 같은 명령을 다시 돌렸으면 그 결과가 최신이다. `unknown` 훅 기록은 확인하지 않는다.
- 오래된 근거: 근거 시각(확인됨이면 실행 시각) 뒤에 그 카드의 `file.changed`가 있으면 「변경 후 미검증」. 같은 시각(같은 도구 호출)은 오래되지 않았다. 커밋은 코드를 바꾸지 않아 보지 않는다. 건너뜀은 오래되지 않는다.
- 세션 종료·카드 연결 해제·체크 상자는 근거 상태를 바꾸지 않는다. 체크 상자는 사용자 판단 표시로 근거와 따로 보인다. 카드를 자동으로 done 처리하지 않는다.
- 훅 기록만 있는 검증(조건 번호 없음)은 카드 수준 「검증 기록」에만 보인다.

### 파생 규칙

- 카드가 **작업중** = 열린 `CardSession` 중 세션 `state == live`인 것이 1개 이상.
- 표시 상태는 `SessionActivityRules`로 판정한다. `live`/`stalled`/`ended`는 이전 버전 호환을 위한 묶음이며 `stalled`는 입력·승인 대기와 활동 없음이지 작업 실패가 아니다. 입력 대기와 실행 중인 도구는 15분이 지나도 다른 상태로 덮지 않는다.
- 마지막 live 세션이 떨어지면 카드 `status`는 작업 시작 전 상태(`statusBeforeActive`)로 돌아간다. **자동으로 done이 되지 않는다.** 완료는 스킬이 사용자 확인 후 `card_update(status: done)` 하거나 사용자가 앱에서 옮긴다.
- **불변식: 열린 연결이 있으면 카드는 `active`다.** 카드가 active를 떠나면(앱 드래그·「완료로 옮기기」·iPhone 분류·`card_update(status)`, 모두 `CardLifecycle.move`) 그 카드의 열린 연결을 서브에이전트 것까지 모두 닫고 세션마다 `card.detached`(`reason: "card-moved"`)를 남긴다. 상태는 새로 정한 그대로 두고 `statusBeforeActive`로 돌리지 않는다. 연결이 풀린 세션은 끝나지 않았으면 카드 없는 세션 줄·타일이 된다.
- 어긋난 연결 점검: 앱이 시작 직후 한 번, 그 뒤 10초마다(세션 정리와 같은 자리), CloudKit 가져오기 뒤에 「카드가 active가 아닌데 열린 연결」을 찾아 닫는다(`CardLifecycle.closeStrayLinks`, `card.detached`에 `reason: "status-not-active"`). 카드 상태·수정 시각은 건드리지 않는다. 불변식 이전 데이터와 iPhone에서 옮긴 카드(연결은 병합하지 않는다)를 위한 것이다.
- 대시보드 "작업중" 목록 = 프로젝트별로 묶은 (세션, 카드) 쌍 + 카드가 붙지 않은 끝나지 않은 메인 세션 한 줄씩(카드 칸 비움, 제목 자리에 그 세션의 마지막 요청 문장 `lastPrompt`(없으면 「카드 없음」), 최근 파일은 그 세션과 서브에이전트가 카드 없이 남긴 `file.changed`). 같은 프로젝트에 세션 2개가 서로 다른 카드를 작업하면 그 프로젝트 아래 2줄. 세션에 카드가 붙으면 카드 없는 줄은 카드 줄로 바뀐다(중복 없음). 카드 없는 서브에이전트는 줄을 만들지 않는다. 제목의 「작업 N개」는 live 줄 수, 사이드바·프로젝트 표의 작업중·멈춤 수는 카드 수 + 카드 없는 메인 세션 수.
- 프로젝트 보드 작업중 칸 = 작업중 카드 + 그 아래 카드 없는 세션 타일(대시보드 카드 없는 줄과 같은 세션, `BoardQuery.sessionTiles`). 타일은 마지막 요청 문장(없으면 「카드 없음」), 세션(`sess·7f2a`), 최근 파일, 끝나지 않은 서브에이전트 수(있으면), 이벤트 기반 상태와 대기 시간. 끌거나 누를 수 없다. 칸 머리 개수는 카드 + 타일(사이드바·프로젝트 표 작업중 수와 같은 기준).
- 작업중 줄·타일·카드 상세는 `SessionFormat.activityText`로 도구 작업·응답 진행·입력 대기·승인 대기·활동 없음을 표시한다. 대기는 해당 전환 시각, 활동 없음은 마지막 활동 시각부터 경과를 표시한다.
- 프로젝트 화면의 **활동** 탭은 이벤트의 불변 `project` 연결을 기준으로 날짜·세션별 요청, 파일 변경, 커밋, 완료, 인수인계 메모를 시간순으로 보여준다. 세션이 나중에 다른 프로젝트로 연결되어도 과거 기록은 이동하지 않는다. 도구·카드·세션 필터와 카드 상세 연결을 제공하며, 같은 파일의 연속 변경만 5분 단위로 묶는다. 처음에는 최신 300건을 읽고 「더 보기」로 확장한다. 검색은 현재 읽은 기록 범위에만 적용된다.

## 5. 훅 → 기록 매핑

### 카드 작업 이어가기

Mac 카드 상세에서 재개 문맥을 준비하고 Claude Code·Codex를 선택해 미리보기·복사한다. 외부 AI 호출 없이 카드 본문, 다음 세션 메모, 미완료 조건, 해당 카드의 변경 파일과 커밋을 조합한다. 본문 6,000자, 메모 3,000자, 조건 20개(각 500자), 중복 없는 최신 파일 10개, 커밋 3개로 제한하며 생략 여부를 표시한다. 생성·복사는 상태나 이벤트를 변경하지 않는다. 완료·보관·프로젝트 없는 카드와 경로 없는 프로젝트는 준비할 수 없다.

사용자가 새 대화에 붙여넣으면 `project_resolve → session_bind → card_get → card_start` 순서로 연결하도록 안내한다. 복사한 과거 ID 대신 현재 대화의 실제 ID를 사용하며, 최신 카드가 완료·보관된 경우 자동으로 재개하지 않는다. 기존 세션 연결이 있으면 `otherSessions`를 통해 알려 작업 범위를 확인한다. 연결이 성공한 뒤에만 작업중으로 표시된다. 앱은 작업을 자동 실행하지 않는다.

재개 창 위쪽에 한 묶음으로 목표(카드 제목·본문 첫 글줄), 남은 완료 조건, 미검증 조건(근거 상태가 미검증·실패·변경 후 미검증, 건너뜀은 제외), 마지막 메모와 작성 시점·이후 변경 파일 수를 보인다(`CardResumeSummary`). 복사할 문맥 원문은 그 아래 접힌 칸에 둔다. 요약은 복사 문맥과 같은 기록을 읽는다.

재개 상태(`CardResumeStatus`)는 카드 상세의 재개 영역과 재개 창에 한 줄로 보인다: **준비됨**(복사 전, 재개 가능) → **복사함**(복사 성공, 고른 도구의 새 세션이 아직 붙지 않음) → **연결됨**(복사 뒤 같은 도구의 새 메인 세션이 이 카드에 열린 연결로 붙고 카드가 작업중). 그 밖에 **연결 끊김**(복사 뒤 붙었던 새 세션이 떨어짐), **재개 불가**(완료·보관 카드, 보관 프로젝트, 작업 폴더 없음, 다른 카드). 복사나 도구 열기만으로는 복사함에 머문다. 연결 판정은 `CardResumeAttempt`: 복사 전에 이 카드에 붙었던 세션(과거 ID), 다른 도구 세션, 서브에이전트, 다른 프로젝트 세션, 다른 카드에 붙은 세션은 치지 않는다. 다른 폴더(하위 폴더, 다른 등록 프로젝트 폴더)에서 시작한 세션도 `session_bind`로 이 프로젝트에 연결한 뒤 `card_start`하면 연결됨이다. 도구를 바꿔 다시 복사하면 그 도구의 새 세션만 본다. 상태는 카드 상세에 머무는 동안만 유지한다.

도구 열기(macOS): 그 도구의 실행 파일(`claude`·`codex`)이 흔한 설치 폴더(`~/.local/bin`, Claude는 `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, `~/.bun/bin`, `~/.volta/bin`)나 앱의 PATH에 있고, Terminal.app이 있고, 프로젝트 폴더가 있을 때만 재개 창에 「Claude Code에서 열기」/「Codex에서 열기」를 둔다(`ToolLaunch`). 누르면 문맥을 복사한 뒤(복사와 같은 재개 시도) 임시 `.command` 파일(0700, 실행되자마자 스스로 지움)을 Terminal.app으로 연다. 파일은 프로젝트 폴더로 `cd`하고 도구를 인자 없이 실행한다. 대화 내용·세션 ID·과거 대화 잇기 옵션은 넘기지 않는다. 조건이 하나라도 빠지면 버튼 없이 복사만 쓴다. 여는 데 실패하면 「터미널 열기 실패 · 문맥은 복사됨」.

활동 탭의 사용자 요청은 `note`의 `kind: user.prompt`로 최대 300자씩 저장한다. 이 버전 이전의 전체 요청 이력은 복원하지 않는다. 재수신된 동일 시각·내용의 요청은 중복 저장하지 않으며, 지연 수신은 세션 시작·프로젝트 연결 이력과 당시 카드 연결 구간으로 소속을 결정한다.

요청 문장 보관(`PromptRetention`): 요청 이벤트의 문장(`text`)은 기록 시각부터 30일이 지나면 지운다. 이벤트·시각·세션·카드 연결은 남고 활동 탭·카드 기록에는 문장 없이 「요청」으로 보인다(세션 묶음 제목은 세션 이름). 끝난 세션의 `lastPrompt`도 `lastPromptAt`(없으면 `endedAt`)부터 30일이 지나면 비운다(`lastPromptAt`은 남긴다). 끝나지 않은 세션의 `lastPrompt`는 두지만, 그 세션의 요청 이벤트 문장은 같은 30일 규칙으로 지운다. Mac 앱이 시작 직후 점검에서 한 번, 그 뒤 하루에 한 번 정리하고 지운 결과는 iCloud로 iPhone에 간다. 30일이 지난 요청이 outbox로 늦게 들어오면 다음 정리 때까지 문장이 남는다.

설정 예시: `integration/hooks/settings.example.json`. 사용자 전역(`~/.claude/settings.json`)에 둔다.
**이벤트 이름과 입력 JSON 필드는 구현 시점의 Claude Code hooks 문서로 반드시 확인할 것.**

2026-09-28 확인: https://code.claude.com/docs/en/hooks. 같은 날 Claude Code 2.1.283에서 로깅 모드(`WAYPOINT_HOOK_LOG=1`)로 실측했다. 실제 입력은 `Tests/Fixtures/hooks/real-*.json`.

### 공통 입력 필드 (문서)

`session_id`, `transcript_path`, `cwd`, `hook_event_name`, (이벤트에 따라) `permission_mode`, `prompt_id`, `effort`.
서브에이전트 안에서 난 훅에는 `agent_id`(서브에이전트 실행 고유 ID)와 `agent_type`(예: `Explore`, 사용자 에이전트 `name`)이 더 붙는다.
문서는 `agent_id`로 「메인 스레드 호출과 서브에이전트 호출을 구분하라」고 한다. **실측 확인: 서브에이전트 훅의 `session_id`는 부모 세션과 같은 값**이고, `agent_id`는 17자 16진 문자열(예: `ad5a8ca20b7faa5f7`)이다.
그래서 서브에이전트 하위 세션의 `Session.id`는 `agent_id`를 쓴다.

### 매핑

| 훅 | 입력(문서) | 서버 동작 | 비고 |
|---|---|---|---|
| `SessionStart` | `source`(startup/resume/clear/compact/fork), `model?` | `cwd`로 프로젝트 조회 → 세션 생성(이미 있으면 다시 살림). 응답 본문을 stdout으로 출력해 **대화 컨텍스트에 주입** | 주입 형식은 아래 「SessionStart 주입」. command 훅만 지원 |
| `UserPromptSubmit` | `prompt` | `lastSeenAt` 갱신, 메인 세션의 사용자 문장을 `lastPrompt`에 저장(아래 「마지막 요청 문장」). 메인 세션이 지금 프로젝트의 블록을 받지 못했으면 같은 블록을 응답 본문으로 돌려줘 stdout으로 **주입**(한 번) | heartbeat. 아래 「늦은 주입」 |
| `PreToolUse` (`Agent`) | `tool_name`=`Agent`, `tool_input.prompt/description/subagent_type`, `tool_use_id` | 부모 세션 heartbeat. 프롬프트의 `[LDG-16]` 같은 카드 ID와 `subagent_type`을 **대기 목록**에 올린다 | 서브에이전트 도구 이름은 `Agent`(옛 이름 `Task`도 matcher에 남겨 둔다) |
| `SubagentStart` | `agent_id`, `agent_type` | 하위 세션 생성(`id`=`agent_id`, `agentName`=`agent_type`, 부모=`session_id` 세션). 대기 목록에서 같은 `agent_type`의 가장 오래된 항목을 꺼내 카드가 있으면 연결 | 두 이벤트를 잇는 키는 실측에도 없다(`SubagentStart`에 `tool_use_id` 없음, 같은 `prompt_id`만 공유) → 순서·종류로 짝짓는다 |
| `PostToolUse` (Edit/Write/Bash 등) | `tool_name`, `tool_input`, `tool_response` | `lastSeenAt` 갱신(서브에이전트면 그 하위 세션도), 변경 파일을 현재 작업중 카드 이벤트로. `Bash`의 `tool_response.gitOperation.commit`(없으면 `git commit` 출력 `[브랜치 해시] 메시지`)에서 commit 이벤트 | 줄 수는 `structuredPatch`·`bashEditDiff.files[].hunks`의 `+`/`-` 줄. 조각이 없으면 `Edit`은 `old_string/new_string`, `Write`는 `content`로 추정. `bashEditDiff.changedFiles`에만 있는 파일은 줄 수 0 |
| `SubagentStop` | `agent_id`, `agent_type`, `last_assistant_message` | 하위 세션 종료, 연결 해제 | 앱 내부 에이전트(`agent_type` 빈 값)에도 불린다 → 모르는 `agent_id`면 무시 |
| `Stop` | `stop_hook_active`, `last_assistant_message` | `lastSeenAt` 갱신 | 턴 종료일 뿐 세션 종료 아님 |
| `SessionEnd` | `reason`(clear/resume/logout/prompt_input_exit/other) | 세션 종료, 모든 연결 해제(하위 세션 포함) | 기본 타임아웃 1.5초. 가끔 오지 않는다 → 아래 「종료 판정」 |

모든 훅: 스크립트가 보낸 Claude Code PID(6장)가 있으면 메인 세션 `claudePid`에 적는다. 비어 있거나 이 훅이 지금까지 받은 것 중 가장 새것(`at >= lastSeenAt`)일 때만 바꾼다(`--resume`은 같은 `session_id`를 새 프로세스로 이어 가고, outbox로 늦게 온 옛 훅은 되돌리지 않는다). 서브에이전트 훅의 PID는 부모와 같은 프로세스라 메인 세션에만 적는다.

재수신(TRK-11, docs/RELIABILITY.md): 실시간 응답이 1초를 넘으면 같은 훅이 outbox에도 쓰여 두 번 들어온다. 같은 세션에 같은 `tool_use_id`의 파일 변경·커밋 기록이 10분 안에 있으면 다시 남기지 않는다(기록 payload에 `toolUseId`). 요청 문장은 `prompt_id`(Claude 2.1.196+)·`turn_id`(Codex)가 같으면 같은 요청이고, ID가 없으면(옛 outbox 줄) 같은 문장이 10초 안에 있을 때 같은 요청으로 본다(payload에 `promptId`). `PreToolUse(Agent)`는 부모 세션·`tool_use_id`마다 대기 목록에 한 번만 올린다. 끝난 세션보다 이른 시각의 늦은 `PostToolUse`는 같은 ID의 세션을 새로 만들지 않는다.

### SessionStart 주입

`Waypoint:`로 시작하는 블록. tracker 스킬(`integration/skills/tracker/SKILL.md`)이 같은 형식을 적어 두고 읽는다. 바꾸면 둘을 같이 고친다.

```
Waypoint: PRB (훅 실측)
sessionId: ae25fca9-6e32-4d91-9b94-e059f57a5972
다음 할 일:
- PRB-1 실측용 카드
다른 세션에서 작업중:
- PRB-4 파서 (sess·a1b2)
직전 세션 메모 (PRB-1 실측용 카드):
  note.txt에 hello 추가함. 볼 파일: note.txt
작업을 시작·전환·마무리하거나 나중에 할 일을 들으면 tracker 스킬을 따른다.
```

- 1줄: `Waypoint: <키> (<이름>)`, 2줄: `sessionId: <Claude Code session_id>`. 마지막 줄은 스킬 안내(고정 문구).
- 다음 할 일: status next, 번호순 상위 5개. 없으면 제목째 뺀다.
- 다른 세션에서 작업중: 대시보드 작업중 줄 중 이 세션·이 세션의 서브에이전트가 아닌 카드 줄(카드 없는 세션 줄은 뺀다). 멈춘 세션은 `, 멈춤`.
- 직전 세션 메모: 다음 세션 메모가 있고 done·archived가 아닌 카드 중 **가장 최근에 `card_handoff`한 카드 하나**(handoff 기록 시각, 없으면 `updatedAt`). 메모 줄은 두 칸 들여쓴다.
- 등록되지 않은 폴더: 한 줄 `Waypoint: 이 폴더는 Waypoint에 없음. `/tracker init`으로 등록할 수 있음.`

**보관된 프로젝트 폴더**(가장 가까운 상위 `rootPath`가 보관된 프로젝트)는 등록되지 않은 폴더처럼 기록하지 않되, `SessionStart`에 안내 줄도 주지 않는다(빈 본문). 보관하기 전에 시작한 세션도 보관 뒤의 훅(heartbeat·파일 변경 등)은 기록하지 않는다. 단 `SessionEnd`·`SubagentStop`은 열린 세션을 닫는다(보관을 풀었을 때 끝난 세션이 작업중으로 남지 않게). 닫히지 않은 세션은 종료 판정이 닫는다. 보관을 풀면 다음 훅부터 다시 기록한다.

### 늦은 주입 (`UserPromptSubmit`)

`SessionStart`는 세션을 열 때 한 번만 난다. 그래서 등록 전에 시작한 세션, 등록 안 된 폴더에서 시작해 등록 폴더로 옮겨 온 세션은 블록을 받지 못해 스킬이 `sessionId`를 모른다(2026-09-28 chainmate 세션: `~/workspace`에서 시작해 옮겨 왔고 CHM은 그 뒤 등록 → 「이 폴더는 Waypoint에 없음」만 받았다).

- 세션에 블록을 준 프로젝트 키를 적는다(`Session.contextProjectKey`). `SessionStart`에서 블록을 줄 때, 그리고 아래 늦은 주입 때.
- 메인 세션의 `UserPromptSubmit`에서 `contextProjectKey`가 없거나 세션의 지금 프로젝트 키와 다르면 「SessionStart 주입」과 같은 블록을 응답 본문(`200 text/plain`)으로 돌려주고 키를 적는다. 그다음부터는 `204`. 블록을 받은 뒤 세션의 프로젝트가 바뀌면 한 번 더 준다(세션의 프로젝트는 처음 만들 때 정해지고 지금은 옮겨 가지 않는다 — 프로젝트를 옮기는 경로가 생기면 저절로 적용된다).
- 주지 않는 경우: 서브에이전트 안의 훅(`agent_id` 있음), 끝난 세션, 미등록·보관 폴더(미등록 안내 줄은 `SessionStart`에서만).
- outbox로 흡수하는 훅(앱이 꺼져 있던 동안의 것)은 이미 지난 일이라 텍스트를 만들지 않고 키도 적지 않는다. `SessionStart`도 같다. 그래서 앱이 꺼진 채 시작한 세션은 앱이 켜진 뒤 첫 프롬프트에 블록을 받는다.
- 문서(2026-09-28 확인, https://code.claude.com/docs/en/hooks 「UserPromptSubmit decision control」): exit 0의 평문 stdout은 `UserPromptSubmit`·`SessionStart` 등에서 Claude가 보는 컨텍스트가 된다. JSON `hookSpecificOutput.additionalContext`(v2.1.196+, 10,000자)도 있지만 `SessionStart`와 같은 평문 방식을 쓴다. 전사에는 사용자 프롬프트 앞에 훅 이름을 보낸 쪽으로 한 별도 메시지로 남는다.
- 이 기능을 넣기 전부터 떠 있던 세션은 `SessionStart`로 블록을 받았어도 키가 비어 있어 다음 프롬프트에 한 번 더 받는다.
- 실측(2026-09-28, Claude Code 2.1.283, Dev, `~/workspace/waypoint-late-probe`): 미등록일 때 `claude -p`로 시작(「이 폴더는 Waypoint에 없음」만 받음) → 앱을 끈 채 폴더를 등록(LPR) → `--resume`에서 `SessionStart`를 빼고(대화형으로 이어 가는 경우와 같게) 프롬프트 → 전사에 `attachment` `{"type":"hook_success","hookEvent":"UserPromptSubmit","stdout":"Waypoint: LPR (늦은 주입 실측)\nsessionId: 0124a6c7-…"}`이 들어갔고 Claude가 블록을 그대로 옮겨 적었다. 두 번째 `--resume`에는 UserPromptSubmit 출력이 없었고 Claude는 「없음」. 저장소 `contextProjectKey` = `LPR`. 전사에서 이 attachment는 사용자 메시지 바로 뒤 줄에 적힌다.

### 마지막 요청 문장 (`UserPromptSubmit`)

카드 없는 세션 줄·타일은 카드 제목이 없어 무슨 작업인지 알 수 없다. 앱은 LLM을 쓰지 않으므로 요약 대신 그 세션에서 사용자가 마지막으로 보낸 문장을 제목 자리에 보여 준다.

- 메인 세션의 `UserPromptSubmit`에서 `prompt`(실측·문서. 옛 문서 예시 이름 `prompt_text`도 받는다)를 앞뒤 공백 정리 후 앞 300자(문자 단위)만 `Session.lastPrompt`에 적고, 그 훅 시각을 `lastPromptAt`에 적는다(`HookParsing.userPrompt`). 세션당 마지막 하나만 둔다. 두 값은 아래 규칙대로 늘 함께 바뀐다.
- 넣지 않는 것: 서브에이전트 안의 훅(`agent_id` 있음), 빈 문장, `<`로 시작하는 자동 메시지(서브에이전트 완료 알림 `<agent-message from=…>` — 실측 `real-UserPromptSubmit-agent-message.json`, 백그라운드 작업 알림 `<task-notification>` 등). 그때는 앞 값을 그대로 둔다. 슬래시 명령(`/tracker init`)은 그대로 적는다. 붙여 넣은 글(`<pasted_content id=…>…</pasted_content>`, 전사에서 확인)은 태그만 벗겨 적는다.
- outbox로 흡수한 훅도 적는다. 단 비어 있지 않으면 이 훅이 지금까지 받은 것 중 가장 새것(`at >= lastSeenAt`)일 때만 바꿔서, 늦게 들어온 옛 프롬프트가 더 최근 값을 덮지 않는다(`claudePid`와 같은 규칙).
- 보관: 끝난 세션은 `lastPromptAt`(없으면 `endedAt`)부터 30일이 지나면 `lastPrompt`를 비운다(위 「요청 문장 보관」).
- 화면(`SessionFormat.promptPreview`): 줄바꿈·연속 공백을 공백 하나로 모아 한 줄로 만들고 앞 160자(넘으면 「…」). 대시보드·iPhone은 흐리게 한 줄(iPhone 두 줄), 보드 타일은 두 줄. Mac은 마우스를 올리면 저장된 문장 전체.

등록되지 않은 폴더의 세션은 무시한다 (단, `SessionStart` 컨텍스트로 "이 폴더는 Waypoint에 없음, `/tracker init` 가능"을 한 줄 알린다). 하위 폴더에서 연 세션은 가장 가까운 상위 `rootPath` 프로젝트로 매칭한다.

### 실측 결과 (2026-09-28, Claude Code 2.1.283, `claude -p`)

`~/workspace/waypoint-probe`에서 `claude -p`로 돌린 세션의 훅 입력을 로깅 모드로 받았다. 실제 입력은 `Tests/Fixtures/hooks/real-*.json`(문서 예시로 만든 `doc-*.json`은 그대로 둔다. 실측과 모순되는 필드는 없었다).

- **서브에이전트**: 서브에이전트 안의 훅(`PostToolUse` 등)과 `SubagentStart`/`SubagentStop`의 `session_id`는 부모 세션과 같다. `agent_id`는 17자 16진(`ad5a8ca20b7faa5f7`), `agent_type`은 `subagent_type` 값(`general-purpose`). 그래서 하위 세션 `Session.id` = `agent_id`로 확정.
- **도구 이름**: `Agent`. `tool_input`은 `description`, `prompt`, `subagent_type`, `run_in_background`. 프롬프트 첫 줄 `[PRB-1]`이 그대로 온다.
- **순서**: 포그라운드·백그라운드(`run_in_background: true`) 모두 `PreToolUse(Agent)` → `SubagentStart`(1~2초 뒤) → 서브에이전트의 `PostToolUse` → `SubagentStop`. 백그라운드는 그사이 부모의 `Stop`·`UserPromptSubmit`이 섞인다. 서브에이전트가 끝나면 부모에 `UserPromptSubmit`(`prompt`가 `<agent-message from="<agent_id>">…`)이 한 번 더 온다 — heartbeat로만 쓰고 `lastPrompt`에 넣지 않는다.
- **앱 내부 에이전트**: `agent_type`이 빈 값인 `SubagentStop`이 `SubagentStart` 없이 온다(대화 요약 같은 내부 작업). 모르는 `agent_id`라 무시한다.
- **`SessionStart`**: `source`와 공통 필드만 온다(`model` 없음). `--resume`은 **같은 `session_id`**에 `source: resume`, `--fork-session`은 **새 `session_id`**에 `source: fork`. resume/fork에는 `context_tokens`, `seconds_since_last_response`, `prompt_cache_likely_expired`, `estimated_cache_write_usd`가 더 붙는다. `clear`/`compact`는 대화형에서만 나서 이번에 재지 못했다.
- **`SessionEnd`**: `-p` 모드에서도 `reason: "other"`로 온다. 단 **늘 오지는 않는다**: 20개 세션 중 17개에서 왔고, 도구를 쓰는 `-p` 세션 2개를 동시에 끝냈을 때 두 번 다 하나가 빠졌고, 서브에이전트를 쓴 단독 세션 하나도 빠졌다. 사용자의 다른 `SessionEnd` 훅(`cc-hook.sh end`)도 같은 세션에서 불리지 않아, Waypoint 스크립트 문제가 아니라 Claude Code가 훅을 부르지 않았거나 끝내기 전에 프로세스를 닫은 것으로 본다. 빠진 세션은 Claude Code 프로세스가 사라지면 앱이 끝낸다(아래 「종료 판정」).
- **공통 필드**: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, 대부분 `prompt_id`, `permission_mode`(`auto` 등). `effort`는 문자열이 아니라 `{"level": "medium"}` 객체다(Waypoint는 안 쓴다). `Stop`·`SubagentStop`에 `background_tasks`, `session_crons`가 붙는다.
- **`Edit`의 `tool_response`**: `filePath`, `oldString`, `newString`, `originalFile`, `structuredPatch`(`[{oldStart, oldLines, newStart, newLines, lines:[" a","-b","+B1"]}]`), `replaceAll`, `userModified`. 줄 수는 `structuredPatch`의 `+`/`-` 줄로 센다(`replace_all`도 정확).
- **`Write`의 `tool_response`**: `type`(`create`/`update`), `filePath`, `content`, `structuredPatch`(새 파일이면 빈 배열), `originalFile`. 새 파일은 `content` 줄 수, 덮어쓰기는 `structuredPatch`로 센다.
- **`Bash`의 `tool_response`**: `stdout`, `stderr`, `interrupted`, `isImage`, `noOutputExpected`. 파일을 바꾸면 `bashEditDiff`: `files:[{filePath, hunks:[…lines], created}]`, `moreFiles`, `changedFiles`. 커밋하면 `gitOperation.commit`: `{sha, kind: "committed", branch}`. 커밋은 이것을 먼저 쓰고, 메시지는 출력 첫 줄 `[브랜치 해시] 메시지`에서 얻는다.
- **`MultiEdit`**: 실측 세션의 도구 목록에 없다. 바이너리에는 권한 규칙 호환용으로 이름이 남아 있어 matcher와 파서는 그대로 둔다.
- **속도**: 훅 한 번 실행에 수십 ms(전사의 `stop_hook_summary`에서 Waypoint `Stop` 32 ms). `claude -p "hi"` 전체 9초로 눈에 띄는 지연 없음.
- **이전 matcher 제한 해소(2026-09-30)**: PreToolUse·PostToolUse는 모든 도구를 관찰한다. 도구 실행은 시작과 완료를 tool_use_id로 연결하므로 장시간 실행을 활동 없음으로 오판하지 않는다.

### 검증 근거 (`PostToolUse`·`PostToolUseFailure`, TRK-10)

셸 도구(Claude `Bash`, Codex `Bash`·옛 이름 `shell`·`exec_command`·`local_shell`)가 검증 명령을 실행하면 그 세션의 열린 카드(서브에이전트가 카드 없이 일하면 부모 세션의 카드)에 `check`(`source: hook`)를 남긴다. 카드가 없는 세션은 남기지 않는다(조건과 이을 곳이 없다). 같은 `tool_use_id`는 한 번만. outbox로 늦게 흡수한 훅도 남긴다.

- 검증 명령 판정(`VerificationCommand`): 따옴표를 존중해 `&&` `||` `|` `;` `&` 줄바꿈에서 나눈 조각이 아래 패턴으로 시작하면(앞 변수 대입·`time`·`env`·`timeout N`·`uv|poetry|pipenv|hatch run` 허용) 검증 명령이다. `swift test|build`, `xcodebuild … test|build|build-for-testing|test-without-building`, `npm|pnpm|yarn|bun (run )test`, `(npx|pnpm exec|yarn) jest|vitest|mocha`, `pytest`, `python(3) -m pytest|unittest`, `python(3) …/test*.py`, `go test`, `cargo test|nextest`, `gradle|gradlew … test`, `mvn … test|verify`, `make test|check`, `bash|sh|zsh …/test*.sh`, `./…/test*.sh`, `deno test`. 패턴 문자열은 `VerificationCommand.pattern` 한 곳이고 훅 스크립트의 `verify_pattern`과 같은 문자열이어야 한다(테스트가 비교). 늘릴 때 둘을 같이 고친다.
- 결과(`HookParsing.check`):
  - Claude: 문서(2026-10-01 확인, https://code.claude.com/docs/en/hooks 「PostToolUseFailure」)와 실측(2.1.286, `real-PostToolUse-Bash-test.json`·`real-PostToolUseFailure-Bash-test.json`)으로 **0이 아닌 종료는 `PostToolUseFailure`로만 오고**, `error` 첫 줄이 `Exit code N`이다(`is_interrupt`도 온다). 성공한 `PostToolUse`의 `tool_response`(`stdout`, `stderr`, `interrupted`, `isImage`, `noOutputExpected`)에는 종료 코드가 없다. 그래서 `PostToolUse` = 종료 코드 0, `PostToolUseFailure` = `Exit code N`의 N. `interrupted`·`is_interrupt`, `Exit code` 줄이 없는 실패(셸을 못 띄움·시간 초과 문구), 백그라운드 실행(`run_in_background` → 시작만 알리는 `PostToolUse`에 `backgroundTaskId`, 실측. 뒤의 종료 코드는 훅으로 오지 않는다)은 `unknown`.
  - Codex: 문서상 0이 아닌 종료도 `PostToolUse`로 온다. `metadata.exit_code`·`exit_code`, 없으면 출력의 `Process exited with code N`·`Exit code: N` 줄. 모르면 `unknown`. Codex 응답 형식은 문서 예시가 없어 `doc-codex-PostToolUse-Bash-test-*.json`은 추정 형식이다(실제 Codex 실행 미확인).
  - 명령 전체의 종료 코드가 검증 조각의 것일 때만 `pass`·`fail`: 첫 검증 조각 앞 연결자는 `&&`·`;`·`|`, 뒤는 `&&`만, 끝이 `&`가 아닐 것. `swift test | tail`(pipefail 없음), `swift test; echo`, `swift test || true`, `make lint || swift test`는 `unknown`.

### 종료 판정 (`SessionEnd`가 오지 않은 세션)

앱이 10초마다, 시작 직후, 앱 활성화·잠자기 복귀 때 outbox를 흡수하고, 끝나지 않은 **메인 세션**을 검사한다(`SessionSweep`, `AppServices.refreshStates`).

- 도구별 PID(Claude의 `claudePid`, Codex의 `processPid`)가 있으면 그 프로세스를 본다(`sysctl KERN_PROC_PID`). 없거나 좀비면 끝낸다(`reason: "process-gone"`). 프로세스 시작 시각(`p_starttime`)이 `lastSeenAt`보다 2초 넘게 늦으면 PID를 재사용한 다른 프로세스로 보고 끝낸다(마지막 훅 뒤에 시작한 프로세스는 그 훅을 보냈을 수 없다. 2초는 outbox `receivedAt`이 초 단위로 잘리는 몫). 프로세스가 살아 있으면 오래 조용해도 둔다.
- PID가 없으면(옛 스크립트, PID를 못 찾은 경우) `lastSeenAt`에서 30분이 지나면 추적을 만료한다(`reason: "tracking-expired-30m"`). 실제 작업 완료로 판단하지 않는다. Claude 네이티브 설치의 버전 번호 실행 파일도 경로로 식별하며 조상을 8단계까지 확인한다.
- 끝내는 경로는 `SessionEnd`와 같다(`HookProcessor.finish`): 끝나지 않은 하위 세션부터 닫고, 카드 연결을 모두 해제해 카드를 작업 전 상태로 돌리고(done으로 바꾸지 않는다), `session.end`에 `reason`을 남긴다. 끝낸 시각은 검사 시각, `lastSeenAt`은 그대로 둔다.
- 끝낸 뒤 그 시각보다 늦은 훅이 오면(resume 등) 세션은 다시 살아난다(기존 규칙). 그 이전 시각의 늦은 outbox 기록은 무시한다. 재개할 때 옛 PID는 비운다. 자동 정리된 세션은 실제 ID를 전달한 `session_bind`로도 재연결할 수 있다. 명시적으로 종료된 세션은 이 경로로 되살리지 않는다.
- 실측(2026-09-28): 도구를 쓰는 `claude -p` 2개를 동시에 돌리다 `kill -9`로 죽이자 두 세션 모두 28초 뒤 `process-gone`으로 끝났다. 같은 날 정상 종료한 동시 세션 12개는 모두 `SessionEnd`가 왔다.

### 남은 문제

- `SessionStart(source: clear/compact)`의 `session_id`는 대화형 세션에서 따로 확인해야 한다.

### Codex 연결 (2026-09-30)

- 공식 기준: https://learn.chatgpt.com/docs/hooks, https://developers.openai.com/codex/mcp. 로컬 Codex CLI 훅을 먼저 지원한다. 클라우드 실행은 로컬 훅 지원 범위에 포함하지 않는다.
- Codex는 `/hooks/codex/<EventName>`으로 원본 JSON을 보낸다. 기존 `/hooks/<EventName>`은 Claude Code 그대로다. 두 입력은 공유 처리기로 들어가기 전에 도구별 필드를 정규화한다.
- 세션은 `providerRaw`(claude/codex, 기본 claude)를 저장한다. 기존 Claude ID는 유지하고 Codex ID는 `codex:<원본 session_id>`로 저장·주입한다. 하위 세션도 같은 접두사를 써서 두 도구의 ID가 겹치지 않게 한다.
- `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `SubagentStart`, `SubagentStop`, `Stop`, `Interrupt`, `SessionEnd`를 받는다. Stop·Interrupt는 활동 기록이고 완료 처리를 하지 않는다. 파일 변경은 성공한 `apply_patch`의 패치·결과에서 추출한다.
- Codex의 훅에는 `tool_input`/`tool_response`가 JSON 문자열로 올 수 있다. `apply_patch`는 command 패치 문자열, Bash는 command 입력과 텍스트 출력으로 정규화한다. Agent 입력의 message/agent_type도 처리한다. 전사 파일 형식은 안정된 API가 아니므로 전사 파일 감시는 하지 않는다.
- Codex PID는 `X-Waypoint-Process-PID`로 받아 `processPid`에 저장하고 기존 Claude `claudePid`는 유지한다. 프로세스 소멸 시 종료 정리는 두 도구에 동일하게 적용한다.
- outbox는 Codex 줄에 `provider: "codex"`, 선택적 `processPid`를 추가한다. provider가 없는 기존 줄은 Claude로 처리한다.
- MCP 서버와 카드 API는 공유한다. card_create는 연결 세션의 도구로 origin을 정하고, 세션이 없는 호출과 project_init에는 선택적 provider를 받는다. 초기 카드에도 해당 origin을 남긴다.
- 훅 출력은 SessionStart·늦은 UserPromptSubmit의 컨텍스트만 허용한다. 스크립트는 1초 HTTP 타임아웃·실패 시 exit 0·outbox 적재를 유지한다. Codex의 `/hooks` 신뢰 검토는 사용자가 직접 한다.
- Codex 픽스처는 `doc-codex-*`로 문서 기반임을 구분한다. 실제 신뢰된 Codex 세션과 CloudKit 스키마 배포는 별도 실측 대상이다.

## 6. 로컬 HTTP API (훅용)

모두 `POST http://127.0.0.1:47821/hooks/<EventName>`, 본문은 Claude Code가 훅에 넘긴 JSON 그대로. 스크립트가 훅을 부른 Claude Code 프로세스를 찾으면 머리 `X-Waypoint-Claude-PID: <PID>`를 더한다(없으면 뺀다). 응답:

- `SessionStart`: `200 text/plain` — 컨텍스트로 주입할 짧은 텍스트 (없으면 빈 본문)
- `UserPromptSubmit`: 늦은 주입(5장)이 있으면 `200 text/plain` 블록, 없으면 `204`
- 나머지: `204`

스크립트는 `SessionStart`·`UserPromptSubmit`이 `200`이고 본문이 있을 때만 stdout으로 찍는다. 다른 이벤트는 본문이 와도 찍지 않는다.

outbox 형식: 한 줄에 `{"event":"<EventName>","receivedAt":<unix>,"claudePid":<PID>,"trimmed":true,"payload":<줄인 JSON>}`. `claudePid`는 PID를 찾았을 때만 있다(Codex는 `"provider":"codex"`, `processPid`). 앱은 실행 시 순서대로 흡수하고 파일을 비운다(흡수한 파일은 지운다). 읽을 수 없는 줄(JSON·필수 필드·`provider` 오류)은 버리지 않고 원문 그대로 `outbox.quarantine.jsonl`(0600)에 덧붙인다. 격리 줄은 다시 흡수하지 않고 미처리 기록 수에도 넣지 않는다(연동 상태에 「누락 기록 N건 형식 오류」). 한 줄의 DB 저장이 실패하면(또는 격리 파일에 쓰지 못하면) 그 줄부터 끝까지를 떼어 낸 파일에 다시 쓰고, 뒤 파일까지 모두 멈춘다. 흡수는 한 번마다 새 `ModelContext`(같은 컨테이너)에서 하고, 저장에 실패하면 그 context를 통째로 버린다(`HookProcessor.absorbOutbox`). 메인 context는 흡수 전에 저장 안 된 변경을 저장하고(저장하지 못하면 그 흡수를 미룬다), 흡수 뒤에는 이미 올려 둔 프로젝트·카드·세션·연결을 저장소 값으로 다시 읽는다(`ContextReload`). 그래서 남긴 줄은 같은 실행의 다음 10초 점검·연동 상태 **다시 점검**·서버 준비 때 그 줄부터 다시 흡수한다. 횟수 제한은 없다(디스크가 잠깐 막혀도 기록을 잃지 않게). 서브에이전트 대기 항목은 흡수용 처리기에 넘겼다가 저장된 결과대로 돌려받는다. 실시간 훅과 세션 정리의 저장 실패는 rollback 뒤 같은 다시 읽기로 메모리를 저장소에 맞춘다(DECISIONS 2026-10-01 TRK-33). MCP 도구·프로젝트 등록·보드 끌어 놓기·카드 상세도 같다(`ContextReload.commit`, TRK-34). 남은 줄을 다시 쓰는 것마저 실패하면 파일을 그대로 두어 앞부분이 다시 들어올 수 있다(손실보다 중복). 줄은 읽혔지만 본문에서 세션 정보를 못 읽은 경우는 저장 실패가 아니므로 소비하고 「누락 기록 세션 정보 읽기 실패」만 알린다.

`payload`는 앱이 읽는 필드만 남긴다(2026-10-01, 스크립트 안 jq 필터 `OUTBOX_FILTER`, `/usr/bin/jq`). 실시간 POST와 로깅 모드(`hook-log/`)는 원본 그대로다. 앱이 세는 값은 같은 결과가 나오는 자리표시로 바꿔서 앱 코드는 그대로 읽는다.

| 자리 | 남기는 것 |
|---|---|
| 최상위 | `session_id`, `cwd`, `hook_event_name`, `agent_id`, `agent_type`, `source`, `reason`, `tool_name`, `tool_use_id`, `prompt_id`, `turn_id`(재수신 판정, TRK-11), `prompt`·`prompt_text`(앞 600자 — 앱은 공백·붙여넣기 태그를 벗긴 뒤 300자), `error`(첫 줄이 `Exit code N`일 때 그 줄만), `is_interrupt` |
| `tool_input` | `file_path`, `subagent_type`, `agent_type`, `workdir`, `cwd`. `old_string`·`new_string`·`content`·`edits[]`는 줄 수만큼의 `\n`. `prompt`·`message`는 `[KEY-n]` 카드 ID만. `command`는 검증 명령 패턴(5장 「검증 근거」, `verify_pattern`)에 맞으면 원문, 아니면 `git commit`이 들어 있으면 `"git commit"`(또는 `"git -c commit"`), 아니면 뺀다. `run_in_background`는 셸 도구만. Codex `apply_patch`의 `command`는 `*** ` 머리 줄과 `+`/`-` 한 글자 줄만 |
| `tool_response` | `structuredPatch[].lines`·`bashEditDiff.files[].hunks[].lines`는 `+`/`-` 한 글자만(조각 개수 유지), `bashEditDiff.files[].filePath`·`changedFiles`, `gitOperation.commit.{sha,branch}`, `stdout`은 커밋 줄 `[브랜치 해시] 메시지` 첫 줄, Codex 종료 코드 줄(`Process exited with code N`·`Exit code: N`) 첫 줄과 Codex `Success. Updated the following files:`·`A/M/D 경로` 줄만, `metadata.exit_code`, `exit_code`, `exitCode`, `interrupted`, `backgroundTaskId`. Codex의 문자열 응답·`output`·`text`는 `stdout`으로 합친 뒤 줄인다 |

그 밖의 필드(`transcript_path`, `permission_mode`, `description`, 파일 내용, 명령 출력·실패 출력 등)는 쓰지 않는다. 검증 명령의 원문은 남는다(앱이 근거로 쓴다). jq가 없거나 실패하면 `session_id`·`cwd`만 남기고(값에 따옴표·역슬래시가 없을 때), 그것도 못 찾으면 줄을 쓰지 않는다. 원문은 어느 경우에도 outbox에 쓰지 않는다. 앱이 꺼진 경로 한 번에 약 5~8 ms가 는다(중앙값 21 → 26~27 ms, 2026-10-01 측정).

Claude Code PID 찾기(스크립트): 조상 프로세스를 4단계까지 올라가며(`ps -o ppid=,comm= -p`) 실행 파일 이름(`comm`의 마지막 경로 조각)이 `claude`인 첫 프로세스. 인자(`args`)로는 비교하지 않는다 — 이 스크립트 경로 `~/.claude/waypoint/…`가 셸 인자에 들어 있다. 2.1.283 실측에서는 스크립트 바로 위 부모가 `claude`라 `ps`를 한 번 부르고, 훅 한 번에 약 3 ms가 늘었다(중앙값 15.9 → 18.7 ms).

## 7. MCP 도구 (스킬용)

스킬이 호출한다. Claude Code에서의 도구 이름은 `mcp__waypoint__<도구>`(실측).

### 엔드포인트 `POST /mcp`

MCP Streamable HTTP 중 필요한 부분만 직접 구현했다(`Shared/MCP/`, 외부 패키지 없음).

- **POST만.** 본문은 JSON-RPC 2.0 메시지 하나 또는 배치(배열). 요청이 있으면 `200 application/json`(배치면 응답 배열, 알림은 빼고), 알림·클라이언트 응답뿐이면 `202` 본문 없음. SSE는 쓰지 않는다. `GET`·`DELETE`는 `405`.
- **`Origin`** 머리가 있고 호스트가 `localhost`·`127.0.0.1`·`[::1]`이 아니면 `403`(DNS 리바인딩 방어). 서버는 루프백에만 묶여 있다(6장).
- **프로토콜 버전**: 초기화 방식(legacy) `2025-11-25`·`2025-06-18`·`2025-03-26`. `initialize`는 클라이언트가 보낸 버전이 이 안에 있으면 그대로, 아니면 `2025-11-25`. `MCP-Protocol-Version` 머리가 이 밖의 값이면 **본문 없는 `400`**.
- **`Mcp-Session-Id`**: `initialize` 성공 응답에 UUID를 준다. 이후 요청에서는 검사하지 않는다(없거나 몰라도 받는다) — 서버가 세션별 상태를 두지 않고, 앱을 다시 켜도 실행 중인 Claude Code 세션이 다시 초기화하지 않고 계속 쓰게.
- 메서드: `initialize`, `notifications/initialized`(202), `ping`, `tools/list`, `tools/call`. 그 밖은 `-32601`. 깨진 JSON은 `400` + `-32700`(`id: null`), 형식이 틀린 메시지·빈 배치는 `-32600`, 모르는 도구 이름은 `-32602`.
- 도구 결과: `content: [{type: "text", text: <JSON 문자열>}]`, `isError`. 도구가 실패하면(카드 없음, 규칙 위반 등) `isError: true`와 `{"error": "<이유>"}`, 그 호출의 변경은 되돌린다. 성공하면 바로 저장한다.

### 실측 (2026-09-28, Claude Code 2.1.283)

- 연결할 때 먼저 **새 방식(2026-07-28, 세션 없는 방식)** 으로 떠본다: `POST /mcp`, 머리 `mcp-protocol-version: 2026-07-28`, `mcp-method: server/discover`, 본문 `server/discover`(`params._meta`에 버전·클라이언트 정보). 본문 없는 `400`을 받으면 `initialize`(`protocolVersion: "2025-11-25"`, 머리에 버전 없음)로 내려온다. 원문은 `Tests/Fixtures/mcp/real-*.json`. 그래서 모르는 버전 머리에는 JSON-RPC 오류를 싣지 않는다(새 방식 오류 본문이면 새 방식 서버로 보고 내려오지 않는다).
- `initialize`에도 실패하면 옛 HTTP+SSE로 `GET /mcp`를 한다(`405`면 연결 실패).
- 요청은 `Connection: keep-alive`로 오지만 서버는 응답마다 닫는다. 문제없이 이어졌다.
- `--allowedTools 'mcp__waypoint__*'`로 도구 8개가 모두 허용됐다(당시 개수. 지금은 아래 표 11개). 도구는 지연 로딩되어 Claude가 `ToolSearch`로 불러 쓴다.
- 스킬은 `~/.claude/skills/tracker/SKILL.md`에서 `-p` 세션에도 불렸다(주입 블록 + 「PRB-1 하자」에 `Skill(tracker)`가 먼저 호출됨).

### 도구

`project`는 키(대소문자 무시) 또는 폴더 경로(가장 가까운 상위 `rootPath`). `id`는 `PRB-1` 꼴 표시 ID. 모든 스키마는 `additionalProperties: false`.

| 도구 | 입력(필수 굵게) | 동작 |
|---|---|---|
| `project_resolve` | **`cwd`** | 폴더 → `{key, name, summary, rootPath}`, 없으면 `null`(오류 아님) |
| `project_init` | **`cwd`**, **`name`**, `key`, `summary`, `stack`, `guideFiles`, `seedCards` | 앱에 등록 확인 창을 띄우고 바로 `pending`으로 답한다(아래 「project_init」) |
| `card_list` | **`project`**, `status`, `query` | status를 안 주면 done·archived를 뺀다. 순서: active → next → idea → done → archived, 같은 상태는 번호순. `query`는 ID·제목·본문 부분 일치 |
| `card_get` | **`id`** | 카드 + `body`, `origin`, `nextSessionNote`, `children`, 최근 기록 20개 |
| `card_create` | **`project`**, **`title`**, `kind`, `status`, `body`, `parentId`, `criteria`, `sessionId` | origin=claude, `originSessionId`=`sessionId`. 기본 kind task, status next(kind idea면 idea). `active`는 거부(만든 뒤 `card_start`). `parentId`는 같은 프로젝트. `card.created` 기록 |
| `card_start` | **`id`**, **`sessionId`** | 세션이 없거나 끝났거나 프로젝트가 다르면 오류. 그 세션에 붙은 **다른** 카드 연결을 먼저 푼다(주제 전환 — 그 카드는 작업 전 상태로, done 아님). 그다음 연결 → 작업중. 같은 카드를 다시 부르면 아무 일 없음. 서브에이전트 세션 ID(`agent_id`)면 그 하위 세션에 붙인다. 결과: `card`, `detached`(풀린 카드 ID), `otherSessions`(같은 카드에 붙은 다른 살아 있는 세션) |
| `card_update` | **`id`**, `title`, `body`, `status`, `criteria` | `status: active`는 거부(작업중은 `card_start`로만). 다른 상태는 `CardLifecycle.move`(done이면 `doneAt`, active였으면 열린 세션 연결을 모두 닫는다 — 4장 불변식). `criteria`는 통째로 바꾼다 |
| `card_note` | **`id`**, **`text`** | `note` 기록 `{text}` |
| `card_handoff` | **`id`**, **`nextSessionNote`** | `nextSessionNote` 저장 + `note` 기록 `{kind: "handoff", text}` |
| `card_evidence` | **`id`**, `criterion`, **`command`**, **`outcome`**, `detail`, `sessionId` | 에이전트 보고 근거 `check`(`source: agent`). `criterion`은 **1부터**(card_get `criteria` 순서, 저장은 0부터 + 조건 글), 빼면 카드 수준. 범위 밖·조건 없는 카드에 번호·정수 아님은 오류. `outcome`은 `pass`·`fail`·`skipped`(일부러 건너뛴 경우만). `detail` 200자. 결과 `{id, outcome, source, criterion?, state?, confirmed?}`(`confirmed`: 훅 기록과 짝지어져 「확인됨」인지) |

`criteria`는 `[{text, done?}]`(문자열 항목도 받는다). `status: done`은 스킬이 사용자 확인을 받은 뒤에만 보낸다. 카드 결과는 `{id, title, kind, status, criteria, updatedAt, parentId?, sessions?}`(`sessions`는 붙어 있는 끝나지 않은 세션).

`sessionId`는 `SessionStart` 훅이 주입한 블록의 `sessionId:` 줄에서 Claude가 읽어 전달한다.

### project_init

`/tracker init`에서만 부른다. 도구는 사용자의 확인을 기다리지 않는다.

- 검사(실패하면 `isError`, 초안을 만들지 않는다): `cwd`가 절대 경로이고 있는 폴더일 것. 이미 등록된 폴더(하위 폴더 포함, `project_resolve`와 같은 매칭)면 `이미 등록된 폴더: <키> (…)`. 같은 폴더를 보관된 프로젝트가 쓰면 `보관된 프로젝트 <키>…`(보관 해제 안내). `name`이 비었으면 오류. `seedCards`는 최대 8개, 항목은 `{title, status: next|idea(기본 next), kind?: task|idea|bug(기본 status가 idea면 idea, 아니면 task), body?}`.
- `guideFiles`: 상대(cwd 기준)·절대 경로를 받아 cwd 아래 실제 `.md`·`.txt` 파일만 상대 경로로 남긴다(중복 제거, 심볼릭 링크는 풀어서 비교). 나머지는 결과 `missingGuideFiles`.
- `key`: 대문자로 바꾼다. 규칙에 안 맞거나 다른 프로젝트가 쓰면 그대로 초안에 두고 결과 `warnings`에 알린다(추천 키 예시 포함) — 사용자가 창에서 고쳐야 등록된다. 안 주면 추천 키.
- 통과하면 앱 메모리의 초안 목록에 넣는다(같은 폴더 초안이 있으면 그 자리에서 바꾼다. 저장소에는 넣지 않고 앱을 끄면 사라진다). 앱은 「새 프로젝트 등록」 창을 앞으로 띄운다.
- 결과: `{status: "pending", message: "Waypoint 앱에서 확인하고 등록해 주세요.", draft: {rootPath, name, key, guideFiles, seedCards(개수)}, replacedDraft, missingGuideFiles?, warnings?}`.

확인 창(`macOS/Init/`, 시안 `Init.dc.html` 본문 구조): 경로(모노), 이름·카드 키(입력하는 대로 대문자, 규칙 위반은 「A–Z 2–5자」, 중복은 「사용 중」을 필드 위에 보이고 「등록」을 막는다)·개요, 스택 칩(빼기·추가), 지침 문서·초기 카드 체크 목록(기본 전부 체크, 카드는 다음·아이디어 표시), 「취소」「등록」. 메인 창과 따로 뜨는 창이라 메인 창이 닫혀 있거나 메뉴 막대만 있어도 보인다. 초안이 여럿이면 먼저 온 것부터 하나씩, 창을 닫으면 지금 초안을 취소한다.

등록(`ProjectRegistry.register`)은 한 번에 저장한다: 규칙 재검사(이름, 키, 폴더 존재·중복) → `Project`(`rootPath` 표준 절대 경로, `createdAt`) → 고른 지침 파일을 8장과 같은 등록(`GuideVersion(local)`, `guide.synced`) → 고른 카드(origin claude, `card.created` `{origin, status}`) → 저장. 중간에 실패하면(지침 파일이 그사이 사라짐 등) 아무것도 남기지 않고 창에 이유를 보인다. 등록 뒤 메인 창(없으면 연다) 사이드바에서 새 프로젝트를 고른다. 그 폴더에서 이미 돌던 세션은 다음 훅부터 잡힌다(지난 기록은 가져오지 않는다).

### M5 완료 조건 실측 (2026-09-28, `~/workspace/waypoint-init-probe`, `claude -p`)

- 새 폴더(README·CLAUDE.md·docs/NOTES.md·`TODO:` 두 줄·커밋 3개)에서 메인 창을 닫고 메뉴 막대만 둔 채 `claude -p "/tracker init"` 한 번(19초, 4턴): 한 번의 `Bash`로 문서·`git log`·TODO를 훑고 → `ToolSearch` → `project_init(cwd, name: notecli, key: NOTE, summary, stack 2, guideFiles [CLAUDE.md, docs/NOTES.md], seedCards 4)` → `Waypoint 앱에서 확인하고 등록해 주세요.` 한 줄로 끝났다.
- 등록 창은 터미널이 앞에 있어도 떴다(앱 활성화는 macOS 14 협조 방식이라 포커스는 터미널에 남고 창만 앞에 보인다). 「등록」 뒤 메인 창이 새로 열려 `notecli`가 골라졌다. 저장소: 프로젝트 NOTE, `GuideDoc` 2개(버전 local), 카드 NOTE-1~4(origin claude, next 2·idea 2), `card.created` 4·`guide.synced` 2.
- 같은 폴더의 `claude -p "hi"`: 주입 블록 `Waypoint: NOTE (notecli)` + 다음 할 일 NOTE-1·2, Claude가 그 두 카드를 먼저 물었다.
- 보관하자 사이드바·대시보드에서 빠지고 「보관됨 1」에만 보였고, 그 폴더의 `SessionStart`는 `200` 빈 본문, 세션을 만들지 않았다. 보관 해제로 돌아왔다. 따로 등록한 프로젝트를 고른 채 「삭제…」 → 「‘삭제 실측’ 삭제 / 카드 3개와 기록이 함께 삭제됩니다.」 → 삭제: 대시보드로 옮겨졌고 남은 카드·문서·버전·이벤트 0, 로컬 파일은 그대로.

### 완료 조건 실측 (2026-09-28, `~/workspace/waypoint-probe`, `claude -p`)

- 「PRB-1 하자 … 나중에 CSV 내보내기도 … 마무리해줘」 한 번에: `Skill(tracker)` → `card_start(PRB-1)` → `card_create(kind idea, status idea)` → 작업 → `card_handoff(PRB-1)`. PRB-1은 17초 동안 active, `SessionEnd` 뒤 next로 돌아갔다(done 아님). PRB-2 「CSV 내보내기」 idea 생성.
- 다음 새 세션의 주입 블록에 `직전 세션 메모 (PRB-1 실측용 카드):`와 그 메모가 들어갔다.
- 서브에이전트: 스킬이 `card_create(parentId: PRB-1)`로 PRB-3을 만들고 프롬프트 첫 줄 `[PRB-3] …`로 `Agent`를 불렀다. 훅이 하위 세션(`general-purpose`)을 PRB-3에 붙여 PRB-3이 45초 동안 작업중, 대시보드에 PRB-1 아래 들여 쓴 줄로 보였다. 끝나자 next로 돌아갔다.

## 8. 지침 문서 동기화

- 등록: 프로젝트 화면의 「지침 문서」에서 폴더 바로 아래·`docs/` 바로 아래의 `.md`와 `.claude/CLAUDE.md`를 후보로 보이고, 「파일 추가…」로 프로젝트 폴더 아래 `.md`·`.txt`를 고른다(폴더 밖은 거부, 심볼릭 링크는 풀어서 비교). 등록하면 파일 내용으로 `GuideDoc`, `GuideVersion(local)`, `guide.synced`(payload `relPath`, `source`). init(M5)도 같은 등록을 쓴다.
- 등록 해제는 기록만 지운다(버전 포함). 파일은 그대로.
- 판정은 내용 해시(SHA-256)만 본다. `GuideSync.decide(저장 내용·해시, draft, 이전 파일 없음, 디스크 상태)`:

| 디스크 | draft | 결과 |
|---|---|---|
| 해시 == 저장 해시 | 무엇이든 | 아무것도 안 함(앱 자신의 쓰기 포함). 파일 없음 표시였으면 풀기만 |
| 바뀜 | 없음, 또는 저장 내용과 같음, 또는 디스크 내용과 같음 | 로컬 내용 반영, draft 버림, `GuideVersion(local)`, `guide.synced`(local) |
| 바뀜 | 저장 내용·디스크 내용과 모두 다름 | **충돌**: 자동 병합하지 않고 로컬 내용을 `conflictContent`에 들고 비교 화면 |
| 없음 | 무엇이든 | 「파일 없음」 표시(등록 유지). 다시 생기면 위 표대로 |

- 로컬 변경 감지: 등록 문서들의 부모 폴더를 FSEvents(파일 단위 이벤트)로 감시하고 0.4초 디바운스 뒤 모든 등록 문서를 다시 판정한다. 앱 시작 때와 감시 폴더가 바뀔 때(등록·해제)도 전부 판정한다 — 앱이 꺼진 동안의 변경은 시작할 때 반영된다.
- 앱 편집: 원문 텍스트 편집. 저장하지 않은 편집은 `draft`로 남아 화면을 떠나도 유지된다(`content`와 같아지면 nil). 저장(⌘S)은 먼저 디스크 해시를 저장 해시와 비교해, 다르면 쓰지 않고 충돌로 멈춘다. 같거나 파일이 없으면 같은 폴더의 임시 파일에 쓰고 `rename`으로 바꿔 끼운 뒤(권한 유지), 같은 메인 스레드 블록에서 `content`·해시·`lastSyncedAt`을 갱신하고 `GuideVersion(app)`, `guide.synced`(app)를 남긴다.
- 충돌 비교 화면: 왼쪽 「로컬 파일」, 오른쪽 「앱에서 편집한 내용」, 한쪽에만 있는 줄에 배경(줄 단위 LCS). 「로컬 파일로」는 draft를 버리고 지금 파일 내용을 반영(local), 「앱 내용으로」는 draft를 파일에 쓴다(app). 어느 쪽을 골라도 읽기 화면으로 돌아간다.
- 버전 기록: 문서당 최근 50개만 남긴다(넘으면 오래된 것부터 삭제). 시각은 초까지(「15:12:16」) 보인다. 버전을 열어 원문을 보고 「이 버전으로 되돌리기」하면 그 내용을 앱 저장과 같은 규칙으로 쓴다(버전 app, 충돌 규칙 동일, 저장 안 한 편집은 그 내용으로 바뀐다).
- 비샌드박스 앱이라 security-scoped bookmark는 쓰지 않는다(샌드박스로 바꾸면 필요).
- 렌더링: 직접 만든 블록 파서(`MarkdownParser`) — 제목 `#`~`######`(화면은 3단계까지 구분), 문단(이어진 줄은 공백으로), 목록(`-`·`*`·`+`·`1.`·`1)`, 들여쓰기 단계, 체크박스), 울타리 코드 블록, 파이프 표(정렬 줄 필수), 인용, 구분선. 인라인(굵게·기울임·코드·링크)은 `AttributedString(markdown:, .inlineOnlyPreservingWhitespace)`. 목차는 제목 1~3단계.

## 9. 사용량 게이지

Claude·Codex 사용량(한도별 사용 비율과 초기화 시각)을 사이드바 아래와 메뉴 막대 메뉴에 도구별로 보인다. 앱은 파일만 읽고 API·네트워크를 쓰지 않는다.

### Claude


- 출처: Claude Code가 상태줄 명령 stdin에 넘기는 JSON의 `rate_limits.five_hour` / `rate_limits.seven_day`(`used_percentage` 0–100, `resets_at` 유닉스 초). 사용자의 상태줄 명령 앞에 중계 스크립트 `integration/statusline/waypoint-statusline-tap.sh`를 끼운다. 스크립트는 입력에 `rate_limits` 객체가 있으면 저장 폴더에 `usage.json`을 원자적으로 쓰고(임시 파일 → `mv`, jq 필요), 같은 입력을 원래 명령에 넘겨 출력을 그대로 내보낸다. jq가 없거나 쓰기에 실패해도 상태줄 출력은 그대로 나온다. 추가 시간은 약 8 ms.
- 파일: `~/Library/Application Support/Waypoint/usage.json`(`WAYPOINT_SUPPORT_DIR`로 바꿀 수 있음), 한 줄 `{"capturedAt":<unix 초>,"rateLimits":<rate_limits 원본>}`.
- 설치: 스크립트를 `~/.claude/waypoint/`에 복사하고 `chmod +x`, `~/.claude/settings.json`의 `statusLine.command`를 `bash ~/.claude/waypoint/waypoint-statusline-tap.sh <원래 명령>`으로 바꾼다(예: `bash ~/.claude/waypoint/waypoint-statusline-tap.sh bash ~/.claude/awesome-statusline.sh`). 원래 명령은 인자 대신 환경 변수 `WAYPOINT_STATUSLINE_NEXT`(셸 명령 문자열)로 줘도 된다. 되돌리려면 `statusLine.command`를 원래 명령으로 돌린다.
- 앱(macOS): 30초마다 파일 수정 시각을 보고 바뀌었을 때만 다시 읽는다(`UsageMonitor`). 파서는 숫자·숫자 문자열, 초·밀리초·ISO 8601 시각, 한쪽 창만 있는 경우를 받는다.

### Codex

- 출처: Codex가 대화마다 남기는 기록 `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`(`CODEX_HOME`이 있으면 `$CODEX_HOME/sessions`). `type: "event_msg"`, `payload.type: "token_count"` 줄의 `payload.rate_limits`: `{"limit_id":"codex","primary":{"used_percent":12.0,"window_minutes":10080,"resets_at":<unix 초>},"secondary":null|{...},"credits":…,"plan_type":"plus",…}`. 줄 시각은 최상위 `timestamp`(ISO 8601, 소수 초). 2026-10-01 실제 기록에서 확인.
- 한도 기간은 `window_minutes`로 정한다(300 → 5시간, 10080 → 7일, 무료 요금제 43200 → 30일). `primary`/`secondary` 순서는 믿지 않고 짧은 기간부터 보인다. 둘 다 null이면 그 줄은 버린다.
- 같은 파일에 `limit_id`가 `premium`(둘 다 null)·`base_model_inference`(다른 7일 한도)인 줄이 섞여 온다. `limit_id`가 `codex`이거나 없는 줄만 받는다.
- 읽기(`CodexUsage`): 날짜 폴더 이름순으로 최근 7개 폴더의 기록 파일을 수정 시각 최근 순으로 최대 5개 훑는다. 폴더 날짜는 기록한 기기의 날짜이고 오래된 대화를 이어 쓰면 옛 폴더 파일이 가장 최근에 바뀌므로 수정 시각으로 고른다. 파일마다 끝 256KB만 읽어(첫 줄은 잘렸을 수 있어 버리고, 쓰는 중인 마지막 줄은 깨져 있으면 건너뜀) 마지막 Codex 줄을 찾고, 없으면 끝 4MB로 한 번 더, 그래도 없으면 다음 파일로 넘어간다. 기록 시각은 그 줄의 `timestamp`, 없으면 파일 수정 시각.
- 30초 폴링. 가장 최근 파일과 지난번 값을 준 파일의 수정 시각이 그대로면 다시 읽지 않는다. 기록이 없으면 Codex 묶음을 숨긴다.

### 표시 공통

- 초기화 시각이 지난 한도는 0%로 보인다. 30분보다 오래된 기록은 묶음째 흐리게, 기록이 없는 도구는 묶음째 숨긴다.
- 설정 창(⌘,) 「사용량」의 Claude·Codex 토글(기본 켬, `UserDefaults` `usage.showClaude`·`usage.showCodex`)을 사이드바·메뉴 막대가 함께 따른다. 둘 다 끄면 게이지 영역과 메뉴 줄이 사라진다(파일 읽기는 계속).
- 메뉴 막대: 「사용량 Claude 5시간 42% · 7일 18% / Codex 7일 12%」. 44자를 넘으면 도구마다 한 줄(둘째 줄은 「Codex 5시간 95% · 7일 39%」).
- iOS에는 없다.

## 10. 화면

`docs/DESIGN.md` 참조. 대시보드 / 프로젝트 보드 / 카드 상세 / 지침 문서 / 새 프로젝트 등록 창 / iPhone 작업중.

## 11. 열린 질문 (구현 중 결정)

- 앱 샌드박스 여부 (로컬 서버·파일 감시 편의 vs 배포 방식). 개인용이면 비샌드박스 + 직접 서명도 가능.
- ~~Swift MCP 서버 구현~~ → 필요한 부분만 직접 구현(7장). 새 방식(2026-07-28, 세션 없음)을 지원할지는 Claude Code가 옛 방식을 버릴 때 다시 본다.
- 서브에이전트의 `session_id`가 부모와 같은지 별도인지 — 실제 훅 입력을 로깅해서 확인 후 `Session` 매핑 확정.

## 작업 대상 프로젝트 연결 (2026-09-30)

시작 cwd는 초기 프로젝트 추정값이다. 실제 작업 대상 폴더가 등록되어 있으면 `session_bind(project, sessionId, provider, cwd)`로 연결한다. cwd는 시작 폴더 그대로 유지한다. 미등록 시작 폴더의 SessionStart도 실제 sessionId와 provider를 전달하지만, 대상이 정해지기 전에는 프로젝트나 카드를 만들지 않는다. Codex는 실행 환경의 실제 CODEX_SESSION_ID/CODEX_THREAD_ID를 ID 근거로 사용할 수 있으며 ID를 추측하지 않는다.

프로젝트 전환은 기존 메인 세션의 카드 연결을 풀어 이전 상태로 돌리고, 세션의 현재 프로젝트와 컨텍스트 키를 바꾼다. 이전 카드·이벤트·이미 실행 중인 하위 세션의 프로젝트는 바꾸지 않는다. 종료된 세션·다른 도구의 ID·보관 프로젝트 연결은 거절한다.

PostToolUse 파일 기록은 변경 파일의 가장 가까운 등록 프로젝트로 귀속한다. 현재 카드의 소속과 같을 때만 해당 카드에도 기록한다. 여러 프로젝트를 한 번에 수정해도 파일별로 나누고 임의의 프로젝트를 기본값으로 고르지 않는다. 등록 밖 절대 경로와 보관 프로젝트에는 기록하지 않는다. 명시적 tool_input.workdir/cwd가 있으면 커밋은 그 폴더의 프로젝트에 기록한다. 없으면 훅의 `cwd`(Claude가 `cd`하면 따라 바뀐다 — hooks 문서 「cwd follows Claude」)가 속한 등록 프로젝트에, 등록 밖이면 세션 프로젝트에 기록한다(미등록 상위 폴더에서 시작해 `session_bind`한 경우). 검증 근거도 같다(TRK-11). 세션의 프로젝트와 요청 문장의 소속은 `cwd`가 바뀌어도 그대로다.

### 로컬 연동 상태 (2026-09-30)

macOS 대시보드의 AI 연동 요약과 모든 화면의 툴바 버튼에서 상태 패널을 연다. 사용자 범위 Claude·Codex 훅 설정의 필수 이벤트, 실행 파일·실행 권한, 앱 포트 일치, 훅 비활성화를 점검한다. 프로젝트별 설정과 신뢰 승인은 설정 파일만으로 단정하지 않는다. 설치만 되어 있으면 「첫 수신 대기」, 실제 훅을 받았으면 「수신 확인」으로 구분한다. 활동 공백은 장애로 취급하지 않는다.

패널에는 마지막 훅 활동·실제 수신 시각·수신 당시 프로젝트, 현재 연결된 프로젝트, MCP 마지막 요청, 미처리 outbox 수와 읽기·처리 오류, 원인에 맞는 복구 안내를 표시한다. 미등록 폴더 수신은 프로젝트 미연결로 표시한다. 10초 점검·활성화·잠자기 복귀·다시 점검 때 설정과 대기 기록을 갱신한다. 「다시 점검」은 실패한 로컬 서버의 시작도 재시도한다.

수신 이력은 이 기기의 저장 폴더 `integration-health.json`에만 남고 CloudKit 모델을 변경하지 않는다. 사용자 대화·파일 경로·세션 ID·설정 원문은 저장하지 않는다. 지연 재수신은 원래 활동 시각으로 비교해 더 최신 상태를 덮어쓰지 않는다. 누락 기록은 활동과 실제 재수신 시각을 따로 표시한다. `/integration/status`는 루프백 서버의 읽기 전용 진단 정보다.

### 기록 지표와 진단 내보내기 (2026-10-01, TRK-11)

이 기기에서만 숫자와 시각을 모은다(`ReliabilityMetrics`, 저장 폴더 `metrics.json` 0600, 10초 점검 때 저장, CloudKit 아님): 실시간 훅의 수신(서버가 연결을 받은 시각)→저장·화면 반영 지연 최근 1000건, 재개 시간(재개 문맥을 처음 복사한 시각 → 그 카드에 같은 도구의 새 메인 세션이 연결된 시각, 최근 100건), 연동 실패(서버 시작·형식 오류·저장 실패), 복구(outbox 흡수·보존·격리, 세션 정리) 횟수. 연동 상태 패널에 짧게 보이고, 「진단 정보 복사」를 누를 때만 같은 숫자를 내보낸다. 프로젝트명·경로·세션 ID·대화는 담지 않는다. `/integration/status`가 `metrics`로 돌려준다. 기준·측정 방법·관측값은 docs/RELIABILITY.md.

### 이벤트 기반 작업 상태 (2026-09-30)

`Session.activityRaw`, `activityAt`, `pendingToolsData`, `endReason`를 추가한다. 기존 stateRaw 캐시와 live/stalled/ended API는 호환을 유지한다. 이전 세션은 마지막 활동만 아는 경우 「최근 활동」 또는 「활동 없음」으로 표시한다.

- SessionStart/Stop/Interrupt → 입력 대기, UserPromptSubmit → 응답 진행 중. 응답 진행이 15분 넘게 갱신되지 않으면 활동 없음.
- PreToolUse → 도구 작업 중(tool_use_id별 목록), PermissionRequest → 승인 대기. 질문 도구 AskUserQuestion/request_user_input → 입력 대기.
- PostToolUse → 해당 도구 종료. Claude의 PostToolUseFailure도 종료한다. Codex는 공식 지원 이벤트만 설치한다. 다른 병렬 호출이 남아 있으면 도구 작업 중을 유지한다. 늦은 완료는 해당 호출만 제거하고 최신 시각을 되돌리지 않는다.
- 진행 중인 하위 작업이 있으면 부모도 작업 중으로 표시한다. 전체 프로세스 종료가 확인되면 세션 종료, PID 없는 활동 유효기간이 끝나면 추적 만료다. 둘 다 카드를 자동 완료하지 않는다. 카드 연결 해제 기록에 종료 이유를 보존해 재개 후에도 과거 추적 만료 표시는 바뀌지 않는다.
- 입력·승인 대기는 작업 실패를 뜻하지 않는다. PID가 없는 세션의 30분 추적 유효기간은 그대로 적용한다.

훅은 관찰만 하며 승인 허용/거절 결정을 출력하지 않는다. Claude·Codex 공식 훅 문서를 확인하여 tool_use_id·PermissionRequest와 전체 matcher를 사용한다. Codex 훅 정의를 바꾸면 /hooks에서 재신뢰가 필요하다.
