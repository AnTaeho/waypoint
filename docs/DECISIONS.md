# 결정 기록 (무인 진행)

2026-09-27~28 밤 클라우드 세션이 사용자 없이 정한 것. 아침에 이 파일만 읽고 뒤집을 수 있게 적는다.
형식: 날짜 · 무엇을 · 왜 · 대안 · 되돌리는 방법.

## 실행 환경

- **Linux(Ubuntu 24.04, x86_64) 클라우드 컨테이너. macOS·Xcode·Swift 툴체인 없음.**
  `sw_vers`, `xcodebuild`, `swift`, `xcodegen` 모두 없음. download.swift.org는 네트워크 정책(403)으로 막혀 툴체인 설치도 못 했다.
- 그래서 이번 실행에서 쓴 코드는 **한 줄도 컴파일·테스트하지 못했다(미검증).** 빌드를 흉내 내는 우회는 하지 않았다.
- `Waypoint.xcodeproj`는 XcodeGen이 파일을 하나하나 적는 방식이라, 새로 만든 앱 쪽 파일(`macOS/Board/*`, `macOS/Card/*`, `macOS/MenuBar/*` 등)이 아직 프로젝트 파일에 없다.
  손으로 pbxproj를 고치면 검증 없이 깨뜨릴 위험이 커서 **고치지 않았다. 로컬에서 먼저 `xcodegen generate`를 돌려야 한다.**

## 결정

