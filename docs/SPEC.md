# Waypoint 명세

## 1. 문제와 목표

여러 프로젝트를 Claude Code·Codex로 동시에 진행하면 다음이 뒤섞인다.

- 지금 어떤 작업이 돌고 있는지 (세션·서브에이전트 여러 개)
- 이전에 무엇을 했는지 (히스토리)
- 나중에 하려던 것이 무엇인지 (아이디어, 다음 할 일)

Waypoint는 이것을 **프로젝트 단위의 카드 보드**로 보여 주는 개인용 추적기다. 세션 안의 **훅(결정적 기록)** 과 **스킬(판단이 필요한 기록, MCP 도구 호출)** 이 자동으로 채운다.

### 하지 않는 것

- LLM API 호출, LLM 기반 요약·추천. 앱은 순수 추적기다.
- 과거 히스토리 가져오기. 프로젝트는 등록 시점부터 기록한다.
- 다중 사용자·팀 기능.

## 2. 용어

| 용어 | 뜻 |
|---|---|
| 프로젝트 | 로컬 폴더 하나(`rootPath`)에 대응. 카드 키(예: `LDG`)를 가진다 |
| 카드 | `LDG-14` 형식 ID를 가진 작업 단위 |
| 세션 | Claude Code·Codex 세션 1개(`session_id`). 서브에이전트는 부모 세션의 하위 세션 |
| 작업중 | 카드에 살아 있는(live) 세션이 붙어 있는 상태 |
| 활동 없음 | 응답 진행 또는 이전 버전 세션에서 15분간 새 활동이 없는 상태. 실패를 뜻하지 않는다 |

## 3. 아키텍처

```
Claude Code·Codex 세션 ──훅(command)──▶ waypoint-hook.sh ──HTTP──▶ ┐
        │                                                          │  Waypoint.app (macOS)
        └──스킬이 MCP 도구 호출──────────────────────────────────▶ ┤  - 로컬 서버 127.0.0.1:47821
                                                                   │    · /hooks/*  (훅 수신)
   앱이 꺼져 있으면 훅은 outbox.jsonl에 적재 ──(앱 실행 시 흡수)─▶ │    · /mcp      (MCP, Streamable HTTP)
                                                                   │  - SwiftData 저장소
                                                                   │  - 지침 파일 감시 (FSEvents)
                                                                   └──▶ CloudKit ──▶ iOS 앱 (읽기 위주)
```

- **Mac 앱이 서버를 겸한다.** 메뉴 막대 상주 모드가 있어 창을 닫아도 서버는 돈다.
- **훅은 curl만 쓴다.** 앱이 꺼져 있거나 응답이 없으면 `~/Library/Application Support/Waypoint/outbox.jsonl`에 한 줄씩 적재한다. 훅은 Claude Code를 막거나 느리게 하지 않는다(타임아웃 1초, 항상 exit 0).
- **MCP 서버**는 앱 내장 Streamable HTTP 엔드포인트다. 사용자 범위로 한 번 등록한다: `claude mcp add --transport http --scope user waypoint http://127.0.0.1:47821/mcp`(`~/.claude.json`의 사용자 범위에 적힌다).
- iOS는 CloudKit 동기화로 같은 데이터를 본다. 로컬 서버·훅·MCP·지침 동기화는 macOS에만 있다. iOS에서 쓰는 것은 아이디어 분류(다음 할 일로 / 보관)뿐이다.
- **인스턴스 두 개**: 평소용(Release, `dev.antaeho.waypoint`, 47821, `~/Library/Application Support/Waypoint/`)과 개발용 Waypoint Dev(Debug, `dev.antaeho.waypoint.dev`, 47822, `…/Waypoint-Dev/`). 번들 ID로 가르고(`AppInstance`), 환경 변수 `WAYPOINT_PORT`·`WAYPOINT_SUPPORT_DIR`가 있으면 그 값이 먼저다. 훅·MCP 전역 설정은 평소용만 가리키고, 실측 폴더만 프로젝트 설정으로 Dev에 잇는다(`docs/DEVELOPMENT.md`).

### CloudKit 구성

- SwiftData `ModelConfiguration(cloudKitDatabase: .private(<컨테이너>))`. 개인 DB 하나, 공유 없음.
- 컨테이너: 평소용 `iCloud.dev.antaeho.waypoint`, 개발용 `iCloud.dev.antaeho.waypoint.dev`(`AppInstance.cloudKitContainerIdentifier`, 엔타이틀먼트는 build setting `WAYPOINT_CONTAINER`).
- 환경: 개발 서명 빌드는 Development. Developer ID 배포 빌드(`scripts/release-mac.sh`)는 Production이고, Production 스키마를 배포하기 전까지 iCloud를 끈다(`docs/RELEASE.md`).
- 끄기(`AppInstance.cloudKitContainer`가 nil): Info.plist `WaypointICloud`가 `NO`(macOS build setting `WAYPOINT_ICLOUD`, 기본 `YES`), `WAYPOINT_CLOUDKIT=0`, 또는 `WAYPOINT_SUPPORT_DIR`로 저장 폴더를 옮긴 실행. 빌드 스위치가 `NO`면 환경 변수로 켤 수 없다. 꺼지면 설정 「기록」 탭에 「이 Mac · iCloud 꺼짐」. 샘플 모드와 테스트는 늘 로컬.
- 푸시: iOS `aps-environment`·백그라운드 모드 `remote-notification`, macOS `com.apple.developer.aps-environment`. iOS는 원격 알림을 직접 등록한다(`PhoneAppDelegate`, 안 하면 Mac 변경이 앱을 다시 열 때까지 오지 않는다).
- iOS 화면은 가져오기가 끝날 때마다 새 `ModelContext`로 다시 읽는다. Mac은 가져오기 뒤 새 context로 읽은 카드의 늦은 값을 메인 context의 같은 카드에 옮겨 적는다(`RemoteCardMerge`, iPhone에서 옮긴 상태를 되돌리지 않게). iPhone이 고치는 것은 카드뿐이다.

## 4. 데이터 모델 (SwiftData)

```swift
Project      id, key(2–5 대문자), name, summary, rootPath, stack:[String],
             nextCardNumber:Int, createdAt, archivedAt?, lastEventAt?

Card         id, project, number:Int, title, body(markdown),
             kind: task | idea | bug,
             status: idea | next | active | done | archived,
             parent: Card?, criteria:[Criterion],
             origin: claude | codex | manual, originSessionId?,
             nextSessionNote?, statusBeforeActive?, createdAt, updatedAt, doneAt?

Criterion    text, isDone

Session      id(Claude는 session_id, Codex는 "codex:<session_id>"), provider: claude | codex,
             project, kind: main | subagent, parent: Session?, agentName?, cwd, gitBranch?,
             startedAt, lastSeenAt, endedAt?, endReason?,
             claudePid:Int?, processPid:Int?,     // 메인 세션만. Claude / Codex 프로세스 PID
             contextProjectKey?,                  // Waypoint 블록을 준 프로젝트 키(5장 「늦은 주입」)
             contextPendingKey?, contextPendingID?, contextPendingCount:Int,  // 5장 「수신 확인」
             lastPrompt?, lastPromptAt?,          // 메인 세션의 마지막 요청 문장(5장 「마지막 요청 문장」)
             state: live | stalled | ended,       // 파생값, 저장 캐시
             activityRaw, activityAt?, pendingToolsData?   // 이벤트 기반 작업 상태(5장 「작업 상태」)

CardSession  card, session, attachedAt, detachedAt?

Event        id, project, card?, session?, at,
             type: session.start | session.end | card.created | card.status |
                   card.attached | card.detached | file.changed | commit |
                   note | guide.synced | check | project.status | session.filed |
                   github.issue | github.pr,
             payload: JSON(Data)

GuideDoc     id, project, relPath, content, contentHash(SHA-256), lastSyncedAt,
             draft?, isMissing, conflictContent?     // 저장 안 한 편집, 파일 없음, 충돌 때 읽은 로컬 내용
GuideVersion doc, content, at, source: app | local
```

- **키**: `^[A-Z]{2,5}$`. 보관된 것까지 포함해 다른 프로젝트 키와 겹치지 않는다. 같은 폴더(`rootPath`를 `~` 펼치고 표준화해 비교)를 쓰는 프로젝트는 보관 포함 하나뿐. 규칙은 `ProjectKey`·`ProjectRegistry`.
- **추천 키**(`ProjectKey.suggest`): 이름의 영문 단어가 둘 이상이면 머리글자 2–4자(`Waypoint Init Probe` → `WIP`), 그다음 첫 단어의 첫 글자 + 자음 둘(`ledger` → `LDG`), 첫 단어 앞 3자. 영문이 없으면 폴더 이름으로 같은 순서, 그래도 없으면 `PRJ`. 모두 쓰이면 후보 앞 4자 + `A`–`Z`.
- **보관**(`archivedAt`): 사이드바·대시보드·메뉴 막대·최근 기록에서 숨기고 사이드바 맨 아래 「보관됨」 접힘 구역에만 보인다. 그 폴더의 훅은 기록하지 않는다(5장). 「보관 해제」로 되돌린다.
- **삭제**: 확인 알림(이름, 카드 수) 뒤 카드·세션·연결·이벤트·지침 문서(버전 포함)가 함께 지워진다(cascade). 로컬 파일은 건드리지 않는다.
- **CloudKit 호환**: `@Attribute(.unique)`를 쓰지 않고 키·ID 중복은 코드에서 막는다. 모든 속성은 기본값이 있거나 옵셔널, 관계는 옵셔널이고 역관계를 둔다. enum은 원시 문자열로 저장한다.
- **새 이벤트 종류**는 `typeRaw` 문자열 값이라 저장 형식(스키마 판)이 그대로다. 옛 앱은 모르는 종류를 `note`로 읽고 `text` 없는 메모를 숨기므로, `note`가 아닌 새 종류의 payload에는 `text` 키를 두지 않는다.

### 검증 근거 (`check` 이벤트)

카드 완료 조건별로 실행한 검증 명령과 결과를 잇는다.

- payload(`CheckRecord`): `command`(변수 대입 값은 `…`로 가림, 300자), `outcome`(`pass`·`fail`·`skipped`·`unknown`), `source`(`hook` = 훅이 실행을 직접 봄, 화면 「확인됨」 / `agent` = 에이전트 보고, 화면 「보고」), `criterion`(0부터, 에이전트 보고만), `criterionText`(보고 때 조건 글), `detail`(200자), `exitCode`, `provider`, `toolUseId`(훅, 재수신 중복 방지).
- 이벤트는 카드와 실행한 세션에 붙는다. 근거를 남기는 것은 훅(5장 「검증 근거」)과 `card_evidence`(7장)뿐이다.

### 완료 조건 근거 상태 (`CardEvidence`, 순수 함수)

- 조건마다 통과·실패·건너뜀·미검증 + 출처·시각·명령. 근거가 없으면 미검증. 완료 조건이 없는 카드는 표시하지 않는다.
- 기준은 그 조건의 가장 최근 에이전트 보고다. 보고 때 조건 글(`criterionText`)이 지금 글과 다르면 근거가 아니다.
- 훅 기록과 짝짓기: 명령을 검증 조각으로 다듬어(리다이렉션·앞 변수 대입 제거, 공백 정리) 보고의 조각이 모두 훅 기록에 있고, 훅 기록이 보고 15분 전 이후이며 `pass`·`fail`이면 짝이다. 가장 최근 짝이 상태를 정하고 출처는 「확인됨」이다(보고가 통과라도 훅이 실패를 봤으면 실패).
- 「변경 후 미검증」: 근거 시각 뒤에 그 카드의 `file.changed`가 있을 때(같은 도구 호출은 제외, 커밋은 보지 않는다, 건너뜀은 해당 없음).
- 세션 종료·연결 해제·체크 상자는 근거를 바꾸지 않는다. 체크 상자는 사용자 판단으로 따로 보인다. 카드를 자동으로 done 처리하지 않는다.
- 조건 번호 없는 훅 기록은 카드 수준 「검증 기록」에만 보인다.

### 지금 상황·정리 안 된 작업 (`project.status`·`session.filed`)

- `project.status`: 프로젝트(필수)·세션(있으면)에 붙는다. payload `summary`(지금 상황 글), `provider`, `sessionId`(있으면). **가장 최근 것이 지금 상황**이다. 7일(`ProjectStatus.staleAfter`)보다 오래되면 「오래됨」. 활동 탭에 「지금 상황」으로 보인다.
- `session.filed`: 정리 안 된 작업 처리. 프로젝트·세션에, 연결이면 카드에도 붙는다. payload `sessionId`, `outcome`(`filed` 카드에 이음 · `dismissed` 넘김), 연결 때만 `cardId`·`files`(경로 수)·`moved`(옮긴 이벤트 수). 카드 기록에 「이전 세션 작업 연결 · 파일 N개」.
- **정리 안 된 작업**(`UnfiledWork`): 이 프로젝트의 메인 세션 중 끝났고 마지막 활동(`lastSeenAt`)이 최근 14일이며, 세션·서브에이전트가 카드에 붙은 적이 한 번도 없고(`CardSession` 없음, 풀린 것 포함), 최근 14일 안에 이 프로젝트에 카드 없는 `file.changed`를 1개 이상 남겼고(서브에이전트 것 포함), `session.filed`가 아직 없는 것. 최근 것부터.
- 연결(`work_file`에 카드): 그 세션·서브에이전트의 카드 없는 `file.changed`·`commit`·`check` 중 이 프로젝트 것을 그 카드로 옮긴다(`Event.card`만 바꾼다). 카드 상태·`updatedAt`·`CardSession`은 그대로라 작업중 판정과 상태 복귀에 영향이 없다. 옮긴 파일 변경이 그 카드 근거보다 늦으면 「변경 후 미검증」이 될 수 있다.

### 파생 규칙

