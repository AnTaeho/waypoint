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
- 환경: 평소용·Dev(개발 서명, Apple Development)는 CloudKit **Development**. 엔타이틀먼트에 환경을 적지 않으면 기본이 Development다. Developer ID 배포 빌드(`scripts/release-mac.sh`)는 Production이지만, Production 스키마를 배포하기 전까지 기본으로 iCloud를 끈다(`WaypointICloud=NO`, `docs/RELEASE.md`). Development 스키마는 앱이 처음 올린 레코드로 자동으로 생긴다.
- 끄기(`AppInstance.cloudKitContainer`가 nil): 빌드 스위치 Info.plist `WaypointICloud`가 `NO`(macOS, build setting `WAYPOINT_ICLOUD`, `Config/Waypoint-macOS-Info.plist`. 기본 `YES`, 외부 베타 배포 `scripts/release-mac.sh`만 기본 `NO`. 키가 없으면 켬 — iOS), 환경 변수 `WAYPOINT_CLOUDKIT=0`, 또는 `WAYPOINT_SUPPORT_DIR`로 저장 폴더를 옮긴 실행(확인용 임시 저장소가 실제 컨테이너와 섞이지 않게). 빌드 스위치가 `NO`면 환경 변수로 켤 수 없다. 꺼지면 설정 「기록」 탭이 「이 Mac · iCloud 꺼짐」으로 보인다. 샘플 모드(메모리 저장소)와 테스트(`makeContainer` 기본값)는 늘 로컬.
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
             origin: claude | codex | manual, originSessionId?,
             nextSessionNote?, statusBeforeActive?, createdAt, updatedAt, doneAt?

Criterion    text, isDone

Session      id(= Claude Code session_id), project, kind: main | subagent,
             parent: Session?, agentName?, cwd, gitBranch?,
             startedAt, lastSeenAt, endedAt?, claudePid:Int?,   // claudePid: 메인 세션만, 훅 스크립트가 보낸 Claude Code PID
             contextProjectKey:String?,          // 대화에 Waypoint 블록을 준 프로젝트 키(5장 「늦은 주입」)
             lastPrompt:String?,                 // 메인 세션의 마지막 사용자 요청 문장, 300자까지(5장 「마지막 요청 문장」). 끝난 세션은 14일 뒤 비운다
             lastPromptAt:Date?,                 // lastPrompt를 적은 훅 시각, lastPrompt와 함께 바뀐다
             state: live | stalled | ended          // 파생값, 저장 캐시

CardSession  card, session, attachedAt, detachedAt?

Event        id, project, card?, session?, at,
             type: session.start | session.end | card.created | card.status |
                   card.attached | card.detached | file.changed | commit |
                   note | guide.synced | check | project.status | session.filed,
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

### 프로젝트 지금 상황·정리 안 된 작업 (`project.status`·`session.filed`, TRK-62·63)

모델 필드는 늘리지 않고 이벤트로 남긴다. 새 종류는 `typeRaw` 문자열 값이라 저장 형식(스키마 판)은 그대로다. 옛 앱은 모르는 종류를 `note`로 읽으므로 두 종류 모두 `text` 키를 두지 않는다(옛 앱·옛 iPhone 앱의 활동 탭에 메모로 보이지 않는다).

- `project.status`: 프로젝트(필수)·세션(있으면)에 붙는다. payload `summary`(지금 상황 글), `provider`(claude·codex), `sessionId`(있으면). **가장 최근 것이 지금 상황**이다. 7일(`ProjectStatus.staleAfter`)보다 오래되면 「오래됨」. 활동 탭에 「지금 상황」으로 보인다.
- `session.filed`: 정리 안 된 작업 처리. 프로젝트·세션에, 연결이면 카드에도 붙는다. payload `sessionId`, `outcome`(`filed` 카드에 이음 · `dismissed` 넘김), `cardId`·`files`(경로 수)·`moved`(옮긴 이벤트 수)는 연결 때만. 카드 기록에 「이전 세션 작업 연결 · 파일 N개」.
- **정리 안 된 작업**(`UnfiledWork`): 이 프로젝트의 메인 세션 중 끝났고(`endedAt`) 마지막 활동(`lastSeenAt`)이 최근 14일이며, 세션·서브에이전트가 카드에 붙은 적이 한 번도 없고(`CardSession`이 없음, 풀린 것 포함), 최근 14일 안에 이 프로젝트에 카드 없는 `file.changed`를 1개 이상 남겼고(서브에이전트 것 포함), `session.filed`가 아직 없는 것. 최근 것부터.
- 연결(`work_file`에 카드): 그 세션·서브에이전트의 카드 없는 `file.changed`·`commit`·`check` 중 이 프로젝트 것을 그 카드로 옮긴다(`Event.card`만 바꾼다). 카드 상태·`updatedAt`·`CardSession`은 그대로라 작업중 판정과 상태 복귀에 영향이 없다. 옮긴 파일 변경이 그 카드 근거보다 늦으면 「변경 후 미검증」, 다음 세션 메모 뒤면 메모 신선도가 바뀔 수 있다(그 파일이 실제로 그 카드 작업이었으므로 그대로 둔다).

### 대시보드 상황판 (`ProjectSituation`, TRK-64)

대시보드 맨 아래 「프로젝트」 구역은 프로젝트 타일 격자다(옛 프로젝트 표·카드를 바꿨다). 여러 프로젝트에서 지금 진행 중인 것과 다음 할 일을 한눈에 보는 자리이고, 값은 모두 에이전트 기록에서 나온다(사람이 넣는 우선순위·마감일 없음). 집계는 `ProjectSituation.board`(순수 함수, `Shared/`).

- 대상: 보관하지 않은 프로젝트 전부.
- 순서: 나를 기다리는 세션이 있는 프로젝트 먼저, 그다음 작업 중(live 줄이 하나라도 있음 — 카드 없는 세션 포함, 사이드바 작업중 점과 같은 기준)인 프로젝트 먼저, 그다음 마지막 활동(`DashboardQuery.lastActivityAt`: `lastEventAt`·세션 `lastSeenAt`·카드 `updatedAt` 중 가장 늦은 것) 최근순, 같으면 키순.
- 타일 머리: 키·이름, 작업 중이면 작업중 점, 마지막 활동 상대 시각. 누르면 프로젝트 보드(사이드바 선택과 같은 길).
- 나를 기다림(`SessionWaiting`, TRK-72): 머리 바로 아래에 「승인 기다림 N」「질문 기다림 N」 알약을 나란히 둔다(0인 쪽은 빼고, 둘 다 0이면 줄이 없다). 승인은 활동이 승인 대기인 세션, 질문은 입력 대기이면서 질문 도구(`SessionActivityRules.questionTools`)가 떠 있는 세션이다. 턴이 끝나 다음 요청을 기다리는 세션과 끝난 세션은 세지 않는다.
- 나를 기다림은 이 프로젝트의 끝나지 않은 세션 전부에서 세션마다 한 번 센다(카드 없는 세션·서브에이전트 포함). 서브에이전트가 기다리면 그 세션 하나로 세고 부모는 세지 않는다. 승인·질문을 기다리는 메인 세션은 서브에이전트가 돌아 활동이 도구 작업 중이어도 저장된 단계(`activityRaw`)로 센다. 다만 그 기다림 뒤에 시작한 끝나지 않은 서브에이전트가 있으면 이미 답한 것으로 보고 세지 않는다(서브에이전트 띄우기를 승인받은 뒤에는 `PostToolUse(Agent)`가 올 때까지 단계가 승인 대기로 남는다). 도구 필터를 고르면 그 도구 세션만 센다. 검색은 이 수를 거르지 않는다.
- 지금 상황: 최신 `project.status` 글. 4줄까지 보이고 그보다 많은 줄이거나 150자를 넘으면 「더 보기」로 편다. 아래에 갱신 상대 시각 · 도구. 7일을 넘으면(`ProjectStatus.staleAfter`, 딱 7일은 아님) 흐리게 + 「오래됨」. 글이 없으면 이 줄이 없다.
- 진행 중: 대시보드 작업중 줄(`DashboardQuery.rows`) 중 카드 줄을 카드마다 한 줄로 모은다(세션 여럿이면 하나라도 live면 live, 도구는 중복 없이). 줄 순서 그대로 최대 3, 머리에 전체 수. 카드 없는 세션은 줄을 만들지 않고 작업중 점에만 든다. 멈춘 카드는 속 빈 점과 「멈춤 · 도구」.
- 다음: 다음 할 일 카드, 보드 다음 칸과 같은 번호순(`BoardQuery.columns`) 최대 3.
- 최근 끝냄: 보드 완료 칸과 같은 7일(`BoardQuery.doneWindow`, 딱 7일 전은 뺀다) 안에 끝낸 카드, 최근순 최대 3, 끝낸 상대 시각.
- 아래 줄: 정리 안 된 작업 수(있을 때만, `liveText`), 아이디어 수(있을 때만). 정리 안 된 작업은 `UnfiledWork.count`(같은 조건, 파일 목록 없이 세션마다 있는지만 센다).
- 비는 구역은 머리째 숨긴다. 카드 줄을 누르면 카드 상세.
- 검색: 프로젝트는 이름·키가 맞거나 맞는 카드(보관 제외)가 있는 것. 이름·키가 맞으면 타일 그대로, 아니면 세 카드 구역에 맞는 카드만 남기고 개수도 거른 뒤 센다(작업중 줄 검색과 같은 규칙).
- 도구 필터(진행 작업의 전체/Claude/Codex): 진행 중 줄과 작업중 점을 그 도구 세션으로만 본다. 프로젝트는 숨기지 않는다.
- 다시 계산: 대시보드와 함께(`LiveDataTimeline`, 저장·훅 직후와 5초마다). 지금 상황은 `project.status` 이벤트를 한 번만 읽는다(`ProjectStatus.latestEntries`). 실제 저장소 사본(프로젝트 4·세션 114·이벤트 6118)에서 상황판 전체 11–25 ms(기계 부하 평균 17에서 잼).

### 같은 파일 작업 중 (`WorkOverlap`, TRK-17)

같은 프로젝트에서 동시에 도는 작업(메인·서브에이전트, Claude·Codex)이 같은 파일을 만지고 있음을 사람과 에이전트에게 알려 덮어쓰기를 미리 막는다. 실제 git 충돌을 뜻하지 않으므로 화면은 「충돌」이라 쓰지 않는다. 모델 필드는 늘리지 않는다.

- `file.changed` payload `checkout`(TRK-17부터): 바뀐 파일의 git 작업 트리 최상위 절대 경로. 파일 폴더부터 위로 올라가며 `.git`(폴더·파일 모두)이 있는 첫 폴더(`GitInfo.checkoutRoot`, git 명령을 부르지 않는다). worktree·하위 모듈은 `.git`이 파일이라 따로 잡힌다. git 밖이면 키가 없다.
- `path`는 그 파일이 속한 가장 가까운 등록 프로젝트의 `rootPath` 기준 상대 경로다(세션 `cwd`·git 최상위는 쓰지 않는다). 등록 폴더 안의 worktree(`.claude/worktrees/x/…`)는 `path`부터 다르고, 등록 폴더 밖 worktree의 파일은 기록되지 않는다(아래 누락).
- 작업 단위: 메인 세션과 그 서브에이전트(뿌리 메인 세션). 같은 단위끼리는 겹침이 아니다.
- 겹침: 같은 프로젝트에서 끝나지 않은(뿌리 메인 세션이 `endedAt` 없고 `SessionRules.state`가 ended 아님 — 대시보드 작업중 줄과 같은 기준) 단위 둘 이상이 같은 `checkout`의 같은 `path`를 각자 최근 60분(`WorkOverlap.window`, 경계 포함) 안에 바꿨다. 단위가 살아 있으면 끝난 서브에이전트의 변경도 단위 것으로 센다. 카드마다 한 건씩 남은 같은 변경은 하나로 센다.
- 누락(경고하지 않는 쪽): `checkout`이 없는 기록(TRK-17 전 기록, git 밖 파일)은 판정에서 뺀다. 한쪽만 있어도 겹침이 아니다.
- 메인 세션 줄은 단위 전체의 변경으로, 서브에이전트 줄은 그 세션의 변경으로 본다. 상대 이름은 상대 단위가 붙은 첫 카드 ID, 카드가 없으면 세션 표시(`sess·1a2b`, Codex는 `Codex · sess·…`).
- 질의: 이 프로젝트·최근 60분의 `file.changed`만(`WorkOverlap.index`). 대시보드는 프로젝트마다 한 번 만든다(`byRow`). 실제 저장소 사본(프로젝트 4·세션 115·이벤트 6150) 5 ms, Dev 저장소 사본(세션 1620·최근 1시간 변경 수천 건) 20 ms.

화면(문구에 「충돌」·만든 쪽 용어를 쓰지 않는다, 색은 `Theme.Overlap` — 작업중 강조색):
- 대시보드 진행 작업 타일, 카드 인스펙터 「지금 연결된 세션」 상자: `같은 파일 N개 · PRB-3`(상대가 여럿이면 `… · PRB-3 외 1`, N은 합집합). 누르면 상대마다 `카드 제목 · 도구 세션`과 파일(상대마다 12개, 넘으면 `외 N개`). 마우스를 올리면 파일 목록.
- 상황판 진행 중 줄: 도구 앞에 `같은 파일 N`(그 카드에 붙은 세션들의 겹친 파일 합집합).

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
- 대시보드 "작업중" 목록 = 프로젝트별로 묶은 (세션, 카드) 쌍 + 카드가 붙지 않은 끝나지 않은 메인 세션 한 줄씩(카드 칸 비움, 제목 자리에 그 세션의 마지막 요청 문장 `lastPrompt`(없으면 「카드 없음」), 최근 파일은 그 세션과 서브에이전트가 카드 없이 남긴 `file.changed`). 같은 프로젝트에 세션 2개가 서로 다른 카드를 작업하면 그 프로젝트 아래 2줄. 세션에 카드가 붙으면 카드 없는 줄은 카드 줄로 바뀐다(중복 없음). 카드 없는 서브에이전트는 줄을 만들지 않는다. 제목의 「작업 N개」는 live 줄 수, 사이드바의 작업중·멈춤 수는 카드 수 + 카드 없는 메인 세션 수.
- 내 답을 기다리는 줄(`DashboardRow.waitingKind`, 판정은 `SessionWaiting.kind` — 승인 대기, 질문 도구가 떠 있는 입력 대기)은 줄의 `workState`가 stalled이고 화면 집계에서만 따로 뗀다(`DashboardOverview.split`): 위 집계의 「내 답 기다림」(`waitingCount`, 줄 수)과 「확인하고 이어가기」의 「내 답 기다림 N개」 묶음에 들고 「대기·활동 없음」(`stalledCount`)에서는 빠진다. 턴이 끝나 쉬는 입력 대기는 「대기·활동 없음」에 남는다. 도구 필터·검색으로 거른 줄을 가른다(위 집계는 거르지 않은 전체). 줄 글은 `SessionWaiting.text`(「승인 대기 3분」·「질문 대기 3분」). 사이드바는 `ProjectSummary.waitingCount`(끝나지 않은 세션 수, 상황판 알약과 같은 셈)가 1 이상이면 작업중·멈춤 점 대신 그 수가 든 알약을 그린다(`ProjectSummary.sidebarMark`: 기다림 > 작업중 > 멈춤). 카드 없는 서브에이전트는 줄이 없으므로 그 기다림을 부모 세션의 첫 줄에 올린다(`SessionWaiting.shown`, `DashboardRow.waiting`): 줄 글은 「승인 대기 3분 · test-writer」(기다리는 서브에이전트의 시각·이름), 여럿이면 가장 오래 기다린 것 하나. 카드가 붙은 서브에이전트는 제 줄에서만 잡는다. 기다림이 든 줄은 세션 `state`가 live여도 줄의 `workState`를 stalled로 둔다. 단위가 달라 수가 어긋나는 경우: 한 세션이 카드 둘에 붙으면 줄 2·알약 1, 카드 없는 서브에이전트 둘(또는 부모와 그 서브에이전트)이 함께 기다리면 줄 1·알약 2, 부모 줄이 없는 서브에이전트는 알약에만 든다.
- 프로젝트 보드 작업중 칸 = 작업중 카드 + 그 아래 카드 없는 세션 타일(대시보드 카드 없는 줄과 같은 세션, `BoardQuery.sessionTiles`). 타일은 마지막 요청 문장(없으면 「카드 없음」), 세션(`sess·7f2a`), 최근 파일, 끝나지 않은 서브에이전트 수(있으면), 이벤트 기반 상태와 대기 시간. 끌거나 누를 수 없다. 칸 머리 개수는 카드 + 타일(사이드바 작업중 수와 같은 기준).
- 작업중 줄·타일·카드 상세는 `SessionFormat.activityText`로 도구 작업·응답 진행·입력 대기·승인 대기·활동 없음을 표시한다. 대기는 해당 전환 시각, 활동 없음은 마지막 활동 시각부터 경과를 표시한다. 내 답을 기다리는 세션은 보드의 카드 없는 세션 타일·작업중 카드·카드 인스펙터의 연결된 세션에서도 `SessionWaiting.Shown.text`(「승인 대기 3분」·「질문 대기 3분」)를 `waitingText`로 보인다. 메뉴 막대 줄(`SessionFormat.menuLine`)은 「승인 대기 N」「질문 대기 N」을 따로 세고 「입력 대기 N」에는 턴이 끝나 쉬는 세션만 남긴다.
- 프로젝트 화면의 **활동** 탭은 이벤트의 불변 `project` 연결을 기준으로 날짜·세션별 요청, 파일 변경, 커밋, 완료, 인수인계 메모를 시간순으로 보여준다. 세션이 나중에 다른 프로젝트로 연결되어도 과거 기록은 이동하지 않는다. 도구·카드·세션 필터와 카드 상세 연결을 제공하며, 같은 파일의 연속 변경만 5분 단위로 묶는다. 처음에는 최신 300건을 읽고 「더 보기」로 확장한다. 검색은 현재 읽은 기록 범위에만 적용된다.