| 날짜 | 무엇을 | 왜 | 대안 | 되돌리는 방법 |
|---|---|---|---|---|
| 09-28 | 보드 칸 순서: 아이디어=만든 시각 최신순, 다음=카드 번호순, 작업중=연결 시각순(하위 카드는 부모 아래), 완료=완료 시각 최신순 | 시안의 아이디어·완료 순서와 맞고, 다음 칸은 시안 순서(17,18,15,20)에 규칙이 안 보여 가장 예측 가능한 번호순을 골랐다 | 다음 칸 수동 정렬(모델에 순서 필드 추가 필요) | `BoardQuery.columns`의 정렬 한 줄씩 |
| 09-28 | 작업중 카드를 아이디어·다음 칸으로 끌어 놓는 것도 허용 | SPEC 「그사이 사용자가 상태를 바꿨으면 그대로 둔다」와 `CardLifecycle.move`가 이미 이 경우를 다룬다. 드래그 중에 끌고 있는 카드를 알 수 없어, 막으면 강조된 칸이 드롭을 거절하는 어색함이 생긴다 | 작업중 카드는 완료로만 허용 | `BoardQuery.canDrop`에 `card.status == .active`면 `column == .done`만 true |
| 09-28 | 드래그 내용은 카드 UUID 문자열(`String`의 Transferable) | 외부 타입·UTType 선언 없이 macOS 14에서 되는 가장 단순한 방법. 드롭 시 그 프로젝트 카드에서만 찾는다 | Card용 Transferable + 사용자 UTType | `BoardColumnView`의 `.draggable`/`.dropDestination` |
| 09-28 | 보드 카드 아래 줄: 아이디어·다음은 「Claude · 어제」「직접 작성 · 9월 24일」, 완료는 「어제 · 세션 2회 · 커밋 3」 | 시안의 「대화에서 감지」「작업 계획에서」는 화면 문구 규칙 위반이라 뺐고, 사실(만든 곳·날짜)만 남겼다 | 만든 곳만 표시 | `CardFormat.originLine`/`doneLine` |
| 09-28 | 작업중 카드 오른쪽 위 경과는 세션 시작이 아니라 **이 카드에 연결된 시각**부터 | 카드 기준 화면이라 「이 카드를 얼마나 했나」가 맞다. 샘플에선 두 값이 같다 | 세션 시작 기준(대시보드와 같음) | `BoardCardView`에서 `link.attachedAt` → `session.startedAt` |
| 09-28 | 누적 작업의 서브에이전트 수 = 이 카드에 직접 붙은 서브에이전트 + 이 카드에 붙은 메인 세션에서 갈라진 서브에이전트 | 시안 LDG-14 「세션 1회 · 서브에이전트 1」과 맞추려면 부모 세션 기준으로 세야 한다 | 직접 붙은 것만 | `BoardQuery.stats` |
| 09-28 | 창이 좁으면 보드를 가로 스크롤(칸 최소 폭 200) | 네 칸이 한 줄에 안 들어갈 때 카드 제목이 한두 글자로 잘리는 것보다 낫다. 바깥은 GeometryReader로 감싸 분할 뷰를 누르지 않는다 | 칸을 두 줄로 접기 | `Theme.Size.boardColumnMinWidth`, `ProjectBoardView` |
| 09-28 | 시안의 「이 프로젝트에서 2개 작업중 · sess·7f2a」 칩 줄은 넣지 않음 | 그 줄은 이번 범위 밖인 탭 줄(보드/활동 기록/…)과 한 줄이라 함께 뺐다 | 머리 아래에 칩만 두기 | — |
| 09-28 | 아이디어 칸은 처음 3장만, 「N개 더 보기」/「접기」 | 시안 그대로. 펼침 상태는 화면을 떠나면 초기화 | 펼침 상태 기억 | `Theme.Board.ideaPreviewCount` |
| 09-28 | 샘플 모드(`-WaypointSampleData`)는 실행마다 메모리 저장소에 새로 채움. `WaypointStore.sampleStoreURL()`은 지우지 않고 남김 | HANDOFF 지시. `sampleStoreURL`은 기존 테스트가 부르고 있어 지우면 테스트를 바꿔야 한다 | 함수·테스트 함께 삭제 | `WaypointApp.makeContainer` |
| 09-28 | 카드 정보는 **기존 인스펙터 자리를 바꿔 쓴다**: 카드 상세가 스택 맨 위면 인스펙터가 「최근 기록」 대신 카드 정보를 보인다. 이를 위해 `RootView`의 `NavigationPath`를 `[Card]`로 바꿨다 | DESIGN.md 「카드 정보처럼 곁들이는 정보는 인스펙터」와 맞고, 본문 오른쪽에 칸을 하나 더 두면 인스펙터와 겹쳐 세 칸이 된다. 스택에 쌓이는 화면이 카드 상세뿐이라 타입 있는 배열로 충분하다 | 본문 오른쪽 고정 칸(시안 그대로) | `RootView.inspector`에서 항상 `RecentEventsInspector`, `CardDetailView`에 칸 추가 |
| 09-28 | 완료 조건 체크 변경은 `note` 이벤트(payload `kind: "criterion"`, `text`, `isDone`)로 기록 | SPEC 이벤트 타입 안에서 가장 가까운 것. 새 타입을 만들지 않아 SPEC을 안 고쳐도 된다. 히스토리에 「완료 조건 체크 · …」로 보인다 | `card.status`에 섞기, 새 타입 `card.criteria` | `CardEditing.setCriterion`, `CardHistoryFormat.line` |
| 09-28 | 완료 조건을 다 채워도 상태는 그대로 | 제품 규칙 「자동으로 done 처리하지 않는다」 | — | — |
| 09-28 | 카드 본문 Markdown은 `inlineOnlyPreservingWhitespace`(굵게·기울임·코드·링크 + 줄바꿈) | HANDOFF 「macOS 14의 AttributedString(markdown:) 수준이면 충분」. 제목·목록 같은 블록 문법은 글자 그대로 보인다 | 블록 문법 직접 렌더링(M4 지침 문서 렌더러와 함께) | `CardMarkdownText` |
| 09-28 | 히스토리 문구: 「카드 생성 · 다음 할 일」「다음 할 일 → 작업중」「세션 연결」「세션 연결 끝」「파일 변경 +84 −12」「커밋 · 메시지」, 시각은 「14:22」「어제 14:22」「9월 26일 22:40」 + 세션 표시 | 사실만 짧게(화면 문구 규칙). 시안의 「세션 시작, …」「대화 중 언급된 기능을 …」은 다른 카드 이벤트를 엮은 문장이라 뺐다 | — | `CardHistoryFormat` |
| 09-28 | 「완료로 옮기기」는 상태 배지 줄 오른쪽 `.bordered` 버튼, 완료·보관 카드에서는 숨김 | 시안의 「Claude에서 이어서 작업」 자리. 동작은 `CardLifecycle.move(.done)` + 저장 | 툴바 버튼 | `CardDetailHeader` |
| 09-28 | 연결된 카드 = 상위·하위만(보관 제외). 「파생」은 모델에 없어 뺐다 | HANDOFF 지시 | — | — |
| 09-28 | 「지금 연결된 세션」에서 세션 종류는 「Claude Code」/「서브에이전트」로 보임 | 시안 문구이고 HANDOFF가 「세션 종류」를 보이라고 했다. 만든 쪽 용어 목록(훅·MCP·스킬·세션 요약)에 없다 | 「세션」 하나로 통일 | `ConnectedSessionBox`, `BoardSessionBox` |
| 09-28 | (M2) 서브에이전트 하위 세션의 `Session.id` = 훅의 `agent_id` | 문서상 서브에이전트 안의 훅은 `session_id`가 부모와 같고 `agent_id`로 구분한다. 실측으로 확정(아래) | `session_id`가 다르면 그것을 쓰기 | `HookProcessor.subagentStart` |
| 09-28 | (M2) 하위 세션은 `SubagentStart`에서 만들고, 카드 ID는 그 직전 `PreToolUse(Agent)` 프롬프트의 `[LDG-16]`에서 가져와 **같은 에이전트 종류의 가장 오래된 대기 항목**과 짝짓는다(10분 지나면 버림, 다른 종류와는 짝짓지 않음) | 문서에 두 이벤트를 잇는 키가 없다. 틀린 카드에 붙이는 것보다 안 붙이는 쪽이 보수적 | `PreToolUse`에서 바로 하위 세션을 만들기(그러면 `agent_id`를 모름) | `HookProcessor.takePending` |
| 09-28 | (M2) 프롬프트에 카드 ID가 없는 서브에이전트는 어떤 카드에도 붙이지 않는다. 다만 그 서브에이전트의 파일 변경은 부모 세션의 작업중 카드에 남긴다 | 카드 연결은 명시적일 때만. 파일 기록은 잃지 않게 | 부모 카드에 자동 연결 | `postToolUse`의 `cards.isEmpty, sub != nil` 분기 |
| 09-28 | (M2) `SessionStart` 없이 다른 훅이 먼저 와도(훅을 세션 중간에 등록한 경우) 등록 폴더면 세션을 만든다. 끝난 세션은 **끝난 시각 뒤의** 훅이 올 때만 다시 살리고(resume), 그 이전 시각의 늦은 기록은 무시 | outbox로 늦게 들어온 기록이 끝난 세션을 되살리지 않게 | SessionStart에서만 생성 | `HookProcessor.mainSession` |
| 09-28 | (M2) 카드가 없는 세션의 파일 변경·커밋은 카드 없이 프로젝트 이벤트로 남긴다 | 기록을 버리지 않는다. 화면에는 아직 안 보인다 | 버리기 | `postToolUse`의 `targets` |
| 09-28 | (M2) 줄 수: Edit=`new_string`/`old_string` 줄 수, Write=`content` 줄 수(지운 줄 0), Bash=`bashEditDiff.changedFiles`(줄 수 0). 커밋은 Bash 명령에 `git commit`이 있고 출력 첫 줄이 `[브랜치 해시] 메시지`일 때 | 문서에 있는 필드만 쓴다. 실제 `tool_response`에 더 정확한 필드가 있으면 실측 후 바꾼다 | git 명령 직접 실행(훅 경로에서 느려짐) | `HookParsing` |
| 09-28 | (M2) git 브랜치는 `.git/HEAD`만 읽어 얻는다(git을 실행하지 않음) | 서버 응답을 느리게 하지 않게. 커밋 출력의 브랜치로도 갱신 | `git rev-parse` 실행 | `GitInfo.branch` |
| 09-28 | (M2) outbox는 먼저 `outbox.processing-<ms>-<uuid>.jsonl`로 이름을 바꿔 떼어 낸 뒤 처리하고 지운다. 서버가 열린 직후 한 번 더 흡수 | 흡수 중 스크립트가 쓰는 줄을 잃지 않고, 도중에 앱이 죽어도 다음 실행에서 이어 처리 | 읽고 파일 비우기(그사이 쓴 줄 유실 위험) | `Outbox.drain`, `AppServices.start` |
| 09-28 | (M2) 샘플 모드에서는 서버를 열지 않고 outbox도 흡수하지 않는다 | 메모리 저장소에 흡수하면 outbox가 비워지면서 실제 기록을 잃는다 | — | `WaypointApp.init` |
| 09-28 | (M2) 훅 스크립트 curl에 `--noproxy '*'`, `--connect-timeout 1` 추가. 로깅 모드 파일은 `hook-log/<YYYY-MM-DD>.jsonl`, 줄 형식은 outbox와 같다. 테스트용 `WAYPOINT_SUPPORT_DIR` 환경 변수 추가 | 셸에 `http_proxy`가 있으면 127.0.0.1 요청이 프록시로 가서 앱에 닿지 않는 것을 이 컨테이너에서 실제로 확인했다 | — | `integration/hooks/waypoint-hook.sh` |
| 09-28 | (M2) 메뉴 막대: 프로젝트별 「가계부 앱 · 작업 2 · 멈춤 1」(카드와 상관없이 메인 세션 수), 받지 못할 때 한 줄, 「Waypoint 열기」, 「종료」. 아이콘 SF Symbol `signpost.right` | 카드 없는 세션도 보이는 곳이 필요했다(대시보드에도 카드 없는 세션 줄을 넣었다, 아래). 사실만 짧게 | — | `MenuBarContent` |
| 09-28 | (M2) 세션 상태 캐시(`stateRaw`)를 60초마다 맞춘다 | 화면 판정은 이미 `TimelineView`가 한다. 캐시는 M6 동기화용 | 타이머 없이 두기 | `AppServices.refreshInterval` |
| 09-28 | (M2) 서버는 루프백(127.0.0.1)에만 묶고, 요청 하나를 받는 데 5초·본문 1 MiB로 제한 | 외부 접속 차단, 멈춘 연결 정리 | — | `LocalServer`, `HTTPRequestParser` |
| 09-28 | (M2, 로컬에서 결정) 대시보드 작업중 표에 **카드 없는 세션 줄**을 넣는다(막힌 것의 (a)). 끝나지 않은 메인 세션에 열린 카드 연결이 없으면 한 줄: 카드 칸 비움, 제목 자리 「카드 없음」(흐리게), 최근 파일은 그 세션과 서브에이전트가 카드 없이 남긴 `file.changed`, 누를 곳 없음. 카드가 붙으면 카드 줄로 바뀐다. 카드 없는 서브에이전트는 줄을 만들지 않는다. 카드 없는 부모 줄이 생기므로 카드 붙은 서브에이전트는 그 아래 들여쓴다. 검색 중에는 카드 없는 줄이 빠진다. `SessionStart` 컨텍스트의 「다른 세션에서 작업중」에는 넣지 않는다 | M2 완료 조건 「세션 2개가 live로 보이고 종료하면 사라진다」를 카드(M3) 없이 채운다 | (b) 메뉴 막대만, (c) M3 뒤 확인 | `DashboardQuery.rows`의 `links.isEmpty` 분기 삭제, `DashboardRow.card`를 다시 필수로 |
| 09-28 | (M2) 사이드바 개수·프로젝트 표 「작업중」도 카드 없는 메인 세션을 센다(작업중 = live 카드 + 카드 없는 live 메인 세션, 멈춤도 같게) | 대시보드 제목 「작업 N개」가 카드 없는 줄을 세는데 사이드바가 0이면 두 숫자가 어긋난다. 메뉴 막대도 이미 카드와 상관없이 세션을 센다 | 카드만 세기(기존) | `DashboardQuery.summary`의 세션 반복 삭제 |
| 09-28 | (최적화) `Project.lastEventAt`(옵셔널) 추가. `Event.record`가 앞으로만 갱신하고, 프로젝트 요약의 「마지막 활동」은 이벤트 전체 대신 이 값을 쓴다. 메뉴 막대는 끝나지 않은 세션만 `@Query`로 읽는다 | M2부터 파일 수정마다 이벤트가 쌓이는데, 사이드바·대시보드가 30초마다 프로젝트의 이벤트 전부를 읽고 있었다. 결과는 같다 | 이벤트 조회에 fetchLimit·정렬을 걸기(요약 함수가 context를 받도록 바꿔야 함) | `DashboardQuery.summary`에서 `project.events` 합치기로 되돌리고 필드 삭제 |
| 09-28 | (M2 실측) 하위 세션 `Session.id` = `agent_id` **확정** | Claude Code 2.1.283 실측: 서브에이전트 안의 훅·`SubagentStart`·`SubagentStop` 모두 `session_id`가 부모와 같고 `agent_id`(17자 16진)로 구분된다(`real-SubagentStart.json`) | — | — |
| 09-28 | (M2 실측) `PreToolUse(Agent)`↔`SubagentStart` 짝짓기는 순서·종류 그대로 둔다 | 실측에도 둘을 잇는 키가 없다(`SubagentStart`에 `tool_use_id` 없음). 포그라운드·백그라운드 모두 `PreToolUse` 1~2초 뒤 `SubagentStart`가 왔고 `[PRB-1]` 카드 연결·해제·`next` 복귀까지 실제 앱에서 확인 | `prompt_id`로 잇기(한 턴에 여러 서브에이전트면 구분 못 함) | — |
| 09-28 | (M2 실측) 줄 수를 실제 diff 조각으로 센다: `Edit`·`MultiEdit`·`Write`는 `tool_response.structuredPatch`, `Bash`는 `bashEditDiff.files[].hunks`의 `+`/`-` 줄. 조각이 없으면(새 파일 `Write`, 옛 입력) 이전 추정 방식 | 실측으로 필드를 확인했다. 입력 추정은 `replace_all`·덮어쓰기에서 틀린다 | 입력 추정 유지 | `HookParsing.changedFiles`에서 `hunkLines` 분기 삭제 |
| 09-28 | (M2 실측) 커밋은 `tool_response.gitOperation.commit`(`sha`, `branch`)을 먼저 쓰고, 메시지는 출력 `[브랜치 해시] 메시지`에서(없으면 빈 문자열). 없으면 이전 방식 | 실측으로 필드를 확인했다. 명령 문자열에 `git commit`이 없는 경우(별칭·스크립트)도 잡는다 | 출력 파싱만 | `HookParsing.commit`의 `gitOperation` 분기 삭제 |
| 09-28 | (M2 실측) `SessionEnd`가 빠진 세션을 처리하는 코드는 넣지 않았다 | `-p` 세션 20개 중 3개에서 `SessionEnd`가 안 왔다(사용자의 다른 `SessionEnd` 훅도 같이 빠짐 → Claude Code 쪽). 어떻게 끝났다고 볼지(전사 파일 시각, 프로세스 확인, 오래 멈춘 세션 자동 종료)는 사용자 결정이 필요하다. 지금은 15분 뒤 「멈춤」으로 남는다 | 위 셋 중 하나 | — |
| 09-28 | (SessionEnd 누락 대비, 사용자 결정) 훅 스크립트가 Claude Code PID를 보내고, 앱이 60초마다(시작 때 outbox 흡수 뒤 한 번) 끝나지 않은 메인 세션의 프로세스를 확인해 없으면 끝낸다(`process-gone`). PID를 모르는 세션만 `lastSeenAt`에서 24시간 뒤 끝낸다(`inactive-24h`). 끝낼 때는 `SessionEnd`와 같은 `HookProcessor.finish`(하위 세션·카드 연결 해제, done 아님) | `-p` 세션 20개 중 3개가 `SessionEnd` 없이 끝나 대시보드에 멈춤으로 영원히 남았다. 프로세스 유무는 세션이 실제로 끝났는지 가장 직접 알려 준다 | 전사 파일(`transcript_path`) 갱신 시각으로 판정(대화형 세션이 오래 입력을 기다리면 오판), 오래 멈춘 세션 자동 종료만(끝난 세션이 그 시간 동안 남는다) | `AppServices.refreshStates`의 `processor?.sweep` 한 줄 삭제(PID 기록은 남겨도 무해). 스크립트는 `claude_pid` 호출 줄 삭제 |
| 09-28 | (SessionEnd 누락 대비, 로컬에서 결정) PID는 비어 있으면 채우고, **더 새 훅**(`at >= lastSeenAt`)이 다른 PID를 가져오면 바꾼다. PID 재사용 검사는 프로세스 시작 시각을 **`lastSeenAt`**(+2초)과 비교한다 | `--resume`은 같은 `session_id`를 새 프로세스로 잇는다. 「비어 있을 때만 채움」+「`startedAt`보다 늦게 시작하면 다른 프로세스」로 하면 resume한 세션이 60초 안에 잘못 끝난다. 마지막 훅 뒤에 시작한 프로세스는 그 훅을 보냈을 수 없으니 `lastSeenAt` 비교가 맞다. 2초는 outbox `receivedAt`이 초 단위로 잘리는 몫 | 지시대로 비어 있을 때만 채우기 + `startedAt` 비교 | `HookProcessor.recordPid`의 조건, `SessionSweep.verdict`의 비교 대상 |
| 09-28 | (SessionEnd 누락 대비, 로컬에서 결정) 스크립트는 `comm` 마지막 조각이 정확히 `claude`인 조상만 찾고, `args` 부분 문자열로는 찾지 않는다. 앱 쪽 확인은 `p_comm`을 보지 않고 존재·좀비·시작 시각만 본다 | 스크립트 경로 `~/.claude/waypoint/…`가 셸 인자에 있어 `args`에 `claude`가 들어간 첫 조상은 셸이다. 네이티브 설치의 `p_comm`은 버전 번호(`2.1.283`)라 이름 확인이 쓸모없다 | `args` 포함 여부, 훅이 물려받는 `CLAUDE_PID` 환경 변수(실측에서 스크립트 부모 PID와 같았다) | `waypoint-hook.sh`의 `claude_pid` |
| 09-28 | (SessionEnd 누락 대비, 로컬에서 결정) 앱이 끝낸 세션의 `endedAt`은 검사 시각, `lastSeenAt`은 옮기지 않는다 | 검사 시각으로 끝내야 그 뒤의 진짜 resume은 되살리고 그 이전 늦은 outbox 기록은 무시하는 기존 규칙이 그대로 맞는다. 마지막 활동은 훅이 온 시각만 뜻하게 둔다 | `endedAt = lastSeenAt`(끝난 뒤 늦은 기록으로 부활할 틈이 생김) | `HookProcessor.sweep`의 `finish(… activity: false)` |
| 09-28 | (SessionEnd 누락 대비, 일회성) 이전 실측에서 남은 PRB 세션 3개(`5d31…`, `7374…`, `b37a…`)는 앱을 끈 채 scratchpad 도구로 `finish(reason: "inactive-24h")`를 불러 끝냈다. 앱 기능에는 넣지 않았다 | PID가 없어 24시간 규칙 대상인데, 그동안 사용자 화면에 멈춤으로 남지 않게 | 24시간 기다리기 | — |
| 09-28 | (M2 실측) `doc-*.json` 픽스처는 고치지 않았다 | 실측과 모순되는 필드가 없었다(실측에만 있는 필드가 더 있을 뿐). 실제 입력은 `real-*.json` 17개로 따로 둔다 | — | — |
| 09-28 | (M3) MCP는 초기화 방식(2025-11-25·06-18·03-26)만 받고, 모르는 `MCP-Protocol-Version` 머리에는 본문 없는 400 | Claude Code 2.1.283 실측: 새 방식(2026-07-28) `server/discover`로 먼저 떠보고, 본문 없는 400이면 `initialize`로 내려온다. 새 방식을 같이 지원하려면 `server/discover`·요청별 `_meta`·머리 검증(-32020/-32022)이 더 필요하다 | 두 방식 모두 지원(dual-era) | `MCPRouter.supportedVersions`와 버전 머리 검사 |
| 09-28 | (M3) `Mcp-Session-Id`는 `initialize` 응답에 주기만 하고 이후 검사하지 않는다 | 서버가 세션별 상태를 두지 않는다. 검사하면 앱을 다시 켤 때마다 실행 중인 Claude Code 세션이 404를 받고 다시 초기화해야 한다 | 모르는 ID에 404 | `MCPRouter.respond`에 검사 추가 |
| 09-28 | (M3) 도구 실패(카드 없음, active 요청 등)는 JSON-RPC 오류가 아니라 `isError: true` 결과로, 그 호출의 변경은 되돌린다. 모르는 도구 이름만 `-32602` | MCP 문서의 도구 실행 오류 방식. Claude가 이유를 읽고 고쳐 부를 수 있다 | 전부 JSON-RPC 오류 | `MCPServer.callTool` |
| 09-28 | (M3) `card_start`는 서브에이전트 세션에도 같은 전환 규칙(그 세션의 다른 카드 연결을 먼저 푼다)을 쓴다. 끝난 세션·다른 프로젝트 세션은 오류. done 카드도 시작할 수 있다(`statusBeforeActive = done`이라 끝나면 done으로 돌아간다) | 세션 하나는 주제 하나라는 규칙을 한 곳에서. done 카드를 다시 여는 일은 사용자 요청일 때뿐이고, 기존 `attach`·`detach` 규칙과 맞는다 | done 카드 시작 거부 | `MCPTools.cardStart` |
| 09-28 | (M3) `card_create` 기본 status: kind idea면 idea, 그 밖은 next | 「나중에」 류를 kind만 idea로 보내도 아이디어 칸에 가게 | 늘 next | `MCPTools.cardCreate` |
| 09-28 | (M3) `card_list` 기본은 done·archived를 뺀다 | 스킬이 시작할 카드를 찾을 때 완료 카드가 섞이지 않게. `status: done`으로 따로 볼 수 있다 | 전부 | `MCPTools.cardList` |
| 09-28 | (M3) 주입 블록의 직전 세션 메모는 카드 하나: 가장 최근에 `card_handoff`한(handoff 기록 시각, 없으면 `updatedAt`) done·archived가 아닌 카드. 마지막 줄에 tracker 스킬 안내를 붙인다 | 「직전 세션」은 하나다. `updatedAt`은 다른 수정에도 움직여 옛 메모가 앞설 수 있다. 안내 줄은 스킬이 이 블록에서 켜지게 돕는다(실측에서 `-p` 세션이 곧바로 `Skill(tracker)`를 불렀다) | 메모 3개(이전 형식) | `SessionContext.latestHandoff`, `skillHint` |
| 09-28 | (M3) handoff는 `note` 이벤트 `{kind: "handoff", text}`로 남긴다 | 카드 기록에 메모 문장이 그대로 보이고(`CardHistoryFormat`은 모르는 kind를 본문 그대로 보인다), 주입 블록이 메모 시각을 찾는다 | 새 이벤트 종류 | `MCPTools.handoffNoteKind` |
| 09-28 | (M3) 커밋은 「MCP 엔드포인트와 도구」를 한 커밋으로 묶었다 | `MCPServer`가 도구 레지스트리를 품고 있어 나누면 중간 커밋이 빌드되지 않는다 | 빌드 안 되는 중간 커밋 | — |
| 09-28 | (M4) 프로젝트 화면 전환은 툴바 가운데 세그먼트 「보드 \| 지침 문서」. 선택은 프로젝트를 바꿔도 유지하고, 고른 문서는 프로젝트를 바꾸면 첫 문서로 | 사이드바 항목을 늘리지 않고 같은 프로젝트 안의 두 화면을 오간다. 프로젝트별 기억은 지시상 필요 없음 | 사이드바에 하위 항목 | `RootView.projectMode` |
| 09-28 | (M4) 문서 목록은 본문 위 가로 줄(시안 그대로). 등록된 문서가 없으면 후보 줄 + 각 줄 「추가」 + 「파일 추가…」, 있으면 + 메뉴 안에 남은 후보와 「파일 추가…」 | 시안의 문서 탭 줄과 맞고, 왼쪽 목록을 두면 목차와 두 칸이 겹친다 | 왼쪽 목록 | `GuideHeaderBar`, `GuideAddMenu`, `GuideEmptyView` |
| 09-28 | (M4) `GuideDoc`에 `draft: String?`, `isMissing: Bool = false`, `conflictContent: String?`를 붙였다. `draftBaseHash`는 두지 않았다 | draft의 기준은 늘 지금 `content`다(`content`는 draft가 없을 때만 로컬에서 바뀌고, 충돌은 draft를 지우지 않는다). 충돌 때 읽은 로컬 내용을 들고 있어야 비교 화면이 파일을 다시 읽지 않고 뜬다 | draft 기준 해시 필드 추가(M6에서 기기 간 draft가 필요해지면) | 필드 삭제 + `GuideSync.decide` 인자 |
| 09-28 | (M4) draft가 저장 내용과 같거나 새 디스크 내용과 같으면 충돌로 보지 않고 로컬을 반영한다 | 실제 편집이 없거나 양쪽이 같은 수정이면 고를 것이 없다 | 늘 충돌 | `GuideSync.decide`의 guard |
| 09-28 | (M4) 감시 이벤트가 오면 이벤트 경로를 맞추지 않고 **모든 등록 문서**를 해시로 다시 판정 | FSEvents는 `/private/var`처럼 실제 경로로 알려 주고, 원자적 교체는 임시 파일 이름으로 온다. 문서 수가 적어 해시 비교가 싸다 | 경로별 판정 | `GuideMonitor` |
| 09-28 | (M4) 감시 폴더는 `ModelContext.didSave`마다 다시 계산하고 달라졌을 때만 감시를 다시 건다(그때 전부 판정) | 등록·해제를 화면 코드가 따로 알리지 않아도 된다 | 화면에서 직접 재시작 호출 | `GuideMonitor.reload` |
| 09-28 | (M4) 저장 뒤·취소 뒤 읽기로 돌아간다. 저장 안 한 편집이 있는 문서를 열면 편집으로 연다 | 시안의 저장·취소 버튼이 읽기로 돌아간다 | 편집에 머물기 | `GuideView`, `GuideEditor` |
| 09-28 | (M4) 충돌이면 본문을 비교 화면으로 바꾼다(시트는 쓰지 않음). 충돌 중에는 읽기/편집 전환을 막는다 | 고르기 전에는 다른 일을 할 수 없는 상태가 한눈에 보이고, 인스펙터(버전 기록)는 그대로 볼 수 있다 | 시트 | `GuideView.content` |
| 09-28 | (M4) 되돌리기는 저장 안 한 편집을 그 버전 내용으로 바꾼 뒤 저장과 같은 규칙으로 쓴다 | 규칙을 하나로. 충돌이면 비교 화면에 그 버전 내용이 오른쪽에 뜬다 | draft가 있으면 되돌리기 막기 | `GuideLibrary.revert` |
| 09-28 | (M4) 버전은 문서당 50개 | 지침 문서는 자주 안 바뀌고 한 버전이 몇 KB라 넉넉하다 | 개수 무제한, 기간 기준 | `GuideLibrary.versionLimit` |
| 09-28 | (M4) 인스펙터 분량은 「섹션 5개 · 39줄」(제목 수 · 줄 수), 제목이 없으면 줄 수만 | 시안 「5개 섹션」 + 편집 크기를 가늠할 줄 수 | 하나만 | `GuideFormat.size` |
| 09-28 | (M4) 텍스트 선택은 블록마다 된다(블록을 넘는 선택은 안 됨) | macOS SwiftUI의 `textSelection`은 `Text` 하나 안에서만 선택한다. 한 `Text`로 합치면 표·코드 블록을 그릴 수 없다 | NSTextView로 전체 렌더링 | — |
| 09-28 | (M5) 등록 확인은 따로 뜨는 창(`NSWindow` + `NSHostingController`, `InitWindowController`)에 띄운다 | `openWindow`는 뷰 환경에서만 얻을 수 있어 메인 창이 닫혀 있거나 메뉴 막대만 있을 때 시트를 띄울 곳이 없고, `WindowGroup`이라 창이 여럿이면 누가 띄울지도 정해야 한다. 따로 뜨는 창은 둘 다 피한다. 등록 뒤 메인 창은 `RootView`가 처음 뜰 때 넣어 둔 `openWindow`로 연다(실측: 창을 닫은 상태에서 열렸다) | 메인 창을 열고 시트 | `macOS/Init/InitWindowController.swift` |
| 09-28 | (M5) 창은 `NSApplication.activate()` + `orderFrontRegardless()`로 앞에 낸다. `activate(ignoringOtherApps:)`는 쓰지 않았다 | 후자는 deprecated라 빌드 경고. macOS 14 협조 방식이라 터미널이 활성이면 포커스는 넘어오지 않지만 창은 맨 앞에 보인다(실측) | `level = .floating` | `InitWindowController.show` |
| 09-28 | (M5) 창을 닫으면(빨간 단추) 그 초안을 취소한 것으로 본다. 초안이 여럿이면 창을 남기고 다음 초안을 보인다 | 닫고 나서 같은 초안이 다시 뜨면 닫을 수 없는 창이 된다 | 닫아도 초안 유지 | `windowShouldClose` |
| 09-28 | (M5) 「이미 등록된 폴더」는 `project_resolve`와 같은 매칭(하위 폴더 포함). 같은 폴더를 보관된 프로젝트가 쓰면 오류로 보관 해제를 알린다. 보관된 프로젝트의 **하위** 폴더는 새로 등록할 수 있다 | 그 폴더의 훅과 스킬이 이미 그 프로젝트를 본다. rootPath 중복 금지가 보관을 포함하므로 같은 폴더는 막는다 | 정확히 같은 폴더만 막기 | `MCPTools.projectInit` |
| 09-28 | (M5) 키가 규칙에 안 맞거나 겹치면 초안은 만들고 `warnings`로 알린다. 키를 안 주면 추천 키. `name`은 필수 | 사용자가 창에서 고치면 되는 일로 Claude가 다시 부르게 하지 않는다 | 오류 | 같은 함수 |
| 09-28 | (M5) 추천 키: 머리글자 2–4자 → 첫 단어 첫 글자+자음 둘 → 앞 3자 → 폴더 이름으로 같은 순서 → `PRJ`, 모두 쓰이면 뒤에 A–Z | 사람이 떠올리는 키(LDG, WIP)에 가깝고 늘 규칙에 맞는 값이 나온다 | 폴더 이름 앞 3자만 | `ProjectKey.suggest` |
| 09-28 | (M5) 초안은 앱 메모리에만(`ProjectDraftQueue`). 앱을 끄면 사라진다 | 등록 전의 초안은 기록이 아니다. CloudKit 동기화 대상도 아니다 | 저장소에 초안 모델 | `Shared/Init/ProjectDraft.swift` |
| 09-28 | (M5) 등록 중 지침 파일이 사라지면 프로젝트까지 되돌리고 창에 「… 파일을 찾을 수 없음」 | 「한 트랜잭션」 요구. 사용자가 체크를 풀고 다시 등록하면 된다 | 없는 파일만 건너뛰기 | `ProjectRegistry.register` |
| 09-28 | (M5) 보관된 폴더의 훅은 기록하지 않되 `SessionEnd`·`SubagentStop`은 열린 세션을 닫는다. 보관할 때 세션을 따로 끝내지 않는다(종료 판정에 맡김) | 보관을 풀었을 때 끝난 세션이 작업중으로 남지 않게. 닫는 것은 새 활동이 아니다 | 모든 훅 무시 | `HookProcessor.sessionEnd`, `mainSession` |
| 09-28 | (M5) 「보관됨」은 사이드바 맨 아래 접힘 구역(기본 접힘, 보관된 것이 있을 때만). 보관된 프로젝트도 골라 보드를 볼 수 있다. 보관·삭제한 프로젝트를 보고 있었으면 대시보드로 옮긴다 | 따로 화면을 만들지 않고 되돌릴 곳을 둔다. 지운 모델을 본문이 다시 읽지 않게 | 설정 화면 | `SidebarView` |
| 09-28 | (M5) 삭제 알림 문구는 「카드 N개와 기록이 함께 삭제됩니다.」(카드가 없으면 「기록이 함께 삭제됩니다.」). 로컬 파일 이야기는 넣지 않았다 | 동작 규칙 설명 문구를 화면에 넣지 않는다 | 파일은 남는다는 문장 | `SidebarProjectParts.swift` |
| 09-28 | (M4 잔여) 버전 기록 시각은 늘 초까지(「15:12:16」) | 같은 분에만 초를 붙이면 목록 안에서 형식이 섞인다 | 같은 분일 때만 | `TimeFormat.timestamp(seconds:)` |
| 09-28 | (M4 잔여) 충돌에서 「로컬 파일로」「앱 내용으로」 어느 쪽이든 읽기로 돌아간다 | 둘 다 고르고 나면 저장 안 한 편집이 없다 | 「로컬 파일로」만 | `GuideConflictView.resolved` |
| 09-28 | (인스턴스 분리) 평소용(Release, `dev.antaeho.waypoint`, 47821, `Waypoint/`)과 개발용 Waypoint Dev(Debug, `dev.antaeho.waypoint.dev`, 47822, `Waypoint-Dev/`)로 나눈다. 번들 ID 끝이 `.dev`면 개발용(`AppInstance`), `WAYPOINT_PORT`·`WAYPOINT_SUPPORT_DIR`가 먼저. `PRODUCT_NAME`은 그대로 둬 Debug 빌드 경로가 같다 | 개발하며 앱을 껐다 켜고 실측하느라 다른 저장소 추적이 끊기고 실측 프로젝트(PRB·NOTE)가 실제 기록에 섞였다 | 실행 인자로 인스턴스 고르기(같은 번들 ID라 동시 실행·로그인 항목이 섞인다) | `project.yml`의 `configs: Debug:` 삭제 후 `xcodegen generate` |
| 09-28 | (인스턴스 분리) Dev 표시는 메뉴 막대 `hammer`·「Waypoint Dev 열기」·사이드바 맨 위 「Dev」(`Theme.Dev`). 표시 이름 `Waypoint Dev`는 Info.plist에만 있고 앱 메뉴 이름은 두 빌드 모두 「Waypoint」 | 둘이 함께 떠 있을 때 메뉴 막대와 창에서 가려 보면 된다 | `PRODUCT_NAME`을 바꿔 앱 메뉴까지 바꾸기(빌드 경로가 바뀐다) | `DevBadge`, `WaypointApp`의 `MenuBarExtra` |
| 09-28 | (인스턴스 분리) 평소용 설치는 `scripts/install-local.sh`. 로그인 항목은 System Events `make login item`(없을 때만) | 앱 코드 없이 스크립트에서 끝나고, 이 기기에서 System Events 접근이 이미 허용돼 있다. SMAppService는 앱 안에 등록 경로(화면·설정)를 더해야 한다 | `SMAppService.mainApp.register()`, LaunchAgent plist | `osascript -e 'tell application "System Events" to delete login item "Waypoint"'` |
| 09-28 | (인스턴스 분리) 실측 폴더는 `scripts/dev-probe-setup.sh`로 폴더 안 `.claude/settings.local.json`(Dev 훅)과 `.mcp.json`(`waypoint` → 47822)만 쓴다. 전역 설정은 평소용 그대로 | 전역 설정을 인스턴스마다 바꾸면 평소 추적이 끊긴다. MCP는 프로젝트 범위가 사용자 범위보다 먼저(문서·실측). 로컬 범위는 `~/.claude.json`에 적혀 쓰지 않았다 | 실측 때만 전역 설정을 바꾸기 | `dev-probe-setup.sh --remove <폴더>` |
| 09-28 | (인스턴스 분리) 평소용에서 실측 프로젝트 PRB·NOTE를 앱의 「삭제…」로 지웠다(폴더는 그대로). PRB는 Dev에 새로 등록 | 실측 폴더는 전역 훅도 받으므로 평소용이 모르는 폴더여야 기록이 섞이지 않는다 | 평소용에서 보관(그러면 `SessionStart`의 「없음」 한 줄도 안 나온다. 기록은 남는다) | 전환 전 백업 저장소로 교체 |