- 카드가 **작업중** = 열린 `CardSession` 중 세션 `state == live`인 것이 1개 이상.
- 표시 상태는 `SessionActivityRules`로 판정한다(5장 「작업 상태」). `live`/`stalled`/`ended`는 호환용 묶음이고, `stalled`는 입력·승인 대기와 활동 없음이다. 입력 대기와 실행 중인 도구는 15분이 지나도 다른 상태로 덮지 않는다.
- 마지막 live 세션이 떨어지면 카드 `status`는 작업 시작 전 상태(`statusBeforeActive`)로 돌아간다. **자동으로 done이 되지 않는다.** 완료는 스킬이 사용자 확인 후 `card_update(status: done)` 하거나 사용자가 앱에서 옮긴다.
- **불변식: 열린 연결이 있으면 카드는 `active`다.** 카드가 active를 떠나면(앱 드래그·「완료로 옮기기」·iPhone 분류·`card_update(status)`, 모두 `CardLifecycle.move`) 그 카드의 열린 연결을 서브에이전트 것까지 닫고 세션마다 `card.detached`(`reason: "card-moved"`)를 남긴다. 상태는 새로 정한 그대로 둔다.
- 어긋난 연결 점검: 앱 시작 직후, 10초마다, CloudKit 가져오기 뒤에 active가 아닌 카드의 열린 연결을 닫는다(`CardLifecycle.closeStrayLinks`, `reason: "status-not-active"`). iPhone에서 옮긴 카드(연결은 병합하지 않는다)를 위한 것이다.
- 대시보드 "작업중" 목록 = 프로젝트별 (세션, 카드) 쌍 + 카드가 붙지 않은 끝나지 않은 메인 세션 한 줄씩(제목 자리에 `lastPrompt`, 없으면 「카드 없음」. 최근 파일은 그 세션과 서브에이전트가 카드 없이 남긴 `file.changed`). 카드 없는 서브에이전트는 줄을 만들지 않는다. 「작업 N개」는 live 줄 수, 사이드바의 작업중·멈춤 수는 카드 수 + 카드 없는 메인 세션 수.
- 프로젝트 보드 작업중 칸 = 작업중 카드 + 카드 없는 세션 타일(`BoardQuery.sessionTiles`, 끌거나 누를 수 없다). 칸 머리 개수는 카드 + 타일.
- 활동 표시(`SessionFormat.activityText`): 도구 작업·응답 진행·입력 대기·승인 대기·활동 없음. 대기는 전환 시각, 활동 없음은 마지막 활동 시각부터 경과.
- **내 답 기다림**(`SessionWaiting.kind`): 승인 대기, 또는 질문 도구(`SessionActivityRules.questionTools`)가 떠 있는 입력 대기. 턴이 끝나 쉬는 입력 대기는 들지 않는다.
  - 대시보드: 그 줄(`DashboardRow.waitingKind`)은 `workState`가 stalled이고, 집계(`DashboardOverview.split`)에서 「내 답 기다림」(`waitingCount`)에 들고 「대기·활동 없음」(`stalledCount`)에서 빠진다. 줄 글은 「승인 대기 3분」·「질문 대기 3분」.
  - 카드 없는 서브에이전트의 기다림은 부모 세션의 첫 줄에 올린다(`SessionWaiting.shown`): 「승인 대기 3분 · test-writer」, 여럿이면 가장 오래 기다린 것. 기다림이 든 줄은 세션이 live여도 stalled로 둔다.
  - 보드 타일·작업중 카드·카드 인스펙터도 같은 글(`waitingText`)을 보인다. 메뉴 막대(`SessionFormat.menuLine`)는 「승인 대기 N」「질문 대기 N」을 따로 세고 「입력 대기 N」에는 쉬는 세션만 남긴다.
  - 사이드바는 `ProjectSummary.waitingCount`(끝나지 않은 세션 수)가 1 이상이면 그 수가 든 알약을 그린다(`sidebarMark`: 기다림 > 작업중 > 멈춤). 줄 수와 세션 수는 단위가 달라 어긋날 수 있다.
- **활동** 탭: 이벤트의 불변 `project` 연결 기준으로 요청·파일 변경·커밋·완료·인수인계 메모를 시간순으로 보인다. 도구·카드·세션 필터, 같은 파일의 연속 변경은 5분 단위로 묶는다. 처음 최신 300건, 「더 보기」로 늘린다. 검색은 읽은 범위에만.

### 같은 파일 작업 중 (`WorkOverlap`)

같은 프로젝트에서 동시에 도는 작업이 같은 파일을 만지고 있음을 알려 덮어쓰기를 미리 막는다. 화면은 「충돌」이라 쓰지 않는다.

- `file.changed` payload `checkout`: 파일 폴더부터 위로 `.git`(폴더·파일)이 있는 첫 폴더(`GitInfo.checkoutRoot`, git 명령 없음). worktree·하위 모듈은 따로 잡힌다. git 밖이면 없다. `path`는 가장 가까운 등록 프로젝트의 `rootPath` 기준 상대 경로.
- 작업 단위는 메인 세션과 그 서브에이전트. 끝나지 않은 단위 둘 이상이 같은 `checkout`의 같은 `path`를 각자 최근 60분(`WorkOverlap.window`, 경계 포함) 안에 바꿨으면 겹침이다. 단위가 살아 있으면 끝난 서브에이전트의 변경도 센다. `checkout`이 없는 기록은 뺀다.
- 상대 이름은 상대 단위가 붙은 첫 카드 ID, 없으면 세션 표시(`sess·1a2b`, Codex는 `Codex · sess·…`).
- 질의는 이 프로젝트·최근 60분의 `file.changed`만(`WorkOverlap.index`), 대시보드는 프로젝트마다 한 번(`byRow`).
- 화면(`Theme.Overlap`): 진행 작업 타일·카드 인스펙터 「지금 연결된 세션」에 `같은 파일 N개 · PRB-3`(여럿이면 `… 외 1`). 누르면 상대마다 `카드 제목 · 도구 세션`과 파일 12개까지. 상황판 진행 중 줄은 `같은 파일 N`.

### 대시보드 상황판 (`ProjectSituation`)

대시보드 맨 아래 「프로젝트」 구역은 보관하지 않은 프로젝트의 타일 격자다. 값은 모두 에이전트 기록에서 나온다. 집계는 `ProjectSituation.board`(순수 함수).

- 순서: 나를 기다리는 세션이 있는 프로젝트 → 작업 중(live 줄이 있음) → 마지막 활동(`DashboardQuery.lastActivityAt`) 최근순 → 키순.
- 타일 머리: 키·이름, 작업중 점, 마지막 활동 상대 시각. 누르면 프로젝트 보드.
- 나를 기다림: 「승인 기다림 N」「질문 기다림 N」 알약(0이면 뺀다). 끝나지 않은 세션마다 한 번 센다(카드 없는 세션·서브에이전트 포함, 서브에이전트가 기다리면 부모는 세지 않는다). 메인 세션은 저장된 단계(`activityRaw`)로 세되, 그 기다림 뒤에 시작한 끝나지 않은 서브에이전트가 있으면 이미 답한 것으로 본다. 도구 필터를 따르고 검색은 따르지 않는다.
- 지금 상황: 최신 `project.status` 글, 4줄·150자를 넘으면 「더 보기」. 갱신 상대 시각 · 도구. 7일을 넘으면 흐리게 + 「오래됨」.
- 진행 중: 대시보드 작업중 카드 줄을 카드마다 한 줄로 모아 최대 3, 머리에 전체 수. 멈춘 카드는 속 빈 점과 「멈춤 · 도구」.
- 다음: 다음 할 일 카드 번호순(`BoardQuery.columns`) 최대 3.
- 최근 끝냄: 7일(`BoardQuery.doneWindow`, 딱 7일 전은 뺀다) 안에 끝낸 카드 최근순 최대 3.
- 아래 줄: 정리 안 된 작업 수(`UnfiledWork.count`), 아이디어 수, 열린 GitHub 이슈·PR 수(각각 있을 때만).
- 비는 구역은 머리째 숨긴다. 카드 줄을 누르면 카드 상세.
- 검색: 이름·키가 맞거나 맞는 카드(보관 제외)가 있는 프로젝트. 이름·키가 맞으면 타일 그대로, 아니면 맞는 카드만 남긴다.
- 도구 필터(전체/Claude/Codex): 진행 중 줄과 작업중 점만 거른다.
- 다시 계산: 대시보드와 함께(`LiveDataTimeline`, 저장·훅 직후(잦으면 0.5초에 한 번으로 묶는다, `RefreshThrottle`)와 5초마다).

## 5. 훅 → 기록 매핑