## 5. 훅 → 기록 매핑

### 카드 작업 이어가기

Mac 카드 상세에서 재개 문맥을 준비하고 Claude Code·Codex를 선택해 미리보기·복사한다. 외부 AI 호출 없이 카드 본문, 다음 세션 메모, 미완료 조건, 해당 카드의 변경 파일과 커밋을 조합한다. 본문 6,000자, 메모 3,000자, 조건 20개(각 500자), 중복 없는 최신 파일 10개, 커밋 3개로 제한하며 생략 여부를 표시한다. 생성·복사는 상태나 이벤트를 변경하지 않는다. 완료·보관·프로젝트 없는 카드와 경로 없는 프로젝트는 준비할 수 없다.

사용자가 새 대화에 붙여넣으면 `project_resolve → session_bind → card_get → card_start` 순서로 연결하도록 안내한다. 복사한 과거 ID 대신 현재 대화의 실제 ID를 사용하며, 최신 카드가 완료·보관된 경우 자동으로 재개하지 않는다. 기존 세션 연결이 있으면 `otherSessions`를 통해 알려 작업 범위를 확인한다. 연결이 성공한 뒤에만 작업중으로 표시된다. 앱은 작업을 자동 실행하지 않는다.

재개 창 위쪽에 한 묶음으로 목표(카드 제목·본문 첫 글줄), 남은 완료 조건, 미검증 조건(근거 상태가 미검증·실패·변경 후 미검증, 건너뜀은 제외), 마지막 메모와 작성 시점·이후 변경 파일 수를 보인다(`CardResumeSummary`). 복사할 문맥 원문은 그 아래 접힌 칸에 둔다. 요약은 복사 문맥과 같은 기록을 읽는다.

재개 상태(`CardResumeStatus`)는 카드 상세의 재개 영역과 재개 창에 한 줄로 보인다: **준비됨**(복사 전, 재개 가능) → **복사함**(복사 성공, 고른 도구의 새 세션이 아직 붙지 않음) → **연결됨**(복사 뒤 같은 도구의 새 메인 세션이 이 카드에 열린 연결로 붙고 카드가 작업중). 그 밖에 **연결 끊김**(복사 뒤 붙었던 새 세션이 떨어짐), **재개 불가**(완료·보관 카드, 보관 프로젝트, 작업 폴더 없음, 다른 카드). 복사나 도구 열기만으로는 복사함에 머문다. 연결 판정은 `CardResumeAttempt`: 복사 전에 이 카드에 붙었던 세션(과거 ID), 다른 도구 세션, 서브에이전트, 다른 프로젝트 세션, 다른 카드에 붙은 세션은 치지 않는다. 다른 폴더(하위 폴더, 다른 등록 프로젝트 폴더)에서 시작한 세션도 `session_bind`로 이 프로젝트에 연결한 뒤 `card_start`하면 연결됨이다. 도구를 바꿔 다시 복사하면 그 도구의 새 세션만 본다. 상태는 카드 상세에 머무는 동안만 유지한다.