## 로컬 확인 (2026-09-28, macOS 26 + Xcode)

- `main`을 합친 뒤 `xcodegen generate` → `swift test`, macOS·iOS 앱 빌드 모두 경고·오류 0으로 통과했다. 클라우드에서 쓴 코드에 고칠 컴파일 오류는 없었다.
- `NWConnection` Sendable 경고는 나지 않았다. 콜백마다 `MainActor.assumeIsolated`로 감싸고 리스너·연결을 `.main` 큐에서 돌려서다.
- 병렬 테스트에서 가끔 signal 11: 같은 스키마로 컨테이너를 동시에 열 때 Core Data 트리거 SQL 생성에서 죽었다. `WaypointStore.makeContainer`에 락을 걸었다.

## 실측 (2026-09-28, Claude Code 2.1.283)

- 사용자 전역 `~/.claude/settings.json`에 Waypoint 훅을 추가하고(기존 `cc-hook.sh` 항목은 그대로), 기본 저장소에 `TRK`(이 저장소)·`PRB`(`~/workspace/waypoint-probe`)를 넣어 `claude -p` 세션으로 확인했다.
- 완료 조건 1: 세션 2개가 대시보드에 live로 보였다. 끝나면 사라지는 것은 `SessionEnd`가 온 세션만 — 동시 실행 두 번 모두 하나는 `SessionEnd`가 안 와 남았다(SPEC 5장).
- 완료 조건 2: 앱을 끈 채 돌린 세션의 5줄이 outbox에 쌓였고, 앱을 켜자 흡수되어 파일이 지워지고 끝난 세션으로 기록됐다.
- `sleep`은 Claude Code가 포그라운드 실행을 막아 `ping -c 45 127.0.0.1`로 긴 명령을 대신했다.