설정 예시: `integration/hooks/settings.example.json`(사용자 전역 `~/.claude/settings.json`, 이벤트 10개, `timeout: 2`, `PreToolUse`·`PostToolUse`는 모든 도구 `*`). 실제 입력은 `Tests/Fixtures/hooks/real-*.json`, 문서 예시로 만든 것은 `doc-*.json`.
**이벤트 이름과 입력 필드는 구현할 때 Claude Code hooks 문서(https://code.claude.com/docs/en/hooks)로 다시 확인한다.**

### 공통 입력 필드

- `session_id`, `transcript_path`, `cwd`, `hook_event_name`, 이벤트에 따라 `permission_mode`, `prompt_id`, `effort`(객체, 쓰지 않음).
- 서브에이전트 안의 훅에는 `agent_id`(17자 16진, 예: `ad5a8ca20b7faa5f7`)와 `agent_type`(`subagent_type` 값, 예: `general-purpose`)이 더 붙는다. **서브에이전트 훅의 `session_id`는 부모 세션과 같다.** 그래서 하위 세션의 `Session.id`는 `agent_id`다.
- `SessionStart`: `--resume`은 같은 `session_id`에 `source: resume`, `--fork-session`은 새 `session_id`에 `source: fork`. `clear`/`compact`의 `session_id`는 확인하지 않았다.
- 등록되지 않은 폴더의 세션은 기록하지 않는다(`SessionStart`에 안내 한 줄만). 하위 폴더에서 연 세션은 가장 가까운 상위 `rootPath` 프로젝트로 매칭한다.

### 매핑

| 훅 | 입력 | 서버 동작 | 비고 |
|---|---|---|---|
| `SessionStart` | `source`(startup/resume/clear/compact/fork) | `cwd`로 프로젝트 조회 → 세션 생성(이미 있으면 다시 살림). 응답 본문을 stdout으로 출력해 **대화 컨텍스트에 주입** | 「SessionStart 주입」 |
| `UserPromptSubmit` | `prompt` | heartbeat, 메인 세션의 `lastPrompt` 저장. 블록을 받지 못한 메인 세션에는 블록을 응답 본문으로 돌려줘 **주입**(한 번) | 「늦은 주입」 |
| `PreToolUse` | `tool_name`, `tool_input`, `tool_use_id` | 도구 작업 시작(「작업 상태」). `Agent`면 부모 heartbeat, 프롬프트의 `[LDG-16]` 같은 카드 ID와 `subagent_type`을 **대기 목록**에 올린다 | 서브에이전트 도구 이름은 `Agent`(옛 이름 `Task`도 받는다) |
| `SubagentStart` | `agent_id`, `agent_type` | 하위 세션 생성(`id`=`agent_id`, `agentName`=`agent_type`, 부모=`session_id` 세션). 대기 목록에서 같은 `agent_type`의 가장 오래된 항목을 꺼내 카드가 있으면 연결 | 두 이벤트를 잇는 키가 없어(`tool_use_id` 없음) 순서·종류로 짝짓는다 |
| `PostToolUse` | `tool_name`, `tool_input`, `tool_response` | heartbeat(서브에이전트면 그 하위 세션도), 도구 종료, 변경 파일을 `file.changed`로, 커밋을 `commit`으로, 검증 명령을 `check`로 | 아래 「파일 변경·커밋」 |
| `PostToolUseFailure` | `error`, `is_interrupt` | 도구 종료, 검증 명령이면 `check` | 「검증 근거」 |
| `PermissionRequest` | | 승인 대기 | 관찰만 하고 결정을 출력하지 않는다 |
| `SubagentStop` | `agent_id`, `agent_type` | 하위 세션 종료, 연결 해제 | 모르는 `agent_id`(앱 내부 에이전트, `agent_type` 빈 값)는 무시 |
| `Stop` | | heartbeat, 입력 대기 | 턴 종료일 뿐 세션 종료가 아니다 |
| `SessionEnd` | `reason` | 세션 종료, 모든 연결 해제(하위 세션 포함) | 가끔 오지 않는다 → 「종료 판정」 |

- 서브에이전트 순서: `PreToolUse(Agent)` → `SubagentStart` → 서브에이전트의 훅 → `SubagentStop`. 백그라운드 실행이면 그사이 부모의 `Stop`·`UserPromptSubmit`이 섞이고, 끝나면 부모에 `<agent-message from="<agent_id>">…` 프롬프트가 한 번 더 온다(heartbeat로만 쓴다).
- 모든 훅: 스크립트가 보낸 PID(6장)가 있으면 메인 세션 `claudePid`(Codex는 `processPid`)에 적는다. 비어 있거나 이 훅이 지금까지 받은 것 중 가장 새것(`at >= lastSeenAt`)일 때만 바꾼다. 서브에이전트 훅의 PID는 부모와 같은 프로세스라 메인 세션에만 적는다. 원격 훅(`waypoint_remote`)의 PID는 적지 않는다(「원격·컨테이너 수집」).
- 재수신(docs/RELIABILITY.md): 실시간 응답이 1초를 넘으면 같은 훅이 outbox에도 쓰여 두 번 들어온다. 같은 세션에 같은 `tool_use_id`의 파일 변경·커밋 기록이 10분 안에 있으면 다시 남기지 않는다(payload `toolUseId`). 요청 문장은 `prompt_id`(Claude)·`turn_id`(Codex)가 같으면 같은 요청이고, ID가 없으면 같은 문장이 10초 안에 있을 때 같은 요청이다(payload `promptId`). `PreToolUse(Agent)`는 부모 세션·`tool_use_id`마다 대기 목록에 한 번만 올린다. 끝난 세션보다 이른 시각의 늦은 `PostToolUse`는 같은 ID의 세션을 새로 만들지 않는다.

### 파일 변경·커밋 (`PostToolUse`)

- 줄 수: `Edit`·`Write`의 `tool_response.structuredPatch`, `Bash`의 `bashEditDiff.files[].hunks`에서 `+`/`-` 줄을 센다. 조각이 없으면 `Edit`은 `old_string/new_string`, 새 파일 `Write`는 `content`로 추정. `bashEditDiff.changedFiles`에만 있는 파일은 줄 수 0. `MultiEdit`도 받는다.
- 커밋: `Bash`의 `tool_response.gitOperation.commit`(`sha`, `branch`)을 먼저 쓰고, 없으면 출력의 `[브랜치 해시] 메시지` 줄. 메시지는 그 줄에서 얻는다.
- 귀속: 파일은 변경 파일의 가장 가까운 등록 프로젝트로, 세션의 현재 카드와 같은 프로젝트일 때만 그 카드에도. 여러 프로젝트를 한 번에 고치면 파일별로 나눈다. 등록 밖 절대 경로와 보관 프로젝트에는 기록하지 않는다. 커밋·검증 근거는 `tool_input.workdir`/`cwd`가 있으면 그 폴더의 프로젝트, 없으면 훅의 `cwd`(Claude가 `cd`하면 따라 바뀐다)가 속한 등록 프로젝트, 등록 밖이면 세션 프로젝트. 세션의 프로젝트와 요청 문장의 소속은 `cwd`가 바뀌어도 그대로다.

### SessionStart 주입

`Waypoint:`로 시작하는 블록. tracker 스킬(`integration/skills/tracker/SKILL.md`)이 같은 형식을 적어 두고 읽는다. 바꾸면 둘을 같이 고친다.

```
Waypoint: PRB (훅 실측)
sessionId: ae25fca9-6e32-4d91-9b94-e059f57a5972
지금 상황 (3시간 전, Claude Code):
  파서 리팩터 진행 중. 다음: 오류 메시지 정리
다음 할 일:
- PRB-1 실측용 카드
다른 세션에서 작업중:
- PRB-4 파서 (sess·a1b2, 응답 진행 중) · 최근 파일: Parser.swift, Lexer.swift
직전 세션 메모 (PRB-1 실측용 카드):
  note.txt에 hello 추가함. 볼 파일: note.txt
정리 안 된 작업:
- 어제 14:32 · Claude Code · 파일 3개: Parser.swift, note.txt, hello.txt 외 1 · 9c3e71d2
작업을 시작·전환하거나 한 단위를 끝낼 때마다, 나중에 할 일을 들으면 tracker 스킬을 따른다.
```

- 1줄: `Waypoint: <키> (<이름>)`, 2줄: `sessionId: <세션 ID>`. 마지막 줄은 스킬 안내(고정 문구).
- 지금 상황: 최신 `project.status`가 있으면 `지금 상황 (<상대 시각>, <도구 이름>[, 오래됨]):`과 두 칸 들여쓴 글 줄. 상대 시각은 `TimeFormat.relative`. 없으면 제목째 뺀다.
- 다음 할 일: status next, 번호순 상위 5개. 없으면 제목째 뺀다.
- 다른 세션에서 작업중: 대시보드 작업중 줄 중 이 세션·이 세션의 서브에이전트가 아닌 카드 줄. 괄호 안은 세션 표시와 활동 상태. 그 세션(메인이면 서브에이전트 포함)이 최근 60분 안에 바꾼 파일이 있으면 ` · 최근 파일: <최근 것부터 최대 3개>`(체크아웃을 몰라도 붙인다).
- 직전 세션 메모: 다음 세션 메모가 있고 done·archived가 아닌 카드 중 **가장 최근에 `card_handoff`한 카드 하나**(handoff 기록 시각, 없으면 `updatedAt`). 메모 줄은 두 칸 들여쓴다.
- 정리 안 된 작업(4장): 블록을 받는 세션 자신은 뺀다. 최대 3개, 줄마다 `- <마지막 활동 시각> · <도구 이름> · 파일 <N>개: <많이 바뀐 파일 최대 3개>[ 외 M] · <짧은 세션 ID>`. 짧은 ID는 원본 ID 앞 8자(Codex는 `codex:` + 8자), `work_file`이 앞부분 일치로 받는다. 3개를 넘으면 `- 외 K개`.
- 속도: 훅 타임아웃 1초 안에 만든다. 정리 안 된 작업은 이 프로젝트·최근 14일의 끝난 메인 세션 ID(`fetchIdentifiers`)와 카드 없는 `file.changed`만 질의하고, 파일 목록은 보일 3개만 읽는다.
- 등록되지 않은 폴더: 한 줄 `Waypoint: 이 폴더는 Waypoint에 없음. `/tracker init`으로 등록할 수 있음.` 원격 세션이면 `remote: <origin 원문>` 줄이 붙는다(6장).
- **보관된 프로젝트 폴더**(가장 가까운 상위 `rootPath`가 보관된 프로젝트): 기록하지 않고 안내 줄도 주지 않는다(빈 본문). 보관 전에 시작한 세션도 보관 뒤의 훅은 기록하지 않는다. 단 `SessionEnd`·`SubagentStop`은 열린 세션을 닫는다. 보관을 풀면 다음 훅부터 다시 기록한다.

### 늦은 주입 (`UserPromptSubmit`)

`SessionStart`는 세션을 열 때 한 번만 난다. 등록 전에 시작한 세션이나 다른 폴더에서 옮겨 온 세션은 블록을 받지 못해 스킬이 `sessionId`를 모른다.

- 세션에 블록을 받은 프로젝트 키를 적는다(`Session.contextProjectKey`). 확인을 보내는 스크립트에는 출력 확인을 받은 뒤에 적는다(「수신 확인」).
- 메인 세션의 `UserPromptSubmit`에서 `contextProjectKey`가 없거나 세션의 지금 프로젝트 키와 다르면 「SessionStart 주입」과 같은 블록을 응답 본문(`200 text/plain`)으로 돌려주고, 그다음부터는 `204`. exit 0의 평문 stdout은 Claude가 보는 컨텍스트가 된다.
- 주지 않는 경우: 서브에이전트 안의 훅(`agent_id` 있음), 끝난 세션, 미등록·보관 폴더(미등록 안내 줄은 `SessionStart`에서만).
- outbox로 흡수하는 훅은 블록을 만들지 않고 키도 적지 않는다(`SessionStart` 포함). 앱이 꺼진 채 시작한 세션은 앱이 켜진 뒤 첫 프롬프트에 블록을 받는다.

### 수신 확인

훅 스크립트는 응답을 1초까지 기다린다. 응답이 늦으면 블록이 출력되지 않으므로, 앱은 출력 확인을 받은 뒤에 키를 확정한다.

- 스크립트는 `SessionStart`·`UserPromptSubmit` 요청에 `X-Waypoint-Context-Ack: 1`을 싣는다.
- 앱은 블록을 주며 키를 대기로 둔다: `contextPendingKey`, `contextPendingID`(소문자 UUID), `contextPendingCount`. 응답에 `X-Waypoint-Context-ID: <ID>`.
- 스크립트는 본문을 stdout에 출력한 **뒤에만** `POST /hooks/ack` `{"contextId":"<ID>"}`를 보낸다. 앱은 서버 큐에서 받아 메모리 집합(`ContextAckInbox`, 1000개)에 넣고 바로 `204`. 그 세션의 다음 훅에서 대기 ID가 집합에 있으면 `contextProjectKey = contextPendingKey`로 확정한다. 저장하지 못하면 ID를 되돌린다.
- 확인이 없으면 다음 `UserPromptSubmit`에 같은 블록을 새 ID로 다시 준다. 확인 없이 같은 키의 블록은 `SessionStart` 포함 3번(`HookProcessor.maxContextAttempts`)까지만.
- 확인을 보내는 스크립트의 `SessionStart`는 확정한 키도 비운다(재개·압축 블록이 빠지면 다음 프롬프트에 다시 준다).
- 머리가 없는 요청(옛 스크립트)에는 바로 확정하고 응답 ID를 싣지 않는다. `session_bind`·명시 재연결은 MCP 응답으로 블록을 돌려주므로 바로 확정하고 대기를 지운다.
- Codex도 같다(확인은 공용 `/hooks/ack`).

### 마지막 요청 문장 (`UserPromptSubmit`)

카드 없는 세션 줄·타일의 제목 자리에 그 세션의 마지막 사용자 문장을 보인다.

- 메인 세션의 `prompt`(옛 이름 `prompt_text`)를 다듬어 앞 300자를 `lastPrompt`에, 훅 시각을 `lastPromptAt`에 적는다(`HookParsing.userPrompt`).
- 넣지 않는 것: 서브에이전트 훅, 빈 문장, `<`로 시작하는 자동 메시지(`<agent-message …>`, `<task-notification>`). 슬래시 명령은 적고, `<pasted_content …>`는 태그만 벗긴다.
- outbox로 흡수한 훅은 `at >= lastSeenAt`일 때만 바꾼다.
- 활동 탭의 요청은 `note`(`kind: user.prompt`, 300자). 재수신은 다시 저장하지 않고, 늦은 요청은 세션 시작·프로젝트 연결 이력과 당시 카드 연결 구간으로 소속을 정한다.
- 화면(`SessionFormat.promptPreview`): 공백을 모아 한 줄 160자(넘으면 「…」). Mac은 마우스를 올리면 전체.

### 작업 대상 프로젝트 연결 (`session_bind`)

- 시작 `cwd`는 초기 프로젝트 추정값이다. 실제 작업 대상 폴더가 등록되어 있으면 스킬이 `session_bind(project, sessionId, provider, cwd)`로 연결한다. 세션의 `cwd`는 시작 폴더 그대로다. 미등록 시작 폴더의 `SessionStart`도 실제 `sessionId`를 전달하지만, 대상이 정해지기 전에는 프로젝트나 카드를 만들지 않는다. Codex는 실행 환경의 `CODEX_SESSION_ID`/`CODEX_THREAD_ID`를 ID 근거로 쓴다. ID를 추측하지 않는다.
- 프로젝트 전환은 메인 세션의 카드 연결을 풀어 이전 상태로 돌리고, 세션의 현재 프로젝트와 컨텍스트 키를 바꾼다. 이전 카드·이벤트·이미 돌고 있는 하위 세션의 프로젝트는 바꾸지 않는다. 끝난 세션(자동 정리된 세션은 예외, 「종료 판정」)·다른 도구의 ID·보관 프로젝트 연결은 거절한다. 프로젝트 옮김은 `note`(`kind: project.bound`)로 남는다.

### 작업 상태 (`activityRaw`)

- `SessionStart`/`Stop`/`Interrupt` → 입력 대기. `UserPromptSubmit` → 응답 진행 중. 응답 진행이 15분 넘게 갱신되지 않으면 활동 없음.
- `PreToolUse` → 도구 작업 중(`tool_use_id`별 목록 `pendingToolsData`). `PermissionRequest` → 승인 대기. 질문 도구 `AskUserQuestion`/`request_user_input` → 입력 대기.
- `PostToolUse`·`PostToolUseFailure` → 해당 도구 종료. 다른 병렬 호출이 남아 있으면 도구 작업 중을 유지한다. 늦은 완료는 해당 호출만 지우고 최신 시각을 되돌리지 않는다.
- 진행 중인 하위 작업이 있으면 부모도 작업 중으로 표시한다. 마지막 활동만 아는 옛 세션은 「최근 활동」 또는 「활동 없음」.
- 카드 연결 해제 기록에 종료 이유를 남겨 재개 뒤에도 과거 추적 만료 표시가 바뀌지 않는다.

### 검증 근거 (`PostToolUse`·`PostToolUseFailure`)

셸 도구(Claude `Bash`, Codex `Bash`·`shell`·`exec_command`·`local_shell`)가 검증 명령을 실행하면 그 세션의 열린 카드(서브에이전트가 카드 없이 일하면 부모의 카드)에 `check`(`source: hook`)를 남긴다. 카드가 없으면 남기지 않는다. 같은 `tool_use_id`는 한 번만. outbox로 늦게 온 훅도 남긴다.

- 판정(`VerificationCommand`): 따옴표를 존중해 `&&` `||` `|` `;` `&` 줄바꿈으로 나눈 조각이 아래로 시작하면(앞 변수 대입·`time`·`env`·`timeout N`·`uv|poetry|pipenv|hatch run` 허용) 검증 명령이다. `swift test|build`, `xcodebuild … test|build|build-for-testing|test-without-building`, `npm|pnpm|yarn|bun (run )test`, `(npx|pnpm exec|yarn) jest|vitest|mocha`, `pytest`, `python(3) -m pytest|unittest`, `python(3) …/test*.py`, `go test`, `cargo test|nextest`, `gradle|gradlew … test`, `mvn … test|verify`, `make test|check`, `bash|sh|zsh …/test*.sh`, `./…/test*.sh`, `deno test`. 패턴은 `VerificationCommand.pattern`과 훅 스크립트 `verify_pattern`이 같아야 한다(테스트가 비교).
- 결과(`HookParsing.check`):
  - Claude: 0이 아닌 종료는 `PostToolUseFailure`로만 오고 `error` 첫 줄이 `Exit code N`이다. 그래서 `PostToolUse` = 0, `PostToolUseFailure` = N. 중단, `Exit code` 줄 없는 실패, 백그라운드 실행(`backgroundTaskId`)은 `unknown`.
  - Codex: 0이 아닌 종료도 `PostToolUse`로 온다. `metadata.exit_code`·`exit_code`, 없으면 출력의 `Process exited with code N`·`Exit code: N`. 모르면 `unknown`. Codex 픽스처는 추정 형식이다.
  - 명령 전체의 종료 코드가 검증 조각의 것일 때만 `pass`·`fail`: 첫 검증 조각 앞 연결자는 `&&`·`;`·`|`, 뒤는 `&&`만, 끝이 `&`가 아닐 것(`swift test | tail`, `swift test || true`는 `unknown`).

### 종료 판정 (`SessionEnd`가 오지 않은 세션)

`SessionEnd`는 늘 오지 않는다. 앱이 10초마다, 시작 직후, 활성화·잠자기 복귀 때 outbox를 흡수하고 끝나지 않은 **메인 세션**을 검사한다(`SessionSweep`).

- PID(`claudePid`, `processPid`)가 있으면 그 프로세스를 본다(`sysctl KERN_PROC_PID`). 없거나 좀비면 끝낸다(`reason: "process-gone"`). 프로세스 시작 시각이 `lastSeenAt`보다 2초 넘게 늦으면 PID 재사용으로 보고 끝낸다. 살아 있으면 오래 조용해도 둔다.
- PID가 없으면 `lastSeenAt`에서 30분 뒤 추적을 만료한다(`reason: "tracking-expired-30m"`).
- 끝내는 경로는 `SessionEnd`와 같다(`HookProcessor.finish`): 하위 세션부터 닫고, 카드 연결을 풀어 작업 전 상태로 돌리고(done 아님), `session.end`에 `reason`을 남긴다.
- 끝낸 시각보다 늦은 훅이 오면 세션이 다시 살아나고 옛 PID는 비운다. 이른 늦은 기록은 무시한다. 자동 정리된 세션은 `session_bind`로도 다시 이을 수 있고, 명시적으로 끝난 세션은 되살리지 않는다.

### Codex 연결

- 기준: https://learn.chatgpt.com/docs/hooks, https://developers.openai.com/codex/mcp. 로컬 Codex CLI 훅만 다룬다.
- Codex는 `/hooks/codex/<EventName>`으로 원본 JSON을 보내고, 공유 처리기 전에 도구별 필드를 정규화한다. `tool_input`/`tool_response`가 JSON 문자열로 올 수 있다. 파일 변경은 성공한 `apply_patch`에서 뽑는다. 전사 파일은 감시하지 않는다.
- 받는 이벤트: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `SubagentStart`, `SubagentStop`, `Stop`, `Interrupt`, `SessionEnd`. `Stop`·`Interrupt`는 완료 처리를 하지 않는다.
- 세션 ID는 `codex:<원본 session_id>`(하위 세션도 같은 접두사). PID는 `X-Waypoint-Process-PID` → `processPid`. outbox 줄은 `provider: "codex"`(없으면 Claude).
- MCP는 공유한다. 출력·타임아웃·outbox·수신 확인 규칙도 Claude와 같다. `/hooks` 신뢰는 사용자가 직접 하고, 훅 정의를 바꾸면 다시 신뢰해야 한다.

### 기록 보관 (`RecordRetention`)

기록 시각(`at`)부터 14일(`RecordRetention.days`, 딱 14일 포함)이 지난 기록 가운데 카드에 이어지지 않은 것을 지운다. 카드에 남긴 글과 완료 근거는 날짜와 상관없이 남는다.

| 종류 | 14일 뒤 | 조건 |
|---|---|---|
| `file.changed` | 지움 | 카드에 이어진 것은 카드마다 가장 최근 것 하나만 남긴다(근거가 「변경 후 미검증」인지 가리는 시각) |
| 요청(`note`, `kind: user.prompt`) | 지움 | 카드에 이어졌어도 지운다 |
| `guide.synced`·`card.attached`·`card.detached` | 지움 | 세션 연결 시각은 `CardSession`에 남는다 |
| `check`·`commit` | 카드 없는 것만 지움 | 카드에 이어진 것은 남긴다 |
| `project.status` | 지움 | 프로젝트마다 가장 최근 것 하나는 남긴다 |
| 세션 | 카드에 이어지지 않은 것만 지움 | 메인 세션과 그 서브에이전트를 한 묶음으로 본다. 묶음 모두가 끝났고, 끝난 시각과 마지막 활동이 모두 14일을 넘겼고, 누구도 카드 연결이나 카드에 이어진 기록(`work_file`로 넘긴 것 포함)이 없을 때 묶음째 지운다. 세션의 `session.start`·`session.end`·`session.filed`·프로젝트 옮김 메모·요청도 같이 지운다 |
| `GuideVersion` | 지움 | 문서마다 가장 최근 판 하나는 남긴다 |
| `card.created`·`card.status`·요청이 아닌 `note`·`github.*`·카드·프로젝트·`CardSession`·끝나지 않은 세션 | 남김 | — |

- 끝난 세션의 `lastPrompt`는 `lastPromptAt`(없으면 `endedAt`)부터 14일이 지나면 비운다(`PromptRetention`, `lastPromptAt`은 남긴다).
- Mac 앱이 시작 직후 점검에서 한 번, 그 뒤 하루에 한 번 정리한다. 한 번에 500건까지 지우고(`batchLimit`) 남으면 1분 뒤 다음 점검 때 이어 간다. 지운 결과는 iCloud로 iPhone에 간다. 파일 크기는 바로 줄지 않는다(VACUUM 안 함). 지워진 세션과 같은 `session_id`의 훅이 다시 오면 새 세션으로 만든다.

## 6. 로컬 HTTP API (훅용)

`POST http://127.0.0.1:47821/hooks/<EventName>`(Codex는 `/hooks/codex/<EventName>`), 본문은 훅이 받은 JSON 그대로. 스크립트가 훅을 부른 도구 프로세스를 찾으면 머리 `X-Waypoint-Claude-PID: <PID>`(Codex는 `X-Waypoint-Process-PID`)를 더한다. 응답:

- `SessionStart`: `200 text/plain` — 주입할 텍스트(없으면 빈 본문)
- `UserPromptSubmit`: 늦은 주입이 있으면 `200 text/plain` 블록, 없으면 `204`
- 나머지: `204`

스크립트는 `SessionStart`·`UserPromptSubmit`이 `200`이고 본문이 있을 때만 stdout으로 찍는다.

수신 확인(5장 「수신 확인」):

- 요청 머리 `X-Waypoint-Context-Ack: 1`: `SessionStart`·`UserPromptSubmit`에만. 없으면 앱은 블록을 바로 확정한다.
- 응답 머리 `X-Waypoint-Context-ID: <소문자 UUID>`: 블록을 대기로 둔 `200` 응답에만. 스크립트는 curl `-w '%header{x-waypoint-context-id}'`로 읽고 꼴이 맞을 때만 쓴다.
- `POST /hooks/ack`, 본문 `{"contextId":"<ID>"}`(Claude·Codex 공용). 응답 `204`(모르는 ID도), 본문·ID 꼴이 틀리면 `400`, POST가 아니면 `405`. 서버 큐에서 바로 답한다. 스크립트는 본문을 출력한 뒤에만 보내고(`--max-time 1 --connect-timeout 1 --noproxy '*'`), 결과를 보지 않으며 실패해도 outbox에 쓰지 않는다.

도구 PID 찾기(스크립트): 조상 프로세스를 8단계까지 올라가며(`ps -o ppid=,comm= -p`) 실행 파일 이름(`comm`의 마지막 경로 조각)이 `claude`(Codex 브리지는 `WAYPOINT_AGENT` 값)인 첫 프로세스. Claude 네이티브 설치는 실행 파일 이름이 버전 번호라 `…/.local/share/claude/versions/<버전>` 경로도 받는다. 인자로는 비교하지 않는다(스크립트 경로 `~/.claude/waypoint/…`가 셸 인자에 들어 있다).

### outbox

- 형식: 한 줄에 `{"event":"<EventName>","receivedAt":<unix>,"claudePid":<PID>,"trimmed":true,"payload":<줄인 JSON>}`. `claudePid`는 찾았을 때만(Codex는 `"provider":"codex"`, `processPid`).
- 흡수: 순서대로 처리하고 흡수한 파일을 지운다. 흡수마다 새 `ModelContext`를 쓰고 저장에 실패하면 버린다(`HookProcessor.absorbOutbox`). 메인 context는 흡수 전에 저장하고(못 하면 미룬다) 흡수 뒤 올려 둔 객체를 다시 읽는다(`ContextReload`).
- 읽을 수 없는 줄은 원문 그대로 `outbox.quarantine.jsonl`(0600)에 옮기고 다시 흡수하지 않는다(연동 상태에 「누락 기록 N건 형식 오류」). 세션 정보를 못 읽은 줄은 소비하고 알리기만 한다.
- 한 줄의 저장이 실패하면 그 줄부터 끝까지를 남기고 멈춘다. 다음 10초 점검·「다시 점검」·서버 준비 때 그 줄부터 다시 흡수한다(횟수 제한 없음). 남은 줄을 다시 쓰지 못하면 파일을 그대로 둔다(손실보다 중복).
- 실시간 훅·세션 정리·MCP 도구·등록·보드 끌어 놓기·카드 상세의 저장 실패도 rollback 뒤 다시 읽는다(`ContextReload.commit`).

payload는 앱이 읽는 필드만 남긴다(스크립트 안 jq 필터 `OUTBOX_FILTER`, `/usr/bin/jq`). 실시간 POST와 로깅 모드(`WAYPOINT_HOOK_LOG=1`)는 원본 그대로다. 앱이 세는 값은 같은 결과가 나오는 자리표시로 바꾼다.

| 자리 | 남기는 것 |
|---|---|
| 최상위 | `session_id`, `cwd`, `hook_event_name`, `agent_id`, `agent_type`, `source`, `reason`, `tool_name`, `tool_use_id`, `prompt_id`, `turn_id`, `waypoint_remote`, `prompt`·`prompt_text`(앞 600자), `error`(`Exit code N` 첫 줄만), `is_interrupt` |
| `tool_input` | `file_path`, `subagent_type`, `agent_type`, `workdir`, `cwd`. `old_string`·`new_string`·`content`·`edits[]`는 줄 수만큼의 `\n`. `prompt`·`message`는 `[KEY-n]` 카드 ID만. `command`는 검증 명령(`verify_pattern`)이면 원문, `git commit`이 들어 있으면 `"git commit"`, 아니면 뺀다. `run_in_background`는 셸 도구만. Codex `apply_patch`는 `*** ` 머리 줄과 `+`/`-` 한 글자 줄만 |
| `tool_response` | 패치 줄(`structuredPatch`·`bashEditDiff` hunks)은 `+`/`-` 한 글자만, `bashEditDiff`의 경로들, `gitOperation.commit.{sha,branch}`, `stdout`은 커밋 줄·Codex 종료 코드 줄·Codex 변경 파일 줄만, `metadata.exit_code`·`exit_code`·`exitCode`, `interrupted`, `backgroundTaskId` |

jq가 없거나 실패하면 `session_id`·`cwd`(·`waypoint_remote`)만 남기고, 그것도 못 찾으면 줄을 쓰지 않는다. 파일 내용·명령 출력 원문은 어느 경우에도 쓰지 않는다.

### 원격·컨테이너 수집

SSH 원격 서버·개발 컨테이너의 Claude Code·Codex 훅을 Mac 앱이 받는다. 설정 절차는 [`REMOTE.md`](REMOTE.md). 웹·클라우드 세션은 다루지 않는다. 앱 서버는 `127.0.0.1`에만 열리고, SSH는 `RemoteForward 47821 127.0.0.1:47821`, Docker Desktop은 `host.docker.internal`로 닿는다.

스크립트:

- 보낼 곳: `WAYPOINT_URL`이 있으면 그 주소, 없으면 `http://127.0.0.1:${WAYPOINT_PORT:-47821}`. 훅·ack·replay가 같은 주소를 쓴다.
- 원격 모드: `WAYPOINT_REMOTE=1`/`0`. 없으면 `WAYPOINT_URL`이 있거나 macOS가 아닐 때 켠다. 저장 폴더는 macOS 밖에서 `${XDG_STATE_HOME:-~/.local/state}/waypoint`.
- 원격 모드에서 훅 `cwd` 위로 `.git`(폴더·`gitdir:` 파일, worktree는 `commondir`)을 찾아 origin url과 브랜치를 읽고 payload 앞에 `"waypoint_remote": {origin, root, branch?, host}`를 붙인다. git 명령·하위 셸은 쓰지 않는다. origin이 없거나 따옴표·역슬래시·제어 문자가 있으면 붙이지 않는다.
- 순서: 쌓인 outbox가 있으면 `SessionStart`·`UserPromptSubmit` 밖의 이벤트는 outbox 끝에 붙인 뒤 replay를 뒤에서 띄운다(먼저 보내면 앱이 이른 줄을 끝난 세션의 지난 기록으로 버릴 수 있다). 훅이 앱에 닿았을 때도 쌓인 줄이 있으면 띄운다.
- replay: 잠금 `replay.lock`(mkdir, 2분 넘으면 치운다) → `outbox.pending.jsonl`로 떼어 → 100줄(500KB 이하)씩 `POST /hooks/replay`(`application/x-ndjson`, `--max-time 10`), 한 번에 5묶음까지. `200`을 받은 줄만 지운다. 한 줄짜리 묶음이 `400`이면 `outbox.rejected.jsonl`로 옮긴다.

앱:

- 매칭(`RemoteMatcher`·`HookProcessor.linkRemote`): origin을 `GitRemoteURL.normalize`(스킴·사용자 정보·포트·끝 `.git`·`/`를 떼고 소문자, scp 꼴 같음, 로컬 경로는 경로만)로 맞춘다. 등록 프로젝트의 origin은 작업 트리 `.git/config`를 읽는다(`LocalOrigin`, 5분 기억). ① `waypoint_remote`가 있고 ② `cwd`가 등록 폴더와 맞지 않고 ③ 원격 경로가 이 Mac에 없고 ④ 같은 주소의 보관 안 된 프로젝트들의 로컬 작업 트리가 **하나**일 때 잇는다.
- 이으면 `cwd`와 파일 경로를 원격 작업 트리 → 로컬 작업 트리로 옮긴 뒤 로컬과 같은 규칙으로 처리한다. 세션 `cwd`는 원격 폴더, `gitBranch`는 `waypoint_remote.branch`, `checkout`은 `<host>:<원격 작업 트리>`.
- 잇지 못한 원격 세션의 시작 블록에는 `remote: <origin>` 줄이 붙는다. `project_resolve`는 `remote`로 같은 규칙을 쓴다.
- 원격 훅의 PID(머리·outbox `claudePid`)는 원격 쪽 프로세스라 적지 않고, 이미 적힌 PID도 지운다. 원격 세션은 PID 없는 세션처럼 30분 규칙으로 끝난다.
- 세션보다 이른 훅이 늦게 들어오면 `startedAt`과 가장 이른 `session.start`를 당기고 `source`를 채운다.
- `POST /hooks/replay`: 본문 outbox 줄 500줄 이하. 읽을 수 있는 줄만 `replay/outbox.jsonl`에 한 번의 `O_APPEND`로 붙이고 바로 `200 {"accepted":n,"rejected":m}`. 읽을 줄이 없거나 상한 초과 `400`, 쓰기 실패 `500`, POST 아님 `405`.
- 처리(`RemoteReplay`): 메인 큐 한 차례에 0.1초씩 실시간 훅과 같은 경로(블록 없음)로 처리하고 남으면 넘긴다. 로컬 훅이 먼저 처리된다. 중복은 `tool_use_id`·`prompt_id`/`turn_id`로 막는다. replay 줄이 남은 동안 `SessionStart`·`UserPromptSubmit` 밖의 실시간 훅은 뒤에 붙이고 `204`(`HookRouter.defersWhileDraining`).

## 7. MCP 도구 (스킬용)

Claude Code에서의 도구 이름은 `mcp__waypoint__<도구>`. 도구는 지연 로딩되어 Claude가 `ToolSearch`로 불러 쓴다.

### 엔드포인트 `POST /mcp`

MCP Streamable HTTP 중 필요한 부분만 직접 구현했다(`Shared/MCP/`, 외부 패키지 없음).

- **POST만.** 본문은 JSON-RPC 2.0 메시지 하나 또는 배치. 요청이 있으면 `200 application/json`(배치면 응답 배열, 알림은 빼고), 알림·클라이언트 응답뿐이면 `202` 본문 없음. SSE는 쓰지 않는다. `GET`·`DELETE`는 `405`.
- **`Origin`** 머리가 있고 호스트가 `localhost`·`127.0.0.1`·`[::1]`이 아니면 `403`(DNS 리바인딩 방어).
- **프로토콜 버전**: `2025-11-25`·`2025-06-18`·`2025-03-26`. `initialize`는 클라이언트가 보낸 버전이 이 안에 있으면 그대로, 아니면 `2025-11-25`. `MCP-Protocol-Version` 머리가 이 밖의 값이면 **본문 없는 `400`**. Claude Code는 먼저 세션 없는 새 방식(`2026-07-28`, `server/discover`)으로 떠보고 본문 없는 `400`을 받으면 `initialize`로 내려온다(JSON-RPC 오류 본문을 실으면 내려오지 않는다). 원문은 `Tests/Fixtures/mcp/real-*.json`.
- **`Mcp-Session-Id`**: `initialize` 성공 응답에 UUID를 준다. 이후 요청에서는 검사하지 않는다(앱을 다시 켜도 실행 중인 세션이 다시 초기화하지 않고 쓰게).
- 메서드: `initialize`, `notifications/initialized`(202), `ping`, `tools/list`, `tools/call`. 그 밖은 `-32601`. 깨진 JSON은 `400` + `-32700`(`id: null`), 형식이 틀린 메시지·빈 배치는 `-32600`, 모르는 도구 이름은 `-32602`.
- 도구 결과: `content: [{type: "text", text: <JSON 문자열>}]`, `isError`. 실패하면 `isError: true`와 `{"error": "<이유>"}`, 그 호출의 변경은 되돌린다. 성공하면 바로 저장한다.
- 서버는 응답마다 연결을 닫는다(요청이 `keep-alive`로 와도 된다).

### 도구

`project`는 키(대소문자 무시) 또는 폴더 경로(가장 가까운 상위 `rootPath`). `id`는 `PRB-1` 꼴 표시 ID. 보관된 프로젝트와 그 카드는 찾지 않는다. 모든 스키마는 `additionalProperties: false`. `provider`는 `claude`·`codex`.

| 도구 | 입력(필수 굵게) | 동작 |
|---|---|---|
| `project_resolve` | **`cwd`**, `remote` | 폴더 → `{key, name, summary, rootPath}`, 없으면 `null`(오류 아님). `cwd`가 어떤 등록 폴더와도 맞지 않고 `remote`(git origin 주소)가 있으면 같은 원격 주소의 등록 프로젝트(로컬 작업 트리가 하나일 때, 그 작업 트리의 가장 바깥 프로젝트). 6장 「원격·컨테이너 수집」 |
| `project_init` | **`cwd`**, **`name`**, `provider`, `key`, `summary`, `stack`, `guideFiles`, `seedCards` | 앱에 등록 확인 창을 띄우고 바로 `pending`으로 답한다(아래 「project_init」) |
| `session_bind` | **`project`**, **`sessionId`**, **`provider`**, **`cwd`** | 세션을 작업 대상 프로젝트에 잇고 그 프로젝트의 블록을 돌려준다(5장 「작업 대상 프로젝트 연결」) |
| `card_list` | **`project`**, `status`, `query` | status를 안 주면 done·archived를 뺀다. 순서: active → next → idea → done → archived, 같은 상태는 번호순. `query`는 ID·제목·본문 부분 일치 |
| `card_get` | **`id`** | 카드 + `body`, `origin`, `nextSessionNote`, `children`, 최근 기록 20개 |
| `card_create` | **`project`**, **`title`**, `provider`, `kind`, `status`, `body`, `parentId`, `criteria`, `sessionId` | origin은 세션의 도구(세션이 없으면 `provider`, 기본 claude), `originSessionId`=`sessionId`(같은 프로젝트 세션일 때). 기본 kind task, status next(kind idea면 idea). `active`는 받지 않는다(만든 뒤 `card_start`). `parentId`는 같은 프로젝트. `card.created` 기록 |
| `card_start` | **`id`**, **`sessionId`** | 세션이 없거나 끝났거나 프로젝트가 다르면 오류. 그 세션에 붙은 **다른** 카드 연결을 먼저 푼다(그 카드는 작업 전 상태로). 그다음 연결 → 작업중. 같은 카드를 다시 부르면 아무 일 없음. 서브에이전트 세션 ID(`agent_id`)면 그 하위 세션에 붙인다. 결과: `card`, `detached`(풀린 카드 ID), `otherSessions`(같은 카드에 붙은 다른 살아 있는 세션) |
| `card_update` | **`id`**, `title`, `body`, `status`, `criteria` | `status: active`는 받지 않는다. 다른 상태는 `CardLifecycle.move`(done이면 `doneAt`, active였으면 열린 연결을 모두 닫는다 — 4장 불변식). `criteria`는 통째로 바꾼다(null이면 그대로). 체크가 바뀐 조건마다 앱의 체크 상자와 같은 `note` `{kind: "criterion", text, isDone}` |
| `card_note` | **`id`**, **`text`** | `note` 기록 `{text}` |
| `card_handoff` | **`id`**, **`nextSessionNote`** | `nextSessionNote` 저장 + `note` 기록 `{kind: "handoff", text}` |
| `card_evidence` | **`id`**, `criterion`, **`command`**, **`outcome`**, `detail`, `sessionId` | 에이전트 보고 근거 `check`(`source: agent`). `criterion`은 **1부터**(card_get `criteria` 순서, 저장은 0부터 + 조건 글), 빼면 카드 수준. 범위 밖·조건 없는 카드에 번호·정수 아님은 오류. `outcome`은 `pass`·`fail`·`skipped`(일부러 건너뛴 경우만). `detail` 200자. 결과 `{id, outcome, source, criterion?, state?, confirmed?}`(`confirmed`: 훅 기록과 짝지어져 「확인됨」인지) |
| `project_status` | **`project`**, `text`, `sessionId`, `provider` | `text`가 있으면 지금 상황을 새로 쓴다: 줄마다 앞뒤 공백을 다듬고 빈 줄을 뺀 뒤 600자·8줄을 넘거나 비면 오류(자르지 않는다). `project.status` 기록(`provider`는 세션이 있으면 세션의 도구). `text`가 없으면 읽기. 결과 `{project, status: {text, at, provider?, sessionId?, stale} \| null}` |
| `work_file` | **`sessionId`**, `cardId` | 정리 안 된 작업 하나를 처리(4장). `sessionId`는 전체 ID 또는 앞부분 8자 이상(메인 세션 중 하나만 맞아야 함). 끝나지 않은 세션·카드에 붙은 적 있는 세션·이미 이은 세션·이미 넘긴 세션을 다시 넘김·다른 프로젝트·보관된 카드는 오류(넘긴 세션은 나중에 카드에 이을 수 있다). `cardId`가 있으면 기록을 카드로 옮기고 `session.filed`(`filed`), 없으면 `session.filed`(`dismissed`). 카드 상태는 바꾸지 않는다. 결과 `{sessionId, outcome, cardId?, files?, moved?}` |
| `github_issue_create` | **`project`**, **`title`**, `body`, `labels`, `cardId`, `sessionId` | 프로젝트 폴더 `origin`의 GitHub 저장소에 이슈를 연다(14장). 결과 `{number, url, title, state, cardId?}` |
| `github_pr_create` | **`project`**, **`title`**, `body`, `base`, `head`, `draft`, `cwd`, `cardId`, `sessionId` | 같은 저장소에 PR을 연다. push하지 않는다. `head` 기본은 `cwd`(없으면 프로젝트 폴더) 작업 트리의 현재 브랜치, `base` 기본은 저장소 기본 브랜치. 결과는 위와 같고 `state`는 `open`·`draft` |

- `criteria`는 `[{text, done?}]`(문자열 항목도 받는다). `status: done`은 스킬이 사용자 확인을 받은 뒤에만 보낸다. 카드 결과는 `{id, title, kind, status, criteria, updatedAt, parentId?, sessions?}`(`sessions`는 붙어 있는 끝나지 않은 세션).
- `sessionId`는 훅이 주입한 블록의 `sessionId:` 줄(Codex는 실행 환경)에서 에이전트가 읽어 전달한다. 다른 프로젝트 세션이면 기록에 세션을 붙이지 않고 도구(`provider`) 판별에만 쓴다(`card_start`·`work_file`은 오류).
- **`overlaps`**: `card_start`·`card_update`·`card_note`·`card_handoff`·`card_evidence`·`project_status` 결과가 객체이고 알릴 같은 파일 작업 중(4장)이 있으면 붙는다. 훅 출력은 늘리지 않는다.
  - 누구의 눈으로: `sessionId`를 주면 그 세션, 아니면 카드에 붙은 끝나지 않은 세션(`project_status`는 `sessionId`가 있을 때만). 메인과 그 서브에이전트가 같이 있으면 메인만.
  - 항목 `{sessionId: 상대 메인 세션 짧은 ID(앞 8자, Codex는 codex:), provider, cards?: 상대가 붙은 카드 ID, files: 최근 것부터 최대 5, fileCount}`.
  - 빈도: `<내 세션>|<상대 메인 세션>`마다 이미 알린 파일을 앱 메모리에 둔다. 지금 겹친 파일이 모두 알린 것이면 붙이지 않고, 새 파일이 끼면 그 상대의 전체 목록을 다시 붙인다. 앱을 다시 켜면 처음부터 센다.

### project_init

`/tracker init`에서만 부른다. 도구는 사용자의 확인을 기다리지 않는다. 그 뒤 스킬은 지침 파일이 「절 머리 + 한 줄에 지침 하나」 꼴이 아니면 다듬을지 한 번만 묻는다(큰 저장소는 묻지 않는다). 앱은 관여하지 않는다.

- 검사(실패하면 `isError`): `cwd`가 있는 절대 경로 폴더, 이미 등록된 폴더(하위 포함)가 아님, 보관된 프로젝트의 폴더가 아님(보관 해제 안내), `name`이 비지 않음. `seedCards`는 최대 8개, `{title, status: next|idea(기본 next), kind?, body?}`(kind 기본은 status가 idea면 idea, 아니면 task).
- `guideFiles`: cwd 아래 실제 `.md`·`.txt`만 상대 경로로 남긴다(링크를 풀어 비교). 나머지는 `missingGuideFiles`.
- `key`: 대문자로 바꾼다. 규칙 위반·중복이면 초안에 그대로 두고 `warnings`에 알린다(창에서 고쳐야 등록된다). 없으면 추천 키.
- 통과하면 앱 메모리의 초안 목록에 넣고(같은 폴더면 바꾼다, 앱을 끄면 사라진다) 「새 프로젝트 등록」 창을 앞으로 띄운다.
- 결과: `{status: "pending", message: "Waypoint 앱에서 확인하고 등록해 주세요.", draft: {rootPath, name, key, guideFiles, seedCards(개수)}, replacedDraft, missingGuideFiles?, warnings?}`.

확인 창(`macOS/Init/`): 경로, 이름·카드 키(대문자, 위반은 「A–Z 2–5자」, 중복은 「사용 중」으로 「등록」을 막는다)·개요, 스택 칩, 지침 문서·초기 카드 체크 목록(기본 전부), 「취소」「등록」. 메인 창과 따로 떠서 메뉴 막대만 있어도 보인다. 초안이 여럿이면 하나씩, 창을 닫으면 그 초안을 취소한다.

등록(`ProjectRegistry.register`)은 한 번에 저장한다: 재검사 → `Project` → 고른 지침 파일 등록(8장) → 고른 카드(origin은 초안의 provider, `card.created`) → 저장. 중간에 실패하면 아무것도 남기지 않는다. 등록 뒤 메인 창에서 새 프로젝트를 고른다. 이미 돌던 세션은 다음 훅부터 잡힌다.

## 8. 지침 문서

### 동기화 (`GuideDoc`)

- 등록: 프로젝트 화면 「지침 문서」에서 폴더 바로 아래·`docs/` 바로 아래 `.md`와 `.claude/CLAUDE.md`를 후보로 보이고, 「파일 추가…」로 폴더 안 `.md`·`.txt`를 고른다(링크를 풀어 비교). 등록하면 `GuideDoc`, `GuideVersion(local)`, `guide.synced`(payload `relPath`, `source`). 해제는 기록만 지운다.
- 판정은 내용 해시(SHA-256)만 본다(`GuideSync.decide`):

| 디스크 | draft | 결과 |
|---|---|---|
| 해시 == 저장 해시 | 무엇이든 | 아무것도 안 함. 파일 없음 표시였으면 풀기만 |
| 바뀜 | 없음, 또는 저장·디스크 내용과 같음 | 로컬 내용 반영, draft 버림, `GuideVersion(local)`, `guide.synced`(local) |
| 바뀜 | 저장·디스크 내용과 모두 다름 | **충돌**: 로컬 내용을 `conflictContent`에 들고 비교 화면 |
| 없음 | 무엇이든 | 「파일 없음」 표시(등록 유지) |

- 감시: 등록 문서들의 부모 폴더를 FSEvents로 보고, 문서 파일(링크를 푼 경로 포함)의 이벤트만 받아 0.4초 디바운스 뒤 모두 다시 판정한다. 앱 시작과 감시 폴더 변경 때도.
- 앱 편집: 저장 안 한 편집은 `draft`. 저장(⌘S)은 디스크 해시가 다르면 쓰지 않고 충돌로 멈추고, 같으면 임시 파일 → `rename`(권한 유지) 뒤 `GuideVersion(app)`, `guide.synced`(app).
- 충돌 비교 화면: 「로컬 파일」 / 「앱에서 편집한 내용」(줄 단위 LCS), 「로컬 파일로」 또는 「앱 내용으로」.
- 버전: 문서당 최근 50개, 「이 버전으로 되돌리기」는 앱 저장과 같은 규칙. 비샌드박스 앱이라 security-scoped bookmark는 쓰지 않는다.
- 렌더링: 자체 블록 파서(`MarkdownParser`: 제목, 문단, 목록·체크박스, 코드 블록, 파이프 표, 인용, 구분선) + 인라인 `AttributedString(markdown:)`. 목차는 제목 1~3단계.

### 지침·기억 출처

Claude·Codex가 읽는 지침과 기억 파일을 찾아 사이드바 「지침」에 보인다. 읽기만 하고 결과는 저장하지 않는다. 수집은 `GuidanceCollector` → `GuidanceSnapshot`.

| 묶음 | Claude | Codex |
|---|---|---|
| 전역 | `/Library/Application Support/ClaudeCode/CLAUDE.md`(관리 정책), `~/.claude/CLAUDE.md`, `~/.claude/rules/**/*.md` | `~/.codex/AGENTS.override.md`, `~/.codex/AGENTS.md`, `~/.codex/rules/*.rules`, `~/.codex/memories_1.sqlite` |
| 상위 폴더 | `CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md`, 저장소 밖 `AGENTS.md` | 저장소 안 `AGENTS.md`·`AGENTS.override.md` |
| 프로젝트 | `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/**/*.md` | `AGENTS.md`, `AGENTS.override.md` |
| 자동 기억 | `~/.claude/projects/<폴더 이름>/memory/*.md`(`MEMORY.md`는 색인) | — |

- `CLAUDE_CONFIG_DIR`·`CODEX_HOME`이 있으면 그 경로를 홈으로 본다.
- 같은 파일이 여러 프로젝트에 걸리면 한 줄에 키를 합친다.
- 상위 폴더: 프로젝트 폴더(링크를 푼 경로)의 부모부터 홈까지(홈 포함), 홈 밖이면 `/` 바로 아래까지. 홈의 `.claude/`는 전역으로 친다. 위 폴더의 `AGENTS.md`는 프로젝트 git 저장소 안이면 Codex, 밖이면 Claude 쪽이다.
- 기억 폴더 이름(`MemoryFolderName.encode`): 경로의 영문자·숫자가 아닌 글자(UTF-16 단위)를 `-`로, 200자를 넘으면 잘라 해시를 붙인다. 등록 경로·푼 경로·git 뿌리 → 상위 폴더 순으로 짝짓고, 맞는 곳이 없으면 「다른 폴더」에 실제 폴더를 찾아(최대 64개) 보이거나 「없는 폴더」를 붙인다. 빈 기억 폴더는 숨기고 대화 기록(`*.jsonl`)은 열지 않는다.
- Codex 기억 DB: `stage1_outputs`의 행 수와 최근 50개를 읽기 전용(`mode=ro`, `SQLITE_OPEN_READONLY`, `query_only`)으로 읽는다. WAL 때문에 `immutable=1`은 쓰지 않는다.
- 갱신(`GuidanceMonitor`): 시작·등록 프로젝트 변경·앱이 앞으로 올 때·지침 화면을 열 때·감시 폴더에서 출처 파일이 바뀔 때. 감시 폴더는 Claude 홈, Codex 홈, 프로젝트 폴더, 상위 폴더(**홈 자체는 감시하지 않는다**). 출처 이름이 아닌 경로와 `-shm`은 디바운스(0.5초) 전에 버린다.
- 다루지 않는 것: `autoMemoryDirectory`, `claudeMdExcludes`, `@path` 가져오기, 하위 폴더 CLAUDE.md, 상위 폴더의 `.claude/rules/`, 스킬 등.

### 지침 항목 나누기

지침 문서를 「지침 항목」으로 나누고 원문 위치를 기억한다(`Shared/Guidance/`, 순수 로직).

- 형식(`GuidanceDocumentFormat(kind:)`): Markdown, 기억 파일, 기억 색인(`MEMORY.md`), Codex 명령 규칙(`*.rules`). Codex 기억 DB는 나누지 않는다.
- 출력 `GuidanceDocument`: 조각을 이어 붙이면 원문과 **바이트까지** 같다. 항목(`GuidanceItem`)은 종류, UTF-8 바이트 범위(줄 경계), 줄 번호, 원문 글, 절 머리 경로, 표시용 글, 하위 항목을 가진다.
- Markdown 항목: 절 머리(`#`~`######`, 밑줄 머리는 쓰지 않는다), 목록·번호 항목(더 깊이 들여쓴 줄까지, 더 깊은 기호 줄은 하위 항목), 문단, 표(머리 + 행마다), 코드 블록, 인용, frontmatter. 줄 판정은 `MarkdownParser`와 같은 함수다. 빈 줄·구분선·한 줄 HTML 주석은 항목이 아니다.
- 기억 파일은 파일 전체가 한 항목(머리의 `name`·`description`·`type`을 읽는다). 기억 색인은 `[제목](파일)`로 시작하는 맨 위 목록 항목을 색인 줄로 보고 `MemoryIndexPairing`이 같은 폴더 파일과 짝짓는다. 명령 규칙은 괄호가 닫힐 때까지가 한 항목(문자열 안 괄호·`#`은 세지 않는다).
- 바꾸기(`replace`)는 항목 글 자리만 바꾸고 CRLF를 맞춘다. 지우기(`delete`)는 항목 줄과 개행을 지우고, 빈 줄이 겹치지 않게 앞뒤 빈 줄 하나를 함께 지우며 끝 개행 없음을 지킨다. 낡은 항목은 `staleItem`.
- 애매한 문서는 나누지 않고 전체를 한 항목(`document`)으로 두고 이유(`ambiguity`)를 적는다: 닫히지 않은 코드 블록·frontmatter, HTML 블록, 목록 들여쓰기의 탭·공백 섞임, 5단 넘는 중첩, 규칙 괄호 짝 오류, 다시 합친 결과가 다름(안전장치), UTF-8 아님(편집도 막음).

### 지침 항목 보기·고치기 (프로젝트 안)

지침 문서를 항목 단위로 보고 고치고 지운다. 프로젝트 폴더 안 파일의 쓰기는 모두 동기화 저장 경로(`GuideLibrary.save`)를 지나 충돌 규칙을 따른다. 로직은 `GuideItemEdit`·`GuideItemTarget`.

- 들어가는 곳: 지침 문서 화면의 「읽기 | 항목 | 편집」, 지침 화면의 「읽기 | 항목」(Codex 기억 DB 제외).
- 쓰는 대상(`GuideItemTarget.resolve`): 등록 문서면 그 문서. 프로젝트의 `CLAUDE.md`·`.claude/CLAUDE.md`·`AGENTS.md`·`AGENTS.override.md`·`CLAUDE.local.md`는 처음 고칠 때 지침 문서로 등록한 뒤 저장한다. 그 밖은 「프로젝트 밖 지침 쓰기」.
- 고치기: 항목 자리에 원문 편집 상자. 상자가 열린 동안 「이 항목만 바꾼 문서 전체」를 `draft`로 둬서 그사이 로컬 파일이 바뀌면 충돌이 된다. 저장 ⌘↩, 취소 Esc.
- 지우기: 바로 지워 저장하고 6초 알림 「지움 · <앞부분>」 + 「되돌리기」(직전 문서로 저장).
- 저장 직전 앱 기록이 바탕 원문과 다르면 쓰지 않고 비교 화면으로 간다. 애매한 문서는 한 덩어리로 보이고 지우기가 없다.
- 보기만인 출처, UTF-8이 아닌 원문, 다른 상자가 열림, `draft`·충돌이 있음 — 이때는 버튼을 숨긴다.

### 프로젝트 밖 지침 쓰기

전역·상위 폴더·기억·`.claude/rules`·Codex 규칙 파일은 지침 문서로 등록하지 않고 파일에 바로 쓴다(`Shared/GuidanceWrite/`).

- 쓰는 대상(`GuidanceFileWrite.isWritable`): 그 종류의 `.md`(규칙은 `.rules`) 파일. 없는 파일은 새로 만들지 않는다. 이미 등록된 파일은 그 문서로.
- 쓰지 않는 것: Codex 기억 DB(`.sqlite`·`-wal`)와 관리 정책 파일(`/Library/…`). 종류와 경로 둘 다로, 쓰기 함수에서도 다시 거절한다.
- 쓰기 순서(`apply`): ① `.rules`면 검사 → ② 바뀔 파일 모두가 화면이 읽은 원문과 바이트까지 같은지 확인(아니면 아무것도 쓰지 않고 「바뀜」) → ③ 백업 → ④ 원자적 쓰기(권한 유지, 심볼릭 링크는 두고 대상 파일에) 또는 지우기. 쓴 뒤 다시 읽고 목록을 다시 모은다.
- 백업(`GuidanceBackupStore`, 이 Mac에만): `<저장 폴더>/guidance-backups/<원본 경로 SHA-256 앞 32자>/<UTC 시각>-<edit|delete|restore|undo>.<확장자>` + `source-path`. 0700/0600, 원본마다 최근 50개.
- 기억 지우기: 기억 파일을 지우면 같은 폴더 `MEMORY.md`의 그 파일 색인 줄도 함께 지운다.
- 되돌리기: 6초 알림. 모든 파일이 지운 직후와 같을 때만, 아니면 「되돌리지 못함 · 바뀜」.
- 백업에서 복원: 출처 위 「백업 N」 → 사본 목록 → 「이 판으로 되돌리기」(먼저 `restore` 백업). 지운 파일은 목록 맨 아래 「지운 파일」에서.
- Codex 규칙 검사(`CommandRulesCheck`): `codex`가 있으면 새 내용을 임시 폴더에 쓰고 `codex execpolicy check --rules <임시 파일> -- waypoint-check-<무작위>`를 `CODEX_HOME=<임시 폴더>`로 돌린다. 실패면 「저장 안 함 · 줄 2 · <오류>」, 3초 초과·실행 실패면 「검사 못 함」으로 저장하지 않는다. `codex`가 없으면 자체 검사(괄호 짝, 문자열, 규칙마다 `prefix_rule`·`host_executable`·`network_rule` 호출)와 「codex 없음 · 간단 검사」. 되돌리기·복원은 검사하지 않는다.
- 열린 세션: 파일을 고르면 그 파일을 읽는 도구의 끝나지 않은 메인 세션 수 「열린 Claude 세션 3」.

## 9. 사용량 게이지

Claude·Codex 사용량(한도별 사용 비율과 초기화 시각)을 사이드바 아래와 메뉴 막대 메뉴에 도구별로 보인다. 앱은 파일만 읽는다.

### Claude

- 출처: Claude Code가 상태줄 명령 stdin에 넘기는 JSON의 `rate_limits.five_hour`/`seven_day`(`used_percentage`, `resets_at`). 상태줄 명령 앞에 중계 스크립트 `integration/statusline/waypoint-statusline-tap.sh`를 끼운다. 스크립트는 jq 한 번으로 값을 뽑아 파일을 원자적으로 쓰고(임시 파일 → `mv`), 같은 입력을 원래 명령에 넘겨 출력을 그대로 내보낸다. jq가 없거나 쓰기에 실패해도 상태줄은 그대로 나온다.
- `usage.json`: `{"capturedAt":<unix 초>,"rateLimits":<원본>}`.
- `session-status.json`: `{"<session_id>":{"at","name","context"},…}` — `session_name`(앞 200자)과 `context_window.used_percentage`. 자기 세션 항목만 바꾸고 24시간 넘은 항목은 뺀다. 비용은 남기지 않는다.
- 읽기: `UsageMonitor`가 30초마다 수정 시각을 보고 바뀌었을 때만 다시 읽는다. 저장소에 넣지 않아 iPhone에는 없다.
- 세션 이름·컨텍스트(macOS): 세션 표시 자리(「sess·7f2a」)에 이름을, 옆에 「컨텍스트 62%」(80% 이상이면 `liveText`로 진하게, 3시간 넘으면 숨김 `contextStaleAfter`). MCP·훅 블록·iPhone은 「sess·7f2a」 그대로.
- 설치는 연동 설치기(11장). 손으로 할 때는 `statusLine.command`를 `bash ~/.claude/waypoint/waypoint-statusline-tap.sh <원래 명령>`으로(또는 `WAYPOINT_STATUSLINE_NEXT`).

### Codex

- 출처: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`(`CODEX_HOME` 따름)의 `payload.type: "token_count"` 줄 `payload.rate_limits`(`primary`/`secondary`: `used_percent`, `window_minutes`, `resets_at`). 시각은 최상위 `timestamp`.
- 기간은 `window_minutes`로 정하고(300 → 5시간, 10080 → 7일, 43200 → 30일) 짧은 것부터 보인다. `limit_id`가 `codex`이거나 없는 줄만, 둘 다 null이면 버린다.
- 읽기(`CodexUsage`): 최근 7개 날짜 폴더에서 수정 시각 최근 파일 5개까지, 파일마다 끝 256KB(없으면 4MB)에서 마지막 줄을 찾는다. 30초 폴링, 파일이 그대로면 다시 읽지 않는다.

### 표시 공통

- 초기화 시각이 지난 한도는 0%. 30분보다 오래된 기록은 묶음째 흐리게, 기록이 없는 도구는 묶음째 숨긴다.
- 설정 「사용량」 탭의 Claude·Codex 토글(기본 켬, `UserDefaults` `usage.showClaude`·`usage.showCodex`)을 사이드바·메뉴 막대가 함께 따른다. 둘 다 끄면 게이지 영역과 메뉴 줄이 사라진다(파일 읽기는 계속).
- 메뉴 막대: 「사용량 Claude 5시간 42% · 7일 18% / Codex 7일 12%」. 44자를 넘으면 도구마다 한 줄.
- iOS에는 없다.

## 10. 화면

화면 구성과 토큰은 `docs/DESIGN.md`. 대시보드 / 지침(출처 목록) / 프로젝트 보드 / 카드 상세 / 지침 문서 / 새 프로젝트 등록 창 / 연결 설정(온보딩) / 설정(일반·사용량·기록) / iPhone 작업중.

### 카드 작업 이어가기 (macOS)

- 카드 상세에서 Claude Code·Codex용 재개 문맥을 만들어 미리보기·복사한다. 본문(6,000자), 다음 세션 메모(3,000자), 미완료 조건(20개, 각 500자), 그 카드의 최신 변경 파일 10개, 커밋 3개를 모으고 생략 여부를 표시한다. 상태나 이벤트는 바꾸지 않는다. 완료·보관·프로젝트 없는 카드, 경로 없는 프로젝트는 준비할 수 없다.
- 문맥은 새 대화에서 `project_resolve → session_bind → card_get → card_start` 순서로 실제 ID를 쓰게 안내한다. 최신 카드가 완료·보관이면 재개하지 않는다. 앱은 작업을 자동 실행하지 않는다.
- 재개 창 위쪽(`CardResumeSummary`): 목표, 남은 조건, 미검증 조건(미검증·실패·변경 후 미검증), 마지막 메모와 그 뒤 변경 파일 수. 원문은 접힌 칸.
- 재개 상태(`CardResumeStatus`): **준비됨** → **복사함** → **연결됨**(복사 뒤 같은 도구의 새 메인 세션이 이 카드에 붙음). 그 밖에 **연결 끊김**, **재개 불가**. 판정(`CardResumeAttempt`)은 복사 전에 붙었던 세션, 다른 도구·프로젝트·카드의 세션, 서브에이전트를 치지 않는다. 카드 상세에 머무는 동안만 유지한다.
- 도구 열기(`ToolLaunch`): 실행 파일(`~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, `~/.bun/bin`, `~/.volta/bin`, 앱 PATH)과 Terminal.app, 프로젝트 폴더가 있을 때만 「Claude Code에서 열기」/「Codex에서 열기」. 문맥을 복사한 뒤 스스로 지우는 임시 `.command`(0700)로 프로젝트 폴더에서 도구를 인자 없이 띄운다. 실패하면 「터미널 열기 실패 · 문맥은 복사됨」.