도구 열기(macOS): 그 도구의 실행 파일(`claude`·`codex`)이 흔한 설치 폴더(`~/.local/bin`, Claude는 `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, `~/.bun/bin`, `~/.volta/bin`)나 앱의 PATH에 있고, Terminal.app이 있고, 프로젝트 폴더가 있을 때만 재개 창에 「Claude Code에서 열기」/「Codex에서 열기」를 둔다(`ToolLaunch`). 누르면 문맥을 복사한 뒤(복사와 같은 재개 시도) 임시 `.command` 파일(0700, 실행되자마자 스스로 지움)을 Terminal.app으로 연다. 파일은 프로젝트 폴더로 `cd`하고 도구를 인자 없이 실행한다. 대화 내용·세션 ID·과거 대화 잇기 옵션은 넘기지 않는다. 조건이 하나라도 빠지면 버튼 없이 복사만 쓴다. 여는 데 실패하면 「터미널 열기 실패 · 문맥은 복사됨」.

활동 탭의 사용자 요청은 `note`의 `kind: user.prompt`로 최대 300자씩 저장한다. 이 버전 이전의 전체 요청 이력은 복원하지 않는다. 재수신된 동일 시각·내용의 요청은 중복 저장하지 않으며, 지연 수신은 세션 시작·프로젝트 연결 이력과 당시 카드 연결 구간으로 소속을 결정한다.

기록 보관(`RecordRetention`, 기준 14일 `RecordRetention.days`): 기록 시각(`at`)부터 14일이 지난(딱 14일 포함) 기록 가운데 카드에 이어지지 않은 것을 지운다. 카드에 남긴 글과 완료 근거는 날짜와 상관없이 남는다.

| 종류 | 14일 뒤 | 조건 |
|---|---|---|
| `file.changed` | 지움 | 카드에 이어진 것은 카드마다 가장 최근 것 하나만 남긴다(같은 시각이 여럿이어도 하나, 근거가 「변경 후 미검증」인지 가리는 시각, `CardEvidence`) |
| 요청(`note`, `kind: user.prompt`) | 지움 | 이벤트째 지운다. 카드에 이어졌어도 지운다 |
| `guide.synced`·`card.attached`·`card.detached` | 지움 | 세션 연결 시각은 `CardSession`에 남는다 |
| `check`·`commit` | 카드 없는 것만 지움 | 카드에 이어진 것은 남긴다(완료 근거) |
| `project.status` | 지움 | 프로젝트마다 가장 최근 것 하나는 남긴다 |
| 세션 | 카드에 이어지지 않은 것만 지움 | 메인 세션과 그 서브에이전트를 한 묶음으로 본다. 묶음 모두가 끝났고, 끝난 시각과 마지막 활동이 모두 14일을 넘겼고, 누구도 카드 연결(`CardSession`)이나 카드에 이어진 기록(`work_file`로 넘긴 것 포함)이 없을 때 묶음째 지운다. 세션의 `session.start`·`session.end`·`session.filed`·프로젝트 옮김 메모·요청도 같이 지운다 |
| `GuideVersion` | 지움 | 문서마다 가장 최근 판 하나는 남긴다 |
| `card.created`·`card.status`·요청이 아닌 `note`·`github.*`·카드·프로젝트·`CardSession`·끝나지 않은 세션 | 남김 | — |

끝난 세션의 `lastPrompt`는 `lastPromptAt`(없으면 `endedAt`)부터 14일이 지나면 비운다(`PromptRetention`, `lastPromptAt`은 남긴다). 끝나지 않은 세션의 `lastPrompt`는 둔다. Mac 앱이 시작 직후 점검에서 한 번, 그 뒤 하루에 한 번 정리한다. 한 번에 500건까지 지우고(`batchLimit`) 남으면 1분이 지난 다음 점검 때 이어서 지운다. 지운 결과는 iCloud로 iPhone에 간다. 파일 크기는 바로 줄지 않는다(VACUUM 안 함). 14일이 지난 기록이 outbox로 늦게 들어오면 다음 정리 때 지운다. 지워진 세션과 같은 `session_id`의 훅이 다시 오면 새 세션으로 만든다. 「자동 갱신 지표」의 기간도 같은 14일이다.

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

- 1줄: `Waypoint: <키> (<이름>)`, 2줄: `sessionId: <Claude Code session_id>`. 마지막 줄은 스킬 안내(고정 문구).
- 지금 상황: 최신 `project.status`가 있으면 `지금 상황 (<상대 시각>, <도구 이름>[, 오래됨]):`과 두 칸 들여쓴 글 줄. 상대 시각은 `TimeFormat.relative`, 7일보다 오래되면 `오래됨`. 없으면 제목째 뺀다.
- 다음 할 일: status next, 번호순 상위 5개. 없으면 제목째 뺀다.
- 다른 세션에서 작업중: 대시보드 작업중 줄 중 이 세션·이 세션의 서브에이전트가 아닌 카드 줄(카드 없는 세션 줄은 뺀다). 괄호 안은 세션 표시와 활동 상태. 그 세션(메인이면 서브에이전트 포함)이 최근 60분 안에 바꾼 파일이 있으면 ` · 최근 파일: <최근 것부터 최대 3개>`(TRK-17, 체크아웃을 몰라도 붙인다 — 새 세션이 같은 파일을 피하게).
- 직전 세션 메모: 다음 세션 메모가 있고 done·archived가 아닌 카드 중 **가장 최근에 `card_handoff`한 카드 하나**(handoff 기록 시각, 없으면 `updatedAt`). 메모 줄은 두 칸 들여쓴다.
- 정리 안 된 작업(4장): 블록을 받는 세션 자신은 뺀다(재개). 최대 3개, 줄마다 `- <마지막 활동 시각> · <도구 이름> · 파일 <N>개: <많이 바뀐 파일 최대 3개>[ 외 M] · <짧은 세션 ID>`. 짧은 ID는 원본 ID 앞 8자(Codex는 `codex:` + 8자), `work_file`이 앞부분 일치로 받는다. 3개를 넘으면 `- 외 K개`. 없으면 제목째 뺀다.
- 속도: `SessionStart` 응답 안에서 만든다(훅 타임아웃 1초). 상황은 `project.status` 이벤트만, 정리 안 된 작업은 이 프로젝트·최근 14일의 끝난 메인 세션 ID(객체를 읽지 않는 `fetchIdentifiers`)와 카드 없는 `file.changed`만 질의하고, 파일 목록은 보일 3개만 읽는다. 측정은 9장 뒤 「자동 갱신 지표」.
- 등록되지 않은 폴더: 한 줄 `Waypoint: 이 폴더는 Waypoint에 없음. `/tracker init`으로 등록할 수 있음.`

**보관된 프로젝트 폴더**(가장 가까운 상위 `rootPath`가 보관된 프로젝트)는 등록되지 않은 폴더처럼 기록하지 않되, `SessionStart`에 안내 줄도 주지 않는다(빈 본문). 보관하기 전에 시작한 세션도 보관 뒤의 훅(heartbeat·파일 변경 등)은 기록하지 않는다. 단 `SessionEnd`·`SubagentStop`은 열린 세션을 닫는다(보관을 풀었을 때 끝난 세션이 작업중으로 남지 않게). 닫히지 않은 세션은 종료 판정이 닫는다. 보관을 풀면 다음 훅부터 다시 기록한다.

### 늦은 주입 (`UserPromptSubmit`)

`SessionStart`는 세션을 열 때 한 번만 난다. 그래서 등록 전에 시작한 세션, 등록 안 된 폴더에서 시작해 등록 폴더로 옮겨 온 세션은 블록을 받지 못해 스킬이 `sessionId`를 모른다(2026-09-28 chainmate 세션: `~/workspace`에서 시작해 옮겨 왔고 CHM은 그 뒤 등록 → 「이 폴더는 Waypoint에 없음」만 받았다).

- 세션에 블록을 받은 프로젝트 키를 적는다(`Session.contextProjectKey`). `SessionStart`에서 블록을 줄 때, 그리고 아래 늦은 주입 때. 확인을 보내는 스크립트에는 스크립트가 블록을 출력했다는 확인을 받은 뒤에 적는다(아래 「수신 확인」).
- 메인 세션의 `UserPromptSubmit`에서 `contextProjectKey`가 없거나 세션의 지금 프로젝트 키와 다르면 「SessionStart 주입」과 같은 블록을 응답 본문(`200 text/plain`)으로 돌려주고 키를 적는다. 그다음부터는 `204`. 블록을 받은 뒤 세션의 프로젝트가 바뀌면 한 번 더 준다(세션의 프로젝트는 처음 만들 때 정해지고 지금은 옮겨 가지 않는다 — 프로젝트를 옮기는 경로가 생기면 저절로 적용된다).
- 주지 않는 경우: 서브에이전트 안의 훅(`agent_id` 있음), 끝난 세션, 미등록·보관 폴더(미등록 안내 줄은 `SessionStart`에서만).
- outbox로 흡수하는 훅(앱이 꺼져 있던 동안의 것)은 이미 지난 일이라 텍스트를 만들지 않고 키도 적지 않는다. `SessionStart`도 같다. 그래서 앱이 꺼진 채 시작한 세션은 앱이 켜진 뒤 첫 프롬프트에 블록을 받는다.
- 문서(2026-09-28 확인, https://code.claude.com/docs/en/hooks 「UserPromptSubmit decision control」): exit 0의 평문 stdout은 `UserPromptSubmit`·`SessionStart` 등에서 Claude가 보는 컨텍스트가 된다. JSON `hookSpecificOutput.additionalContext`(v2.1.196+, 10,000자)도 있지만 `SessionStart`와 같은 평문 방식을 쓴다. 전사에는 사용자 프롬프트 앞에 훅 이름을 보낸 쪽으로 한 별도 메시지로 남는다.
- 이 기능을 넣기 전부터 떠 있던 세션은 `SessionStart`로 블록을 받았어도 키가 비어 있어 다음 프롬프트에 한 번 더 받는다.
- 실측(2026-09-28, Claude Code 2.1.283, Dev, `~/workspace/waypoint-late-probe`): 미등록일 때 `claude -p`로 시작(「이 폴더는 Waypoint에 없음」만 받음) → 앱을 끈 채 폴더를 등록(LPR) → `--resume`에서 `SessionStart`를 빼고(대화형으로 이어 가는 경우와 같게) 프롬프트 → 전사에 `attachment` `{"type":"hook_success","hookEvent":"UserPromptSubmit","stdout":"Waypoint: LPR (늦은 주입 실측)\nsessionId: 0124a6c7-…"}`이 들어갔고 Claude가 블록을 그대로 옮겨 적었다. 두 번째 `--resume`에는 UserPromptSubmit 출력이 없었고 Claude는 「없음」. 저장소 `contextProjectKey` = `LPR`. 전사에서 이 attachment는 사용자 메시지 바로 뒤 줄에 적힌다.

### 수신 확인 (TRK-35, 2026-10-01)

훅 스크립트는 응답을 1초까지 기다린다. 앱이 블록을 만들었어도 응답이 그보다 늦으면 스크립트는 아무것도 출력하지 않는다. 예전에는 앱이 응답을 만들 때 키를 적어서, 그런 세션은 블록을 끝내 받지 못했다(TRK-11 부하 측정 최대 0.8초).

- 스크립트는 `SessionStart`·`UserPromptSubmit` 요청에 머리 `X-Waypoint-Context-Ack: 1`을 싣는다(출력 뒤 확인을 보낸다는 뜻).
- 그런 요청에 블록을 줄 때 앱은 키를 바로 적지 않고 대기로 둔다: `contextPendingKey`(블록의 프로젝트 키), `contextPendingID`(새 응답 ID, 소문자 UUID), `contextPendingCount`(같은 키의 블록을 확인 없이 보낸 횟수). 응답에 머리 `X-Waypoint-Context-ID: <ID>`를 싣는다.
- 스크립트는 `200` 본문을 stdout에 출력한 **뒤에만** `POST /hooks/ack` `{"contextId":"<ID>"}`를 보낸다(6장). 출력에 실패하면 보내지 않는다. 앱은 확인을 서버 큐에서 받아 메모리 집합(`ContextAckInbox`)에 넣고 바로 `204`로 답한다(메인 액터·저장·화면 갱신을 거치지 않는다). 그 세션의 다음 훅을 메인에서 처리할 때 대기 ID가 집합에 있으면 늦은 주입 판단 전에 `contextProjectKey = contextPendingKey`로 확정하고 대기를 지운다. 지금 대기와 맞지 않는 ID(이미 확정, 새 블록으로 바뀜, 프로젝트 재연결)는 쓰이지 않고 집합에 남다가 오래된 것부터 버려진다(1000개). 확정을 저장하지 못하면 ID를 집합에 되돌린다.
- 확인이 없으면(응답 시간 초과, 스크립트 실패, 확인 유실, 확인을 받아 둔 뒤 다음 훅 전에 앱을 다시 켬) 다음 `UserPromptSubmit`이 늦은 주입 조건(`contextProjectKey` ≠ 지금 키)에 걸려 같은 블록을 새 ID로 다시 준다. 같은 블록을 두 번 받는 것은 블록은 출력됐는데 확인을 잃었을 때뿐이다(블록 유실보다 낫다, DECISIONS).
- 같은 키의 블록은 확인 없이 `SessionStart` 포함 3번(`HookProcessor.maxContextAttempts`)까지만 보낸다. 그 뒤로는 확인이 오거나 프로젝트가 바뀔 때까지 주지 않는다(확인이 계속 닿지 않는 환경에서 프롬프트마다 블록이 붙지 않게).
- 확인을 보내는 스크립트의 `SessionStart`는 이미 확정한 키도 비운다. 재개·압축으로 다시 온 `SessionStart`의 블록이 시간 초과로 빠지면 다음 프롬프트에 다시 준다.
- 머리가 없는 요청(옛 스크립트, 버전이 섞인 Codex 사본)에는 예전처럼 블록을 주는 즉시 확정하고 대기를 지운다. 응답 ID도 싣지 않는다. 옛 앱은 응답 ID를 주지 않으므로 새 스크립트도 확인을 보내지 않는다.
- outbox로 흡수한 훅(앱이 꺼져 있던 동안)은 블록이 출력되지 않았으므로 대기도 확인도 없다. 앱이 켜진 뒤 첫 `UserPromptSubmit`이 블록과 응답 ID를 준다.
- `session_bind`·명시 재연결은 MCP 응답으로 블록을 직접 돌려주므로 확인 없이 확정한다. 프로젝트 재연결은 대기도 지운다.
- Codex도 같다(`/hooks/codex/<Event>` 요청의 머리, 확인은 공용 `/hooks/ack`).
- 걸리는 시간(2026-10-01, Dev Debug, 세션 사이 1.5초 쉼, 20회씩 두 번, 옛 → 새 스크립트): 훅 전체 중앙값 `SessionStart` 267 → 289 ms·251 → 263 ms, 늦은 주입 258 → 303 ms·241 → 254 ms, 최대 522 ms. SessionStart 바로 뒤의 확인 요청은 중앙값 1.7 ms(최대 5.5 ms)에 답한다. 메인 큐에서 받던 첫 구현은 같은 측정에서 확인이 앞 훅의 화면 갱신을 기다려 약 0.5초가 늘었다(DECISIONS).

### 마지막 요청 문장 (`UserPromptSubmit`)

카드 없는 세션 줄·타일은 카드 제목이 없어 무슨 작업인지 알 수 없다. 앱은 LLM을 쓰지 않으므로 요약 대신 그 세션에서 사용자가 마지막으로 보낸 문장을 제목 자리에 보여 준다.

- 메인 세션의 `UserPromptSubmit`에서 `prompt`(실측·문서. 옛 문서 예시 이름 `prompt_text`도 받는다)를 앞뒤 공백 정리 후 앞 300자(문자 단위)만 `Session.lastPrompt`에 적고, 그 훅 시각을 `lastPromptAt`에 적는다(`HookParsing.userPrompt`). 세션당 마지막 하나만 둔다. 두 값은 아래 규칙대로 늘 함께 바뀐다.
- 넣지 않는 것: 서브에이전트 안의 훅(`agent_id` 있음), 빈 문장, `<`로 시작하는 자동 메시지(서브에이전트 완료 알림 `<agent-message from=…>` — 실측 `real-UserPromptSubmit-agent-message.json`, 백그라운드 작업 알림 `<task-notification>` 등). 그때는 앞 값을 그대로 둔다. 슬래시 명령(`/tracker init`)은 그대로 적는다. 붙여 넣은 글(`<pasted_content id=…>…</pasted_content>`, 전사에서 확인)은 태그만 벗겨 적는다.
- outbox로 흡수한 훅도 적는다. 단 비어 있지 않으면 이 훅이 지금까지 받은 것 중 가장 새것(`at >= lastSeenAt`)일 때만 바꿔서, 늦게 들어온 옛 프롬프트가 더 최근 값을 덮지 않는다(`claudePid`와 같은 규칙).
- 보관: 끝난 세션은 `lastPromptAt`(없으면 `endedAt`)부터 14일이 지나면 `lastPrompt`를 비운다(위 「기록 보관」).
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
- 훅 출력은 SessionStart·늦은 UserPromptSubmit의 컨텍스트만 허용한다. 스크립트는 1초 HTTP 타임아웃·실패 시 exit 0·outbox 적재를 유지한다. 블록을 출력한 뒤의 수신 확인(5장 「수신 확인」)도 Claude와 같다. Codex의 `/hooks` 신뢰 검토는 사용자가 직접 한다.
- Codex 픽스처는 `doc-codex-*`로 문서 기반임을 구분한다. 실제 신뢰된 Codex 세션과 CloudKit 스키마 배포는 별도 실측 대상이다.

## 6. 로컬 HTTP API (훅용)

모두 `POST http://127.0.0.1:47821/hooks/<EventName>`, 본문은 Claude Code가 훅에 넘긴 JSON 그대로. 스크립트가 훅을 부른 Claude Code 프로세스를 찾으면 머리 `X-Waypoint-Claude-PID: <PID>`를 더한다(없으면 뺀다). 응답:

- `SessionStart`: `200 text/plain` — 컨텍스트로 주입할 짧은 텍스트 (없으면 빈 본문)
- `UserPromptSubmit`: 늦은 주입(5장)이 있으면 `200 text/plain` 블록, 없으면 `204`
- 나머지: `204`

스크립트는 `SessionStart`·`UserPromptSubmit`이 `200`이고 본문이 있을 때만 stdout으로 찍는다. 다른 이벤트는 본문이 와도 찍지 않는다.

수신 확인(5장 「수신 확인」, TRK-35):

- 요청 머리 `X-Waypoint-Context-Ack: 1`: 스크립트가 `SessionStart`·`UserPromptSubmit`에만 싣는다. 없으면 앱은 블록을 바로 확정한다(옛 스크립트).
- 응답 머리 `X-Waypoint-Context-ID: <소문자 UUID>`: 앱이 블록을 대기로 둔 `200` 본문 응답에만 싣는다. 스크립트는 curl `-w '%header{x-waypoint-context-id}'`로 읽고, 꼴이 맞을 때만 쓴다.
- `POST /hooks/ack`, 본문 `{"contextId":"<ID>"}`(Claude·Codex 공용, ID가 세션을 가리킨다). 응답 `204`(모르는 ID도 `204`), 본문·ID 꼴이 틀리면 `400`, POST가 아니면 `405`. 서버 큐에서 바로 답한다(메인 액터를 기다리지 않는다). 스크립트는 본문을 stdout에 출력한 뒤에만 보내고, curl은 `--max-time 1 --connect-timeout 1 --noproxy '*'`, 결과를 보지 않으며 실패해도 outbox에 쓰지 않는다(exit 0, stdout 없음).

outbox 형식: 한 줄에 `{"event":"<EventName>","receivedAt":<unix>,"claudePid":<PID>,"trimmed":true,"payload":<줄인 JSON>}`. `claudePid`는 PID를 찾았을 때만 있다(Codex는 `"provider":"codex"`, `processPid`). 앱은 실행 시 순서대로 흡수하고 파일을 비운다(흡수한 파일은 지운다). 읽을 수 없는 줄(JSON·필수 필드·`provider` 오류)은 버리지 않고 원문 그대로 `outbox.quarantine.jsonl`(0600)에 덧붙인다. 격리 줄은 다시 흡수하지 않고 미처리 기록 수에도 넣지 않는다(연동 상태에 「누락 기록 N건 형식 오류」). 한 줄의 DB 저장이 실패하면(또는 격리 파일에 쓰지 못하면) 그 줄부터 끝까지를 떼어 낸 파일에 다시 쓰고, 뒤 파일까지 모두 멈춘다. 흡수는 한 번마다 새 `ModelContext`(같은 컨테이너)에서 하고, 저장에 실패하면 그 context를 통째로 버린다(`HookProcessor.absorbOutbox`). 메인 context는 흡수 전에 저장 안 된 변경을 저장하고(저장하지 못하면 그 흡수를 미룬다), 흡수 뒤에는 이미 올려 둔 프로젝트·카드·세션·연결을 저장소 값으로 다시 읽는다(`ContextReload`). 그래서 남긴 줄은 같은 실행의 다음 10초 점검·연동 상태 **다시 점검**·서버 준비 때 그 줄부터 다시 흡수한다. 횟수 제한은 없다(디스크가 잠깐 막혀도 기록을 잃지 않게). 서브에이전트 대기 항목은 흡수용 처리기에 넘겼다가 저장된 결과대로 돌려받는다. 실시간 훅과 세션 정리의 저장 실패는 rollback 뒤 같은 다시 읽기로 메모리를 저장소에 맞춘다(DECISIONS 2026-10-01 TRK-33). MCP 도구·프로젝트 등록·보드 끌어 놓기·카드 상세도 같다(`ContextReload.commit`, TRK-34). 남은 줄을 다시 쓰는 것마저 실패하면 파일을 그대로 두어 앞부분이 다시 들어올 수 있다(손실보다 중복). 줄은 읽혔지만 본문에서 세션 정보를 못 읽은 경우는 저장 실패가 아니므로 소비하고 「누락 기록 세션 정보 읽기 실패」만 알린다.

`payload`는 앱이 읽는 필드만 남긴다(2026-10-01, 스크립트 안 jq 필터 `OUTBOX_FILTER`, `/usr/bin/jq`). 실시간 POST와 로깅 모드(`hook-log/`)는 원본 그대로다. 앱이 세는 값은 같은 결과가 나오는 자리표시로 바꿔서 앱 코드는 그대로 읽는다.

| 자리 | 남기는 것 |
|---|---|
| 최상위 | `session_id`, `cwd`, `hook_event_name`, `agent_id`, `agent_type`, `source`, `reason`, `tool_name`, `tool_use_id`, `prompt_id`, `turn_id`(재수신 판정, TRK-11), `prompt`·`prompt_text`(앞 600자 — 앱은 공백·붙여넣기 태그를 벗긴 뒤 300자), `error`(첫 줄이 `Exit code N`일 때 그 줄만), `is_interrupt` |
| `tool_input` | `file_path`, `subagent_type`, `agent_type`, `workdir`, `cwd`. `old_string`·`new_string`·`content`·`edits[]`는 줄 수만큼의 `\n`. `prompt`·`message`는 `[KEY-n]` 카드 ID만. `command`는 검증 명령 패턴(5장 「검증 근거」, `verify_pattern`)에 맞으면 원문, 아니면 `git commit`이 들어 있으면 `"git commit"`(또는 `"git -c commit"`), 아니면 뺀다. `run_in_background`는 셸 도구만. Codex `apply_patch`의 `command`는 `*** ` 머리 줄과 `+`/`-` 한 글자 줄만 |
| `tool_response` | `structuredPatch[].lines`·`bashEditDiff.files[].hunks[].lines`는 `+`/`-` 한 글자만(조각 개수 유지), `bashEditDiff.files[].filePath`·`changedFiles`, `gitOperation.commit.{sha,branch}`, `stdout`은 커밋 줄 `[브랜치 해시] 메시지` 첫 줄, Codex 종료 코드 줄(`Process exited with code N`·`Exit code: N`) 첫 줄과 Codex `Success. Updated the following files:`·`A/M/D 경로` 줄만, `metadata.exit_code`, `exit_code`, `exitCode`, `interrupted`, `backgroundTaskId`. Codex의 문자열 응답·`output`·`text`는 `stdout`으로 합친 뒤 줄인다 |

그 밖의 필드(`transcript_path`, `permission_mode`, `description`, 파일 내용, 명령 출력·실패 출력 등)는 쓰지 않는다. 검증 명령의 원문은 남는다(앱이 근거로 쓴다). jq가 없거나 실패하면 `session_id`·`cwd`만 남기고(값에 따옴표·역슬래시가 없을 때), 그것도 못 찾으면 줄을 쓰지 않는다. 원문은 어느 경우에도 outbox에 쓰지 않는다. 앱이 꺼진 경로 한 번에 약 5~8 ms가 는다(중앙값 21 → 26~27 ms, 2026-10-01 측정).

Claude Code PID 찾기(스크립트): 조상 프로세스를 4단계까지 올라가며(`ps -o ppid=,comm= -p`) 실행 파일 이름(`comm`의 마지막 경로 조각)이 `claude`인 첫 프로세스. 인자(`args`)로는 비교하지 않는다 — 이 스크립트 경로 `~/.claude/waypoint/…`가 셸 인자에 들어 있다. 2.1.283 실측에서는 스크립트 바로 위 부모가 `claude`라 `ps`를 한 번 부르고, 훅 한 번에 약 3 ms가 늘었다(중앙값 15.9 → 18.7 ms).


### 원격·컨테이너 수집 (2026-10-03, TRK-53)

SSH 원격 서버·개발 컨테이너에서 도는 Claude Code·Codex의 훅을 Mac 앱이 받는다. 사용자 설정 절차는 [`REMOTE.md`](REMOTE.md). 웹·클라우드 세션은 다루지 않는다. 저장 형식(모델·이벤트 종류)은 바꾸지 않았다.

보낼 곳(스크립트):

- `WAYPOINT_URL`(예 `http://host.docker.internal:47821`)이 있으면 그 주소로, 없으면 `http://127.0.0.1:${WAYPOINT_PORT:-47821}`. 훅 POST·`/hooks/ack`·replay가 같은 주소를 쓴다. 타임아웃 1초·exit 0·stdout 규칙은 그대로.
- 원격 모드: `WAYPOINT_REMOTE=1`이면 켜고 `0`이면 끈다. 없으면 `WAYPOINT_URL`이 있거나 macOS가 아닐 때(`$OSTYPE`) 켠다. macOS 로컬은 기본으로 꺼져 payload·outbox 동작이 전과 같다.
- 저장 폴더 기본값: macOS `~/Library/Application Support/Waypoint`, 그 밖 `${XDG_STATE_HOME:-~/.local/state}/waypoint`.

원격 주소(원격 모드):

- 스크립트가 훅 `cwd`에서 위로 `.git`(폴더 또는 `gitdir:` 파일, worktree는 `commondir`)을 찾아 `config`의 `[remote "origin"] url`과 `HEAD`의 브랜치를 읽고 payload 맨 앞에 붙인다: `"waypoint_remote": {"origin": "<url 원문>", "root": "<작업 트리 최상위>", "branch": "<브랜치, 없으면 뺌>", "host": "<$HOSTNAME>"}`. git 명령도 하위 셸도 쓰지 않는다(Ubuntu 컨테이너 0.3 ms, git 명령 두 번은 22 ms). origin이 없거나 값에 따옴표·역슬래시·제어 문자가 있으면 붙이지 않는다.
- outbox 줄에도 남긴다(`OUTBOX_FILTER`의 최상위 허용 필드, jq가 없을 때의 최소 줄에도).

원격 주소 매칭(앱, `RemoteMatcher`·`HookProcessor.linkRemote`):

- 정규화(`GitRemoteURL.normalize`): 스킴·사용자 정보(`user@`, `user:token@`)·포트·끝 `.git`·끝 `/`를 떼고 소문자로. scp 꼴 `git@host:a/b`도 같다. 로컬 경로(`/srv/b.git`, `file://`)는 경로만.
- 등록 프로젝트의 로컬 origin: `rootPath`가 든 작업 트리의 `.git/config`를 읽는다(git 명령 없음, `LocalOrigin.read`). 프로젝트 폴더마다 5분 기억(`LocalOriginCache`). 원격 훅이 올 때만 읽는다.
- 잇는 조건: ① 훅에 `waypoint_remote`가 있고 ② 훅 `cwd`가 어떤 등록 폴더(보관 포함)와도 맞지 않고 ③ 원격 작업 트리 경로가 이 Mac에 없고 ④ 같은 정규화 주소를 가진 보관 안 된 등록 프로젝트들의 로컬 작업 트리가 **하나**일 때. 서로 다른 작업 트리(클론) 둘 이상이면 잇지 않는다. 한 작업 트리 안의 여러 프로젝트(모노레포 하위 폴더)는 하나로 본다.
- 이으면 처리 전에 훅의 `cwd`와 파일 경로(`tool_input.file_path`·`workdir`·`cwd`, `bashEditDiff`, Codex `apply_patch`)를 원격 작업 트리 최상위 → 로컬 작업 트리 최상위로 옮긴다. 그 뒤 프로젝트 매칭·`file.changed`의 `path`(등록 `rootPath` 기준 상대 경로)는 로컬과 같은 규칙. 작업 트리 밖 파일은 남기지 않는다.
- 세션 `cwd`는 원격 쪽 원래 폴더, `gitBranch`는 `waypoint_remote.branch`. `file.changed`의 `checkout`은 `<host>:<원격 작업 트리>`(host가 없으면 경로) — Mac의 같은 저장소 체크아웃과 다른 작업 트리로 본다(5장 「같은 파일 작업 중」).
- 잇지 못한 원격 세션의 시작 블록(미등록 안내)에는 `remote: <origin 원문>` 줄이 붙는다. MCP `project_resolve`는 `remote`(origin 주소)를 받아 같은 규칙으로 찾는다(7장).
- 세션을 만든 훅보다 이른 시각의 훅이 늦게 들어오면(replay) 세션 `startedAt`과 가장 이른 `session.start` 기록을 그 시각으로 당기고, `SessionStart`의 `source`를 채운다.

원격 outbox replay:

- 원격 모드에서 훅이 앱에 닿으면(`200`·`204`) 쌓인 outbox가 있을 때 replay를 뒤에서 띄운다(표준 입출력을 모두 `/dev/null`로, `disown`). 훅은 replay를 기다리지 않는다.
- 순서(스크립트): 원격 모드에서 쌓인 줄(`outbox.jsonl`·`outbox.pending.jsonl`·`outbox.claim-*`)이 있으면 `SessionStart`·`UserPromptSubmit` 밖의 이벤트는 실시간으로 보내지 않고 outbox 끝에 붙인 뒤 replay를 띄운다. 먼저 보내면 앱이 그 세션의 이른 줄을 늦게 받아 「끝난 세션의 지난 기록」으로 버릴 수 있다(다시 이어진 뒤 첫 훅이 `SessionEnd`인 경우 등). 블록이 필요한 두 이벤트는 실시간으로 보낸다.
- replay: 잠금 `replay.lock`(mkdir, 2분 넘으면 죽은 것으로 보고 치운다) → `outbox.pending.jsonl`이 비면 `outbox.jsonl`을 떼어 붙임 → 앞에서부터 100줄(500KB 넘으면 그 전까지)씩 `POST /hooks/replay`(`Content-Type: application/x-ndjson`, `--max-time 10`), 한 번에 5묶음까지. 보내는 동안 새로 쌓인 줄도 이어서 보내고, 잠금을 푸는 사이에 온 줄이 있으면 한 번 더 돈다. `200`을 받은 줄만 지운다. 받지 못하면(옛 앱 `404`, 시간 초과) 남겨 다음 훅 때 다시. 한 줄짜리 묶음이 `400`이면 그 줄은 `outbox.rejected.jsonl`로 옮긴다.
- `POST /hooks/replay`(앱): 본문은 outbox 줄(JSON Lines, 500줄 이하). 읽을 수 있는 줄(`Outbox.parse`)만 저장 폴더의 `replay/outbox.jsonl` 끝에 한 번의 `O_APPEND` 쓰기로 붙인 뒤 바로 `200 {"accepted":n,"rejected":m}`(원격은 200을 받아야 줄을 지운다). 읽을 수 있는 줄이 없거나 상한을 넘으면 `400`, 붙이지 못하면 `500`, POST가 아니면 `405`.
- 처리(앱, `RemoteReplay`·`AppServices+Replay`): 메인 큐 한 차례에 0.1초(적어도 한 줄)씩 실시간 훅과 같은 경로(`HookProcessor.handle(_:)`, 블록 없음)로 처리하고 남으면 다음 차례로 넘긴다(`Outbox.drain`의 `deadline`, 남은 줄은 떼어 낸 파일에 다시 써서 순서 유지). 그사이 온 로컬 훅이 먼저 처리된다. 저장에 실패하면 그 줄부터 남기고 10초 점검에서 다시 한다. 같은 묶음을 다시 받아도 `tool_use_id`·`prompt_id`/`turn_id`로 한 번만 남는다. 처리한 줄은 outbox 흡수 지표(`recordAbsorb`)에 센다. 앱을 다시 켜면 남은 줄부터 이어 간다.
- 순서(앱): replay 줄이 남은 동안 `SessionStart`·`UserPromptSubmit` 밖의 실시간 훅은 처리하지 않고 `replay/outbox.jsonl` 뒤에 붙인 뒤 `204`(`HookRouter.defersWhileDraining`, `Outbox.line`).
- Mac 로컬 outbox(원격 모드 아님)는 전과 같이 앱이 직접 흡수한다. 스크립트는 건드리지 않는다.

앱 서버는 계속 `127.0.0.1`에만 열린다. SSH는 원격 포트 포워딩(`RemoteForward 47821 127.0.0.1:47821`), Docker Desktop 컨테이너는 `host.docker.internal`로 닿는다.

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
- `--allowedTools 'mcp__waypoint__*'`로 도구 8개가 모두 허용됐다(당시 개수. 지금은 아래 표 13개). 도구는 지연 로딩되어 Claude가 `ToolSearch`로 불러 쓴다.
- 스킬은 `~/.claude/skills/tracker/SKILL.md`에서 `-p` 세션에도 불렸다(주입 블록 + 「PRB-1 하자」에 `Skill(tracker)`가 먼저 호출됨).

### 도구

`project`는 키(대소문자 무시) 또는 폴더 경로(가장 가까운 상위 `rootPath`). `id`는 `PRB-1` 꼴 표시 ID. 모든 스키마는 `additionalProperties: false`.

| 도구 | 입력(필수 굵게) | 동작 |
|---|---|---|
| `project_resolve` | **`cwd`**, `remote` | 폴더 → `{key, name, summary, rootPath}`, 없으면 `null`(오류 아님). `cwd`가 어떤 등록 폴더와도 맞지 않고 `remote`(git origin 주소)가 있으면 같은 원격 주소의 등록 프로젝트(로컬 작업 트리가 하나일 때, 그 작업 트리의 가장 바깥 프로젝트). 6장 「원격·컨테이너 수집」 |
| `project_init` | **`cwd`**, **`name`**, `key`, `summary`, `stack`, `guideFiles`, `seedCards` | 앱에 등록 확인 창을 띄우고 바로 `pending`으로 답한다(아래 「project_init」) |
| `card_list` | **`project`**, `status`, `query` | status를 안 주면 done·archived를 뺀다. 순서: active → next → idea → done → archived, 같은 상태는 번호순. `query`는 ID·제목·본문 부분 일치 |
| `card_get` | **`id`** | 카드 + `body`, `origin`, `nextSessionNote`, `children`, 최근 기록 20개 |
| `card_create` | **`project`**, **`title`**, `kind`, `status`, `body`, `parentId`, `criteria`, `sessionId` | origin=claude, `originSessionId`=`sessionId`. 기본 kind task, status next(kind idea면 idea). `active`는 거부(만든 뒤 `card_start`). `parentId`는 같은 프로젝트. `card.created` 기록 |
| `card_start` | **`id`**, **`sessionId`** | 세션이 없거나 끝났거나 프로젝트가 다르면 오류. 그 세션에 붙은 **다른** 카드 연결을 먼저 푼다(주제 전환 — 그 카드는 작업 전 상태로, done 아님). 그다음 연결 → 작업중. 같은 카드를 다시 부르면 아무 일 없음. 서브에이전트 세션 ID(`agent_id`)면 그 하위 세션에 붙인다. 결과: `card`, `detached`(풀린 카드 ID), `otherSessions`(같은 카드에 붙은 다른 살아 있는 세션) |
| `card_update` | **`id`**, `title`, `body`, `status`, `criteria` | `status: active`는 거부(작업중은 `card_start`로만). 다른 상태는 `CardLifecycle.move`(done이면 `doneAt`, active였으면 열린 세션 연결을 모두 닫는다 — 4장 불변식). `criteria`는 통째로 바꾼다. 체크가 바뀐 조건(같은 글의 체크 변경, 체크된 채 새로 생긴 조건)마다 앱의 체크 상자와 같은 `note` `{kind: "criterion", text, isDone}`을 남긴다 |
| `card_note` | **`id`**, **`text`** | `note` 기록 `{text}` |
| `card_handoff` | **`id`**, **`nextSessionNote`** | `nextSessionNote` 저장 + `note` 기록 `{kind: "handoff", text}` |
| `project_status` | **`project`**, `text`, `sessionId`, `provider` | `text`가 있으면 지금 상황을 새로 쓴다: 줄마다 앞뒤 공백을 다듬고 빈 줄을 뺀 뒤 600자·8줄을 넘거나 비면 오류(자르지 않는다 — 에이전트가 줄여 다시 보내게). `project.status` 기록(`provider`는 세션이 있으면 세션의 도구). `text`가 없으면 읽기. 결과 `{project, status: {text, at, provider?, sessionId?, stale} \| null}` |
| `work_file` | **`sessionId`**, `cardId` | 정리 안 된 작업 하나를 처리(4장). `sessionId`는 전체 ID 또는 앞부분 8자 이상(메인 세션 중 하나만 맞아야 함). 끝나지 않은 세션·카드에 붙은 적 있는 세션·이미 이은 세션·이미 넘긴 세션을 다시 넘김·다른 프로젝트·보관된 카드는 오류(넘긴 세션은 나중에 카드에 이을 수 있다). `cardId`가 있으면 기록을 카드로 옮기고 `session.filed`(`filed`), 없으면 `session.filed`(`dismissed`). 카드 상태는 바꾸지 않는다. 결과 `{sessionId, outcome, cardId?, files?, moved?}` |
| `github_issue_create` | **`project`**, **`title`**, `body`, `labels`, `cardId`, `sessionId` | 프로젝트 폴더 `origin`의 GitHub 저장소에 이슈를 연다(「GitHub 이슈·PR 열기」 절). 결과 `{number, url, title, state, cardId?}` |
| `github_pr_create` | **`project`**, **`title`**, `body`, `base`, `head`, `draft`, `cwd`, `cardId`, `sessionId` | 같은 저장소에 PR을 연다. push하지 않는다. `head` 기본은 `cwd`(없으면 프로젝트 폴더) 작업 트리의 현재 브랜치, `base` 기본은 저장소 기본 브랜치. 결과는 위와 같고 `state`는 `open`·`draft` |
| `card_evidence` | **`id`**, `criterion`, **`command`**, **`outcome`**, `detail`, `sessionId` | 에이전트 보고 근거 `check`(`source: agent`). `criterion`은 **1부터**(card_get `criteria` 순서, 저장은 0부터 + 조건 글), 빼면 카드 수준. 범위 밖·조건 없는 카드에 번호·정수 아님은 오류. `outcome`은 `pass`·`fail`·`skipped`(일부러 건너뛴 경우만). `detail` 200자. 결과 `{id, outcome, source, criterion?, state?, confirmed?}`(`confirmed`: 훅 기록과 짝지어져 「확인됨」인지) |

`criteria`는 `[{text, done?}]`(문자열 항목도 받는다). `status: done`은 스킬이 사용자 확인을 받은 뒤에만 보낸다. 카드 결과는 `{id, title, kind, status, criteria, updatedAt, parentId?, sessions?}`(`sessions`는 붙어 있는 끝나지 않은 세션).

**`overlaps`(TRK-17)**: `card_start`·`card_update`·`card_note`·`card_handoff`·`card_evidence`·`project_status` 결과가 객체이고 알릴 같은 파일 작업 중(4장)이 있으면 붙는다. 훅 출력은 늘리지 않는다.
- 누구의 눈으로: `sessionId`를 주면 그 세션, 아니면 카드에 붙은 끝나지 않은 세션(`project_status`는 `sessionId`가 있을 때만). 메인과 그 서브에이전트가 같이 있으면 메인만.
- 항목 `{sessionId: 상대 메인 세션 짧은 ID(앞 8자, Codex는 codex:), provider, cards?: 상대가 붙은 카드 ID, files: 최근 것부터 최대 5, fileCount}`.
- 빈도: `<내 세션>|<상대 메인 세션>`마다 이미 알린 파일을 앱 메모리에 둔다. 지금 겹친 파일이 모두 알린 것이면 붙이지 않고, 새 파일이 끼면 그 상대의 전체 목록을 다시 붙인다. 앱을 다시 켜면 처음부터 센다. 없으면 키째 없다.

`sessionId`는 `SessionStart` 훅이 주입한 블록의 `sessionId:` 줄에서 Claude가 읽어 전달한다.

### project_init

`/tracker init`에서만 부른다. 도구는 사용자의 확인을 기다리지 않는다. `project_init` 뒤 스킬은 지침 파일이 「절 머리 + 한 줄에 지침 하나」 꼴이 아니면 대상 파일·줄 수와 그 파일에서 뽑은 전/후 예시 하나를 보여 주고 다듬을지 한 번만 묻는다(TRK-65). 큰 저장소에서는 그 자체가 큰 작업이라 묻지 않고 하지 않는다. 동의하면 뜻은 그대로 구조만 다듬고 diff 확인 뒤에만 커밋한다. 앱은 관여하지 않는다(다듬는 것은 에이전트).

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


- 출처: Claude Code가 상태줄 명령 stdin에 넘기는 JSON의 `rate_limits.five_hour` / `rate_limits.seven_day`(`used_percentage` 0–100, `resets_at` 유닉스 초). 사용자의 상태줄 명령 앞에 중계 스크립트 `integration/statusline/waypoint-statusline-tap.sh`를 끼운다. 스크립트는 입력에 `rate_limits` 객체가 있으면 저장 폴더에 `usage.json`을 원자적으로 쓰고(임시 파일 → `mv`, jq 필요), 같은 입력을 원래 명령에 넘겨 출력을 그대로 내보낸다. 같은 jq 호출에서 세션 이름·컨텍스트 사용률도 뽑아 `session-status.json`에 쓴다(아래). jq가 없거나 쓰기에 실패해도 상태줄 출력은 그대로 나온다. 추가 시간은 약 10 ms(jq 한 번 + 파일마다 `mv` 한 번).
- 파일: `~/Library/Application Support/Waypoint/usage.json`(`WAYPOINT_SUPPORT_DIR`로 바꿀 수 있음), 한 줄 `{"capturedAt":<unix 초>,"rateLimits":<rate_limits 원본>}`.
- 세션 이름 · 컨텍스트 사용률: 같은 입력의 `session_id`(훅의 `session_id` = `Session.id`), `session_name`(`--name`·`/rename`으로 붙인 이름이나 AI가 만든 제목. 없을 수 있다), `context_window.used_percentage`(0–100, 없거나 null일 수 있다)를 같은 폴더의 `session-status.json`에 쓴다. 한 줄 `{"<session_id>":{"at":<unix 초>,"name":"…","context":62.5},…}`. 스크립트는 자기 세션 항목만 바꾸고(`name`은 앞 200자, 입력에 없는 값은 키도 없다), `at`이 24시간 넘은 항목은 쓸 때 뺀다. `session_id`가 없으면 이 파일은 건드리지 않는다. 임시 파일 → `mv`라 여러 세션이 동시에 써도 깨진 파일은 남지 않고, 겹치면 나중에 쓴 쪽이 남는다(밀린 항목은 그 세션의 다음 갱신 때 다시 들어온다). 비용(`cost.*`)은 남기지 않는다.
  - 읽기: `Shared/Usage/SessionStatusSnapshot.swift`가 파싱하고 `UsageMonitor`가 `usage.json`과 같이 30초마다 수정 시각을 보고 다시 읽는다. 저장소(SwiftData)에 넣지 않으므로 iCloud로 가지 않고 iPhone에는 보이지 않는다.
  - 화면(macOS): 상황판 작업 타일·보드의 세션 타일·작업중 카드 안 세션 상자에서 세션 표시 자리(「sess·7f2a」)에 이름을 보인다(이름이 없으면 그대로 「sess·7f2a」, 요청 문장 자리는 그대로). 그 옆에 작은 글 「컨텍스트 62%」(반올림, 0–100), 80% 이상이면 `liveText`로 진하게. `at`이 3시간 넘은 사용률은 숨기고 이름은 계속 쓴다(`SessionStatusSnapshot.contextStaleAfter`). 값이 없으면 자리를 차지하지 않는다. MCP·훅 블록·iPhone의 세션 표시는 「sess·7f2a」 그대로다.
- 설치: 앱 안 연동 설치기가 한다(아래 「앱 안 연동 설치기」 절). 손으로 할 때는 스크립트를 `~/.claude/waypoint/`에 복사하고 `chmod +x`, `~/.claude/settings.json`의 `statusLine.command`를 `bash ~/.claude/waypoint/waypoint-statusline-tap.sh <원래 명령>`으로 바꾼다(예: `bash ~/.claude/waypoint/waypoint-statusline-tap.sh bash ~/.claude/awesome-statusline.sh`). 원래 명령은 인자 대신 환경 변수 `WAYPOINT_STATUSLINE_NEXT`(셸 명령 문자열)로 줘도 된다. 되돌리려면 `statusLine.command`를 원래 명령으로 돌린다.
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

`docs/DESIGN.md` 참조. 대시보드 / 지침(출처 목록) / 프로젝트 보드 / 카드 상세 / 지침 문서 / 새 프로젝트 등록 창 / 연결 설정(온보딩) / iPhone 작업중.

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

### 앱 안 연동 설치기 (2026-10-02, TRK-43)

Claude·Codex 연동 설치를 앱 코드(`Shared/Integration/Installer/`)로 옮겼다. 화면은 온보딩(아래 「온보딩」, TRK-44)이다. 셸·파이썬 스크립트는 개발용으로 남고, 기준은 앱 설치기다.

- 자원: 훅 스크립트·상태줄 중계·Codex 브리지·tracker 스킬은 앱 번들 리소스(macOS)다. `project.yml`이 저장소 `integration/`의 파일을 빌드 때 그대로 복사한다(`IntegrationSources.bundle`, 테스트는 `repository`).
- 두 단계: **계획**(`IntegrationInstaller.plan`)은 읽기만 하고 대상 파일마다 지금 내용과 바꿀 내용을 담는다. 내용·권한이 같으면 넣지 않으므로 이미 설치된 상태에서는 빈 계획이다. **적용**(`apply`)은 ① 계획 이후 파일이 바뀌었으면 아무것도 쓰지 않고 멈춤 ② 대상 파일 전부 백업 ③ 차례로 원자적 쓰기(같은 폴더 임시 파일 → 권한 → `rename`, 심볼릭 링크는 가리키는 파일에 씀) ④ 하나라도 실패하면 이미 쓴 파일을 이전 내용·권한으로 되돌리고 새로 만든 빈 폴더를 지운 뒤 오류. 파일 단계가 끝난 뒤 명령 단계(MCP 등록)를 돈다.
- 백업: `<저장 폴더>/integration-backups/<UTC 시각>-<8자>/`(0700)에 사본(0600, `01-settings.json` 꼴)과 `paths.json`(사본 이름·원래 경로·권한, 없던 파일은 `file: null`). 계획마다 하나.
- 대상 인스턴스: `AppInstance`. 평소용은 47821·`Waypoint`, Dev는 47822·`Waypoint-Dev`. 한 번에 하나만 사용자 범위에 잇는다(Dev로 설치하면 평소용 항목을 바꿔 끼운다).
- 멈춤·건너뜀: 설정 파일을 읽을 수 없으면(JSON·TOML 아님, `hooks`가 객체 아님) 아무것도 쓰지 않고 멈춘다. Claude 쪽에서 사용자 것과 겹치는 단계(같은 이름의 다른 tracker 스킬, 다른 주소의 `waypoint` MCP, 명령이 아닌 상태줄, 손으로 고친 중계 명령)는 그 단계만 건너뛰고 `notes`에 남긴다. Codex 쪽은 파이썬 설치기와 같이 멈춘다.

Claude Code:

| 대상 | 설치·재설치 | 해제 |
|---|---|---|
| `~/.claude/settings.json` `hooks` | 10개 이벤트(`settings.example.json`과 같은 차례·matcher)에 Waypoint 훅. 명령에 `/.claude/waypoint/waypoint-hook.sh`가 든 것만 Waypoint 것으로 본다. 이벤트에 Waypoint 훅이 정확히 하나이고 명령·`timeout: 2`가 같고 matcher가 같은 뜻(없음·`""`·`"*"`은 모든 도구)이면 그 이벤트는 손대지 않는다. 아니면 Waypoint 훅만 빼고 첫 자리(없으면 끝)에 새 묶음을 넣는다. 다른 훅·키 순서는 그대로 | Waypoint 훅만 뺀다. Waypoint 훅만 있던 묶음·이벤트는 지우고 `hooks`가 비면 키를 지운다. 설치 전 사용자 설정은 바이트까지 돌아온다. 설치기가 새로 만든 파일이면 `{}`로 남는다 |
| `statusLine` | 없으면 중계만(`bash ~/.claude/waypoint/waypoint-statusline-tap.sh`, 출력 없음. 사용량 게이지용). 다른 명령이면 중계로 감싼다: 셸 특수 문자가 없으면 뒤에 그대로, 있으면 `bash -c '<원래 명령>'`. 이미 감쌌으면 그대로 | 감싼 꼴에서 원래 명령을 되찾아 돌린다. 중계만 있었으면 `statusLine`을 지운다 |
| `~/.claude/waypoint/waypoint-hook.sh`, `waypoint-statusline-tap.sh` | 번들 내용, 0755 | 남긴다(열린 세션이 파일 누락으로 실패하지 않게) |
| `~/.claude/skills/tracker/SKILL.md` | 번들 내용(머리말 `name: tracker`이고 Waypoint를 말하는 옛 판은 덮어씀) | Waypoint tracker 스킬이면 지우고, 비게 된 폴더도 지운다 |
| MCP `waypoint`(사용자 범위) | `~/.claude.json`은 읽기만. 없으면 `claude mcp add --transport http --scope user waypoint <url>`, 다른 포트의 Waypoint 주소면 `claude mcp remove waypoint -s user` 뒤 추가, 같으면 그대로 | Waypoint 주소면 `claude mcp remove waypoint -s user` |

- JSON은 키 순서와 숫자 원문을 지키는 자체 해석기(`OrderedJSON`)로 읽고 쓴다. 바뀔 것이 있을 때만 다시 쓰며, 그때 들여쓰기(원문 둘째 줄)와 끝 줄바꿈은 원문을 따른다. 문자열 이스케이프는 표준 꼴(`é` → `é`, `\/` → `/`)로 바뀔 수 있다.
- `claude` 실행 파일은 `ToolLaunch`의 탐색 폴더에서 찾고, PATH 앞에 그 폴더와 흔한 설치 폴더를 붙여 실행한다(launchd PATH 대비, 20초 제한). 못 찾으면 그 단계만 「실행 파일 없음」(`executableMissing`)으로 남고 파일 단계는 적용된 채다(`Result.isPartial`). 다시 계획하면 MCP 단계만 남는다.

Codex: `scripts/install-codex.py`를 그대로 옮겼다(`CodexInstallPlanner`). 같은 입력에서 `hooks.json`·`config.toml`·스크립트·스킬이 바이트·권한까지 같고 `install.json`은 `backup` 경로만 다르다(테스트가 임시 홈에서 파이썬과 비교한다). Codex는 훅을 해시로 신뢰하므로(`[hooks.state]`) 다시 설치해도 같은 `hooks.json`이어야 신뢰가 풀리지 않는다.

- 다른 점: 백업은 위 저장 폴더에 남기고, 바뀔 것이 없으면 아무것도 쓰지 않는다(파이썬은 매번 모든 파일과 `install.json`의 백업 경로를 다시 쓴다).
- 해제는 파이썬과 같다: `config.toml`은 표시 블록만 빠져 TOML 값은 설치 전과 같지만 끝에 빈 줄 하나가 남는다(설치 때 끝 공백을 지우고 빈 줄 둘을 붙인 몫). 스크립트·`install.json`은 남는다.
- `config.toml`은 설치기에 필요한 것만 읽는 작은 TOML 해석기(`MiniTOML`)로 본다: 구조 오류, 표시 블록 밖의 `mcp_servers.waypoint`, `features.hooks = false`. 날짜·숫자 꼴 검사는 `tomllib`보다 느슨하다.

### 온보딩 (2026-10-02, TRK-44)

셸 명령 없이 처음 설정부터 첫 기록 확인까지 끝내는 메인 창 시트(「Waypoint 연결」, `macOS/Onboarding/`). 단계 판정은 순수 타입 `OnboardingProgress`(`Shared/Onboarding/`)가 한다.

1. **도구**: Claude Code·Codex(둘 다 기본 선택). 도구마다 지금 연결 상태(`IntegrationInstallation`). 연결돼 있으면 그 자리에서 「다시 설치」「연결 해제」 — 둘 다 계획을 펼쳐 보이고 확인 버튼으로 적용한다.
2. **연결**: 고른 도구마다 설치 계획(파일 `~` 경로 · 새로 만듦/바꿈/지움, Claude Code 등록, 건너뛴 단계)을 보이고 「연결」로 적용한다. 계획이 비면 「이미 연결됨」. 성공하면 「백업 보기」(Finder)와 도구 쪽 한 줄(Claude Code는 새로 연 세션부터 기록, Codex는 새로 연 Codex의 `/hooks`에서 Waypoint 신뢰). 설치기 오류(`IntegrationInstallError`)는 화면용 원인 문장(예: 「설정 파일을 읽을 수 없음 · ~/.claude/settings.json」, 「다른 Waypoint 등록이 있어 그대로 둠」) + 「다시 시도」. 도구 상태도 `IntegrationInstallation.detail` 대신 「연결 일부 빠짐」「다른 Waypoint에 연결됨」 같은 말로 보인다(`OnboardingText`, 원문은 연동 상태 패널에 그대로), 부분 실패(`isPartial`, 예: `claude` 실행 파일 없음)는 안 된 단계 + 「다시 시도」. 다시 시도는 다시 계획해 바로 적용한다(이미 확인한 일이고, 끝난 도구는 빈 계획이라 건너뛴다). 계획 중 한 도구라도 오류면 적용하지 않는다.
3. **프로젝트**: 「폴더 고르기…」(NSOpenPanel). 등록된 폴더면 그 프로젝트를 고른 것으로 보고, 아니면 그 폴더로 `ProjectDraft.folder`(이름 = 폴더 이름, 키 = `ProjectKey.suggest`, 지침 문서 = 폴더 바로 아래 `AGENTS.md`·`CLAUDE.md`·`.claude/CLAUDE.md` 중 있는 것, 개요·스택·카드는 비움)를 만들어 기존 등록 창(`InitSheetView`)에 넣는다. 그 옆 「/tracker init 복사」는 명령을 클립보드에 넣는다(그 폴더의 Claude Code·Codex에서 등록할 때). 보관된 프로젝트의 폴더면 막고 까닭을 보인다. 등록된 프로젝트가 이미 있으면 고르지 않아도 넘어간다.
4. **첫 기록**: 고른 도구마다 기다린다. 온보딩을 연 시각 이후 활동(`IntegrationReceipt.at`)의 기록이고 프로젝트에 연결된 것이 오면 끝 화면(도구 · 프로젝트 키 · 시각)이 된다. 등록 밖 폴더의 기록이면 그 사실을, 서버가 준비되지 않았으면(`serverState != .ready`) 그 까닭과 「다시 시도」(`retryIntegration`)를 보인다. 이 단계와 연결 단계는 2초마다 연결 상태를 다시 읽는다. 끝은 사용자가 「끝」을 눌러야 한다(자동으로 닫지 않는다).

- 앞 단계가 막히면(도구 없음·연결 안 됨·확인 필요·프로젝트 없음) 뒤 단계를 요청해도 그 단계를 보인다. 「다음」은 그 단계가 막히지 않았을 때만.
- 메인 창이 여럿이면 먼저 뜬 창 하나에만 시트가 뜬다(그 창이 닫히면 다음 창).
- **진입점**: 첫 실행 자동 표시(등록된 프로젝트가 보관 포함 하나도 없고 「끝」을 누른 적이 없을 때, UserDefaults `onboarding.completed`), 연동 상태 패널의 「연결 설정」, 메뉴 막대 「연결 설정…」. 「닫기」는 끝낸 것으로 기억하지 않는다.
- **Dev 제한**: Dev 앱(`AppInstance.isDev`)이 실제 홈에 설치·해제하면 평소용 연결이 47822로 바뀌어 평소용 기록이 끊긴다. 그래서 Dev는 연결이 다 된 상태가 아니면 연결 단계에서 막히고(「Waypoint Dev는 평소용 연결을 바꾸지 않음」), 도구 단계의 다시 설치·연결 해제도 비활성이다(`IntegrationHomePolicy.installBlock`, 링크를 푼 경로로 비교). Debug 빌드는 `WAYPOINT_INTEGRATION_HOME`이 있으면 그 폴더를 홈으로 써서(설치기 컨텍스트·`IntegrationMonitor` 둘 다) 설치를 허용한다. Release는 이 변수를 무시한다.

### 로그인할 때 열기 (2026-10-03, TRK-55)

앱이 `SMAppService.mainApp`(macOS 13+)으로 자기 자신을 로그인 항목에 등록·해제한다. System Events·Apple Events는 쓰지 않는다. 판정은 순수 타입 `LoginItemPolicy`, 상태·기억은 `LoginItemController`(`Shared/Instance/LoginItem.swift`), 실제 등록은 `SystemLoginItemService`(`macOS/Settings/`).

- **저절로 켜기**: 온보딩 「끝」에서 켠다. 실행 때는 기존 사용자(등록된 프로젝트가 있거나 `onboarding.completed`)이거나 설치 스크립트가 옛 항목을 지웠다는 표시가 있으면 켠다. 처음 쓰는 사람은 실행 때 켜지 않고 「끝」을 기다린다.
- **한 번만**: 저절로 켜기가 성공하면 `loginItem.autoApplied`를 남기고 다시 하지 않는다. 시스템 설정에서 끈 것을 되살리지 않는다. 등록이 실패하면 남기지 않아 다음 실행 때 다시 해 본다. 이미 켜져 있거나 승인 대기면 등록하지 않고 표시만 남긴다.
- **사용자 선택**: 설정 「일반」 탭의 「로그인할 때 열기」를 한 번이라도 바꾸면 `loginItem.userChoice`(켬·끔)를 남기고, 그 뒤로는 저절로 켜지 않는다.
- **Dev**: 등록하지 않고 상태도 읽지 않는다. 토글은 꺼짐·비활성.
- **화면**: 토글은 실제 상태를 따른다(켜짐 = `enabled`·`requiresApproval`). 아래 줄에 「켜짐」「꺼짐」「승인 필요」, 등록·해제가 실패하면 「바꾸지 못함」. 승인 필요면 「시스템 설정에서 허용」(`SMAppService.openSystemSettingsLoginItems()`). 앱이 앞으로 올 때마다 상태를 다시 읽는다.
- **옛 항목**: `scripts/install-local.sh`가 앱을 실행하기 전에 System Events로 만든 옛 항목 「Waypoint」를 지우고, 지웠으면 `defaults write dev.antaeho.waypoint WaypointLoginItemLegacyRemoved -bool true`를 남긴다. 앱은 실행 때 이 값을 읽고 지운다. 스크립트는 새 방식 항목을 만들지 않는다.

### 자동 업데이트 (2026-10-03, TRK-56)

macOS 앱만. Sparkle 2.10.0(SwiftPM, 사용자 승인)의 표준 화면(`SPUStandardUpdaterController`)이 새 판 찾기·내려받기·서명 확인·설치·재실행을 맡는다. 판정은 순수 타입 `UpdateFeed`(`Shared/Instance/UpdateFeed.swift`), 앱 쪽은 `AppUpdater`(`macOS/Update/`). 배포·서명 키·공개 절차는 [RELEASE.md](RELEASE.md) 「자동 업데이트」.

- **꺼짐 조건**: Info.plist `SUFeedURL`(빌드 설정 `WAYPOINT_FEED_URL`)이 비었거나 `http`·`https` 주소가 아니거나, `SUPublicEDKey`가 32바이트 base64가 아니면 `UpdateFeed`가 nil이고 Sparkle을 시작하지 않는다. 메뉴·설정 항목도 없다. 기본값은 빈 주소라 평소용·Dev·피드 없이 만든 배포 빌드는 모두 꺼진다. 샘플 모드(`-WaypointSampleData`)도 꺼진다.
- **켜질 때**: 배포 스크립트 `--feed-url`로 만든 빌드. 저절로 확인은 기본 켬(Info.plist `SUEnableAutomaticChecks`, Sparkle 기본 간격 하루) — 그래서 Sparkle의 「자동으로 확인할까요」 질문 창은 뜨지 않는다. 새 판이 있으면 Sparkle 창이 릴리스 노트와 함께 알리고, 사람이 고른다. 그 창의 「자동으로 내려받아 설치」를 고르면 다음부터는 뒤에서 받아 두었다가 앱을 끌 때 바꾼다.
- **화면**: 메뉴 막대 메뉴 「업데이트 확인…」(「연결 설정…」 아래), 설정 「일반」 탭 「자동으로 업데이트 확인」 토글과 「지금 확인」. 확인·설치가 진행 중이면 두 버튼이 비활성(`canCheckForUpdates`).
- **안전**: 서명(EdDSA)이 맞지 않는 zip은 설치하지 않는다. 설치가 실패하면 옛 앱이 남는다. 새 빌드가 처음 열릴 때 저장소를 백업한다(TRK-46 `store-version.json`, `upgrade`). 앱은 업데이트 서버에 피드·zip 요청 말고는 보내지 않는다(시스템 정보 전송 `SUEnableSystemProfiling` 끔 — Sparkle 기본).

### 기록 지표와 진단 내보내기 (2026-10-01, TRK-11)

이 기기에서만 숫자와 시각을 모은다(`ReliabilityMetrics`, 저장 폴더 `metrics.json` 0600, 10초 점검 때 저장, CloudKit 아님): 실시간 훅의 수신(서버가 연결을 받은 시각)→저장·화면 반영 지연 최근 1000건, 재개 시간(재개 문맥을 처음 복사한 시각 → 그 카드에 같은 도구의 새 메인 세션이 연결된 시각, 최근 100건), 연동 실패(서버 시작·형식 오류·저장 실패), 복구(outbox 흡수·보존·격리, 세션 정리) 횟수. 연동 상태 패널에 짧게 보이고, 「진단 정보 복사」를 누를 때만 같은 숫자를 내보낸다. 프로젝트명·경로·세션 ID·대화는 담지 않는다. `/integration/status`가 `metrics`로 돌려준다. 기준·측정 방법·관측값은 docs/RELIABILITY.md.

### 자동 갱신 지표 (2026-10-02, TRK-62·63)

에이전트가 일하면서 기록을 얼마나 갱신했는지 본다(`TrackingCoverage`, 순수 함수, 저장하지 않고 요청 때 저장소에서 계산). 최근 14일(`RecordRetention.days`, 그보다 오래된 파일 변경·카드 없는 세션은 지워져 셀 수 없다), 보관 안 된 프로젝트별, 세션은 마지막 활동(`lastSeenAt`)이 기간 안인 끝난 메인 세션.

- 카드 연결: 파일을 바꾼 세션(세션·서브에이전트의 `file.changed`가 있음) 중 카드에 붙은 적이 있거나 `work_file`로 처리한(연결·넘김 모두) 세션 / 파일을 바꾼 세션.
- 메모 갱신: 카드에 붙은 세션 중 세션 동안(`startedAt`…`endedAt`) 붙었던 카드에 `card_note` 메모·다음 세션 메모·완료 조건 체크 변경(`note` kind 없음·`handoff`·`criterion`)이나 에이전트 검증 보고(`check` `source: agent`)가 하나라도 남은 세션 / 카드에 붙은 세션. `card_note`·`card_handoff`는 세션을 적지 않으므로 시각으로 가른다.
- 상황 경과: 마지막 `project.status` 이후 일수(없으면 없음).
- 내보내기: 숫자와 프로젝트 키만. 「진단 정보 복사」 끝에 `자동 갱신 (최근 14일)` · `전체: 카드 연결 a/b · 메모 갱신 c/d` · 프로젝트마다 `<키>: 카드 연결 … · 메모 갱신 … · 상황 N일 전|오늘|없음`. `/integration/status`의 `coverage` `{windowDays, projects: [{key, workedSessions, linkedSessions, linkRate, attachedSessions, notedSessions, noteRate, statusAgeDays}]}`(분모 0이면 비율 `null`). 연동 상태 패널 「기록 지표」에 `최근 14일 · 카드 연결 a/b · 메모 갱신 c/d`, `지금 상황 · 7일 안에 갱신 x/y 프로젝트`(패널을 열 때 한 번 계산).
- 시작 블록 지연(2026-10-02, Dev Debug, `SessionStart` 새 세션 → 끝을 반복해 왕복을 잼, 확인 머리 있음): 같은 저장소에서 main과 이 변경을 30회씩 번갈아 6번 — 중앙값 평균 218 → 233 ms, p95 평균 386 → 407 ms(회차마다 134–289 ms로 흔들려 차이는 잡음 안), 최대 595 ms(main)·528 ms(이 변경). 블록 생성만 따로 재면(저장소 사본, swift test Debug) 끝난 메인 세션 732개·카드 없는 파일 변경 1,279건인 Dev 실측 저장소에서 정리 안 된 작업 17 ms, 실제 저장소 백업 사본(메인 세션 9개)에서 0.5–1 ms. 첫 구현(세션마다 관계를 따라감)은 Dev 저장소에서 280 ms라 질의를 바꿨다.

### 이벤트 기반 작업 상태 (2026-09-30)

`Session.activityRaw`, `activityAt`, `pendingToolsData`, `endReason`를 추가한다. 기존 stateRaw 캐시와 live/stalled/ended API는 호환을 유지한다. 이전 세션은 마지막 활동만 아는 경우 「최근 활동」 또는 「활동 없음」으로 표시한다.

- SessionStart/Stop/Interrupt → 입력 대기, UserPromptSubmit → 응답 진행 중. 응답 진행이 15분 넘게 갱신되지 않으면 활동 없음.
- PreToolUse → 도구 작업 중(tool_use_id별 목록), PermissionRequest → 승인 대기. 질문 도구 AskUserQuestion/request_user_input → 입력 대기.
- PostToolUse → 해당 도구 종료. Claude의 PostToolUseFailure도 종료한다. Codex는 공식 지원 이벤트만 설치한다. 다른 병렬 호출이 남아 있으면 도구 작업 중을 유지한다. 늦은 완료는 해당 호출만 제거하고 최신 시각을 되돌리지 않는다.
- 진행 중인 하위 작업이 있으면 부모도 작업 중으로 표시한다. 전체 프로세스 종료가 확인되면 세션 종료, PID 없는 활동 유효기간이 끝나면 추적 만료다. 둘 다 카드를 자동 완료하지 않는다. 카드 연결 해제 기록에 종료 이유를 보존해 재개 후에도 과거 추적 만료 표시는 바뀌지 않는다.
- 입력·승인 대기는 작업 실패를 뜻하지 않는다. PID가 없는 세션의 30분 추적 유효기간은 그대로 적용한다.

훅은 관찰만 하며 승인 허용/거절 결정을 출력하지 않는다. Claude·Codex 공식 훅 문서를 확인하여 tool_use_id·PermissionRequest와 전체 matcher를 사용한다. Codex 훅 정의를 바꾸면 /hooks에서 재신뢰가 필요하다.

## 지침·기억 출처 (2026-10-01, TRK-37)

Claude·Codex가 읽는 지침과 기억 파일을 찾아 목록으로 보인다. 수집은 읽기만 하고 아무것도 쓰지 않으며(프로젝트 안 지침 고치기는 TRK-40), 모은 결과는 저장하지 않는다(SwiftData 모델 없음). 수집은 `GuidanceCollector`(입력: 홈, Claude 홈, Codex 홈, 등록 프로젝트 `(key, rootPath)`, 파일 시스템 `GuidanceFileSystem`) → `GuidanceSnapshot`(출처: 종류·도구·경로·묶음·걸리는 프로젝트 키·크기·수정 시각·항목 수).

### 찾는 곳

| 묶음 | Claude | Codex |
|---|---|---|
| 전역 | `/Library/Application Support/ClaudeCode/CLAUDE.md`(관리 정책), `~/.claude/CLAUDE.md`, `~/.claude/rules/**/*.md` | `~/.codex/AGENTS.override.md`, `~/.codex/AGENTS.md`, `~/.codex/rules/*.rules`(명령 규칙), `~/.codex/memories_1.sqlite`(내부 기억) |
| 상위 폴더 | `CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md`, 저장소 밖 `AGENTS.md` | 저장소 안 `AGENTS.md`·`AGENTS.override.md` |
| 프로젝트 | `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`(개인), `.claude/rules/**/*.md` | `AGENTS.md`, `AGENTS.override.md` |
| 자동 기억 | `~/.claude/projects/<폴더 이름>/memory/*.md`(`MEMORY.md`는 기억 목록) | — |

- `CLAUDE_CONFIG_DIR`가 있으면 그 경로를 Claude 홈으로, `CODEX_HOME`이 있으면 그 경로를 Codex 홈으로 본다(빈 값은 없는 것으로).
- 항목 수: 기억 목록은 `- `·`* ` 줄 수, 명령 규칙은 `#`로 시작하지 않는 줄 수, Codex 기억은 행 수, 그 밖은 비지 않은 줄 수(앞 1MB만 센다).
- 같은 파일이 여러 프로젝트에 걸리면(공통 상위 폴더, 프로젝트 안의 프로젝트) 한 줄로 두고 걸리는 키를 합친다.

### 상위 폴더 규칙

- 문서(code.claude.com memory 「How CLAUDE.md files load」, 2026-10-01): Claude Code는 작업 폴더와 **그 위 모든 폴더**의 `CLAUDE.md`·`CLAUDE.local.md`를 시작할 때 읽는다(파일 시스템 뿌리부터 작업 폴더 순으로 이어 붙임). `.claude/CLAUDE.md`는 「작업 폴더 또는 그 위에 있으면 AGENTS.md 대신 읽는 파일」 목록에 있어 함께 본다. `AGENTS.md`는 위 폴더 어디에도 CLAUDE 계열 파일이 없을 때만 읽는다(기본 설정). 하위 폴더의 CLAUDE.md는 그 폴더 파일을 읽을 때 불려 이번 목록에 넣지 않는다.
- 문서(Codex AGENTS.md 안내): Codex는 프로젝트 뿌리(보통 git 뿌리)에서 작업 폴더까지 내려오며 폴더마다 `AGENTS.override.md` → `AGENTS.md` 중 하나를 읽는다. git 뿌리 위는 읽지 않는다.
- Waypoint의 결정: 등록 프로젝트 폴더(심볼릭 링크를 푼 경로)의 부모부터 **홈까지(홈 포함)** 올라간다. 홈 밖 프로젝트는 `/` 바로 아래 폴더까지. 홈의 `.claude/`는 전역 지침이라 상위 폴더로 치지 않는다. 위 폴더의 `AGENTS.md`는 그 폴더가 프로젝트의 git 저장소 안이면 Codex, 밖이면 Claude 쪽으로 표시하고, `AGENTS.override.md`는 저장소 안에서만 본다.

### 기억 폴더 이름과 짝짓기

- 이름 규칙(문서 sessions 「Where transcripts are stored」): 경로의 영문자·숫자가 아닌 글자를 모두 `-`로 바꾼다. 200자를 넘으면 200자로 자르고 경로 해시를 붙인다. 실제 폴더로 확인: `~/workspace/projects/credit_system` → `-Users-antaeho-workspace-projects-credit-system`. 글자는 UTF-16 단위로 바꾼다(한글 한 글자 → `-` 하나). `MemoryFolderName.encode`.
- 문서(memory 「Storage location」): 기억 폴더는 git 저장소 기준이라 작업 트리와 하위 폴더가 한 기억 폴더를 같이 쓰고, 저장소 밖이면 프로젝트 뿌리를 쓴다.
- 짝짓기: 폴더 이름을 ① 등록 프로젝트의 등록 경로·푼 경로·git 저장소 뿌리(`.git`이 파일이면 `gitdir:`이 가리키는 원래 저장소) → ② 상위 폴더 순으로 맞춘다. 같은 이름으로 바뀌는 프로젝트가 여럿이면(예: `a_b`와 `a-b`) 모두에 건다 — Claude Code도 한 폴더를 같이 쓴다. 200자를 넘는 경로는 해시를 다시 만들 수 없어 앞 200자 + `-`로만 맞춘다(실제 긴 경로로는 확인하지 못함).
- 맞는 곳이 없으면 「다른 폴더」에 모은다. 이름만으로는 `-`가 `/`·`_`·`.`·공백 중 무엇이었는지 알 수 없으므로 `/`부터 실제 하위 폴더를 하나씩 읽어(최대 64개 폴더) 이름이 맞는 경로를 찾고, 없으면 `-`를 `/`로 바꾼 추정에 「없는 폴더」를 붙인다(표시용).
- 빈 기억 폴더(`.md` 없음)는 보이지 않는다. 대화 기록(`*.jsonl`)은 열지 않는다.

### Codex 내부 기억 DB

- `memories_1.sqlite`의 표 `stage1_outputs`에서 행 수와 최근 50개(`source_updated_at` 내림차순)의 `thread_id`·`raw_memory` 앞 240자·시각을 읽는다. 시스템 SQLite(`import SQLite3`)로 `file:…?mode=ro` URI, `SQLITE_OPEN_READONLY`, `PRAGMA query_only = 1`. 열지 못하거나 표·열이 다르면 「읽을 수 없음」.
- Codex가 WAL로 쓰고 있어 `immutable=1`은 쓰지 않는다(WAL에만 있는 행을 놓친다). WAL을 읽을 때 SQLite가 `-shm`(공유 메모리 색인)의 읽기 표시를 고친다. 본문·`-wal`은 바뀌지 않고 새 파일도 생기지 않는다(`GuidanceReadOnlyTests`).

### 갱신

- macOS 앱(`GuidanceMonitor`)이 시작할 때, 등록 프로젝트가 바뀔 때(저장 알림), 앱이 앞으로 올 때, 지침 화면을 열 때, 감시 폴더에서 출처 파일이 바뀔 때 다시 모은다(백그라운드, 이 Mac에서 약 70 ms).
- 감시는 M4 `GuideWatcher`(FSEvents)에 경로 거르기를 더해 쓴다. 감시 폴더: Claude 홈, Codex 홈, 등록 프로젝트 폴더, 상위 폴더 — 다른 폴더 안에 든 것은 빼고, **홈 자체는 감시하지 않는다**(홈 바로 아래 `CLAUDE.md` 등은 앱이 앞으로 올 때·화면을 열 때만 다시 본다). 받는 경로: 이름이 `CLAUDE.md`·`CLAUDE.local.md`·`AGENTS.md`·`AGENTS.override.md`·`memories_1.sqlite`(·`-wal`)·`*.rules`, `memory/` 안 `.md`, `rules/` 안 `.md`, 폴더 `memory`·`rules`·`.claude`, `~/.claude/projects` 바로 아래 폴더. 대화 기록·로그·`-shm`은 디바운스 전에 버려 갱신을 미루지 않는다. 디바운스 0.5초.

### 다루지 않는 것

`autoMemoryDirectory` 설정, `CLAUDE_CODE_PROJECT_DIR_NAME`, `claudeMdExcludes`, 지침 파일 고르기 설정(`instructionFiles`), Codex `project_doc_fallback_filenames`, `@path` 가져오기, 하위 폴더 CLAUDE.md, 상위 폴더의 `.claude/rules/`, `~/.codex/skills`·Claude 스킬. 파일 편집·삭제는 없다(항목 나누기는 아래 TRK-38, 파일 쓰기는 TRK-40/41).

## 지침 항목 나누기 (2026-10-01, TRK-38)

지침 문서를 「지침 항목」으로 나누고 원문 위치를 기억한다. 순수 로직(`Shared/Guidance/`)이고 문자열만 다룬다. 파일 쓰기는 아래 「지침 항목 보기·고치기」(TRK-40, 프로젝트 안 파일)와 TRK-41(프로젝트 밖 파일·기억).

- 입력: 원문 문자열(또는 바이트)과 형식. 형식은 출처 종류에서 정한다(`GuidanceDocumentFormat(kind:)`): Markdown(CLAUDE.md·AGENTS.md·rules·CLAUDE.local.md), 기억 파일, 기억 색인(`MEMORY.md`), Codex 명령 규칙(`*.rules`). Codex 기억 DB는 나누지 않는다.
- 출력 `GuidanceDocument`: 맨 위 조각(항목 또는 항목이 아닌 줄) 배열. 조각을 이어 붙이면 원문과 **바이트까지** 같다. 항목(`GuidanceItem`): 종류, 원문 범위(UTF-8 바이트, 늘 줄 경계), 줄 번호, 원문 글(마지막 개행 제외)과 그 개행, 소속 절 머리 경로(예: `["작업 취향", "git"]`), 표시용 글, 목록 기호, 하위 항목.

### 항목 규칙(Markdown)

줄 판정(코드 울타리·절 머리·구분선·목록·표)은 보기 화면의 `MarkdownParser`와 같은 함수를 쓴다. 화면에 절 머리로 보이는 줄은 항목에서도 절 머리다.

| 종류 | 범위 |
|---|---|
| 절 머리 | `#`~`######` 한 줄. 뒤 항목의 절 경로가 된다(같거나 높은 단계가 나오면 닫힌다). `---`·`===` 밑줄 머리는 쓰지 않는다(`---`는 늘 구분선) |
| 목록 항목·번호 항목 | 기호 줄 + 그보다 깊이 들여쓴 줄(사이 빈 줄 포함). 들여쓰지 않은 줄을 만나면 끝난다(바로 붙은 줄도 새 문단). 안의 코드 울타리는 들여쓰기와 상관없이 닫는 줄까지 이 항목. 더 깊은 기호 줄은 하위 항목(부모 범위 안) |
| 문단 | 이어진 줄들(보기 화면의 문단 끝 판정과 같다) |
| 표 | 머리 줄 + 구분 줄이 한 항목(표 머리), 그 아래 줄마다 표 행 |
| 코드 블록 | 여는 울타리부터 닫는 울타리까지. 안의 `-`·`#` 줄은 항목이 아니다 |
| 인용 | 이어진 `>` 줄들 |
| frontmatter | 첫 줄 `---`부터 닫는 `---`까지(`GuidanceText.splitHeader`와 같은 판정) |

빈 줄과 구분선(`---`·`***`), 한 줄 안에서 열고 닫는 HTML 주석 하나(`<!-- … -->`)만 있는 줄은 항목이 아니다. 원문 그대로 남는다.

- **기억 파일**: frontmatter + 본문 전체가 한 항목. 머리에서 `name`·`description`(맨 위 키)과 `type`(맨 위 또는 `metadata:` 아래)을 읽는다. 표시는 설명 → 이름 → 본문 첫 줄.
- **기억 색인**(`MEMORY.md`): Markdown과 같이 나누고, 맨 위 목록 항목이 `[제목](파일)`로 시작하면 색인 줄(`link`). `MemoryIndexPairing`이 같은 폴더의 기억 파일과 파일 이름으로 짝짓는다(`./`·`#절`·퍼센트 인코딩을 걷는다). 짝 없는 색인 줄과 색인 없는 파일을 따로 돌려준다.
- **Codex 명령 규칙**: 규칙 하나가 항목 하나(보통 한 줄). 괄호(`()`·`[]`·`{}`)가 닫히지 않으면 닫힐 때까지 다음 줄을 묶는다. 문자열(`"…"`·`'…'`·`"""…"""`, 역슬래시 이스케이프) 안의 괄호와 `#`은 세지 않는다. `#` 주석 줄과 빈 줄은 항목이 아니다.

### 편집 규칙

`replace(item, with:)`·`delete(item)` → 새 문서 문자열. 다른 문서에서 나온 항목이나 낡은 항목은 `staleItem`으로 거절한다.

- **바꾸기**: 항목 글 자리(첫 줄 시작 ~ 마지막 줄 개행 앞)만 바꾼다. 그 밖 바이트는 그대로. 항목 첫 줄이 CRLF면(개행 없는 마지막 줄이면 앞 줄을 보고) 바꿀 글의 줄바꿈도 CRLF로 맞춘다. 하위 항목이 있으면 함께 바뀐다(원문 글에 하위 줄이 들어 있다). 빈 글로 바꾸면 빈 줄이 남는다(지우려면 `delete`).
- **지우기**: 항목 줄 전체와 마지막 줄 개행을 지운다(하위 항목 포함). 하위 항목만 지울 수도 있다. 빈 줄은:
  - 앞이 빈 줄(또는 문서 처음)이고 뒤도 빈 줄이면 뒤 빈 줄 하나를 함께 지운다 — 절의 마지막 문단을 지워도 빈 줄이 두 개 겹치지 않는다.
  - 앞이 빈 줄이고 뒤가 문서 끝이면 앞 빈 줄 하나를 함께 지운다.
  - 그 밖(목록 가운데 항목 등)은 항목 줄만 지운다.
  - 지운 뒤가 문서 끝이고 원문 끝에 개행이 없었으면 앞 줄의 개행도 지워 「끝 개행 없음」을 지킨다.
- 들여쓰기·목록 기호(`-`·`*`·`+`·`1.`·`1)`)·탭·한글·이모지·CRLF·UTF-8 BOM은 원문 바이트를 자르고 붙이기만 하므로 그대로 남는다.

### 애매한 문서

아래 중 하나면 나누지 않고 문서 전체를 한 항목(`document`)으로 두고 이유(`ambiguity`)를 적는다. 기준은 보수적이다.

- 닫히지 않은 코드 블록, 닫히지 않은 frontmatter(첫 줄 `---`)
- HTML 블록(문단 안 어느 줄이든 다듬은 첫 글자가 `<` + 글자·`!`·`/`·`?` — 여러 줄 주석, 문단에 붙은 주석, 뒤에 글이 더 있는 주석 줄 포함)
- 목록 들여쓰기에 탭과 공백이 섞임(문서 전체에서)
- 목록 중첩이 5단을 넘음
- 명령 규칙의 괄호가 닫히지 않거나 짝이 맞지 않음
- 다시 합친 결과가 원문과 다르거나, 항목에 들지 않은 줄이 빈 줄·구분선·한 줄 HTML 주석(규칙 파일은 주석)이 아님(안전장치)
- UTF-8로 읽을 수 없음(바이트 입력) — 이때는 편집도 막는다(`notEditable`)

### 검증

단위 테스트(종류별, CRLF, 끝 개행 없음, 3단 중첩, 코드 안 목록 기호, 표, frontmatter, 빈 문서, 애매 판정)와 속성 검사: 모든 픽스처(만든 예시, `Tests/Fixtures/guidance/`)에서 다시 합치기 == 원문, 각 항목을 지우거나 바꾼 뒤 범위 밖 바이트·줄이 그대로(지우기는 빈 줄 하나까지 예외). `GuidanceRealFileTests`는 이 Mac의 실제 지침(수집기로 찾은 Markdown·기억·`.rules`)을 읽기만 해서 같은 검사를 돌리고 경로·수만 출력한다. 내용은 저장소에 옮기지 않는다.

## 지침 항목 보기·고치기 (2026-10-02, TRK-40)

지침 문서를 항목(TRK-38) 단위로 보고, 등록 프로젝트 폴더 안의 지침 파일은 항목마다 고치고 지운다. 쓰기는 모두 8장 저장 경로(`GuideLibrary.save`: 디스크 해시 확인 → 원자적 쓰기 → `GuideVersion(app)`·`guide.synced`(app), 다르면 충돌)를 지난다. 로직은 `GuideItemEdit`·`GuideItemTarget`(`Shared/Guide/`).

- **들어가는 곳**: 프로젝트 지침 문서 화면의 「읽기 | 항목 | 편집」, 지침 화면(사이드바)의 출처 내용 「읽기 | 항목」(Codex 기억 DB 제외).
- **쓰는 대상**(`GuideItemTarget.resolve`): 등록 문서면 그 문서. 등록 프로젝트 묶음의 프로젝트 `CLAUDE.md`·`.claude/CLAUDE.md`·`AGENTS.md`(·`AGENTS.override.md`)·`CLAUDE.local.md`이고 프로젝트 폴더 아래(`GuidePaths.relativePath`, 심볼릭 링크를 푼 경로)면 처음 고치거나 지울 때 지침 문서로 등록(8장 등록: `GuideVersion(local)`, `guide.synced`(local))한 뒤 저장한다. 그 밖(전역·상위 폴더·기억·색인·Codex 파일·`.claude/rules`)은 아래 TRK-41 경로로 파일에 바로 쓴다.
- **바탕 원문**: 등록 문서는 앱 기록(`content`). 등록 전 파일은 UTF-8 그대로 전부 읽은 원문(`GuideFile.read`. 보기용 읽기는 2MB 앞부분이라 쓰지 않는다). 못 읽으면 보기만.
- **고치기**: 항목 줄 자리에 원문 편집 상자(하위 항목 줄 포함). 상자를 열 때의 문서를 기억하고, 글이 바뀌는 동안 「그 문서에서 이 항목만 바꾼 문서 전체」를 `draft`로 둔다(같으면 nil). 그래서 상자가 열린 사이 로컬 파일이 바뀌면 8장 규칙대로 충돌 → 비교 화면. 저장(⌘↩)은 상자를 연 문서를 다시 나눠 같은 번호·종류·글의 항목을 찾아 바꾼 뒤 저장 경로로, 취소(Esc)는 `draft`를 비운다.
- **지우기**: 누르면 바로 지금 문서에서 그 항목(하위 포함)을 지워 저장한다(TRK-38 지우기 규칙). 저장되면 화면 아래 알림 「지움 · <앞부분 24자>」(하위가 있으면 「· 하위 N개 포함」)과 「되돌리기」, 6초.
- **되돌리기**: 지우기 직전 문서로 저장(새 버전 app).
- **낡은 바탕 막기**: 저장 직전 앱 기록이 바탕 원문과 다르면(그사이 로컬 변경이 반영됐거나, 등록하며 읽은 파일이 화면과 다르면) 쓰지 않고 편집 결과를 `draft`, 앱 기록을 `conflictContent`로 두어 비교 화면으로 간다. 되돌리기도 같다(지운 뒤 로컬 변경이 있으면 덮어쓰지 않는다). 다시 나눈 문서에 같은 항목이 없으면 `staleItem`으로 거절한다.
- **애매한 문서**(문서 전체 한 항목): 한 덩어리 원문으로 보이고 지우기 버튼이 없다. 고치기는 지침 문서 화면에서는 「편집」 보기로, 지침 화면에서는 그 자리 상자(문서 전체)로.
- 버튼을 숨기는 때: 보기만인 출처, UTF-8이 아닌 원문, 다른 항목 상자가 열려 있을 때, 저장 안 한 전체 편집(`draft`)이나 충돌이 있을 때.
- 지침 화면에서 고른 등록 문서가 충돌이면 그 자리에 8장 비교 화면을 보인다.

검증: `GuideItemEditTests`(고치기·하위 포함 지우기·되돌리기가 임시 파일과 버전에 반영, 애매 문서 지우기 거절, 낡은 항목 거절, 상자 연 사이 로컬 변경 → 충돌, `draft`가 있으면 감시가 충돌로 판정, 감시 전 디스크 변경 → 충돌, 지운 뒤 로컬 변경 → 되돌리기 충돌), `GuideItemTargetTests`(등록 전 프로젝트 파일은 처음 고칠 때 등록되고 버전 `[app, local]`, 전역·상위 폴더·기억·폴더 밖 경로·rules는 쓰기 대상 아님).

## 프로젝트 밖 지침 쓰기 (2026-10-02, TRK-41)

전역·상위 폴더·기억·`.claude/rules`·Codex 규칙 파일도 항목 화면(TRK-40)에서 고치고 지운다. 지침 문서(`GuideDoc`)로 등록하지 않고 파일만 다룬다. 로직은 `Shared/GuidanceWrite/`.

- **쓰는 대상**(`GuidanceFileWrite.isWritable`, `GuideItemTarget.file`): 종류가 전역·상위 폴더·rules(전역·프로젝트)·기억·기억 색인·명령 규칙이고 `.md`(규칙은 `.rules`)인 파일. `~/.claude/CLAUDE.md`(`CLAUDE_CONFIG_DIR`), `~/.codex/AGENTS.md`·`AGENTS.override.md`(있을 때만 — 수집기가 있는 파일만 찾으므로 새로 만들지 않는다), `~/.codex/rules/*.rules`(`CODEX_HOME`), 상위 폴더 지침, `~/.claude/projects/*/memory/*.md`. 프로젝트 `CLAUDE.md` 등은 지금처럼 지침 문서로. 이미 지침 문서로 등록된 파일은 그 문서로.
- **쓰지 않는 것**: Codex 기억 DB(`memories_1.sqlite`, `-wal` 포함, `.sqlite` 전부)와 관리 정책 파일(`/Library/…`). 종류와 경로 둘 다로 거절하고, 쓰기 함수(`apply`·`restore`)도 경로로 다시 거절한다. DB에 쓰는 코드는 없다.
- **쓰기 순서**(`GuidanceFileWrite.apply`): ① 바뀔 파일 모두를 다시 읽어 화면이 나눈 원문과 바이트까지 같은지 확인(하나라도 다르거나 사라졌으면 아무것도 쓰지 않고 「바뀜」) → ② `.rules`면 새 내용 전체를 검사(아래) → ③ 파일마다 지금 내용을 백업 → ④ 원자적 쓰기(`GuideFile.writeAtomically`: 같은 폴더 임시 파일 → `rename`, 원래 권한 유지) 또는 지우기.
- **바탕 원문**: 출처 파일을 UTF-8 그대로 전부 읽은 것. 쓴 뒤와 「다시 읽기」에서 다시 읽는다. 못 읽으면 보기만.
- **백업**(`GuidanceBackupStore`, 이 Mac에만): `<저장 폴더>/guidance-backups/<원본 경로 SHA-256 앞 32자>/<UTC 시각 yyyyMMddTHHmmss.SSSZ>-<까닭>.<원래 확장자>`와 같은 폴더의 `source-path`(원본 절대 경로). 까닭: `edit`(고치기 전)·`delete`(지우기 전)·`restore`(복원 전)·`undo`(되돌리기 전). 폴더 0700, 파일 0600. 원본 하나에 최근 50개(이름순 = 시각순, 같은 밀리초면 1 ms 뒤로). 저장 폴더는 `WAYPOINT_SUPPORT_DIR`를 따른다. SwiftData·CloudKit에 넣지 않는다.
- **기억 지우기**: 기억 파일 항목(파일 하나 = 한 항목)을 지우면 그 파일과, 같은 폴더 `MEMORY.md`에서 그 파일을 가리키는 색인 줄 모두(`MemoryIndexPairing.fileName` 기준, TRK-38 지우기 규칙)를 한 번에 지운다. 색인이 없거나 가리키는 줄이 없거나 색인이 애매한 문서면 파일만. `MEMORY.md`의 색인 줄만 지울 수도 있고(파일이 없는 줄도), 기억 파일 내용(머리·본문)도 고칠 수 있다.
- **되돌리기**: 지운 뒤 화면 아래 알림(6초) 「지움 · 앞부분」(+「· 하위 N개 포함」·「· 색인 줄 포함」) + 「되돌리기」. 바뀜을 거꾸로 적용한다 — 모든 파일이 지운 직후와 같을 때만, 아니면 쓰지 않고 「되돌리지 못함 · 바뀜」. 알림은 지침 화면이 들고 있어 지운 기억 파일이 목록에서 빠져도 남는다.
- **백업에서 복원**: 출처 위 한 줄의 「백업 N」 → 사본 목록(시각 · 까닭)과 원문 → 「이 판으로 되돌리기」. 지금 파일이 있으면 먼저 백업(`restore`)하고 사본 내용으로 원자적 쓰기, 없으면 다시 만든다. 지운 파일은 출처 목록 맨 아래 「지운 파일」(사본은 있고 파일은 없는 경로)에서 같은 화면으로.
- **Codex 규칙 검사**(`CommandRulesCheck`): `codex`를 재개 열기(TRK-12 `ToolLaunch`)와 같은 폴더들에서 찾고, 있으면 새 내용을 0700 임시 폴더에 쓰고 `codex execpolicy check --rules <임시 파일> -- waypoint-check-<무작위>`를 `CODEX_HOME=<임시 폴더>`로 실행한다(사용자 Codex 홈에 아무것도 남기지 않는다). 끝 코드 0이고 오류 출력에 `failed to parse policy`가 없으면 통과. 아니면 마지막 `error:` 문장과, 그 줄 원문이 함께 찍힌 경우에만 줄 번호(구문 오류는 `1:1`로 찍히고 원문이 비어 있어 믿지 않는다)를 「저장 안 함 · 줄 2 · invalid decision: maybe」로 보이고 저장하지 않는다. `codex`가 있는데 3초 안에 끝나지 않거나 실행하지 못하면 저장하지 않고 「검사 못 함」(상자는 열린 채라 다시 저장할 수 있다). `codex`가 없을 때만 자체 검사: 괄호 짝(TRK-38 규칙 나누기), 한 줄 문자열이 그 줄에서 닫힘, 규칙마다 `prefix_rule`·`host_executable`·`network_rule` 중 하나의 호출이고 닫는 괄호 뒤에는 공백·주석만. `codex`가 없으면 위 한 줄에 「codex 없음 · 간단 검사」. 빈 파일·주석만 있는 파일은 통과. 되돌리기·복원은 있던 내용으로 돌리는 것이라 검사하지 않는다. 확인한 판: codex-cli 0.159.2(`execpolicy check --rules <PATH> <COMMAND>...`).
- **열린 세션**: 이 경로로 쓰는 파일을 고를 때 위 한 줄에 그 파일을 읽는 도구의 끝나지 않은 메인 세션 수 「열린 Claude 세션 3」(`liveText`, 없으면 안 보임). 전역이면 그 도구의 모든 세션, 아니면 걸리는 프로젝트의 세션.
- 쓴 뒤에는 지침 목록을 다시 모은다(홈 바로 아래 파일은 감시하지 않으므로).

검증: `GuidanceFileWriteTests`(쓰기·백업 내용·권한 0700/0600·원래 권한 유지·50개 정리·같은 밀리초 순서·복원 전 백업·지운 파일 복원·디스크 변경과 사라진 파일 거절·여러 파일 중 하나만 바뀌어도 아무것도 안 씀·기억 지우기와 되돌리기(바이트까지)·색인 바뀐 뒤 되돌리기 거절·색인 없는 파일·`MEMORY.md` 없는 폴더·파일 없는 색인 줄·한 파일을 가리키는 색인 줄 여럿·애매한 색인·기억 내용 고치기·Codex DB 쓰기 거절·잘못된 규칙 저장 거절), `CommandRulesCheckTests`(자체 검사 통과·거절과 줄 번호, Codex 오류 출력 읽기, 가짜 실행 파일로 시간 초과·실행 실패 → 「검사 못 함」·저장 안 함, `codex`가 있을 때만 실제 CLI로 맞는 파일·빈 파일·검사 명령을 막는 규칙·잘못된 결정값(줄 2)·닫히지 않은 괄호·모르는 이름), `GuidanceOpenSessionsTests`, `GuideItemTargetTests`(파일 대상 6종, 보기만 4종). 모든 테스트는 임시 폴더만 쓴다.

## 저장소 백업·복구 (2026-10-02, TRK-46)

업데이트나 깨진 파일 때문에 기록을 잃지 않게 한다. 코드는 `Shared/Store/`(`WaypointSchema`·`StoreBackup`·`StoreLaunch`·`SQLiteFile`), 앱은 `WaypointStore.openForLaunch`로 연다(macOS·iOS 같은 `App/WaypointApp.swift`).

### 저장 형식 판

- 지금 모델을 `WaypointSchemaV1`(1.0.0)로 고정하고 `WaypointMigrationPlan`(판 하나, 단계 없음)으로 연다. 모델 정의·저장 형식은 그대로라 판을 붙이기 전 저장소가 그대로 열린다(`StoreSchemaTests`: 판 없는 `Schema`로 만든 저장소, 이 Mac 실제 저장소의 사본 — 프로젝트 4·카드 110·이벤트 4628, CloudKit 끔).
- **다음 판을 더할 때**: ① 지금 모델 클래스를 `WaypointSchemaV1` 안으로 옮겨 그 판의 모습을 얼린다(`static var models`가 그 안의 타입을 가리키게) ② 바꾼 모델로 `WaypointSchemaV2`(예: 1.1.0)를 만든다 ③ `WaypointMigrationPlan.schemas`에 V2를 더하고 `stages`에 `.lightweight(fromVersion:toVersion:)`(CloudKit 스키마는 필드를 더하기만 하므로 속성 더하기·옵셔널·기본값 안에서 바꾼다. 사용자 정의 단계가 미러링과 맞는지는 쓸 때 확인) ④ `WaypointStore.schema`를 V2로, `currentSchemaVersion`이 V2를 읽게 ⑤ V1 저장소를 만들어 V2로 여는 테스트를 더한다. 판이 바뀌면 처음 여는 실행이 열기 전에 `upgrade` 백업을 뜬다.

### 백업

- 자리 `<저장 폴더>/store-backups/<UTC yyyyMMddTHHmmss.SSSZ>-<사유>/`(0700), 안에 저장소 파일(0600)과 `info.json`(사유·시각·앱 버전·빌드·판·뜬 방법·파일별 바이트). 앱 버전·빌드·판은 그 백업의 저장소를 마지막으로 연 앱이다(판 기록이 없던 저장소면 `unknown`/`unknown`/1.0.0). `info.json`을 마지막에 쓰므로 없으면 끝나지 않은 백업으로 보고 정리 때 지운다. 최근 7개만 남긴다(같은 밀리초면 1 ms 뒤로 밀어 이름순 = 시각순).
- 사유: `upgrade` — 앱 버전·빌드·판이 `store-version.json`(지난번 연 판, 열기에 성공한 뒤에 쓴다)과 다르거나 그 파일이 없을 때(TRK-46 이전 앱이 쓰던 저장소의 첫 실행 포함), 컨테이너를 열기 전. `daily` — 마지막 백업이 24시간보다 오래면 실행할 때(열기 전, 파일 복사). macOS는 떠 있는 동안에도 10초 점검마다 판정해(`StoreDailyBackup`, 마지막 시각을 기억해 디스크는 하루에 한 번꼴로 읽는다) 열린 저장소를 SQLite 온라인 백업으로 뜬다. 백그라운드 큐에서 한 번에 하나, 실패하면 남기지 않고 다음 점검에서 다시. iOS는 실행 때만. `manual` — 열린 상태(화면은 TRK-47). `beforeRestore` — 예약 복원 바로 전.
- 방법: 열기 전(`upgrade`·`daily`·`beforeRestore`)은 store·-wal·-shm 파일 복사(`beforeRestore`는 옮기기). 열린 상태(`manual`)는 SQLite 온라인 백업(`sqlite3_backup_*`, 읽기 전용 원본 연결): WAL에만 있는 변경까지 담긴 한 시점의 사본을 롤백 저널 모드 파일 하나로 남긴다.
- `Waypoint_ckAssets/`는 넣지 않는다. 동기화가 큰 첨부를 내려받아 두는 캐시이고, 모델에 `.externalStorage` 속성이 없으며, 이 Mac의 폴더도 비어 있다(2026-10-02 확인).
- 백업이 실패해도(디스크 등) 열기는 막지 않고 로그에만 남긴다.

### 열기 순서와 복구

1. 예약 복원(`pending-restore.json`)이 있으면 지운 뒤: 지금 저장소를 `beforeRestore` 백업으로 옮기고 → 예약한 백업을 저장소 자리에 복사 → `store-restore.json`(`kind: manual`). 예약한 백업이 없거나 크기가 맞지 않으면 건너뛴다. 중간에 실패하면 옮긴 파일을 제자리로 돌려놓는다.
2. 복원하지 않았으면 `upgrade` 또는 `daily` 백업.
3. 연다. 성공하면 `store-version.json`을 쓴다.
4. 실패하고 저장소 파일이 있으면: store·-wal·-shm을 `<저장 폴더>/store-failed/<UTC 시각>/`(0700)로 옮기고 `failure.json`(원인, `quick_check` 결과)을 남긴다. 지우지 않는다. 백업을 최신순으로 하나씩 저장소 자리에 복사해 `PRAGMA quick_check`(읽기 전용) → 열기를 해 보고, 처음 열리는 것을 쓴다(`store-restore.json`, `kind: automatic`, 쓴 백업·옮긴 폴더·원인). 이번 실행이 방금 뜬 백업이 깨진 저장소의 사본일 수 있어서 최신 하나만 보지 않는다. 안 맞는 사본은 지운다(백업 폴더는 그대로).
5. 열리는 백업이 없으면 옮긴 파일을 제자리로 돌려놓고 처음 오류로 멈춘다(지금처럼 원인 메시지). 저장소 파일이 없는데 못 열었으면 저장소 탓이 아니므로 복구하지 않는다.

- 저장소 자리에 백업을 놓기 전에는 store·-wal·-shm이 하나도 남아 있지 않아야 한다(남은 -wal이 다른 저장소 파일에 붙으면 조용히 깨진다).
- 실패 원인을 가리지 않는다: 깨진 파일과 판이 맞지 않는 저장소(예: 새 판으로 옮긴 뒤 옛 앱을 다시 설치) 모두 복구 대상이다. 그래서 일시적인 원인이었다면 더 오래된 백업으로 돌아갈 수 있지만, 열지 못한 파일이 `store-failed/`에 그대로 남는다.
- 알림: macOS 연동 상태 패널의 미처리 기록 아래 한 줄(「기록을 열지 못해 <백업 시각> 백업으로 되돌림」, 예약 복원은 「<백업 시각> 백업으로 되돌림」) + 「알림 확인」(기록 파일을 지운다). `/integration/status`의 `storeRestore`. 복원 목록·예약 화면은 TRK-47.

### 수동 복원 API (TRK-47 화면용)

`StoreBackup(storeURL:)`의 `list()`(최신순), `backupOpenStore(stamp:at:)`(manual), `scheduleRestore(_:)`·`scheduledRestore()`·`cancelScheduledRestore()`. 열린 저장소를 바꿔 끼우지 않는다. 적용은 다음 실행의 1단계.

### CloudKit과의 관계

복원은 이 기기의 저장소 파일만 되돌린다. CloudKit 쪽 기록은 건드리지 않는다.

- **확인함(저장소 사본 실측)**: 미러링 상태가 저장소 파일 안에 있다 — 레코드 메타데이터(`ANSCKRECORDMETADATA` 5036행), 영역 `com.apple.coredata.cloudkit.zone`의 서버 변경 토큰과 마지막 가져오기 시각(`ANSCKRECORDZONEMETADATA.ZCURRENTCHANGETOKEN`·`ZLASTFETCHDATE`), 마지막으로 내보낸 기록 이력 토큰(`ANSCKMETADATAENTRY`의 `NSCloudKitMirroringDelegateLastHistoryTokenKey`), 기록 이력(`ATRANSACTION`·`ACHANGE`). 그래서 백업을 되돌리면 동기화 상태도 백업 시점으로 함께 돌아간다.
- **확인함(Apple 문서, `CKFetchRecordZoneChangesOperation`)**: 이전 서버 변경 토큰을 주면 CloudKit은 그 뒤에 생긴 변경만 돌려준다.
- **확인 못 함**: `NSPersistentCloudKitContainer`가 복원한 저장소의 옛 토큰으로 다음 가져오기를 해서 백업 이후 다른 기기·이 기기가 올린 변경을 다시 받는지(내부 동작이라 Apple 문서에 없다). 백업 뒤 서버에서 바뀐 레코드가 복원한 로컬 값을 덮는지, 백업 뒤 지운 레코드가 다시 지워지는지. 옛 토큰이 만료돼 전체를 다시 받는 경우가 있는지(제3자 글에만 있다). CloudKit을 켠 복원 실측은 하지 않았다(Dev 실측은 `WAYPOINT_SUPPORT_DIR`로 CloudKit이 꺼진다). CloudKit을 켠 채 판을 붙인 스키마로 여는 것은 Dev 자기 폴더에서 확인했다(docs/RELIABILITY.md).
- 그래서 지금 말할 수 있는 것: 깨진 로컬 파일을 되살리는 데에는 쓸 수 있다. 동기화를 켠 채 「예전 데이터로 되돌리기」로 쓰면 서버의 이후 변경을 다시 받아 되돌림이 일부 풀릴 수 있다(확인 못 함). 기기 실측은 남은 일.

검증: `StoreDailyBackupTests`(24시간 경계·백업 없으면 바로·진행 중 중복 거절·실패 뒤 다음 점검에서 다시·백그라운드 한 번), `StoreBackupTests`(판 기록 없는 저장소 = upgrade·빌드 바뀜 → 열기 전 upgrade·같은 판은 없음·daily 24시간·7개 유지와 끝나지 않은 백업 정리·같은 밀리초 순서·0700/0600과 저장 폴더 권한 그대로·첨부 캐시 제외·깨진 저장소 → 보존 폴더 + 앞의 정상 백업 복원 + 열림·백업이 못 쓰면 실패 그대로 + 파일 제자리·저장소 없으면 복구 안 함·검사는 통과하지만 열리지 않는 백업 건너뛰기·온라인 백업으로 복구(남은 -wal 없이)·열린 저장소 온라인 백업의 일관성과 열림·예약 복원·정리에도 남는 예약 대상·없는 예약 백업), `StoreSchemaTests`. Dev 실측은 docs/RELIABILITY.md 「저장소 백업·복구(TRK-46)」.

## 기록 탭 (2026-10-02, TRK-47)

설정 창(⌘,)은 탭 둘: 「사용량」(전과 같음), 「기록」. 기록 탭은 grouped Form 한 장에 위에서부터 남기는 것 · 어디에 · 백업 · 내보내기·지우기. 화면 `macOS/Settings/Records*`, 로직 `Shared/Store/RecordScope`·`RecordExport`·`RecordWipe`, `Shared/Instance/AppRelaunch`, 문구 `Shared/Format/RecordFormat`.

### 저장 범위 표 (`RecordScope`)

저장소의 저장 속성 전부(`WaypointStore.schema`, 관계 제외)와 이벤트 payload 키를 화면 항목으로 나눈다. 화면 문장은 이 표에서만 만든다. `RecordScopeTests`가 스키마 속성 목록과 표를 양쪽으로 맞추고(빠진 속성·없는 속성 모두 실패), 실제 생성 지점(훅 픽스처 전부·MCP 도구·`CardLifecycle`·`CardEditing`·`GuideLibrary`·샘플)이 만든 payload 키가 모두 표에 있는지, `Shared/`의 `Event.record(` 호출 수가 아는 목록과 같은지 본다.

| 항목 | 남기는 것(코드에서 확인) | 보관 |
|---|---|---|
| 프로젝트 | 이름·키·폴더 경로·개요·스택·다음 카드 번호·만든/보관 시각 | 계속 |
| 카드 | 제목·본문·종류·상태·완료 조건(글·체크)·만든 쪽·부모·시각, 세션 연결(붙은/떨어진 시각), 이벤트 `card.created`·`card.status`(`card.attached`·`card.detached`는 14일), 조건 체크 메모(`kind: criterion`), 정리 안 된 작업 처리(`session.filed`: 세션 ID·결과·카드 ID·파일·옮긴 수) | 계속 |
| 세션 | 도구·종류·에이전트 이름·작업 폴더·브랜치·시작/마지막/끝 시각·끝난 까닭·마지막 요청 시각(`lastPromptAt`), `session.*`, 프로젝트 옮김(`kind: project.bound`) | 14일 · 카드에 이어진 것은 계속 |
| 요청 문장 | `Session.lastPrompt`와 요청 이벤트(`text` 앞 300자·시각·`promptId`) | 14일(`RecordRetention`·`PromptRetention`) |
| 바뀐 파일 | `file.changed`: 프로젝트 기준 경로·저장소 폴더(`checkout`)·늘고 준 줄 수 | 14일(카드마다 가장 최근 것 하나는 계속) |
| 커밋 | `commit`: 해시·메시지 첫 줄(커밋 출력의 `[branch hash] 메시지` 줄) | 14일 · 카드에 이어진 것은 계속 |
| 검증 기록 | `check`: 명령(값 가림, 300자)·결과·출처·조건 번호와 글·짧은 설명(200자)·끝 코드 | 14일 · 카드에 이어진 것은 계속 |
| 메모 | 카드 메모(`card_note`)·다음 세션 메모(`nextSessionNote`, `kind: handoff`)·프로젝트 지금 상황(`project.status`: 글·도구·세션 ID). 에이전트가 도구로 남긴 글도 여기 든다 | 계속(지난 `project.status`는 14일) |
| 지침 문서 | 등록한 문서의 **내용 전체**·저장 안 한 편집·충돌 때 읽은 로컬 내용·이전 판(`GuideVersion`) | 14일 · 최신 판은 계속 |

- 남기지 않는 것: AI 답변, 대화 전체, 명령 출력(끝 코드·커밋 줄만 뽑고 버린다), 지침 문서가 아닌 파일의 내용(편집 원문·읽은 파일은 저장하지 않는다. outbox에는 앱이 켜질 때까지 요청 600자·편집 크기·앱이 읽는 출력 줄(끝 코드·커밋 줄을 찾는 몫)이 잠시 머문다).
- 내보내기에 넣지 않는 작동 상태 값(표의 `exported: false`): `Project.lastEventAt`, `Card.statusBeforeActive`, `Session`의 PID·블록 확인(`context*`)·상태 캐시·활동 상태·대기 중인 도구, `GuideDoc.contentHash`.
- 어디에: 저장소 전부 = iCloud · 이 Mac과 iPhone(iCloud를 끈 실행은 「이 Mac」). 이 Mac에만: 기록 백업(`store-backups`), 지침 파일 백업(`guidance-backups`), 연결 설정 백업(`integration-backups`), 앱이 꺼진 동안 온 기록(`outbox.jsonl`), 연결 상태와 지표(`integration-health.json`·`metrics.json`), 사용량(`usage.json`), 세션 이름 · 컨텍스트 사용률(`session-status.json`).

### 백업·복원

- 「지금 백업」: 열린 저장소를 `manual`로 SQLite 온라인 백업(백그라운드). `StoreDailyBackup.runNow`로 daily와 같은 진행 중 표시를 써 겹치지 않는다.
- 목록: `StoreBackup.list()` 최신순 한 줄 「시각 · 까닭 · 크기」. 까닭 `upgrade` 업데이트 전 · `daily` 매일 · `manual` 직접 · `beforeRestore` 복원 전 · `beforeDelete` 지우기 전. 「Finder에서 보기」.
- 「복원…」 → 확인(다시 시작하며 되돌림, 지금 기록도 먼저 백업, iCloud가 그 뒤 바뀐 내용을 다시 받아 올 수 있음) → `scheduleRestore` → 다시 시작. 적용은 다음 실행의 열기 1단계(「저장소 백업·복구」).
- 다시 시작(`AppRelaunch`): `/bin/sh -c`로 지금 PID가 끝나기를 0.2초 간격 최대 20초 기다린 뒤 `open <지금 번들 경로>`, 그다음 `NSApp.terminate`. 같은 번들 경로라 평소용·Dev가 저마다 자기만 다시 띄운다. `open`은 셸 환경을 넘기지 않아 `WAYPOINT_SUPPORT_DIR`·`WAYPOINT_PORT`·`WAYPOINT_CLOUDKIT`·`WAYPOINT_INTEGRATION_HOME`·`WAYPOINT_RELAUNCH_HIDDEN`을 `--env`로 넘긴다. 실행 인자는 넘기지 않는다. `WAYPOINT_RELAUNCH_HIDDEN=1`이면 `-g -j`(확인용).

### 내보내기 형식 (`RecordExport`, formatVersion 1)

UTF-8 JSON, 들여쓰고 키 정렬, 날짜는 ISO 8601 UTC 밀리초(`2026-10-02T04:31:31.224Z`). NSSavePanel, 이름 제안 `Waypoint-<키|전체>-<yyyy-MM-dd>.json`.

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

- 프로젝트 하나: 그 프로젝트의 카드·세션·이벤트·지침 문서만. 이벤트는 바뀌지 않는 `Event.project`로 가른다. `unassigned` 없음.
- 형식의 이름·뜻을 바꾸면 `formatVersion`을 올린다. 필드 더하기는 그대로.

### 모든 기록 지우기 (`RecordWipe`)

- 확인 두 번: ① 「모든 기록을 지울까요?」 + 무엇이 지워지는지·백업은 남음·(iCloud가 켜져 있으면) iPhone에서도 지워짐 → 「계속」 ② 「프로젝트 N개 · 카드 M개를 지울까요?」 + 지우기 전 백업·다시 시작 → 「지우기」.
- 순서: 저장 → `beforeDelete` 온라인 백업(`runNow`, 다른 백업이 도는 중이거나 실패하면 지우지 않음) → 7종 모델을 잎부터 한 행씩 `delete` 후 저장(일괄 삭제를 쓰지 않아 iCloud 미러링이 지운 것을 보낸다) → 다시 시작.
- 건드리지 않는 것: 저장소 밖 파일(백업·지표·연결 설정)과 UserDefaults. 그래서 온보딩은 「끝」을 누른 적이 없을 때만 다시 뜬다(프로젝트 0개, 「온보딩」 진입 조건 그대로).

### Debug 실행 인자

`-WaypointSettingsTab records`(설정 창을 기록 탭으로 연다), `-WaypointSettingsScroll bottom`, `-WaypointExport <경로>`(+`-WaypointExportProject <키>`), `-WaypointBackupNow 1`, `-WaypointRestore <백업 폴더 이름|latest>`, `-WaypointWipe 1`. 버튼과 같은 `RecordsModel` 길을 대화상자 없이 탄다. 절차는 docs/DEVELOPMENT.md 「기록 탭 실측」.

검증: `RecordScopeTests`(스키마 속성 ↔ 표 양방향, 생성 지점 payload 키, `Event.record(` 호출 목록, 보관 기간 표시, 지침 문서 내용·판), `RecordExportTests`(전체 왕복 디코드·재인코드 바이트 같음, 프로젝트 하나에 다른 프로젝트 것 없음, 작동 상태 값 제외, 임시 저장소 지우기 → 7종 0개 + `beforeDelete` 백업이 먼저 생기고 지우기 전 내용을 담음, 백업 실패·진행 중이면 안 지움, 지금 백업과 daily의 겹침, 문구, 다시 시작 명령의 환경 변수 전달과 따옴표).

## GitHub 이슈·PR 열기 (2026-10-08, TRK-68)

외부 이슈 도구 연동은 하지 않는다는 방향의 예외다(사용자 요청). 하는 일은 둘뿐이다: 이슈·PR을 열고, 그렇게 연 것을 Waypoint에서 본다. 다른 곳에서 연 이슈·PR을 가져오지 않고, 댓글·리뷰·병합·닫기도 하지 않는다.

### 호출

- GitHub은 사용자의 `gh` CLI로 부른다(`Shared/GitHub/GitHubCLI`, `Process`). 앱은 토큰을 다루지 않는다. 실행 파일은 흔한 설치 폴더와 앱 PATH에서 찾고(`ToolLaunch.searchDirectories`), `GH_PROMPT_DISABLED=1`·stdin 없음으로 돌린다.
- 저장소는 프로젝트 `rootPath`가 든 작업 트리의 `origin`이다(`.git/config`를 읽는 TRK-53 코드, `GitRemoteURL.normalize`). `github.com/<owner>/<name>` 꼴만 받는다.
- 이슈: `gh issue create --repo <owner/name> --title … --body … [--label …]`. PR: `gh pr create --repo … --title … --body … --head <브랜치> [--base …] [--draft]`. 본문은 받은 글 그대로 올린다(표시 문구를 붙이지 않는다). 결과는 출력의 마지막 주소 줄에서 번호를 읽는다.
- PR은 push하지 않는다. 브랜치가 그 작업 트리의 `refs/remotes/origin/`(packed-refs 포함)에 없으면 호출 전에 오류로 답한다. `owner:branch` 꼴은 확인하지 않고 넘긴다.
- 제한 시간 20초. 넘으면 프로세스를 멈추고 오류.

### 응답을 미루는 길

`gh`는 몇 초 걸린다. MCP 요청은 메인 큐에서 처리하므로 그대로 기다리면 훅 응답(1초 규칙)이 밀린다. 이 두 도구만 세 토막으로 나눈다.

1. 메인 큐: 인자 확인, 프로젝트·카드 찾기, 저장소·브랜치 읽기(`MCPTools.githubPlan`). 여기서 난 오류는 바로 답한다.
2. 백그라운드: `gh` 실행(`GitHubJob.run`). 모델 객체는 넘기지 않는다(키·ID만).
3. 메인 큐: 기록하고 저장한 뒤 응답을 보낸다(`MCPTools.githubFinish`).

`LocalServer.deferredHandler`가 요청을 맡으면 연결을 열어 둔 채 끝났을 때 응답을 쓴다. 맡는 것은 `MCPRouter.deferredCall`이 고른 단독 `tools/call`(두 도구)뿐이고, 다른 도구·훅·배치는 지금까지의 동기 길 그대로다. 배치에 섞어 보내면 오류로 답한다.

### 기록

성공하면 이벤트 `github.issue`·`github.pr`를 남긴다. payload `number`·`url`·`title`·`state`(`open`·`draft`)·`repo`·`branch`(PR만)·`provider`(세션이 있을 때 그 세션의 도구). 저장 형식(모델 속성)은 바뀌지 않는다. 옛 앱은 모르는 종류를 `note`로 읽으므로 `text` 키를 두지 않는다.

잇는 곳: `cardId`가 있으면 그 카드(같은 프로젝트여야 한다) → 없으면 `sessionId` 세션의 작업중 카드가 하나일 때 그 카드 → 아니면 프로젝트에만. 카드 상태는 건드리지 않는다.

### 보기 (macOS)

- 카드 인스펙터 「GitHub」 구역: 그 카드의 이슈·PR(번호·제목·상태 알약 열림/닫힘/병합됨/초안). 누르면 브라우저로 연다. 프로젝트 폴더가 GitHub 저장소에 이어져 있으면 「이슈 열기…」「PR 열기…」 버튼.
- 프로젝트 보드 머리 「이슈 N · PR N」(열린 수, 초안 포함): 누르면 이 프로젝트에서 연 것 전부(열린 것 먼저, 이어진 카드 ID). 연 것이 없으면 버튼이 없다.
- 상황판 타일 아래 줄에 같은 열린 수(열린 것이 있을 때만).
- 활동 탭 「이슈 #12 열림」, 카드 기록 「이슈 #12 열림 · 제목」.
- 열기 시트: 제목(카드 제목), 본문(카드 본문 + 완료 조건 체크리스트), 저장소. PR은 브랜치(원격에 있는 로컬 브랜치, 기본은 현재 브랜치)·합칠 곳(비우면 저장소 기본)·초안. 도구와 같은 `GitHubPlanner`·`GitHubJob`·`GitHubLog`를 쓴다. 실패하면 시트 안에 원인이 보인다.

### 상태 갱신

목록(상황판·보드 머리 목록)이나 카드 인스펙터를 열 때, 마지막 확인(없으면 연 시각)에서 5분이 지난 항목이 있으면 뒤에서 `gh api graphql` 한 번으로 보이는 항목 전부의 `state`·`title`·`isDraft`를 읽는다(`GitHubStatusQuery`). 결과는 `<저장 폴더>/github-cache.json`(0600, 이 Mac에만, `RecordScope.localItems`)에 두고 화면은 이벤트 값 위에 덮어 보인다. 이벤트와 카드 상태는 바꾸지 않는다(자동 done 금지). 실패하면 1분 동안 다시 시도하지 않고 마지막으로 아는 상태를 보인다.

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

화면에는 위 문구만 보이고, 도구 응답에는 해결 명령이 괄호로 붙는다(예: 「(터미널에서 gh auth login)」). 실패하면 아무것도 기록하지 않는다.

### Debug 실행 인자

`-WaypointProject <키>`(그 프로젝트 보드에서 시작), `-WaypointGitHub list`(보드 머리 목록을 시트로 — 숨긴 채 띄운 앱은 팝오버가 뜨지 않는다), `-WaypointGitHub issue|pr`(카드 인스펙터에서 열기 시트, `-WaypointOpenCard`와 함께).

검증: `GitHubTests`(가짜 `gh` 실행 파일, 네트워크 없음 — 인자 조립, 결과 해석, 실패 일곱 가지, 카드 연결 규칙, 이벤트·저장 범위 표, 상태 캐시 만료·0600, 미룬 응답 동안 다른 요청이 밀리지 않음). 실측은 [RELIABILITY.md](RELIABILITY.md) 「GitHub 이슈·PR 열기」.