## 막힌 것

- 새 옵셔널 필드 `Project.lastEventAt`는 SwiftData 자동 경량 마이그레이션으로 붙는다고 보고 있다(미검증). 이미 있는 저장소는 이 값이 비어 있어, 다음 이벤트가 올 때까지 「마지막 활동」이 세션·카드 기준으로만 보인다.
- 실측 결과는 `docs/SPEC.md` 5장 「실측 결과」, 남은 것은 같은 장 「남은 문제」(`SessionEnd`가 빠진 세션 처리, `clear`/`compact` 세션 ID).

## 제안(하지 않음)

- `DashboardQuery.rows`와 `summary`는 여전히 프로젝트의 **끝난 세션까지** 모두 훑는다. 세션은 이벤트보다 훨씬 천천히 쌓여 지금은 두었다. 느려지면 끝나지 않은 세션만 `@Query`로 받아 넘기도록 바꾼다.

- 외부 Swift 패키지는 추가하지 않았다. MCP(M3)도 공식 Swift SDK 없이 필요한 부분만 직접 구현했다.

## M4 실측 (2026-09-28)

- 실제 앱(Debug)에서 PRB(`~/workspace/waypoint-probe`)의 `GUIDE.md`를 후보 줄 「추가」로 등록했다. TRK에는 등록하지 않았다.
- 앱 편집·⌘S → 파일에 반영(`cat`), 버전 app. `printf` 덮어쓰기와 `python3` 임시 파일 → `os.replace` 모두 1초 안에 반영, 버전 local. 저장 안 한 편집 중 `sed -i`로 파일을 고치자 충돌 → 비교 화면 → 「로컬 파일로」 반영. 앱을 끈 채 고친 내용은 다시 켤 때 반영(local).
- 교체 전 저장소는 scratchpad에 복사해 두었고, 복사본에서 먼저 새 필드 마이그레이션(자동 경량)을 확인했다.