## 11. 연동 설치·상태

### 로컬 연동 상태

- macOS 대시보드의 AI 연동 요약과 툴바 버튼에서 상태 패널을 연다. 사용자 범위 Claude·Codex 훅 설정의 필수 이벤트, 실행 파일·실행 권한, 앱 포트 일치, 훅 비활성화를 점검한다. 프로젝트별 설정과 신뢰 승인은 설정 파일만으로 단정하지 않는다. 설치만 되어 있으면 「첫 수신 대기」, 실제 훅을 받았으면 「수신 확인」. 활동 공백은 장애로 치지 않는다.
- 패널: 마지막 훅 활동·실제 수신 시각·수신 당시 프로젝트, 연결된 프로젝트, MCP 마지막 요청, 미처리 outbox 수와 읽기·처리 오류, 원인에 맞는 복구 안내, 저장소 복원 알림(12장), 기록 지표. 미등록 폴더 수신은 프로젝트 미연결로 표시한다. 10초 점검·활성화·잠자기 복귀·「다시 점검」 때 갱신한다. 「다시 점검」은 실패한 로컬 서버의 시작도 다시 해 본다. 10초 점검도 실패한 서버를 10초·20초·40초… 최대 5분 간격으로 다시 연다(`ServerRestartBackoff`, 열리거나 「다시 점검」하면 처음부터).
- 수신 이력은 저장 폴더 `integration-health.json`에만 남는다(10초 점검·앱 종료 때 쓴다). 대화·파일 경로·세션 ID·설정 원문은 저장하지 않는다. 늦은 재수신은 원래 활동 시각으로 비교해 더 최신 상태를 덮지 않는다. `/integration/status`는 루프백 서버의 읽기 전용 진단 정보다(`metrics`, `coverage`, `storeRestore` 포함).

