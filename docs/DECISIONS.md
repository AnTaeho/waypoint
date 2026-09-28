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

- 외부 Swift 패키지는 추가하지 않았다. MCP(M3)에서 공식 Swift SDK를 쓸지는 그때 판단.