## M6 iPhone과 CloudKit (2026-09-28)

| 날짜 | 무엇을 | 왜 | 대안 | 되돌리는 방법 |
|---|---|---|---|---|
| 09-28 | 컨테이너를 인스턴스마다 따로(`iCloud.dev.antaeho.waypoint`, `….dev`), 둘 다 Development 환경 | 개발·실측 기록이 평소용 iPhone에 섞이지 않게. Development는 스키마를 손으로 배포하지 않아도 된다. 개인 앱이라 Production이 필요 없다 | 한 컨테이너 + 영역 나누기, Production 배포 | `AppInstance.cloudKitContainerIdentifier`, `project.yml`의 `WAYPOINT_CONTAINER` |
| 09-28 | `WAYPOINT_SUPPORT_DIR`로 저장 폴더를 옮긴 실행은 CloudKit을 끈다(`WAYPOINT_CLOUDKIT=0`과 같게) | 이 변수는 「실제 저장소를 건드리지 않고 띄우기」용인데, 미러링이 켜져 있으면 실제 컨테이너의 기록을 받아 오고 임시 기록을 올린다 | 명시한 `WAYPOINT_CLOUDKIT=0`만 | `AppInstance.cloudKitContainer(environment:)`의 두 번째 조건 |
| 09-28 | iOS 앱이 `registerForRemoteNotifications()`를 직접 부른다(`PhoneAppDelegate`, Release 포함) | 실측: 등록하지 않은 빌드는 Mac 변경을 50초 넘게 못 받았고(가져오기 0번), 등록한 빌드는 Mac 내보내기 1–2초 뒤 알림 → 가져오기. macOS 쪽 미러링은 로그에 알림 수신기를 스스로 열었다 | — | `WaypointApp`의 `@UIApplicationDelegateAdaptor` |
| 09-28 | iOS는 CloudKit 가져오기가 끝날 때마다 새 `ModelContext`를 만들어 목록을 다시 읽는다(`RootView`, `.id(generation)`) | 실측: 가져오기가 끝나도 메인 context의 세션이 옛 `endedAt`(nil)을 들고 있어 끝난 세션이 30초 틱 뒤에도 작업중에 남았다. 새로 생긴 세션은 떴다. 목록 스크롤 위치는 가져오기마다 맨 위로 돌아간다(한 화면이라 두었다) | 원격 변경 알림에서 `rollback` 등으로 새로 고치기(SwiftData에 공개 API 없음) | `RootView`를 `@Query` 두 개만 두던 꼴로 |
| 09-28 | 작업중 목록은 시안처럼 카드를 이어 놓고 프로젝트 이름을 카드 윗줄에 둔다(그룹 머리 없음). 순서는 대시보드 그룹 순서 | 시안 구조 그대로. 한 프로젝트 안의 줄은 이어져 묶음이 보인다 | 프로젝트 이름 머리 줄 | `PhoneHomeView` |
| 09-28 | 「방금 기록된 아이디어」 = 보관 안 된 프로젝트의 idea 상태 카드 중 최근 7일에 생긴 것, 새것부터(`IdeaInbox`) | 오래된 아이디어는 Mac 보드에서 정리한다. iPhone은 방금 생긴 것만 빠르게 분류 | 기간 없이 전부 | `IdeaInbox.defaultWindow` |
| 09-28 | 시안의 아래 탭 줄(작업중·프로젝트·기록·지침)과 상태 막대는 옮기지 않았다 | 이번 범위는 작업중·아이디어 분류뿐이고, 없는 화면으로 가는 탭을 두지 않는다 | — | — |
| 09-28 | Debug 빌드에만 콘솔 실측 로그(`[waypoint] …Z`)와 실행 인자 `-WaypointMoveIdea <ID>` | `devicectl`에 화면 캡처가 없어 iPhone에 뜬 시각을 콘솔로 잰다. 인자는 버튼과 같은 `PhoneIdeaAction.move`를 탄다 | 사용자가 화면을 보고 알려 주기 | `#if DEBUG` 블록 |
| 09-28 | Mac은 CloudKit 가져오기가 끝나면 새 context로 카드를 읽어, 메인 context에 이미 올라온 같은 카드 중 `updatedAt`이 더 늦은 것의 값을 옮겨 적고 저장한다(`RemoteCardMerge`, `AppServices`) | 실측: iPhone에서 옮긴 카드가 Mac 보드에 아이디어로 남았고, Mac에서 본문만 고친 `card_update`가 저장소 상태를 아이디어로 되돌렸다(PRB-3·PRB-4). 다시 fetch해도, `rollback`해도 옛 값 그대로였다. SwiftData에 객체를 새로 읽는 API가 없다. 서버·훅·MCP·화면이 모두 메인 context를 붙잡고 있어 context를 바꾸는 것보다 좁게 고쳤다. iPhone이 고치는 것은 카드뿐이라 카드만 맞춘다 | 가져오기마다 메인 context 대신 새 context로 전부 갈아타기 | `AppServices.observeCloudKitImports` 제거 |
| 09-28 | 앱 아이콘: 이정표(후보 1). 평소용 `AppIcon`(클레이 바탕), 개발용 `AppIconDev`(검은 바탕, Debug 구성만 `ASSETCATALOG_COMPILER_APPICON_NAME`) | 사용자 선택. 두 인스턴스를 Dock·홈 화면에서 가려 보게 | — | `project.yml`의 `ASSETCATALOG_COMPILER_APPICON_NAME`, `App/Assets.xcassets` |
| 09-28 | iPad 방향 4개(`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`) | iOS 기기 빌드가 「All interface orientations must be supported」 경고를 냈다 | iPhone만 지원(`TARGETED_DEVICE_FAMILY=1`) | `project.yml` 한 줄 |
| 09-28 | 늦은 주입: 블록을 받지 못한 메인 세션의 다음 `UserPromptSubmit`에 같은 블록을 한 번(`Session.contextProjectKey`로 판정), 평문 stdout | 등록 전에 시작하거나 다른 폴더에서 옮겨 온 세션은 `SessionStart` 블록을 못 받아 스킬이 카드를 붙이지 못했다(chainmate). 문서상 `UserPromptSubmit` 평문 stdout은 컨텍스트가 되고, `SessionStart`와 같은 방식이라 스크립트가 단순하다 | JSON `additionalContext`(v2.1.196+, 10,000자) | `HookProcessor.lateContext`, `HookRouter.lateContextEvents`, 스크립트 `case`를 `SessionStart`만으로 |
| 09-28 | 세션의 프로젝트는 옮기지 않는다. 「다른 프로젝트로 옮긴 세션」은 `contextProjectKey != project.key` 비교로만 다룬다 | 세션을 옮기면 열린 카드 연결·서브에이전트·이벤트 소유가 함께 걸리고, 잠깐 `cd`한 것만으로 프로젝트가 뒤집힌다. 레코드는 두고 cwd 기준 다른 프로젝트 블록만 주면 `card_start`가 「세션과 카드의 프로젝트가 다름」으로 막힌다 | UserPromptSubmit의 cwd로 세션을 다른 프로젝트로 옮기기 | — |
| 09-28 | outbox로 흡수한 훅(`SessionStart` 포함)은 주입 텍스트를 만들지 않고 `contextProjectKey`도 적지 않는다(`delivers: false`) | 이미 지난 훅이라 대화에 들어가지 않았다. 적어 두면 앱이 꺼진 채 시작한 세션이 블록을 영영 못 받는다 | 흡수 때도 키 적기 | `HookProcessor.handle(_ entry:)`의 `delivers: false` |
| 09-28 | 보드 작업중 칸에 카드 없는 세션 타일(카드 아래), 칸 머리 개수는 카드 + 타일 | 대시보드 작업중 줄·사이드바·프로젝트 표 작업중 수가 이미 카드 없는 메인 세션을 센다. 보드만 빼면 같은 프로젝트의 숫자가 화면마다 다르다 | 카드 수만 | `BoardColumnView` 머리 `items.count` |
| 09-28 | 카드 없는 세션 줄·타일의 제목 자리에 그 세션의 마지막 사용자 요청 문장(`Session.lastPrompt`, `UserPromptSubmit`의 `prompt`, 300자까지). **프라이버시**: 사용자가 Claude Code에 보낸 문장이 평소용 저장소와 개인 CloudKit(개인 iCloud 컨테이너)에 저장된다. 세션당 마지막 1개만, 300자까지, 세션을 지우면 함께 지워진다 | 타일이 「카드 없음 · sess·8f33 · layout.md」만 보여 무슨 작업인지 알 수 없었다. 앱은 LLM을 쓰지 않으므로 요약은 할 수 없고, 사용자 자신의 문장이 가장 알아보기 쉽다 | 첫 요청 문장(오래 이어진 세션은 지금 일과 멀다), 전사 파일 읽기(앱이 훅 밖의 파일을 읽게 된다) | `HookProcessor.userPromptSubmit`의 저장 줄 삭제, 화면은 `SessionFormat.noCardTitle` |
| 09-28 | `lastPrompt`에서 빼는 것: 서브에이전트 훅, 빈 문장, `<`로 시작하는 자동 메시지(`<agent-message>`, `<task-notification>` 등). 붙여 넣은 글 `<pasted_content …>`는 사용자 입력이라 태그만 벗겨 남긴다. outbox로 늦게 온 옛 프롬프트는 `at >= lastSeenAt`일 때만(비어 있으면 늘) 바꾼다 | 서브에이전트 완료 알림도 `UserPromptSubmit`으로 와서(실측) 그대로 두면 사용자 문장을 덮는다. 전사에서 사용자가 붙여 넣은 글이 `<pasted_content`로 시작하는 것을 봤다 | 알려진 태그 목록만 빼기 | `HookParsing.userPrompt` |
| 09-28 | 평소용 반영 순서: 훅 스크립트 교체 → 앱 설치 | 새 앱 + 옛 스크립트면 앱이 UserPromptSubmit에 블록(200)을 주고 키를 적는데 옛 스크립트는 찍지 않아 한 번뿐인 주입이 사라진다. 새 스크립트 + 옛 앱은 204라 무해하다 | 앱 먼저 | — |