### 앱 안 연동 설치기

Claude·Codex 연동 설치의 기준은 앱 코드(`Shared/Integration/Installer/`)다. 셸·파이썬 스크립트는 개발용이다. 화면은 온보딩.

- 자원: 훅 스크립트·상태줄 중계·Codex 브리지·tracker 스킬은 앱 번들 리소스다(`project.yml`이 `integration/`을 복사, `IntegrationSources`).
- **계획**(`IntegrationInstaller.plan`)은 읽기만 하고 바뀔 파일만 담는다(설치된 상태면 빈 계획). **적용**(`apply`)은 계획 이후 파일이 바뀌었으면 멈추고, 대상 전부를 백업한 뒤 원자적으로 쓰고, 하나라도 실패하면 쓴 파일을 되돌린다. 그 뒤 명령 단계(MCP 등록).
- 백업: `<저장 폴더>/integration-backups/<UTC 시각>-<8자>/`(0700)에 사본(0600)과 `paths.json`.
- 한 번에 한 인스턴스(`AppInstance`)만 사용자 범위에 잇는다.
- 설정 파일을 읽을 수 없으면 아무것도 쓰지 않는다. Claude 쪽에서 사용자 것과 겹치는 단계(다른 tracker 스킬, 다른 주소의 `waypoint` MCP, 명령이 아닌 상태줄, 손으로 고친 중계)는 그 단계만 건너뛰고 `notes`에 남긴다.

| 대상(Claude Code) | 설치 | 해제 |
|---|---|---|
| `~/.claude/settings.json` `hooks` | 10개 이벤트(`settings.example.json`과 같은 차례·matcher)에 Waypoint 훅(`/.claude/waypoint/waypoint-hook.sh`가 든 명령). 이미 같은 훅 하나뿐이면 그대로, 아니면 Waypoint 훅만 바꿔 첫 자리에 넣는다. 다른 훅·키 순서는 그대로 | Waypoint 훅만 빼고 빈 묶음·이벤트·`hooks`를 지운다. 설치 전 설정이 바이트까지 돌아온다 |
| `statusLine` | 없으면 중계만, 다른 명령이면 중계로 감싼다(특수 문자가 있으면 `bash -c '<원래 명령>'`) | 원래 명령을 되찾아 돌린다 |
| `~/.claude/waypoint/*.sh` | 번들 내용, 0755 | 남긴다(열린 세션 보호) |
| `~/.claude/skills/tracker/SKILL.md` | 번들 내용 | Waypoint 스킬이면 지운다 |
| MCP `waypoint` | 없으면 `claude mcp add --transport http --scope user waypoint <url>`, 다른 포트면 remove 뒤 add | Waypoint 주소면 `claude mcp remove waypoint -s user` |