### 관찰 (2026-09-28, Dev)

- 처음 만든 컨테이너로 바로 켜자 `CKError 5`(내부 1014)로 미러링 설정이 실패했고 다시 시도하지 않았다. 4분 뒤 다시 켜니 성공했다.
- 기존 Dev 저장소(PRB 프로젝트·카드·세션·이벤트 9개)는 설정 직후 한 번에 올라갔다(「Found 9 objects needing export」 → 「Modify records finished」). iPhone에 PRB가 떴다.
- Mac 내보내기는 시스템이 「discretionary」로 다룬다(`nsurlsessiond` 로그, 앱이 막 켜졌을 때만 non-discretionary). 대개 저장 1–1.5초 뒤 끝났지만(창 연 채 뒤에 있을 때 5번, 창 닫고 메뉴 막대만일 때 5번 모두), 한 번은 요청이 5분 넘게 멈췄다가 풀렸다. 코드로 고칠 공개 API가 없어 두었다.
- 40초 실측 세션 하나에 Mac 내보내기 5번(시작·도구 전후·끝).

### 완료 조건 실측 (2026-09-28, Dev, `claude -p` + `ping -c 40`, 시각은 두 기기 NTP 기준 ±1초)

| 측정 | 결과 |
|---|---|
| Mac 세션 시작(`startedAt`) → iPhone 작업중 표시(콘솔 `rows=1 live`) | 3.1초, 2.7초, 7.6초(마지막은 Mac 내보내기 1.1초 뒤 알림이 5.3초 늦게 옴) |
| Mac 세션 끝(`endedAt`, `SessionEnd`) → iPhone에서 사라짐(`rows=0`) | 2.5초(가져오기마다 새 context로 읽게 고친 뒤). 고치기 전에는 30초 틱 뒤에도 남았다 |
| iPhone 「다음 할 일로」(`-WaypointMoveIdea`) → Mac 저장소 `next` | PRB-2 2.7초 이하, PRB-3 2.3초, PRB-5 2.3초(0.5초 간격 조회) |
| iPhone에서 옮긴 카드 → Mac 화면·메인 context | 고치기 전: 보드에 아이디어로 남고 Mac 저장이 상태를 되돌림(PRB-3·4). 고친 뒤(PRB-5): 3초 안에 보드 「다음 할 일」 칸, `card_get` next, 본문 수정 뒤에도 저장소 next |