- JSON은 키 순서·숫자 원문을 지키는 `OrderedJSON`으로 다루고, 들여쓰기와 끝 줄바꿈은 원문을 따른다.
- `claude`는 `ToolLaunch`의 탐색 폴더에서 찾아 PATH를 붙여 실행한다(20초 제한). 못 찾으면 그 단계만 「실행 파일 없음」(`isPartial`)이고, 다시 계획하면 MCP 단계만 남는다.
- Codex(`CodexInstallPlanner`)는 `scripts/install-codex.py`와 같은 입력에서 같은 바이트·권한을 쓴다(테스트가 비교). Codex는 훅을 해시로 신뢰하므로 다시 설치해도 같은 `hooks.json`이어야 한다. 다른 점은 백업 위치와 바뀔 것이 없을 때 쓰지 않는 것. `config.toml`은 `MiniTOML`로 구조 오류, 표시 블록 밖 `mcp_servers.waypoint`, `features.hooks = false`를 본다.

### 온보딩

셸 명령 없이 첫 설정부터 첫 기록 확인까지 끝내는 메인 창 시트(「Waypoint 연결」, `macOS/Onboarding/`). 단계 판정은 `OnboardingProgress`.

1. **도구**: Claude Code·Codex(기본 둘 다). 도구마다 연결 상태, 연결돼 있으면 「다시 설치」「연결 해제」(계획을 보이고 확인으로 적용).
2. **연결**: 도구마다 설치 계획(파일 · 새로 만듦/바꿈/지움, 등록, 건너뛴 단계)을 보이고 「연결」로 적용한다. 성공하면 「백업 보기」와 도구 쪽 한 줄(Codex는 `/hooks`에서 신뢰). 오류·상태는 화면용 문장(`OnboardingText`)으로, 부분 실패는 안 된 단계 + 「다시 시도」.
3. **프로젝트**: 「폴더 고르기…」. 미등록 폴더면 `ProjectDraft.folder`(이름 = 폴더 이름, 추천 키, 폴더 바로 아래 `AGENTS.md`·`CLAUDE.md`·`.claude/CLAUDE.md`)로 등록 창을 연다. 「/tracker init 복사」도 있다. 보관된 폴더는 막는다. 등록된 프로젝트가 있으면 건너뛸 수 있다.
4. **첫 기록**: 온보딩을 연 뒤 프로젝트에 연결된 기록이 오면 끝 화면(도구 · 키 · 시각). 등록 밖 폴더의 기록, 서버 미준비(`serverState != .ready`, 「다시 시도」)도 보인다. 2초마다 다시 읽는다. 「끝」을 눌러야 닫힌다.

- 앞 단계가 막히면 그 단계를 보인다. 메인 창이 여럿이면 먼저 뜬 창에만 뜬다.
- 진입점: 첫 실행(프로젝트가 보관 포함 0개이고 `onboarding.completed`가 없을 때), 연동 상태 패널 「연결 설정」, 메뉴 막대 「연결 설정…」. 「닫기」는 끝낸 것으로 기억하지 않는다.
- Dev 제한: Dev(`AppInstance.isDev`)는 평소용 연결을 바꾸지 않으려고 연결 단계에서 막히고 다시 설치·해제도 비활성이다(`IntegrationHomePolicy.installBlock`). Debug 빌드는 `WAYPOINT_INTEGRATION_HOME`이 있으면 그 폴더를 홈으로 써서 허용한다(Release는 무시).

### 기록 지표와 진단 내보내기

- 이 기기에서만 숫자와 시각을 모은다(`ReliabilityMetrics`, 저장 폴더 `metrics.json` 0600, 10초 점검·앱 종료 때 저장): 실시간 훅의 수신 → 저장·화면 반영 지연 최근 1000건, 재개 시간(재개 문맥을 처음 복사한 시각 → 같은 도구의 새 메인 세션이 그 카드에 연결된 시각, 최근 100건), 연동 실패(서버 시작·형식 오류·저장 실패), 복구(outbox 흡수·보존·격리, 세션 정리) 횟수.
- 연동 상태 패널에 짧게 보이고, 「진단 정보 복사」를 누를 때만 내보낸다. 프로젝트명·경로·세션 ID·대화는 담지 않는다. 기준·측정 방법은 docs/RELIABILITY.md.

### 자동 갱신 지표 (`TrackingCoverage`)

에이전트가 일하면서 기록을 얼마나 갱신했는지 본다. 순수 함수이고 요청 때 저장소에서 계산한다. 기간은 최근 14일(`RecordRetention.days`, 그보다 오래된 기록은 지워져 셀 수 없다), 보관 안 된 프로젝트별, 세션은 마지막 활동이 기간 안인 끝난 메인 세션.

- 카드 연결: 파일을 바꾼 세션(세션·서브에이전트의 `file.changed`가 있음) 중 카드에 붙은 적이 있거나 `work_file`로 처리한 세션 / 파일을 바꾼 세션.
- 메모 갱신: 카드에 붙은 세션 중 세션 동안(`startedAt`…`endedAt`) 붙었던 카드에 메모·다음 세션 메모·완료 조건 체크 변경(`note` kind 없음·`handoff`·`criterion`)이나 에이전트 검증 보고(`check` `source: agent`)가 하나라도 남은 세션 / 카드에 붙은 세션. `card_note`·`card_handoff`는 세션을 적지 않으므로 시각으로 가른다.
- 상황 경과: 마지막 `project.status` 이후 일수(없으면 없음).
- 내보내기: 숫자와 프로젝트 키만. 「진단 정보 복사」 끝에 `자동 갱신 (최근 14일)` · `전체: 카드 연결 a/b · 메모 갱신 c/d` · 프로젝트마다 `<키>: 카드 연결 … · 메모 갱신 … · 상황 N일 전|오늘|없음`. `/integration/status`의 `coverage` `{windowDays, projects: [{key, workedSessions, linkedSessions, linkRate, attachedSessions, notedSessions, noteRate, statusAgeDays}]}`(분모 0이면 비율 `null`). 패널 「기록 지표」에 `최근 14일 · 카드 연결 a/b · 메모 갱신 c/d`, `지금 상황 · 7일 안에 갱신 x/y 프로젝트`(패널을 열 때 한 번 계산).

## 12. 저장소와 기록

### 저장소 백업·복구

업데이트나 깨진 파일 때문에 기록을 잃지 않게 한다. 코드는 `Shared/Store/`(`WaypointSchema`·`StoreBackup`·`StoreLaunch`·`SQLiteFile`), 앱은 `WaypointStore.openForLaunch`로 연다.

- 판: 지금 모델은 `WaypointSchemaV1`(1.0.0), `WaypointMigrationPlan`(단계 없음).
- **다음 판을 더할 때**: ① 지금 모델 클래스를 `WaypointSchemaV1` 안으로 옮겨 얼린다 ② 바꾼 모델로 `WaypointSchemaV2` ③ `schemas`에 V2, `stages`에 `.lightweight`(CloudKit 때문에 속성 더하기·옵셔널·기본값 안에서) ④ `WaypointStore.schema`·`currentSchemaVersion`을 V2로 ⑤ V1 → V2 여는 테스트.
- 백업 자리: `<저장 폴더>/store-backups/<UTC yyyyMMddTHHmmss.SSSZ>-<사유>/`(0700), 저장소 파일(0600)과 마지막에 쓰는 `info.json`(사유·시각·앱 버전·빌드·판·방법·바이트). `info.json`이 없으면 끝나지 않은 백업으로 보고 지운다. 최근 7개.
- 사유: `upgrade`(앱 버전·빌드·판이 `store-version.json`과 다르거나 없을 때, 열기 전), `daily`(마지막 백업이 24시간보다 오래될 때. macOS는 떠 있는 동안 10초 점검마다 판정, `StoreDailyBackup`. 실패하면 만들던 폴더를 지우고 1시간 뒤 다시), `manual`, `beforeRestore`, `beforeDelete`.
- 방법: 열기 전에는 store·-wal·-shm 파일 복사(`beforeRestore`는 옮기기), 열린 상태에서는 SQLite 온라인 백업(`sqlite3_backup_*`, 롤백 저널 파일 하나). `Waypoint_ckAssets/`는 넣지 않는다. 백업 실패는 열기를 막지 않는다.

열기 순서:

1. 예약 복원(`pending-restore.json`)이 있으면 지금 저장소를 `beforeRestore`로 옮기고 예약한 백업을 제자리에 복사 → `store-restore.json`(`kind: manual`). 실패하면 원래대로 돌린다.
2. 아니면 `upgrade`·`daily` 백업.
3. 연다. 성공하면 `store-version.json`을 쓴다.
4. 실패하고 저장소 파일이 있으면 파일들을 `store-failed/<UTC 시각>/`로 옮기고(`failure.json`) 백업을 최신순으로 `PRAGMA quick_check` → 열기를 해 보며 처음 열리는 것을 쓴다(`kind: automatic`). 방금 뜬 백업이 깨진 사본일 수 있어 하나만 보지 않는다.
5. 열리는 백업이 없으면 파일을 제자리로 돌리고 처음 오류로 멈춘다.