- 세션 종료는 네 번 모두 `SessionEnd`가 왔다(`endedAt == lastSeenAt`).
- iPhone 앱이 뒤에 있을 때도(`applicationState` 2) 알림이 와서 가져오기가 돌았다.
- Mac 화면의 최근 기록 인스펙터와 `card_get`의 `recentEvents`에는 iPhone이 남긴 `card.status` 이벤트가 앱을 다시 켤 때까지 안 보인다(이미 읽은 카드의 이벤트 관계가 옛 값). 카드 상태는 맞다.

### 평소용 반영 (2026-09-28 20:02)

- 백업: scratchpad `m6/backup-20260928-200211/`(sqlite `.backup` + 폴더 통째 복사). 무결성 ok, TRK·CHM, 카드 8, 세션 14, 이벤트 411.
- `scripts/install-local.sh`: 「Waypoint 0.0.1 설치됨: /Applications/Waypoint.app · PID 60977 · 127.0.0.1:47821 LISTEN · 로그인 항목 이미 있음」. 컨테이너가 앞선 Release 빌드 때 만들어져 있어 첫 실행에 CloudKit 설정 성공(환경 Sandbox = Development), 기존 기록 453 + 54개를 8초 안에 올렸다. 오류 로그 없음.
- 평소용 iPhone 앱(Release) 설치·실행 뒤 기기의 저장소를 `devicectl device copy from`으로 꺼내 조회: TRK·CHM, 카드 8, 세션 14, 이벤트 412, 이 저장소 메인 세션(29de4c3b…) 끝나지 않음.