- 백업을 놓기 전에 store·-wal·-shm이 하나도 남지 않아야 한다(남은 -wal은 조용히 깨뜨린다).
- 판이 안 맞는 저장소(새 판 뒤 옛 앱)도 복구 대상이다.
- 알림: 연동 상태 패널 「기록을 열지 못해 <시각> 백업으로 되돌림」(예약 복원은 「<시각> 백업으로 되돌림」) + 「알림 확인」, `/integration/status`의 `storeRestore`.
- API: `StoreBackup.list()`, `backupOpenStore`, `scheduleRestore`·`scheduledRestore`·`cancelScheduledRestore`. 적용은 다음 실행의 1단계.
- CloudKit: 복원은 이 기기 파일만 되돌린다. 미러링 상태도 파일 안에 있어 백업 시점으로 돌아가므로, 동기화를 켠 채 되돌리면 서버의 이후 변경을 다시 받을 수 있다(기기 확인 안 함).

### 기록 탭

설정 창(⌘,)의 탭은 「일반」, 「사용량」, 「기록」. 기록 탭은 남기는 것 · 어디에 · 백업 · 내보내기·지우기. 화면 `macOS/Settings/Records*`, 로직 `RecordScope`·`RecordExport`·`RecordWipe`·`AppRelaunch`, 문구 `RecordFormat`.

저장 범위 표(`RecordScope`)는 저장 속성 전부와 이벤트 payload 키를 화면 항목으로 나누고, 화면 문장은 이 표에서만 만든다. `RecordScopeTests`가 스키마·payload 키·`Event.record(` 호출과 표를 맞춘다.

| 항목 | 남기는 것 | 보관 |
|---|---|---|
| 프로젝트 | 이름·키·폴더·개요·스택·다음 번호·시각 | 계속 |
| 카드 | 내용·완료 조건·만든 쪽·부모·시각, 세션 연결, `card.created`·`card.status`, 조건 체크 메모, `session.filed` | 계속(`card.attached`·`card.detached`는 14일) |
| 세션 | 도구·종류·에이전트·폴더·브랜치·시각·끝난 까닭, `session.*`, 프로젝트 옮김 | 14일 · 카드에 이어진 것은 계속 |
| 요청 문장 | `lastPrompt`와 요청 이벤트(300자) | 14일 |
| 바뀐 파일 | 경로·`checkout`·줄 수 | 14일(카드마다 최근 하나는 계속) |
| 커밋 | 해시·메시지 첫 줄 | 14일 · 카드에 이어진 것은 계속 |
| 검증 기록 | 명령(300자)·결과·출처·조건·설명·끝 코드 | 14일 · 카드에 이어진 것은 계속 |
| 메모 | 카드 메모·다음 세션 메모·지금 상황 | 계속(지난 `project.status`는 14일) |
| 지침 문서 | 등록 문서의 **내용 전체**·편집·충돌 내용·이전 판 | 14일 · 최신 판은 계속 |

- 남기지 않는 것: AI 답변, 대화 전체, 명령 출력, 지침 문서가 아닌 파일 내용. outbox에는 요청 600자 등이 앱이 켜질 때까지 머문다.
- 내보내기에서 빼는 작동 상태 값: `Project.lastEventAt`, `Card.statusBeforeActive`, `Session`의 PID·`context*`·상태 캐시·활동·대기 도구, `GuideDoc.contentHash`.
- 어디에: 저장소는 iCloud · 이 Mac과 iPhone(iCloud를 끄면 「이 Mac」). 이 Mac에만: `store-backups`, `guidance-backups`, `integration-backups`, `outbox.jsonl`, `integration-health.json`·`metrics.json`, `usage.json`, `session-status.json`, `github-cache.json`.
- 「지금 백업」: `manual` 온라인 백업(`StoreDailyBackup.runNow`, daily와 겹치지 않는다). 목록은 최신순 「시각 · 까닭 · 크기」, 「Finder에서 보기」.
- 「복원…」 → 확인 → `scheduleRestore` → 다시 시작. 다시 시작(`AppRelaunch`)은 지금 PID가 끝나기를 기다린 뒤(0.2초 간격, 최대 20초) `open <번들 경로>`로 띄우고 `WAYPOINT_SUPPORT_DIR`·`WAYPOINT_PORT`·`WAYPOINT_CLOUDKIT`·`WAYPOINT_INTEGRATION_HOME`·`WAYPOINT_RELAUNCH_HIDDEN`을 `--env`로 넘긴다(`HIDDEN=1`이면 `-g -j`).

내보내기(`RecordExport`, formatVersion 1): UTF-8 JSON, 들여쓰고 키 정렬, 날짜는 ISO 8601 UTC 밀리초. 이름 제안 `Waypoint-<키|전체>-<yyyy-MM-dd>.json`.

```
{ formatVersion: 1, exportedAt, app: { version, build, schemaVersion }, scope: "all" | "project",
  projects: [ { id, key, name, summary, rootPath, stack, nextCardNumber, createdAt, archivedAt?,
                cards: [ { id, displayID, number, title, body, kind, status, origin, originSessionId?, parent?(표시 ID),
                           criteria: [{ text, isDone }], nextSessionNote?, createdAt, updatedAt, doneAt?,
                           sessions: [{ sessionId?, attachedAt, detachedAt? }] } ],
                sessions: [ { id, provider, kind, parent?, agentName?, cwd, gitBranch?, startedAt, lastSeenAt,
                              endedAt?, endReason?, lastPrompt?, lastPromptAt? } ],
                events: [ { id, at, type, card?(표시 ID), session?(세션 ID), payload?: { 키: 문자열|정수|참거짓 } } ],
                guideDocs: [ { id, relPath, content, draft?, conflictContent?, isMissing, lastSyncedAt,
                               versions: [{ at, source, content }] } ] } ],
  unassigned?: { cards, sessions, events, guideDocs } }   // 전체만: 프로젝트에 붙지 않은 행
```

- 프로젝트 하나면 그 프로젝트 것만(이벤트는 `Event.project`로 가른다). 이름·뜻을 바꾸면 `formatVersion`을 올리고, 필드 더하기는 그대로.

모든 기록 지우기(`RecordWipe`): 확인 두 번(무엇이 지워지는지·iPhone에서도 지워짐 → 「프로젝트 N개 · 카드 M개를 지울까요?」). 저장 → `beforeDelete` 온라인 백업(실패·진행 중이면 지우지 않음) → 7종 모델을 잎부터 한 행씩 `delete`(미러링이 지운 것을 보내게) → 다시 시작. 저장소 밖 파일과 UserDefaults는 그대로다.

Debug 실행 인자: `-WaypointSettingsTab records`, `-WaypointSettingsScroll bottom`, `-WaypointExport <경로>`(+`-WaypointExportProject <키>`), `-WaypointBackupNow 1`, `-WaypointRestore <백업 폴더 이름|latest>`, `-WaypointWipe 1`. 버튼과 같은 `RecordsModel` 길을 대화상자 없이 탄다.

## 13. 로그인·업데이트 (macOS)

### 로그인할 때 열기

`SMAppService.mainApp`으로 로그인 항목에 등록·해제한다. 판정 `LoginItemPolicy`, 상태 `LoginItemController`, 등록 `SystemLoginItemService`.

- 온보딩 「끝」에서 켠다. 실행 때는 기존 사용자(프로젝트가 있거나 `onboarding.completed`)이거나 설치 스크립트가 옛 항목을 지웠다는 표시가 있으면 켠다.
- 저절로 켜기는 한 번만(`loginItem.autoApplied`, 실패하면 남기지 않는다). 설정 「일반」 탭의 토글을 한 번이라도 바꾸면(`loginItem.userChoice`) 그 뒤로는 저절로 켜지 않는다.
- Dev는 등록하지 않고 토글이 비활성이다.
- 토글은 실제 상태(`enabled`·`requiresApproval`이면 켜짐)를 따르고 앱이 앞으로 올 때마다 다시 읽는다. 승인 필요면 「시스템 설정에서 허용」.
- 옛 항목: `scripts/install-local.sh`가 System Events로 만든 옛 항목을 지우고 `WaypointLoginItemLegacyRemoved`를 남긴다. 앱은 실행 때 읽고 지운다.

### 자동 업데이트

Sparkle 2.10.0(SwiftPM) 표준 화면(`SPUStandardUpdaterController`)이 찾기·내려받기·서명 확인·설치·재실행을 맡는다. 판정 `UpdateFeed`, 앱 쪽 `AppUpdater`. 배포 절차는 [RELEASE.md](RELEASE.md) 「자동 업데이트」.

- 꺼짐: `SUFeedURL`(빌드 설정 `WAYPOINT_FEED_URL`)이 비었거나 http(s)가 아니거나 `SUPublicEDKey`가 32바이트 base64가 아니면 Sparkle을 시작하지 않고 메뉴·설정 항목도 없다. 기본값이 빈 주소라 `--feed-url` 없는 빌드와 샘플 모드는 꺼진다.
- 켜지면 저절로 확인이 기본 켬(`SUEnableAutomaticChecks`, 하루 간격)이고, 새 판은 Sparkle 창이 알려 사람이 고른다.
- 화면: 메뉴 막대 「업데이트 확인…」, 설정 「일반」 탭 「자동으로 업데이트 확인」·「지금 확인」(진행 중이면 비활성).
- 서명(EdDSA)이 맞지 않으면 설치하지 않는다. 새 빌드가 처음 열릴 때 `upgrade` 백업을 뜬다. 시스템 정보 전송은 끈다.

## 14. GitHub 이슈·PR 열기

외부 이슈 도구 연동을 하지 않는다는 방향의 예외다. 하는 일은 이슈·PR을 열고, 그렇게 연 것을 Waypoint에서 보는 것뿐이다. 다른 곳에서 연 이슈·PR을 가져오지 않고, 댓글·리뷰·병합·닫기도 하지 않는다.

### 호출

- 사용자의 `gh` CLI로 부른다(`GitHubCLI`). 앱은 토큰을 다루지 않는다. `ToolLaunch.searchDirectories`·앱 PATH에서 찾고, `GH_PROMPT_DISABLED=1`·stdin 없음, 20초 제한.
- 저장소는 `rootPath` 작업 트리의 `origin`(`GitRemoteURL.normalize`), `github.com/<owner>/<name>`만 받는다.
- 이슈 `gh issue create --repo … --title … --body … [--label …]`, PR `gh pr create --repo … --title … --body … --head <브랜치> [--base …] [--draft]`. 본문은 받은 그대로. 번호는 출력의 마지막 주소 줄에서 읽는다.
- PR은 push하지 않는다. 브랜치가 `refs/remotes/origin/`(packed-refs 포함)에 없으면 호출 전에 오류. `owner:branch`는 확인하지 않는다.
- 미루는 응답: MCP는 메인 큐에서 처리하므로 이 두 도구만 ① 메인 큐 준비(`MCPTools.githubPlan`) ② 백그라운드 `gh`(`GitHubJob.run`, 키·ID만) ③ 메인 큐 기록·응답(`githubFinish`)으로 나눈다. `LocalServer.deferredHandler`가 연결을 열어 두며, 단독 `tools/call`만 맡는다(`MCPRouter.deferredCall`, 배치에 섞으면 오류).

### 기록

- 성공하면 이벤트 `github.issue`·`github.pr`. payload `number`·`url`·`title`·`state`(`open`·`draft`)·`repo`·`branch`(PR만)·`provider`(세션이 있을 때).
- 잇는 곳: `cardId`가 있으면 그 카드(같은 프로젝트) → 없으면 `sessionId` 세션의 작업중 카드가 하나일 때 그 카드 → 아니면 프로젝트에만. 카드 상태는 건드리지 않는다.
- 실패하면 아무것도 기록하지 않는다.

### 보기 (macOS)

- 카드 인스펙터 「GitHub」: 그 카드의 이슈·PR(번호·제목·열림/닫힘/병합됨/초안), 누르면 브라우저. 저장소가 이어져 있으면 「이슈 열기…」「PR 열기…」.
- 보드 머리 「이슈 N · PR N」(열린 수): 이 프로젝트에서 연 것 전부. 상황판 타일 아래 줄에도 열린 수. 활동 탭 「이슈 #12 열림」.
- 열기 시트: 제목(카드 제목), 본문(카드 본문 + 완료 조건 체크리스트), PR은 브랜치·합칠 곳·초안. 도구와 같은 `GitHubPlanner`·`GitHubJob`·`GitHubLog`.
- 상태 갱신: 목록·인스펙터를 열 때 5분 지난 항목이 있으면 `gh api graphql` 한 번으로 `state`·`title`·`isDraft`를 읽어(`GitHubStatusQuery`) `github-cache.json`(0600)에 두고 화면에만 덮어 보인다. 이벤트·카드 상태는 바꾸지 않는다. 실패하면 1분 쉬고 마지막 값을 보인다.

### 실패

| 원인 | 문구 |
|---|---|
| `gh`가 없음 | 「이 Mac에 GitHub 도구가 없음 — 설치한 뒤 로그인」 |
| 로그인 안 됨(종료 코드 4, 「gh auth login」) | 「GitHub에 로그인되어 있지 않음」 |
| `origin`이 없음 / GitHub 주소가 아님 | 「이 프로젝트 폴더에 원격 저장소가 없음」 / 「원격 저장소가 GitHub 주소가 아님: …」 |
| 현재 브랜치를 모름(분리된 HEAD) | 「지금 브랜치를 알 수 없음 — 브랜치를 골라야 함」 |
| 브랜치가 원격에 없음 | 「브랜치가 원격에 없음 — 먼저 push: <브랜치>」 |
| 20초 초과 | 「20초 안에 끝나지 않음」 |
| 그 밖 | `gh` 오류 출력 첫 줄 |

화면에는 위 문구만 보이고, 도구 응답에는 해결 명령이 괄호로 붙는다(예: 「(터미널에서 gh auth login)」).

Debug 실행 인자: `-WaypointProject <키>`(그 프로젝트 보드에서 시작), `-WaypointGitHub list`(보드 머리 목록을 시트로), `-WaypointGitHub issue|pr`(카드 인스펙터에서 열기 시트, `-WaypointOpenCard`와 함께).
