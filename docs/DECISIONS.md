# 결정 기록 (무인 진행)

2026-09-27~28 밤 클라우드 세션이 사용자 없이 정한 것. 아침에 이 파일만 읽고 뒤집을 수 있게 적는다.
형식: 날짜 · 무엇을 · 왜 · 대안 · 되돌리는 방법.

## Codex 연결 — 2026-09-30

- macOS + Xcode 27, Codex CLI 0.159.2에서 작업했다. 아래의 Linux 미검증 기록은 초기 구현 당시 이력이다.
- 기존 Claude 세션 ID·claudePid는 유지하고 Codex에 providerRaw, codex: ID 접두사, processPid를 추가했다. 기존 카드·인수인계·서버·상태 규칙을 공유한다. 되돌리기는 연결 해제와 이전 앱 재설치이며 기존 Claude ID 변환은 필요 없다.
- 공식 Codex 훅 문서의 JSON 값·apply_patch·Agent/spawn_agent 입력을 연결부에서 정규화했다. 성공 결과가 확인된 패치만 기록한다. 전사 감시는 안정된 인터페이스가 아니어서 쓰지 않는다.
- Codex 설치기는 사용자 훅·MCP·스킬을 백업 후 추가하며 신뢰 상태는 바꾸지 않는다. Python 3.11+ 표준 라이브러리만 사용한다. 해제는 이 설치기의 항목만 지운다.
- 검증: Swift 303개·Codex 설치/브리지 10개·기존 Claude 훅 테스트 통과. macOS Debug 팀 서명·iOS Simulator 빌드 성공(Swift 경고 0, AppIntents 메타데이터 건너뜀 경고만 있음).
- 개발용 앱 + 격리 저장소에서 실제 HTTP·MCP로 카드 생성/연결/파일 변경/인수인계/종료를 확인했다. 앱을 끈 동안 설치된 Codex 브리지가 outbox에 기록하고 재실행에서 Codex 세션으로 흡수하는 것도 확인했다. 같은 원본 ID의 Claude 세션은 열린 상태로 유지됐다.
- doc-codex-*는 문서 기반 픽스처다. 실제 Codex 에이전트의 훅·하위 에이전트 동시 실행과 iPhone 기기 동기화는 사용자 신뢰 설정 후 별도 확인한다. 신뢰 우회 실행은 하지 않았다.
- 검증 후 `scripts/install-local.sh`로 평소용을 팀 서명 Release 빌드·갱신했고 47821 리스닝 및 MCP 0.6.0 응답을 확인했다. `install-codex.py`로 실제 사용자 훅·MCP·waypoint-tracker를 설치했다. 사용자 설정 백업을 남겼으며 훅 신뢰는 사용자가 직접 진행한다. iPhone 기기 앱은 이번에 설치하지 않았다.

## 초기 실행 환경

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
| 09-28 | 카드 없는 세션 줄·타일(대시보드·보드·iPhone)의 경과는 **마지막 요청 시각**(`Session.lastPromptAt`)부터, 없으면 비운다. 대시보드·iPhone의 카드 줄도 세션 시작 대신 **카드 연결 시각**부터(보드 카드와 같게) | 세션 시작은 Waypoint가 세션을 처음 본 시각이라(등록 전에 시작한 chainmate 세션이 첫 훅부터 「4시간 37분」) 세션 나이도 지금 작업 시간도 아니다. 제목 자리가 마지막 요청 문장이니 경과도 그 요청부터가 맞다 | 세션 시작 기준 유지, 요청 시각 없을 때 `startedAt`으로 대신 | `SessionFormat.rowElapsed`에서 `lastPromptAt` 대신 `startedAt` |
| 09-28 | 평소용 반영 순서: 훅 스크립트 교체 → 앱 설치 | 새 앱 + 옛 스크립트면 앱이 UserPromptSubmit에 블록(200)을 주고 키를 적는데 옛 스크립트는 찍지 않아 한 번뿐인 주입이 사라진다. 새 스크립트 + 옛 앱은 204라 무해하다 | 앱 먼저 | — |
| 09-28 | (앞 결정 뒤집음) 카드가 active를 떠나면 그 카드의 열린 세션 연결을 모두 닫는다(`CardLifecycle.move`, 서브에이전트 연결 포함, `card.detached` `reason: card-moved`). 상태 복귀는 하지 않는다. 앱이 시작 직후·60초마다·CloudKit 가져오기 뒤 「active가 아닌 카드의 열린 연결」을 닫는다(`closeStrayLinks`, `reason: status-not-active`). 이전에는 「move는 열린 연결을 건드리지 않는다」(`move` 주석, 작업중 카드 드래그 허용 결정의 근거) | nihongo 세션이 `card_start(NHG-2)` 뒤 `card_update(NHG-2, status: idea)`로 카드를 돌렸는데 연결이 열린 채 남았다. 세션이 멈추자 사이드바·프로젝트 표는 「멈춤 1」(카드 기준 `workState`)인데 보드 작업중 칸은 비었다(카드는 아이디어 칸, 세션은 카드가 붙어 있어 타일도 아님). 연결을 닫으면 그 세션이 카드 없는 세션 타일이 되어 모든 화면이 같은 수를 센다 | 요약·대시보드가 `status == active` 카드의 연결만 세게 하기(연결 기록이 계속 거짓으로 남는다), 연결을 닫고 `statusBeforeActive`로 복귀(사용자·Claude가 정한 새 상태를 덮는다) | `move` 끝의 `closeOpenLinks` 호출과 `AppServices`의 `closeStrayLinks` 호출 삭제 |
| 09-29 | (앞 결정 뒤집음) 보드 칸 최소 폭 165 → 220, 프로젝트 보드는 인스펙터를 닫은 채 시작(보드 전용 상태, 연 뒤에는 앱을 끌 때까지 기억). 카드·칸 안쪽 가로 여백 12 → 10. 이전: 처음 200(가로 스크롤 결정)이었다가 0752e51에서 「1280 창에 인스펙터가 열려도 네 칸이 다 들어가게」 165로 내렸다 | 165 근처에서 카드 제목이 4~5줄로 꺾여 읽기 어려웠다(chainmate 보드, 긴 제목 5줄). 인스펙터를 열어 둔 채 네 칸을 끼워 넣는 전제를 버리면 1280 창에서 칸이 약 240이 되어 같은 제목이 3줄. 더 좁은 창은 칸을 줄이지 않고 가로로 넘긴다 | 인스펙터 열린 채 165 유지, 보드에서 인스펙터 상태를 기억하지 않고 들어올 때마다 닫기 | `Theme.Size.boardColumnMinWidth`, `Theme.Board.cardPadding*`/`columnPadding*`, `RootView.showsBoardInspector` 기본값 |

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

## 2026-09-30 — 세션 시작 폴더와 실제 작업 프로젝트를 분리

상위 workspace에서 시작한 Codex 대화가 하위 Waypoint 저장소를 수정해도 기록이 빠졌다. 시작 cwd만으로 귀속하지 않고 실제 세션 ID에 대한 명시적 session_bind와 변경 파일 경로를 함께 사용한다. 프로젝트 전환은 현재 연결만 바꾸고 이전 기록은 유지한다. 파일 소속이 다른 프로젝트이면 현재 카드에 붙이지 않는다. 과거에 수집되지 않은 훅·파일 로그를 만들어 복원하지 않는다.

## 2026-09-30 — 저장 직후 화면 갱신, 완료 뒤 대화 타일 분리

30초 TimelineView 갱신만 기다리지 않고 저장 알림·로컬 요청 처리를 화면 갱신에 연결한다. 시간 경과 확인은 5초, 종료 누락 세션 점검은 10초로 줄인다. 완료한 카드에서 떨어진 세션은 이후 새 사용자 요청이나 실행 중인 하위 작업이 없는 한 작업중 타일로 되살리지 않는다. 대화와 역사 기록은 종료·삭제하지 않는다.

### 2026-09-30 — 종료 누락과 최신 상태 유지

Claude 네이티브 실행 파일의 이름이 버전 번호여서 PID를 놓치던 브리지를 경로 식별로 수정한다. PID를 모르는 세션의 24시간 대기 규칙은 30분 활동 유효기간으로 대체한다. 살아 있는 PID는 조용해도 유지하고, 자동 정리 때 기록을 삭제하거나 카드를 완료하지 않는다. 실제 ID의 새 훅 또는 명시적 session_bind로 재연결하며 옛 PID·카드 연결은 복원하지 않는다. 10초 타이머를 common 모드로 실행하고 앱 활성화·잠자기 복귀 때도 outbox 흡수와 세션 점검을 수행한다.

### 2026-09-30 — 실제 수신에 근거한 AI 연동 진단

설정 설치와 실제 수신을 분리하고, 활동이 없다고 연동 장애를 추측하지 않는다. 도구별 훅 설정·포트·마지막 수신·연결 프로젝트와 공유 서버·MCP·outbox 상태를 한 패널로 제공한다. 사용자 범위 검사임을 명시해 프로젝트별 설치를 미설치로 단정하지 않는다. 신뢰 승인 여부를 추측하거나 자동 승인하지 않는다. 로컬 진단 기록은 입력 내용을 제외한 시각·프로젝트 키만 저장하며 앱 재시작 후에도 유지한다.

### 2026-09-30 — 작업 상태는 이벤트를 우선

시간만으로 멈춤을 단정하던 표시를 도구 작업·응답 진행·입력 대기·승인 대기·활동 없음·추적 만료·세션 종료로 구분한다. 병렬 도구는 호출 ID별로 저장하고 순서가 뒤바뀐 완료도 해당 호출만 닫는다. 긴 도구 작업과 입력 대기는 15분만으로 상태를 바꾸지 않는다. 상태 필드는 기존 저장소에 추가하며 이전 세션과 coarse API는 호환한다. 모든 도구의 시작·완료를 받도록 matcher를 확장하고 사용자 승인 흐름에는 개입하지 않는다.

## 2026-10-01 — outbox에 앱이 읽는 필드만 남긴다

PreToolUse·PostToolUse matcher를 `*`로 넓힌 뒤 앱이 꺼진 동안 outbox에 모든 도구의 입력·출력 원문(읽은 파일 내용, 명령 출력, Edit 문자열)이 쌓였다. 훅 스크립트가 outbox에 쓰기 전에 jq 허용 목록으로 앱이 읽는 필드만 남기고, 줄 수·커밋·카드 ID는 같은 값이 나오는 자리표시로 바꾼다. 앱 코드는 바꾸지 않아 옛 앱도 새 줄을 그대로 읽는다. 실시간 POST와 로깅 모드는 원본을 유지한다. 대안: 오프라인 줄 수 포기(기록 차이가 생겨 버림), 앱에 새 카운트 필드 추가(설치 순서 문제). 되돌리려면 스크립트의 outbox 적재를 원본 `line`으로 바꾸면 된다(앱 쪽 변경 없음).

## 2026-10-01 — 요청 문장은 30일만 둔다, iCloud 동기화는 유지

- 요청 이벤트(`user.prompt`)의 문장과 끝난 세션의 `lastPrompt`를 30일 뒤 지운다. 이벤트·시각·세션·카드 연결은 남긴다. 모든 요청 문장이 기한 없이 쌓이고 동기화되던 것을 줄인다. 되돌리거나 기간을 바꾸려면 `PromptRetention.days`만 고친다(이미 지운 문장은 돌아오지 않는다).
- 요청 문장도 iCloud(개인 Private DB) 동기화를 유지한다. 문장만 동기화에서 빼려면 저장소 구성을 둘로 나눠야 해 범위가 크다. 대신 30일 보관으로 노출 기간을 줄인다. 동기화를 빼려면 로컬 전용 구성을 따로 만들어 문장을 옮겨야 한다.

## 2026-10-01 — 완료 근거: 검증 명령·결과·출처를 조건에 잇는다 (TRK-10)

| 무엇을 | 왜 | 대안 | 되돌리는 방법 |
|---|---|---|---|
| 근거는 새 이벤트 종류 `check`(payload `CheckRecord`)로 남기고 모델 필드는 늘리지 않는다. payload에 `text` 키를 두지 않는다 | 기존 카드·CloudKit 스키마를 그대로 두고 마이그레이션 없이 동작. 옛 앱은 모르는 종류를 `note`로 읽는데 `text` 없는 메모는 숨겨 근거가 메모로 새지 않는다 | `Criterion`에 결과 필드 추가(조건을 통째로 바꾸는 `card_update`에 지워지고 동기화 스키마가 바뀐다), `note` + `kind: check` | `EventType.check`와 기록 경로(`HookProcessor.recordCheck`, `card_evidence`) 삭제. 남은 이벤트는 옛 앱처럼 숨는다 |
| Claude 성공·실패 구분: `PostToolUse` = 종료 코드 0, `PostToolUseFailure`의 `error` 첫 줄 `Exit code N` | 문서(「A Bash command … fails」·`Exit code N` 첫 줄)와 실측 2.1.286(`bash test-fail.sh` → `PostToolUseFailure` `"Exit code 3\n1 test failed"`, 성공 `PostToolUse`에는 종료 코드 필드 없음)이 같다 | 출력 글로 추정 | `HookParsing.exitCode` |
| 결과를 모르면 `unknown`으로 남기고 통과로 보지 않는다: 중단, `Exit code` 없는 실패, 백그라운드 실행(실측: 시작 때 `PostToolUse` + `backgroundTaskId`, 끝난 코드는 훅으로 오지 않음), `| tail`·`; echo`·`|| true`·`&`처럼 다른 명령의 결과가 남는 꼴 | `swift test | tail`은 pipefail이 없으면 실패해도 0이다. 「검증 이후 변경과 세션 종료만으로 검증 완료를 오인하지 않는다」 | 파이프는 통과로 보기 | `VerificationCommand.Parsed.decidesExitStatus` |
| 조건 상태 기준은 조건에 직접 붙은 에이전트 보고, 훅 기록은 같은 검증 조각·보고 전 15분 안이면 「확인됨」으로 올린다. 다르면 훅 결과, 보고 뒤 같은 명령을 다시 돌렸으면 그 결과 | 훅은 어느 조건의 검증인지 모른다. 실행을 직접 본 기록이 보고보다 믿을 만하다. 명령 문자열 완전 일치는 `cd … &&`·`2>&1` 때문에 거의 맞지 않아 검증 조각으로 비교한다 | 문자열 완전 일치, 창 없이 아무 때나 | `CardEvidence.confirmWindow`, `decide` |
| 오래된 근거는 그 카드의 `file.changed`만 본다(커밋은 보지 않음). 같은 시각은 오래되지 않음 | 테스트 → 커밋은 흔한 순서이고 커밋은 코드를 바꾸지 않는다. `swift test`가 같은 호출에서 `Package.resolved`를 바꿀 수 있다 | 커밋도 변경으로 보기 | `CardEvidence.evaluate`의 `latestChange` |
| 카드가 붙지 않은 세션의 검증 실행은 기록하지 않는다 | 조건과 이을 곳이 없고 프로젝트 이벤트로 쌓이면 활동 탭만 시끄럽다 | 프로젝트 이벤트로 기록 | `recordCheck`의 카드 조건 |
| `card_evidence.criterion`은 1부터(저장은 0부터 + 조건 글) | 사람과 에이전트가 「조건 1」로 말한다. 조건 글을 함께 저장해 조건을 바꾸면 옛 보고가 엉뚱한 조건에 붙지 않는다 | 0부터 | `MCPTools+Evidence` |
| 검증 명령 패턴은 Swift 상수 한 곳(`VerificationCommand.pattern`)과 훅 스크립트 `verify_pattern`에 같은 문자열로 두고 테스트로 비교한다. outbox는 패턴에 맞는 명령의 원문을 남긴다(출력은 여전히 남기지 않음) | 앱이 꺼진 동안의 검증 실행도 근거가 되게. 셸·앱 판정이 어긋나면 outbox 근거가 사라진다 | 스크립트가 판정 결과만 남기기(앱 코드와 판정이 둘로 갈린다) | 스크립트 `command_shape`의 `verify_pattern` 줄 삭제 |
| 실패 색은 새 색 대신 `liveText` | 팔레트가 따뜻한 계열만 쓴다(DESIGN). 빨강은 처음 등장 | 새 빨강 토큰 | `Theme.Evidence.fail` |

실측(Dev, Claude Code 2.1.286, `~/workspace/waypoint-probe`, PRB-6 조건 3개): `card_start` → `bash test-pass.sh`(0) → `bash test-fail.sh`(3) → `card_evidence` 조건 1 pass·조건 2 fail. 저장소에 훅 근거 `pass`/`exitCode 0`, `fail`/`exitCode 3`(`source: hook`)과 보고 2건(`criterion` 0·1). 두 `card_evidence` 결과 모두 `confirmed: true`. 세션 종료 뒤 PRB-6은 next(done 아님). 다음 세션에서 같은 카드에 `note.txt`를 고치자 `file.changed`(06:25:50)가 근거(06:25:16) 뒤에 생겨 조건 1은 「변경 후 미검증」 조건이 된다. 조건 3은 근거 없음(미검증).

## 2026-10-01 — Codex 사용량은 대화 기록 파일 끝에서 읽는다

Codex 한도는 `~/.codex/sessions`의 최근 기록 파일 끝부분에서 마지막 `limit_id: "codex"` 줄을 읽는다(네트워크 없이, 큰 파일 전체를 읽지 않게). 다른 한도(`premium`·`base_model_inference`)가 같은 파일에 섞여 오므로 걸러 낸다. 사용량 표시는 설정 창에서 도구별로 끌 수 있다(기본 켬). 대안: Codex 앱 서버·API 조회(네트워크·프로세스 의존이라 버림). 되돌리려면 설정에서 Codex를 끄거나 `UsageMonitor.reloadCodex`를 빼면 된다.

## 2026-10-01 — 미처리 기록 저장 실패 시 원본 보존과 재시도 (TRK-32)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 저장 실패한 줄부터 끝까지를 떼어 낸 파일에 남기고 그 뒤 파일까지 멈춘다. 다음 흡수가 그 줄부터 다시 한다 | 순서가 중요하다(`SessionStart` 전에 `Stop`이 들어가면 안 된다). 실패 원인은 대개 디스크·저장소 전체 문제라 뒤 줄도 실패한다 | 실패한 줄만 따로 빼고 계속 | `Outbox.drain`의 `preserve` 대신 `continue` |
| ~~저장 실패로 남긴 줄은 다음 앱 실행 때만 다시 흡수한다.~~ (TRK-33에서 뒤집음, 아래 항목) 같은 실행에서는 10초 점검·**다시 점검**·서버 준비 때도 흡수하지 않는다(`AppServices.outboxHeld`). 횟수 제한은 없다 | 아래 rollback 한계 때문에 같은 context로 다시 처리하면 잘못된 기록(세션 id `""`, 세션 없는 연결)이 저장된다. 새 실행의 새 context로 처리하면 깨끗하다(`OutboxTests.preservedLineRetriedWithFreshContextLeavesNoStaleRecords`). N번 실패 시 격리는 디스크가 잠깐 막혀도 멀쩡한 기록을 치워 버린다 | 10초 점검마다 재시도(처음 구현, 잘못된 기록이 생겨 버림). outbox 흡수를 별도 `ModelContext`에서 하고 실패하면 그 context를 버리기 — 같은 실행 안 재시도가 가능해지지만 서버 실시간 경로·`pendingSpawns` 공유를 함께 바꿔야 해서 다음 카드로 남김 | `drainOutbox`의 `outboxHeld` 줄 삭제 |
| 읽을 수 없는 줄은 `outbox.quarantine.jsonl`에 원문 그대로 덧붙이고(0600) 미처리 수에 넣지 않는다. 덧붙이기 실패는 저장 실패와 같이 다룬다 | 원본을 잃지 않는다. outbox 줄은 이미 줄인 형식이라(6장) 파일 내용·명령 출력이 없다. 미처리 수에 넣으면 지울 화면이 없어 연동 상태가 늘 「확인 필요」 | 버리기(이전 동작), 미처리 수에 포함 | `quarantine` 호출을 `skipped += 1`로 |
| 저장 실패 때 `HookProcessor.pendingSpawns`(메모리의 서브에이전트 대기)를 처리 전 값으로 되돌린다 | DB는 rollback되는데 대기 항목만 남으면 재시도한 `PreToolUse(Agent)`가 두 번 쌓이고, `SubagentStart`는 짝을 잃는다 | 그대로 두기 | `handle(_:at:delivers:)`의 `spawns` 복원 줄 |

알려진 한계(다음 실행 재시도로 outbox 경로는 막았다): SwiftData `rollback()`은 이미 메모리에 올라온 모델의 값과 관계를 되돌리지 않는다(실측: 실패한 `SubagentStart` 뒤에도 메모리의 카드는 active·연결 1개, 새 context로 읽으면 next·연결 0개). 그 상태에서 같은 줄을 다시 처리하면 남은 연결이 기본값(세션 id `""`, 연결 `session` nil)으로 함께 저장된다(메모리 저장소와 임시 파일 SQLite 저장소에서 같았다). 그래서 같은 실행에서는 다시 흡수하지 않는다. 남은 위험: 실패 뒤 메인 화면은 앱을 다시 켤 때까지 되돌려지지 않은 값을 보여 주고, 같은 실행에서 실시간 훅이 그 카드의 연결을 또 바꾸면 남은 모델이 함께 저장될 수 있다. 근본 해결은 위 대안(별도 `ModelContext`)이다. → TRK-33에서 별도 context 흡수와 저장 실패 뒤 다시 읽기(`ContextReload`)로 해결했다(아래 항목).

## 2026-10-01 — outbox 흡수를 별도 저장 문맥으로, 실패하면 통째로 폐기 (TRK-33)

TRK-32의 「다음 실행 때만 다시 흡수」를 뒤집는다.

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 흡수 한 번마다 새 `ModelContext`(같은 컨테이너, autosave 끔)와 흡수용 `HookProcessor`로 처리한다. 줄마다 저장하고, 실패하면 그 context를 버린다(`HookProcessor.absorbOutbox`). 남긴 줄은 같은 실행의 10초 점검·**다시 점검**·서버 준비 때 바로 다시 흡수한다. 횟수 제한 없음 유지 | rollback이 되돌리지 못한 메모리 값이 버린 context에만 남아 메인 context로 들어오지 않는다. 디스크 저장소로 실패 → 같은 실행 재흡수가 깨끗함을 확인(`OutboxAbsorbTests`) | 다음 실행 때만(TRK-32). 메인 context에서 흡수하고 실패 시 다시 읽기만 — 다시 읽기는 관찰한 SwiftData 동작이라, 흡수 쪽은 버리는 context로 이중으로 막는다 | `drainOutbox`가 `Outbox.drain`에 메인 처리기를 바로 넘기게 |
| 흡수 뒤(처리한 줄이 있거나 실패했으면) 메인 context가 올려 둔 프로젝트·카드·세션·연결을 모두 다시 가져온다(`ContextReload`). 기록(`Event`)은 넣기만 하므로 빼다 | 다른 context의 저장은 이미 올라온 객체에 저절로 들어오지 않고, 그 객체를 저장하면 옛 값이 저장소를 덮는다(실측: 카드 상태가 되돌아가고 연결이 끊김). 다시 가져오면 돌려받은 객체가 저장소 값·관계로 바뀐다(`ContextReloadTests`가 고정) | 바뀐 객체만 골라 맞추기(`RemoteCardMerge`처럼 값 복사) — 세션·연결·관계까지 옮겨야 해 길고 빠뜨리기 쉽다 | `absorbOutbox`의 `ContextReload.apply` 줄 |
| 흡수 전에 메인 context의 저장 안 된 변경을 저장한다. 저장하지 못하면 그 흡수를 미루고 `retryPending` | 저장 안 된 객체는 다시 가져와도 바뀌지 않고, 나중에 저장하면 흡수가 쓴 값을 덮는다(실측) | 그대로 흡수 | `absorbOutbox` 앞 `hasChanges` 블록 |
| `pendingSpawns`(메모리의 서브에이전트 대기)는 흡수용 처리기에 복사해 넘기고, 흡수가 끝나면 성공·실패와 상관없이 그 처리기의 값을 돌려받는다 | 흡수용 처리기는 실패한 줄의 대기 항목을 이미 되돌리므로(TRK-32) 끝난 값이 저장된 줄까지의 결과와 같다. 흡수는 메인 액터에서 동기로 돌아 실시간 훅이 끼어들지 않는다 | 실패 시 처리 전 값으로 통째 복원 — 저장에 성공한 앞 줄(`PreToolUse(Agent)`)의 대기 항목을 잃는다 | `absorbOutbox`의 `pendingSpawns = worker.pendingSpawns` |
| 실시간 훅(`HookProcessor.handle`)과 세션 정리(`sweep`)의 저장 실패도 rollback 뒤 `ContextReload`로 메모리를 저장소에 맞춘다 | 같은 위험이 있었다: 실패한 `SubagentStart`를 같은 context로 다시 처리하면 세션 id `""`·세션 없는 연결이 저장됐다. rollback 뒤 다시 가져오면 깨끗하다(`ContextReloadTests.failedLiveSaveRetriedInSameContextLeavesNoStaleRecords`). 요청마다 context를 새로 만드는 것보다 바꿀 곳이 적다 | 요청 단위 context — 훅마다 메인 context 전체를 다시 읽어야 하고 MCP·화면과의 순서를 다시 맞춰야 한다 | `handle`·`sweep`의 `ContextReload.apply` 줄 |

알아 둘 것: 저장소가 계속 막혀 있으면 「작업 기록 저장 실패 · 미처리 기록 보존」이 10초마다 다시 적힌다(TRK-32 전과 같은 동작). MCP 도구(`MCPServer`), 프로젝트 등록(`ProjectRegistry`), 보드·카드 화면의 저장 실패 rollback은 아직 다시 읽지 않는다 — 같은 한계가 남아 있다. → TRK-34에서 모두 `ContextReload.commit`으로 다시 읽게 했다(아래 항목).

## 2026-10-01 — MCP·등록·보드·카드 상세의 저장 실패 뒤 다시 읽기 (TRK-34)

TRK-33에서 남긴 rollback 경로를 마저 막는다.

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 「바꾸고 저장, 실패하면 rollback 뒤 다시 읽고 오류를 다시 던짐」을 `ContextReload.commit(context, save:) { 변경 }` 하나로 묶고 MCP 도구(`MCPServer.callTool`), 프로젝트 등록(`ProjectRegistry.register`), 보드 끌어 놓기(`BoardQuery.dropAndSave`), 카드 상세의 완료·완료 조건(`CardEditing.completeAndSave`·`setCriterionAndSave`)이 쓴다. `save`는 테스트 이음새 | rollback만 하면 실패한 값(카드 상태·번호, 연결)이 메모리에 남아 화면에 보이고 다음 저장에 섞인다. 다시 읽기를 빼면 새 테스트(`SaveFailureReloadTests`)가 MCP·보드·카드 상세에서 모두 실패한다 | 경로마다 `rollback(); ContextReload.apply` 두 줄 — 빠뜨리기 쉽다. 화면 코드는 테스트할 수 없어 `Shared/`로 옮겼다 | 각 호출부를 `try context.save()` + `rollback()`으로 |
| MCP는 도구가 오류를 던진 경우(입력 검사 실패 포함)에도 다시 읽는다 | 도구가 일부를 바꾼 뒤 던지면 저장 실패와 같이 메모리가 남는다. 다시 읽기는 프로젝트·카드·세션·연결 네 번 가져오기라 개인 저장소에서는 가볍다 | 저장 실패에만 다시 읽기 | `callTool`에서 `commit` 대신 저장만 감싸기 |
| 보드에서 놓을 수 없는 칸(`canDrop` false)과 바꿀 것이 없는 완료 조건은 `commit`에 들어가기 전에 거른다 | 거절에도 rollback하면 메인 context의 다른 저장 안 된 변경을 버린다(`boardRefusedDropKeepsOtherChanges`) | 모두 `commit` 안에서 판단 | 두 함수의 앞 `guard` |

알아 둘 것: 프로젝트 등록은 새로 넣기만 해서 rollback만으로도 테스트가 통과한다. 다시 읽기는 같은 도우미를 쓰는 덕에 따라온 방어다. 화면 쪽 실패 표시는 그대로다(보드는 끌어 놓기 실패, 카드 상세는 표시 없음).

## 2026-10-01 — 기록 신뢰성 기준과 로컬 지표 (TRK-11)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 재수신은 ID로 거른다: 파일·커밋은 세션+`tool_use_id`(10분 안), 요청은 `prompt_id`/`turn_id`, ID 없는 옛 줄의 요청은 같은 문장 10초 안. 서브에이전트 대기는 부모+`tool_use_id`로 한 번만. outbox 필터가 `prompt_id`·`turn_id`를 남긴다 | 실시간 응답이 1초를 넘으면 같은 훅이 outbox에도 쓰인다. 시나리오에서 요청·파일·커밋 중복과, 재수신된 `PreToolUse(Agent)` 때문에 다음 서브에이전트가 앞 카드에 붙는 오귀속이 나왔다. 기록 payload에 키를 더해 모델(CloudKit 스키마)은 바꾸지 않았다 | 시각·내용이 같으면 같은 것으로(같은 수정을 짧게 두 번 하면 잃는다), 모델에 필드 추가 | `HookProcessor`의 `isRedeliveredTool`·`isRedeliveredPrompt`·`seenSpawns` |
| 커밋·검증 근거의 프로젝트는 도구 입력 폴더 → 훅 `cwd`의 등록 프로젝트 → 세션 프로젝트 순 | 훅 `cwd`는 Claude의 `cd`를 따라간다(hooks 문서). 다른 등록 프로젝트에서 한 커밋·테스트가 시작 프로젝트 카드에 붙었다. 등록 밖이면 세션 프로젝트를 써서 미등록 상위 폴더 + `session_bind` 경우를 지킨다 | `cwd`가 바뀌면 세션을 그 프로젝트로 옮기기(명세의 전환은 `session_bind`로만) | `toolProject`를 예전 `workdir == nil ? acting.project` 로 |
| 끝난 세션보다 이른 시각의 늦은 `PostToolUse`는 세션을 새로 만들지 않고 버린다 | 같은 ID의 세션이 하나 더 생겼다. 그 기록은 실시간으로 이미 받은 것이다 | 끝난 세션에 늦은 사실 기록을 붙이기 — 명세 변경이라 메인 세션 판단으로 남김 | `postToolUse`의 `fetchSession(...) == nil` 조건 |
| 수신 지연은 서버가 연결을 받은 시각부터 저장 끝, 데이터 변경 알림 뒤 메인 큐 한 번까지를 앱 안에서 재고, 측정 스크립트가 왕복 시간을 같이 잰다. 판정은 둘 다 p95 2초 미만 | 앱의 출발점은 메인 큐가 연결을 받을 때라 그 전 대기를 놓친다. 왕복이 그 몫을 메운다 | SwiftUI 렌더 완료 시각(가져올 공개 API가 없다) | `AppServices`의 `reliability.receipt` |
| 지표는 숫자와 시각만, `metrics.json`(0600)에 10초 점검 때 쓴다. 재개 대기 목록은 메모리에만 | 훅마다 파일을 쓰면 지연을 늘린다. 문자열 필드가 없으면 민감 내용이 들어갈 자리가 없다 | 훅마다 저장, CloudKit 모델에 저장 | `ReliabilityMonitor` |
| 재개 시간은 첫 복사부터 연결 시각까지(도구를 바꿔 다시 복사해도 시작은 처음 복사) | 로드맵의 재개는 「작업을 고른 시점」부터다. 앱이 아는 가장 이른 시점이 첫 복사다 | 마지막 복사부터 | `ResumeTracker.copied` |

관측(Dev Debug, M4, 500건·세션 6): 앱 수신→화면 p95 442 ms, 왕복 p95 417 ms. 부하(세션 12)에서도 p95 729 ms. 목표 2초 통과. 자세한 표는 docs/RELIABILITY.md.

## 2026-10-01 — 재개 요약·준비/복사/연결 상태·도구 열기 (TRK-12)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 목표·남은 조건·미검증·메모 시점 요약은 재개 창 위쪽에 둔다. 카드 상세 재개 영역에는 상태 한 줄과 메모만 | 카드 상세는 바로 아래에 본문·완료 조건·근거가 있어 같은 내용이 겹친다. 재개 창은 재개할 때 여는 곳이다 | 카드 상세 영역에 요약 | `CardResumeSheet`의 `CardResumeSummaryView` |
| 미검증 = 근거 상태 미검증·실패·변경 후 미검증. 건너뜀은 넣지 않는다 | 건너뜀은 에이전트가 이유를 남긴 판단이다. 복사 문맥에는 건너뜀도 그대로 실린다 | 건너뜀 포함 | `CardResumeSummary.needsVerification` |
| 상태 이름은 준비됨·복사함·연결됨(+연결 끊김·재개 불가). 연결 판정은 TRK-31 `CardResumeAttempt`를 그대로 쓴다 | 복사·도구 열기만으로 연결됨이 되지 않게. 판정 규칙을 두 군데 두지 않는다 | 새 판정 | `CardResumeStatus` |
| 연결 뒤 그 세션이 다른 프로젝트로 `session_bind`하면 상태는 복사함으로 돌아간다 | TRK-31 판정이 세션의 현재 프로젝트를 본다. 옮겨 간 세션은 이 프로젝트의 재개로 치지 않는다 | 연결 끊김으로 표시 | `CardResumeAttempt.newLinks`의 `session.project` 조건 |
| 복사 뒤 이 카드에 처음 붙은 세션이면 복사 전에 시작한 대화도 연결로 친다 | 이미 열어 둔 대화창에 붙여넣는 경우가 흔하다. 복사 전에 이 카드에 붙었던 세션(과거 ID)만 뺀다 | 복사 뒤 시작한 세션만 | `CardResumeAttempt.newLinks` |
| 도구 열기는 임시 `.command` 파일(0700, 실행되자마자 스스로 지움)을 `NSWorkspace.open(_:withApplicationAt:)`으로 Terminal.app에 넘긴다 | Apple Events(AppleScript `do script`)를 쓰지 않아 자동화 권한 창이 뜨지 않는다. 앱은 샌드박스를 쓰지 않아 격리 표시가 붙지 않는다. Terminal은 `.command`를 사용자 로그인 셸 안에서 실행하므로 PATH(node 등)가 사용자 환경과 같다 | AppleScript로 Terminal 조종(권한 창), `Process`로 직접 실행(창 없음·launchd PATH) | `ToolLauncher`와 재개 창의 열기 버튼 |
| 실행 파일은 흔한 설치 폴더(`~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, `~/.bun/bin`, `~/.volta/bin`) → 앱 PATH 순으로 찾는다. 로그인 셸을 띄워 `command -v`를 묻지 않는다 | 앱은 launchd PATH(`/usr/bin:/bin:…`)로 뜬다. 셸을 띄우면 사용자 설정 파일이 실행되고 느리다 | `zsh -lc 'command -v claude'` | `ToolLaunch.searchDirectories` |
| 지원 환경 = macOS + Terminal.app + 실행 파일 + 작업 폴더. 하나라도 없으면 버튼 없이 복사만 | 카드의 「지원이 검증된 실행 환경에 한해」. iTerm 등은 확인하지 않았다 | 기본 터미널 앱 자동 선택 | `ToolLauncher.plan` |
| 도구는 인자 없이 실행한다. 문맥은 클립보드로만 | 대화 내용을 명령 인자로 넘기면 셸 기록·프로세스 목록에 남는다. `--resume`/`--continue`는 과거 세션 ID를 다시 쓰게 된다 | 첫 메시지를 인자로 | `ToolLaunch.script` |

알아 둘 것: 실제 Terminal.app 열기는 테스트에서 하지 않는다(`ToolLaunchTests`는 스크립트를 `/bin/sh`로 돌려 `cd`·따옴표만 확인). 도구 열기도 재개 시간 지표에서 복사와 같은 시도로 센다.

## 2026-10-01 — 블록 수신 확인 (TRK-35)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 블록은 스크립트가 stdout에 출력한 뒤 보낸 확인(`POST /hooks/ack`)을 받아야 받은 것으로 적는다. 확인이 없으면 다음 `UserPromptSubmit`에 다시 준다 | 응답이 1초를 넘으면 스크립트는 출력하지 않는데 앱은 응답을 만들 때 키를 적어 늦은 주입도 막혔다. 블록을 잃으면 스킬이 `sessionId`를 모른다 | 응답 기한 늘리기(Claude를 더 오래 막는다), 앱이 응답 시간을 재서 1초가 넘으면 안 적기(스크립트 쪽 시간과 다르다) | `offerContext`가 늘 `confirmContext`를 부르게. 스크립트의 `send_ack`·머리 삭제 |
| 같은 블록을 두 번 받는 것을 허용한다(블록은 출력됐는데 확인만 잃은 경우) | 블록 유실보다 중복이 낫다. 블록은 짧고, 스킬은 같은 `sessionId`를 다시 읽을 뿐이다 | 확인을 재시도(훅 시간이 더 는다) | — |
| 확인 본문은 응답 ID 하나(`{"contextId":…}`). 세션 ID를 싣지 않는다 | ID가 세션 하나의 대기 블록을 가리킨다. 세션 ID를 실으면 Codex `codex:` 접두사를 확인 경로에서 다시 맞춰야 한다. 경로도 `/hooks/ack` 하나 | 세션 ID + 프로젝트 키 | `HookRouter.respondAck` |
| 옛 스크립트는 요청 머리(`X-Waypoint-Context-Ack: 1`)가 없는 것으로 가린다. 머리가 없으면 예전처럼 바로 확정 | 확인을 보내지 않는 스크립트에 대기를 두면 매 프롬프트에 블록이 다시 나간다. 앱과 스크립트(전역 사본·Codex 사본)를 어느 순서로 바꿔도 예전 동작으로 떨어진다 | 대기 후 횟수만으로 막기(옛 스크립트에서도 블록이 몇 번 반복된다) | `HookRouter.acknowledges` |
| 확인을 보내는 스크립트에도 같은 키의 블록은 `SessionStart` 포함 3번까지만 | 확인 경로가 계속 막힌 환경(포트·프록시 등)에서 프롬프트마다 블록이 붙지 않게. 시간 초과 한두 번은 넘긴다 | 2번, 시간으로 제한 | `HookProcessor.maxContextAttempts` |
| 확인을 보내는 스크립트의 `SessionStart`는 확정한 키도 비운다 | 재개·압축 뒤의 `SessionStart` 블록이 시간 초과로 빠져도 다음 프롬프트에 다시 준다. 옛 키가 남으면 늦은 주입 조건에 걸리지 않는다 | 키를 그대로 두기 | `offerContext`의 `restart` |
| 대기 블록은 세션 모델 필드 셋(`contextPendingKey`·`contextPendingID`·`contextPendingCount`, 옵셔널·기본값)에 저장하고, 받은 확인은 메모리 집합(`ContextAckInbox`)에만 둔다 | 블록을 줬다는 사실은 훅 처리와 함께 저장돼야 앱을 다시 켜도 늦은 주입이 이어진다. 확인은 다음 훅에서 확정하므로 저장하지 않아도 된다. 앱을 다시 켜 집합을 잃으면 블록이 한 번 더 나갈 뿐이다(반복 상한 3 유지). CloudKit Development 스키마는 자동으로 늘어난다 | 대기도 메모리에만 | 필드 삭제 |
| 확인은 서버 큐에서 받아 집합에 넣고 바로 `204`. 메인 액터·저장·화면 갱신을 거치지 않는다. 확정은 그 세션의 다음 훅을 메인에서 처리할 때(늦은 주입 판단 전). 이를 위해 `LocalServer`의 연결 받기·읽기를 서버 전용 큐로 옮기고 `fastHandler`를 두었다 | 「훅이 세션을 느리게 하면 안 된다」. 확인을 메인에서 저장하던 첫 구현은 확인이 앞 훅의 화면 갱신을 기다려 Dev에서 `SessionStart` 훅이 중앙값 263 → 758 ms, 늦은 주입 262 → 861 ms(최대 1.19초)로 늘었다 | 저장하는 확인(위 측정으로 버림). 백그라운드 확인(`curl … &`): 훅 시간은 늘지 않지만 Claude·Codex가 훅이 끝날 때 프로세스 그룹을 정리하는지 확인할 수 없고, `claude -p`처럼 바로 이어지는 훅보다 확인이 늦게 닿을 수 있어 버림 | `LocalServer`의 `fastHandler`와 `AppServices`의 확인 분기, `applyAcknowledgement` |

측정(Dev Debug, 세션 사이 1.5초 쉼, 20회씩 두 번, 옛 → 새 스크립트): 훅 전체 중앙값 `SessionStart` 267 → 289 ms·251 → 263 ms, 늦은 주입 258 → 303 ms·241 → 254 ms, 최대 522 ms. SessionStart 바로 뒤의 확인 요청은 중앙값 1.7 ms(최대 5.5 ms). `LocalServerTests`가 메인 액터를 1초 막은 동안 빠른 경로가 답하는지 고정한다. Dev에 새·옛 스크립트로 보낸 82개 확인(확인 뒤 다음 프롬프트에 블록 없음, 출력 못 한 블록은 다음 프롬프트에 다시)이 모두 맞았다.

알아 둘 것: 서버 큐로 옮기면서 수신 지연 지표(TRK-11)의 출발점이 서버 큐가 연결을 받은 시각이 되어, 그전에 놓치던 메인 큐 대기가 지표에 들어간다.

## 2026-10-01 — 지침·기억 출처 목록 (TRK-37)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 상위 폴더는 프로젝트 폴더의 부모부터 홈까지(홈 포함)만 찾는다. 홈 밖 프로젝트는 `/` 바로 아래까지 | Claude Code는 뿌리까지 읽지만 홈 위(`/Users`)에 지침을 두는 경우는 드물고, 카드가 「홈까지」로 정했다 | 뿌리까지 | `GuidanceCollector.ancestors(of:home:)` |
| 같은 이름으로 바뀌는 기억 폴더(`a_b`·`a-b`)는 맞는 등록 프로젝트 모두에 건다 | Claude Code도 두 폴더를 같은 기억 폴더로 쓴다. 하나를 고르면 다른 쪽에서 실제로 읽히는 기억이 안 보인다 | 짝짓지 못한 것으로 따로 | `GuidanceCollector.match` |
| 기억 폴더는 등록 경로·심볼릭 링크를 푼 경로·git 저장소 뿌리(작업 트리는 원래 저장소) 셋 중 하나와 맞으면 그 프로젝트 | 문서상 기억은 저장소 기준이고, 예전 대화 기록 폴더는 작업 폴더 기준이었다 | 등록 경로만 | `Root.memoryPaths` |
| 짝짓지 못한 폴더의 경로는 `/`부터 실제 폴더를 읽어 되돌리고, 못 찾으면 `-`→`/` 추정에 「없는 폴더」 | `-`가 `/`·`_`·`.`·공백 중 무엇이었는지 이름만으로 알 수 없다. 실제 폴더가 있으면 틀릴 일이 없다 | 늘 단순 치환 | `MemoryFolderName.locate` |
| 빈 기억 폴더는 보이지 않는다. 보관한 프로젝트도 등록 프로젝트로 친다 | 빈 폴더는 읽을 것이 없다. 보관해도 폴더와 지침은 그대로라 「다른 폴더」로 떨어지면 헷갈린다 | 빈 폴더도 표시, 보관 제외 | `collectMemory`의 `files.isEmpty`, `GuidanceMonitor.currentProjects` |
| Codex 기억 DB는 `mode=ro` + `SQLITE_OPEN_READONLY` + `query_only`로 연다. `immutable=1`은 쓰지 않는다 | 실제 DB가 WAL로 쓰이고 있어(`-wal` 8 KB) `immutable`은 WAL에만 있는 행을 놓친다. 대신 SQLite가 `-shm` 읽기 표시를 고친다(본문·WAL·파일 목록은 그대로, 테스트로 고정) | `immutable=1`, 임시 폴더로 복사해 열기(복사 중 쓰기와 엇갈리면 깨진 사본) | `CodexMemoryStore.read` |
| 홈 자체는 감시하지 않는다. 홈 바로 아래 지침은 앱이 앞으로 올 때·화면을 열 때 다시 본다 | 홈 전체를 FSEvents로 보면 모든 파일 변경이 들어온다 | 홈 감시 + 거르기 | `GuidanceWatchPlan.init` |
| `GuideWatcher`에 경로 거르기(`accept`)를 더했다. 거른 경로는 디바운스를 다시 걸지 않는다 | `~/.claude/projects/*/*.jsonl`·`~/.codex/logs_2.sqlite`가 쉬지 않고 쓰여 디바운스가 끝나지 않는다. 기본값은 모두 받기라 지침 문서 감시는 그대로 | 출처 파일이 든 폴더만 따로 감시(기억 폴더·rules 폴더가 새로 생기는 것을 놓친다) | `GuideWatcher.init(accept:)` |
| `-shm`은 감시에서 거른다 | 이 앱이 DB를 읽어도 바뀔 수 있어 다시 모으기가 끝없이 돌 수 있다. 쓰기는 `-wal`로 드러난다 | — | `GuidanceWatchPlan.accepts` |
| 위 폴더의 `AGENTS.md`는 프로젝트의 git 저장소 안이면 Codex, 밖이면 Claude 쪽으로 표시한다. 프로젝트 폴더의 `AGENTS.md`는 Codex | Codex는 git 뿌리 위를 읽지 않고, Claude는 CLAUDE 계열 파일이 없을 때 읽는다 | 도구 둘 다 표시 | `GuidanceCollector.collect` |
| Codex 스킬(`~/.codex/skills`)·Claude 스킬은 넣지 않았다 | 지침·기억 범위 밖. 스킬은 부를 때만 읽힌다 | 목록에 넣기 | — |
| Debug 실행 인자 `-WaypointSidebar guidance`로 지침 화면에서 시작한다 | 손 없이 창 하나만 캡처해 화면을 확인하려고. Release에는 없다 | — | `RootView.launchSelection` |

검증: 이 Mac에서 등록 프로젝트 셋(TRK·CHM·NHG)으로 수집 약 70 ms, 출처 46개. 기억 폴더 8개 중 짝지은 것 3(TRK·NHG 프로젝트, `~/workspace` 상위 폴더), 다른 폴더 5. Dev 앱을 임시 `CLAUDE_CONFIG_DIR`·`CODEX_HOME`으로 띄워 기억 파일·규칙 줄을 더하자 2초 안에 목록이 바뀌었다.

## 2026-10-01 — 지침 항목 나누기 (TRK-38)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 원문 범위는 UTF-8 바이트 위치로, 줄은 `\n`에서 나누고 앞 `\r`은 개행에 넣는다. 바이트 비교는 `Array(utf8)`로 | Swift `String`은 `"\r\n"`을 글자 하나로 보고 `==`가 정규화 비교라 바이트 차이를 놓친다. 잘라 붙이는 자리가 늘 `\n` 경계라 조각마다 올바른 UTF-8이 남는다 | `String.Index` 범위 | `GuidanceLines` |
| M4 `MarkdownParser`에서 줄 판정 함수(`fence`·`heading`·`isRule`·`listItem`·`table`)를 가져다 쓰고(`private` → 모듈 안) 블록 조립은 새로 짠다 | M4 블록 조립은 줄을 다듬고 CRLF를 바꿔 위치가 남지 않는다. 판정을 같이 써야 보기 화면에서 절 머리로 보이는 줄이 항목에서도 절 머리다 | 따로 만든 판정(화면과 어긋날 수 있다) | `GuidanceMarkdownSplitter`의 판정 호출 |
| 보기 화면을 따라 `---`는 늘 구분선(밑줄 머리 없음), 목록 뒤 들여쓰지 않은 줄은 새 문단 | 화면과 항목이 같은 모양이어야 편집 화면(TRK-40)이 읽기 화면과 다르지 않다 | CommonMark(밑줄 머리, 게으른 이어짐) | `GuidanceMarkdownSplitter.scan`·`listItem` |
| 목록 항목 안에서 연 코드 울타리는 들여쓰기와 상관없이 닫는 줄까지 그 항목 | 목록 아래 코드를 들여쓰지 않고 쓰는 경우가 흔하다. 중간에 끊으면 닫는 울타리가 새 코드 블록으로 열려 문서가 애매해진다 | CommonMark처럼 들여쓰지 않은 줄에서 항목 끝 | `listItem`의 울타리 분기 |
| 표 머리 줄 + 구분 줄을 한 항목(표 머리)으로 | 구분 줄만 따로 지우면 표가 깨진다 | 구분 줄을 항목 밖 줄로 | `scan`의 표 분기 |
| 지울 때 빈 줄: 앞이 빈 줄(또는 처음)이고 뒤도 빈 줄이면 뒤 빈 줄 하나, 앞이 빈 줄이고 뒤가 끝이면 앞 빈 줄 하나를 함께 지운다. 끝 개행이 없던 문서는 그대로 없게 | 절의 마지막 문단을 지워도 빈 줄 두 개가 남지 않고, 목록 가운데 항목은 줄만 빠진다. 한 줄 이상은 건드리지 않아 결과를 예측할 수 있다 | 빈 줄을 손대지 않기(빈 줄이 쌓인다), 이어진 빈 줄 모두 합치기(항목 밖 줄을 여럿 바꾼다) | `GuidanceDocument.deletionRange` |
| 바꾸기는 항목 글(마지막 개행 제외)만 바꾸고, 항목 줄이 CRLF면 새 글의 줄바꿈을 CRLF로 맞춘다. 빈 글로 바꾸면 빈 줄이 남는다 | `item.text`를 고쳐 그대로 넘기면 되도록. 한 파일에 개행 모양이 섞이지 않게 | 새 글 끝 개행을 걷기 | `GuidanceDocument.replace` |
| HTML 주석(`<!-- … -->`)도 HTML 블록으로 보아 문서 전체 한 항목 | 카드의 「보수적으로」. 주석 안에 지침이 숨어 있을 수 있고, 주석 짝을 깨는 편집을 막는다. 이 Mac에서 걸린 것은 Next.js가 만든 AGENTS.md 두 개뿐 | 주석 줄을 항목 밖 줄로 | `GuidanceMarkdownSplitter.isHTMLStart` |
| 탭·공백 섞임은 문서 안의 들여쓴 목록 기호 줄 전체로 본다. 목록 중첩은 5단까지 나눈다 | 탭 폭을 몇 칸으로 볼지에 따라 하위 관계가 바뀐다. 5단은 실제 지침에서 드문 깊이 | 줄마다 판정, 3단 제한 | `listItem`의 `tabIndented`·`maxListDepth` |
| 기억 파일 머리의 `type`은 맨 위 또는 `metadata:` 아래에서 읽는다 | 이 Mac의 기억 파일은 `metadata:` 아래에 `type`을 둔다 | 맨 위만 | `GuidanceDocument.memoryFields` |
| 색인 짝짓기는 링크의 파일 이름만 본다(`./`·`#절`·퍼센트 인코딩 걷기) | 기억 폴더는 한 단계라 이름이 겹치지 않는다 | 상대 경로 그대로 | `MemoryIndexPairing.fileName` |
| 바이트 입력이 UTF-8이 아니면 문서 전체 한 항목에 편집 금지 | 깨진 바이트를 대체 문자로 읽어 저장하면 원문이 바뀐다 | 대체 문자로 읽고 편집 허용 | `GuidanceDocument.parse(data:)` |

검증: 이 Mac의 실제 지침 57개(Markdown 18, 기억 30, 색인 8, 명령 규칙 1)에서 항목 701개, 다시 합치기와 항목마다 지우기·바꾸기 속성 검사 통과. 애매 판정 2개(HTML 주석). `~/workspace`·`~/workspace/projects`·`~/workspace/app-factory` 바로 아래 폴더를 등록 프로젝트처럼 넘겨 모았다.

## 2026-10-01 — 한 줄 HTML 주석은 항목 밖 줄 (TRK-39)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 한 줄 안에서 열고 닫는 HTML 주석 하나만 있는 줄은 빈 줄·구분선처럼 항목 밖 줄로 두고 원문 그대로 남긴다. 여러 줄 주석, 문단에 붙은 주석, 뒤에 글이 더 있는 줄은 여전히 문서 전체 한 항목 | Next.js가 `AGENTS.md`에 갱신 표식으로 넣는 `<!-- BEGIN/END:… -->` 때문에 그 문서의 지침을 항목으로 다룰 수 없었다. 한 줄 주석에는 지침이 숨지 않고, 항목 밖이라 편집이 짝을 깨지 않는다 | 모든 HTML 주석을 애매로(TRK-38) | `GuidanceMarkdownSplitter.isLineComment` |

검증: 이 Mac의 실제 지침 57개에서 항목 705개, 애매 판정 2개 → 0개.

## 2026-10-02 — 지침 항목 보기·고치기 (TRK-40)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 시안 1 「항목 목록」으로 구현한다 | 메인 세션이 시안 1·2·3을 비교해 골랐다 | 시안 2·3 | — |
| 카드 원문의 「기억 항목을 지우면 파일과 MEMORY.md 색인 줄을 함께 정리」는 TRK-41로 옮겼다. 이번 쓰기는 등록 프로젝트 폴더 안 지침 파일만, 프로젝트 밖(전역·상위 폴더·기억·Codex)은 항목 보기만 | 프로젝트 밖 파일은 버전·충돌 기록을 붙일 등록 문서(`GuideDoc`)가 없다 | 이번에 모두 | `GuideItemTarget.resolve` |
| 등록 안 된 프로젝트 지침은 처음 고치거나 지울 때 지침 문서로 자동 등록한다. 등록 전에 쓸 수 있는 종류는 프로젝트 `CLAUDE.md`·`.claude/CLAUDE.md`·`AGENTS.md`(·override)·`CLAUDE.local.md`. 프로젝트 `.claude/rules/*.md`는 보기만 | 버전·충돌 처리를 붙이려면 등록 문서가 있어야 한다. rules는 지시서 범위에 없었다 | 등록을 먼저 묻기, rules도 쓰기 | `GuideItemTarget.writableKinds` |
| 항목 상자의 글을 「그 항목만 바꾼 문서 전체」로 `draft`에 둔다 | 상자가 열린 사이 로컬 변경이 오면 M4 판정이 그대로 충돌 → 비교 화면을 띄운다(완료 조건 3). 화면을 떠나도 편집이 남는다(돌아오면 「편집」 보기) | 저장할 때만 바탕 비교(비교 화면이 저장 때에야 뜬다) | `GuideItemEdit.setDraft` |
| 저장·지우기·되돌리기 직전 앱 기록이 바탕 원문과 다르면 쓰지 않고 충돌로 둔다. 항목은 바탕을 다시 나눠 같은 번호·종류·글로 찾는다 | 감시가 `draft` 없이 로컬 변경을 반영한 뒤 낡은 바탕으로 쓰면 해시 확인을 지나 로컬 변경을 덮는다 | 지금 문서에서 같은 항목을 찾아 합치기 | `GuideItemEdit.commit`·`locate` |
| 등록 전 파일의 바탕은 `GuideFile.read`로 다시 읽은 전체 원문 | 보기용 읽기는 2MB 앞부분이고 깨진 바이트를 대체 문자로 바꿔 그대로 쓰면 원문이 바뀐다 | 보기용 글 그대로 | `GuidanceSourceItems` |
| 저장 안 한 전체 편집이나 충돌이 있으면 항목 버튼을 숨긴다. 상자가 하나 열려 있으면 다른 줄 버튼도 숨긴다 | 항목 저장이 `draft`를 비워 전체 편집을 잃거나, 지우기가 열린 상자의 바탕을 낡게 만든다 | 경고 문구 | `GuidanceItemsView.canWrite` |
| 절 머리 줄에도 고치기·지우기를 둔다. 절 머리를 지우면 그 줄만 빠지고 절 안 항목은 남는다(알림의 「하위 N개」는 목록 하위만 센다) | 절 머리도 TRK-38 항목이고 지운 뒤 되돌릴 수 있다 | 절 머리는 버튼 없음, 절 통째로 지우기 | `GuidanceItemsView.row` |
| 애매한 문서 고치기는 지침 문서 화면에서는 「편집」 보기로, 지침 화면에서는 그 자리 상자(문서 전체)로 | 지침 화면에는 전체 편집 보기가 없다. 문서 전체 항목 바꾸기는 TRK-38 편집기로 바이트 그대로 된다 | 지침 화면에서는 고치기 숨김 | `GuidanceItemWriter.openFullEditor` |
| 지움 알림은 6초, 앞부분 24자 | 되돌리기를 누를 시간은 주되 화면을 오래 가리지 않는다 | 알림을 닫을 때까지 | `Theme.GuideItems.toastSeconds`, `GuideItemEdit.previewLength` |
| Debug 실행 인자 `-WaypointGuideMode items`·`-WaypointGuideItemsEdit N` | 손 없이 창 하나만 캡처해 항목 보기·상자를 확인하려고. Release에는 없다 | — | `GuideLaunch` |

## 2026-10-02 — 프로젝트 밖 지침 쓰기와 안전장치 (TRK-41)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 전역·상위 폴더·기억·Codex 파일은 지침 문서(`GuideDoc`)로 등록하지 않고 파일 그대로 쓰며, 버전은 파일 사본으로 이 Mac에만 남긴다 | 개인 지침·기억은 iCloud로 다른 기기에 올리지 않는다. `GuideDoc`은 프로젝트에 매이고 CloudKit으로 동기화된다 | `GuideDoc`에 프로젝트 없는 문서를 더하기 | `GuidanceBackupStore` |
| 쓰기 직전 디스크 내용이 화면이 읽은 원문과 바이트까지 다르면 쓰지 않고 「바뀜 · 다시 읽기」. 비교 화면은 두지 않았다 | 이 파일들엔 앱 기록(`content`)이 없어 M4 비교 화면(`GuideConflictView`)이 `GuideDoc`에 매여 있다. 다시 읽고 다시 고치면 된다 | 간단한 비교 창 새로 만들기 | `GuidanceFileWrite.apply`·`GuidanceItemsView.reload` |
| 프로젝트 `.claude/rules/*.md`와 전역 `~/.claude/rules/*.md`도 이번에 쓰기를 열었다(같은 안전장치) | 같은 Markdown 지침이고 안전장치가 그대로 맞는다 | 보기만 | `GuidanceFileWrite.writableKinds` |
| 관리 정책 `CLAUDE.md`(`/Library/…`)는 보기만 | 조직이 배포하는 파일이고 보통 관리자 권한이다 | — | `isWritablePath` |
| 바뀜은 파일 여럿을 한 묶음으로 확인한 뒤 쓴다(기억 지우기 = 파일 + 색인). 되돌리기는 묶음을 거꾸로 | 기억 지우기·색인 줄만 지우기·파일만 지우기·되돌리기가 한 코드 경로가 된다. 둘 중 하나만 바뀌었을 때 반쪽만 쓰지 않는다 | 파일마다 따로 | `GuidanceFileWrite.ChangeSet` |
| 기억 파일은 문서가 애매해도(머리가 닫히지 않음) 지울 수 있다. 색인이 애매하면 파일만 지운다 | 파일 하나가 한 항목이라 「지우기」는 파일 지우기다. 애매한 색인을 지우기 규칙으로 고치면 문서가 비거나 깨진다 | 애매하면 막기 | `GuidanceFileEdit.canDelete`·`removingIndexLines` |
| 규칙 검사는 Codex CLI를 임시 `CODEX_HOME`으로 돌리고, 없는 명령(`waypoint-check-…`)으로 검사한다. 끝 코드와 `failed to parse policy`를 같이 본다 | Codex가 `CODEX_HOME/tmp`를 만든다(실측). 규칙이 검사 명령을 막아도 끝 코드는 0이지만, 없는 명령이면 결과가 규칙에 흔들리지 않는다 | `-- true`로 검사, 실제 `~/.codex` | `CommandRulesCheck.run` |
| `codex`가 있는데 검사가 3초를 넘거나 실행하지 못하면 저장하지 않고 「검사 못 함」. 자체 검사는 `codex`가 없을 때만 | 자체 검사를 지나도 Codex가 읽지 못하는 줄이 저장될 수 있다(완료 조건 2). 메인 세션 결정 | 자체 검사로 대신하고 저장 | `CommandRulesCheck.check`·`Outcome.unchecked` |
| 되돌리기·백업 복원은 규칙 검사를 하지 않는다 | 있던 내용으로 돌리는 것이고, 원래 파일이 Codex 판에 맞지 않았더라도 되돌릴 수 있어야 한다 | 검사 | `apply(checkRules: nil)`·`restore` |
| 지움 알림은 지침 화면이 들고 있다 | 기억 파일을 지우면 출처가 목록에서 빠져 항목 화면이 사라진다 | 항목 화면 안 | `GuidanceView.toast` |
| 지운 파일은 출처 목록 맨 아래 「지운 파일」에서 사본으로 되살린다. 기억 파일을 지우면 고른 자리가 그 줄로 옮겨 간다 | 사라진 파일엔 출처 줄이 없어 「백업 N」에 갈 길이 없다 | 백업 전체 목록 창 | `GuidanceDeletedDetail` |
| 사본 이름은 UTC 밀리초 + 까닭, 원본 경로 해시 폴더에 원본 경로 파일 | 이름순이 시각순이고, 원본이 사라져도 어디 것인지 안다 | 사본 목록 JSON | `GuidanceBackupStore.fileName` |
| 열린 세션 수는 위 한 줄에 「열린 Claude 세션 N」 사실만 | 고친 지침이 이미 떠 있는 세션에 바로 반영되지 않을 수 있다. 설명 문구는 넣지 않는다 | 저장 전 확인 창 | `GuidanceOpenSessions` |
| Debug 실행 인자 `-WaypointGuidanceSource <경로 끝>` | 손 없이 지침 화면의 출처(지운 파일 포함)를 골라 창 하나만 캡처하려고. Release에는 없다 | — | `GuideLaunch.guidanceSource` |

검증: 임시 `CLAUDE_CONFIG_DIR`·`CODEX_HOME`·`WAYPOINT_SUPPORT_DIR`로 Dev를 띄워 전역 지침 항목 상자, 기억 파일 한 줄(이름·설명), 「지운 파일」 사본 화면을 창 하나만 캡처했다. 실제 사용자 지침·기억·Codex 파일에는 쓰지 않았다.

## 2026-10-02 — 앱 안 연동 설치기 (TRK-43)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 설치기는 「계획 → 적용」. 계획은 읽기만 하고 내용·권한이 같은 파일은 넣지 않는다. 적용은 계획 이후 바뀐 파일이 있으면 멈추고, 전부 백업한 뒤 차례로 원자적으로 쓰고, 실패하면 쓴 파일을 이전 내용·권한으로 되돌린다 | 이미 설치된 Mac에서 다시 설치해도 아무것도 쓰지 않아야 한다(완료 조건 3). 확인 화면(TRK-44)이 계획을 그대로 보여 줄 수 있다. 메인 세션 결정 | 매번 다시 쓰기(파이썬 스크립트 방식) | `IntegrationInstaller`·`IntegrationApplier` |
| 백업은 `<저장 폴더>/integration-backups/<UTC 시각>-<8자>/`(0700) + 사본(0600) + `paths.json` | 지침 쓰기(TRK-41)처럼 이 Mac에만, Waypoint 폴더에 모은다. 같은 밀리초에 두 번 돌아도 겹치지 않게 8자를 붙였다 | `~/.codex/waypoint/backups/`(파이썬과 같은 자리) | `IntegrationApplier.backupFolder` |
| JSON은 키 순서·숫자 원문을 지키는 자체 해석기(`OrderedJSON`)로 쓴다. 들여쓰기·끝 줄바꿈은 원문을 따르고, 이스케이프는 표준 꼴로 바뀔 수 있다 | `JSONSerialization`은 키 순서를 잃고 `settings.json`을 통째로 섞는다. Codex는 파이썬 `json.dumps`와 같은 바이트가 필요하다 | 외부 JSON 라이브러리 | `OrderedJSON` |
| Claude 훅은 이벤트마다 「Waypoint 훅이 하나, 명령·`timeout`이 같고 matcher가 같은 뜻(없음·`""`·`"*"`)」이면 손대지 않는다. 새로 넣는 묶음은 `settings.example.json`처럼 `matcher: "*"` | 지금 깔린 PreToolUse·PostToolUse 훅엔 matcher가 없다. Claude Code는 없는 matcher를 모든 도구로 본다(`IntegrationInstallation`도 같은 판정) | 예시와 다르면 고쳐 쓰기(완료 조건 3 깨짐) | `ClaudeInstallPlanner.satisfied` |
| 상태줄이 없으면 중계만 넣는다(출력 없음) | 사용량 게이지가 이 입력을 쓴다. 해제하면 `statusLine`을 지워 원래대로 | 상태줄이 없으면 건너뛰기 | `ClaudeInstallPlanner.planStatusLine` |
| 원래 상태줄 명령은 따로 적어 두지 않고 감싼 꼴에서 되찾는다. 셸 특수 문자가 있으면 `bash -c '<원래 명령>'`로 감싼다 | 지금 Mac엔 설치 기록 파일이 없다(새 파일을 만들면 완료 조건 3이 깨진다). 낱말로 나눠도 같은 명령만 그대로 붙인다 | 설치 기록 파일 | `StatusLineWrap` |
| Claude tracker 스킬은 머리말 `name: tracker`이고 Waypoint를 말하면 Waypoint 것으로 보고 덮어쓰기·지우기(백업 있음). 아니면 그 단계만 건너뜀 | Claude 쪽엔 Codex의 `skillHash` 같은 기록이 없어 옛 판과 사용자가 고친 판을 가를 수 없다 | Codex처럼 기록 파일을 두고 해시 비교 | `ClaudeInstallPlanner.isWaypointTrackerSkill` |
| 해제해도 `~/.claude/waypoint/`·`~/.codex/waypoint/`의 스크립트는 남긴다 | 열린 세션이 이전 설정으로 스크립트를 부른다(파이썬 설치기와 같은 까닭) | 지우기 | 계획의 `remove` 분기 |
| MCP는 `claude mcp add/remove` CLI로, `~/.claude.json`은 읽기만. CLI가 없거나 실패하면 그 단계만 결과에 남기고 파일은 둔다 | `~/.claude.json`은 Claude Code가 자주 쓰는 큰 파일이다. 파일과 MCP는 서로 독립이라 MCP 실패로 훅까지 되돌릴 까닭이 없다. 메인 세션 결정 | 직접 편집, 실패하면 전부 되돌리기 | `ClaudeCommandRunner`·`Result.isPartial` |
| 다른 포트의 Waypoint 주소(`http://127.0.0.1:<포트>/mcp`)로 등록돼 있으면 지우고 다시 등록, 다른 주소면 건너뜀 | 평소용↔Dev 전환을 설치기 하나로. 남의 서버는 건드리지 않는다 | 다른 주소도 멈춤 | `ClaudeInstallPlanner.planMCP` |
| Dev 설치도 사용자 범위에 한다(평소용 항목을 바꿔 끼움) | 카드 지시(`AppInstance` 기준 포트 선택). 이 Mac처럼 평소용이 늘 켜져 있으면 Dev는 실측 폴더(`dev-probe-setup.sh`)가 맞다 — TRK-44에서 Dev의 실제 홈 설치를 막기로 정했다(「온보딩 화면 (TRK-44)」) | Dev는 프로젝트 범위 | `IntegrationInstallContext.instance` |
| Codex는 `install-codex.py`를 그대로 옮기고 같은 입력에서 결과 파일을 바이트 비교한다(`install.json`의 `backup`만 다름). 바뀔 것이 없으면 쓰지 않는 것만 다르다 | Codex는 훅을 해시로 신뢰한다. 같은 `hooks.json`이어야 다시 설치해도 신뢰가 풀리지 않는다 | 새로 설계 | `CodexInstallPlanner` |
| TOML은 필요한 것만 읽는 작은 해석기(`MiniTOML`) | 외부 의존성 없이 구조 오류·`mcp_servers.waypoint`·`features.hooks`만 알면 된다. `tomllib`보다 날짜·숫자 검사가 느슨하다 | 외부 TOML 라이브러리 | `MiniTOML` |
| 이번 카드엔 디버그 진입점을 두지 않았다 | 테스트(임시 홈·가짜 CLI)로 모든 경로를 돌렸고, 실제 홈에 쓰는 진입점은 위험만 늘린다 | Debug 메뉴 | — |

검증: 임시 홈에서 처음 설치·재설치(빈 계획)·해제(사용자 설정 바이트 복원)·Dev 전환·두 번째 쓰기 실패 되돌림·백업 권한·가짜 `claude` CLI. Codex는 Homebrew python3로 파이썬 설치기와 결과 비교. 이 Mac의 실제 설정을 임시 홈에 복사(읽기만)해 Claude·Codex 모두 빈 계획임을 확인했다. 실제 `~/.claude`·`~/.claude.json`·`~/.codex`·`~/.agents`에는 쓰지 않았고 `claude mcp`도 실제 홈으로 돌리지 않았다.

## 2026-10-02 — 온보딩 화면 (TRK-44)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| Dev 앱은 실제 홈에 설치·해제하지 않는다(버튼 비활성 + 까닭 한 줄). Debug 빌드의 `WAYPOINT_INTEGRATION_HOME`이 있으면 그 폴더를 홈으로 써서 허용하고 Release는 변수를 무시한다. 판정은 `IntegrationHomePolicy`(순수, 테스트). TRK-43 표의 Dev 행을 이 카드에서 정했다. 메인 세션 결정 | 평소용이 늘 켜진 이 Mac에서 Dev가 사용자 범위에 설치하면 평소용 연결이 47822로 바뀌어 기록이 끊긴다. 확인용 홈이 있어야 화면·설치를 실제로 돌려 볼 수 있다 | Dev도 사용자 범위에 설치(TRK-43 그대로) | `IntegrationHomePolicy.installBlock`·`IntegrationEnvironment` |
| Dev가 막혀 있으면 「확인 필요」 상태(평소용 포트로 연결됨)도 막힌 까닭으로 보인다 | Dev가 실제 홈을 보면 평소용 연결이 늘 포트 불일치로 나온다. Dev에서는 고칠 수 없으니 그 까닭이 맞다 | 확인 필요 문구 그대로 | `OnboardingProgress.blocker(.install)` |
| 첫 실행 자동 표시는 프로젝트가 보관 포함 하나도 없고 「끝」을 누른 적이 없을 때만. 「닫기」는 끝낸 것으로 기억하지 않는다. 메인 세션 결정(조건), 닫기 처리는 이 카드 판단 | 이 Mac처럼 프로젝트가 있으면 뜨지 않아야 한다. 프로젝트 없이 닫았다면 다음 실행에 다시 보이는 편이 낫다 | 닫아도 끝낸 것으로 | `OnboardingProgress.shouldAutoPresent`·`OnboardingModel.finish` |
| 다시 열기는 연동 상태 패널 「연결 설정」과 메뉴 막대 「연결 설정…」. 다시 설치·연결 해제는 도구 단계에서 도구마다, 해제도 계획을 보이고 확인한 뒤 적용. 메인 세션 결정 | 연동 상태를 보는 곳에서 고치러 간다. 설정 창은 사용량 표시뿐이라 두지 않았다 | 설정 창 | `IntegrationHealthPanel`·`MenuBarContent`·`OnboardingToolsStep` |
| 온보딩은 메인 창 시트. 진행 상태(`OnboardingModel`)는 `AppServices`가 들어 창을 닫았다 열어도 이어진다 | 메인 창이 없는 메뉴 막대 상태에서도 다시 열면 같은 자리로. 등록 창(별도 창)과 함께 떠도 겹치지 않는다 | 별도 창 | `RootView.sheet`·`AppServices.onboarding` |
| 폴더를 고르면 `ProjectDraft.folder`로 초안을 만들어 기존 등록 창에 넣는다. 이름 = 폴더 이름, 키 = `ProjectKey.suggest(이름, 폴더)`, 지침 문서 = 폴더 바로 아래 `AGENTS.md`·`CLAUDE.md`·`.claude/CLAUDE.md` 중 있는 것. 이미 등록된 폴더면 고른 것으로 본다. 보관된 프로젝트면 막는다. 메인 세션 결정(경로), 필드는 이 카드 판단 | `project_init`과 같은 등록 규칙·창을 쓴다. 앱은 LLM을 부르지 않으므로 개요·스택·카드를 지어내지 않고, `/tracker init` 스킬이 꼽는 지침 파일 중 이름이 정해진 것만 찾는다. 보관 프로젝트 폴더는 기록을 받지 않는다 | `docs/` 아래까지 훑기 | `ProjectDraft.folder`·`OnboardingModel.choose` |
| 「첫 기록」은 온보딩을 연 뒤 활동(`IntegrationReceipt.at`)의, 프로젝트에 연결된 기록. 연결 안 된 기록이면 그 사실을 보이고 계속 기다린다. 판정은 `OnboardingProgress`(순수, 테스트). 메인 세션 결정 | 늦게 재전송된 옛 기록(`at`이 앞)이 첫 기록으로 잡히지 않게. 등록 밖 폴더의 기록은 카드에 안 쌓인다 | 수신 시각(`receivedAt`) 기준 | `OnboardingProgress.received` |
| 연결·첫 기록 단계는 2초마다 `IntegrationMonitor.refresh`, 끝은 사용자가 「끝」. 메인 세션 결정 | 기록 수신은 바로 반영되지만 설치 상태는 파일을 다시 읽어야 한다 | 10초 점검만 | `OnboardingView.poll` |
| 계획 화면은 설치기의 `summary` 대신 파일 `~` 경로 + 새로 만듦/바꿈/지움(`before`/`after`로 판정), 명령은 「Claude Code에 Waypoint 등록」, 건너뜀은 「… 건너뜀 · 까닭」 | `summary`에는 훅·MCP·스크립트 같은 만든 쪽 용어가 들어 있다. 설치 동작은 바꾸지 않는다 | 설치기 문구 고치기(범위 밖) | `OnboardingText` |
| 설치 오류·멈춤 까닭(`IntegrationInstallError`)과 연결 상태(`IntegrationInstallation.detail`)도 온보딩에서는 화면용 문장으로 옮긴다(「설정 파일을 읽을 수 없음 · <경로>」「다른 Waypoint에 연결됨」「연결 일부 빠짐」 등). 원문은 연동 상태 패널·진단 정보에 그대로. 메인 세션 결정 | 원문에 이벤트 이름·포트·훅·MCP·`features.hooks`가 들어 있다. 원인을 파고들 때는 패널을 본다 | 원문 그대로 | `OnboardingText.error`·`installation` |
| 프로젝트 단계의 `/tracker init` 경로는 설명 문장 대신 「/tracker init 복사」 버튼(누르면 잠깐 「복사됨」). 메인 세션 결정 | 흐름 중간에 조작법 문장을 두지 않는다 | 안내 한 줄 | `OnboardingProjectStep` |
| 메인 창이 여럿이면 먼저 뜬 창 하나에만 시트(창마다 `UUID`, 맡은 창이 닫히면 놓는다). 메인 세션 결정(문제), 방법은 이 카드 판단 | 창마다 시트가 뜨면 같은 진행을 두 곳에서 만진다 | 별도 창 | `OnboardingSheet`·`OnboardingModel.hostWindow` |
| 다시 시도는 다시 계획해 바로 적용한다. 계획에 오류가 하나라도 있으면 적용하지 않는다 | 이미 확인한 일이고 끝난 도구는 빈 계획이라 건너뛴다. 「계획 이후 바뀜」 오류는 다시 계획해야 풀린다. 한쪽만 적용되면 어디까지 됐는지 헷갈린다 | 다시 시도도 확인 화면 | `OnboardingTask.retry`·`canApply` |
| Debug 실행 인자 `-WaypointOnboarding tools\|install\|apply\|project\|receive`, `-WaypointOnboardingFolder <경로>`(확인 창 없이 등록) | 손 없이 단계별 화면을 창 하나로 캡처하려고. `apply`는 확인용 홈이 있을 때만 적용한다. Release에는 없다 | — | `OnboardingLaunch` |

검증: `WAYPOINT_INTEGRATION_HOME`·`WAYPOINT_SUPPORT_DIR`를 임시 폴더로 Dev를 뒤에서 띄워 첫 실행 자동 표시(도구), 연결 계획, 적용 결과(임시 홈에 Claude·Codex 설치, `claude mcp add`도 임시 홈의 `.claude.json`에 47822로), 첫 기록 대기, 끝 화면을 시트 창 하나만 캡처했다. 끝 화면은 임시 홈에 깔린 훅 명령으로 가짜 `SessionStart`(등록한 임시 폴더)를 47822에 보내 넘어가는 것을 봤다. 실제 홈으로 띄운 Dev는 연결 단계에서 막히는 것을 봤다(설정 파일은 읽기만). 실제 `~/.claude`·`~/.codex`·`~/.agents`에는 쓰지 않았다.

## 2026-10-02 — 저장소 판·백업·복구 (TRK-46)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 지금 모델을 `WaypointSchemaV1`(1.0.0)로 감싸고 빈 `WaypointMigrationPlan`으로 연다. 모델 클래스는 옮기지 않았다(다음 판을 더할 때 V1 안으로 얼린다). 메인 세션 결정 | 판이 붙어 있어야 다음 판에서 옮기기 단계를 적을 수 있다. 실제 저장소 사본과 판 없는 저장소가 그대로 열리는 것을 확인했다 | 다음 판이 필요할 때 처음 붙이기 | `WaypointStore.schema`를 `Schema([...])`로, `migrationPlan` 인자 빼기 |
| 열기 전 백업은 파일 복사, 열린 상태(`manual`)는 SQLite 온라인 백업. 둘을 다 둔다 | 열기 전에는 쓰는 쪽이 없어 복사가 바이트 그대로이고 깨진 파일도 그대로 남긴다(SQLite 백업은 깨진 파일에서 실패한다). 열린 상태는 WAL·쓰기 중이라 복사로는 일관성이 없다 | 둘 다 SQLite 백업 | `StoreLaunch.backupBeforeOpening`이 `backupOpenStore`를 부르게 |
| 최근 7개 유지(사유 구분 없이) | 실제 저장소 30 MB 안팎 × 7 ≈ 200 MB. daily가 한 주 치를 덮는다 | 사유별 개수, 10개 | `StoreBackup.keep` |
| 복구는 백업을 최신순으로 훑어 `quick_check` + 열기가 되는 첫 백업을 쓴다 | 이번 실행이 열기 전에 뜬 백업이 깨진 저장소의 사본일 수 있다(테스트 `brokenStoreIsMovedAsideAndRestored`로 재현) | 최신 하나만 | `StoreLaunch.recover`의 반복을 첫 항목으로 |
| 실패 원인을 가리지 않고 복구한다. 다 안 되면 옮긴 파일을 제자리로 돌려놓고 멈춘다 | 판이 안 맞는 저장소(옛 앱 재설치)도 살릴 수 있다. 일시적 원인이었어도 원본이 `store-failed/`에 남는다. 다 실패했을 때 반쯤 바뀐 자리를 남기지 않는다 | `quick_check`가 실패할 때만 복구 | `StoreLaunch.open`에서 `SQLiteFile.quickCheck(storeURL)`이 true면 바로 던지기 |
| 예약 복원은 지금 저장소를 `beforeRestore` 백업으로 **옮긴다**(복사 후 지우지 않음). 정리할 때 예약 대상과 그 백업은 지키고, 예약 파일은 처리 시작 때 지운다 | 지우는 단계가 없고 빠르다. 7개 정리가 복원할 백업을 지우지 않게. 중간에 죽어도 다음 실행에서 되풀이하지 않게 | 복사 | `StoreLaunch.applyScheduledRestore` |
| 판 기록은 `<저장 폴더>/store-version.json`(앱 버전·빌드·판), 열기에 성공한 뒤에 쓴다. 파일이 없고 저장소가 있으면 `upgrade` | TRK-46 이전 저장소의 첫 실행이 곧 업데이트다. UserDefaults는 `WAYPOINT_SUPPORT_DIR`를 따르지 않아 확인용 폴더와 섞인다 | UserDefaults | `StoreLaunch.versionFileName` |
| 복원 알림은 `store-restore.json` + 연동 상태 패널 미처리 기록 아래 한 줄과 「알림 확인」, `/integration/status`의 `storeRestore` | 화면은 TRK-47이 만든다. 그전까지도 사람이 알아채고 HTTP로 확인할 수 있게. 기존 「알림 확인」 모양을 따랐다 | UserDefaults·알림 센터 | `IntegrationHealthPanel`의 `storeRestore` 블록 |
| 저장 폴더 자체의 권한은 바꾸지 않는다(없을 때 만들기만). 백업·보존 폴더만 0700 | 평소용 `~/Library/Application Support/Waypoint`의 기존 권한을 업데이트가 몰래 바꾸지 않게(Dev 실측에서 처음 구현이 0700으로 바꾸는 것을 보고 고쳤다) | 저장 폴더도 0700 | — |
| `daily`는 실행할 때와, macOS에서는 떠 있는 동안 10초 점검마다 본다(`StoreDailyBackup`, 열린 저장소 → SQLite 온라인 백업, 백그라운드, 한 번에 하나, 실패하면 다음 점검에서 다시). iOS는 실행 때만. 메인 세션 결정 | 평소용은 로그인 항목이라 거의 다시 시작하지 않아 실행 때만으로는 하루 한 번이 되지 않는다 | 실행 때만 | `AppServices.refreshStates`의 `dailyBackup?.startIfDue` 한 줄 |
| CloudKit: 복원은 로컬만 되돌린다. 미러링 상태(레코드 메타데이터·서버 변경 토큰·이력 토큰)가 저장소 파일 안에 있음은 사본에서 확인, 옛 토큰 뒤 변경만 받는다는 것은 `CKFetchRecordZoneChangesOperation` 문서로 확인. 복원 뒤 `NSPersistentCloudKitContainer`가 실제로 그 뒤 변경을 다시 받는지, 서버 값이 복원값을 덮는지, 토큰 만료 시 동작은 **확인 못 함** | Apple 문서에 내부 동작이 없고 CloudKit을 켠 복원 실측은 범위 밖(Dev 실측은 CloudKit 꺼짐) | — | 실측 뒤 SPEC 「CloudKit과의 관계」 고치기 |

검증: `swift test` 전체 통과, macOS Debug·iOS Simulator 빌드. Dev 실측(스크래치 저장 폴더, CloudKit 꺼짐)은 docs/RELIABILITY.md.

## 2026-10-02 — 배포 빌드 (TRK-48)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 빌드 번호 = `git rev-list --count HEAD`, xcodebuild에 `CURRENT_PROJECT_VERSION=<n>`으로 넘긴다. `install-local.sh`도 같은 함수(`scripts/build-version.sh`). 메인 세션 결정 | 늘 증가하고 커밋과 이어진다. 번호가 고정(1)이면 새 빌드를 설치해도 TRK-46의 실행 전 백업이 생기지 않았다 | 날짜·시각 번호, `agvtool`로 파일 고치기 | 두 스크립트의 `CURRENT_PROJECT_VERSION=` 인자 빼기 |
| 마케팅 버전은 `project.yml`이 원본, `--version X.Y.Z`로 그 빌드만 덮는다(파일은 고치지 않음). 메인 세션 결정 | 베타 때 번호만 바꿔 다시 내기 쉽게, 원본은 한 곳에 | 매번 `project.yml` 고치기 | `--version` 분기 빼기 |
| 배포 스크립트는 더러운 트리에서 멈춘다. `--allow-dirty`는 개발용이고 산출물 이름에 `-dirty`를 붙인다(이름의 `-dirty`는 내 판단) | 빌드 번호가 커밋 수라 커밋 안 된 변경은 번호에 안 잡힌다. 섞인 산출물이 밖으로 나가지 않게 이름으로 표시 | 이름 표시 없이 허용 | `release-mac.sh`의 `-dirty` 줄 |
| archive 단계에서만 `ENABLE_HARDENED_RUNTIME=YES`로 덮는다. `project.yml`은 NO 그대로(내 판단) | 공증은 하드닝 런타임이 필수다. `project.yml`을 바꾸면 평소용 빌드도 바뀐다. 앱은 `Process`·`NSWorkspace.open`만 써서 예외 엔타이틀먼트가 필요 없다(export 결과에 `com.apple.security.cs.*` 없음). 하드닝 런타임에서의 실제 동작은 앱을 실행하지 않아 **확인 못 함** | `project.yml`에서 켜기 | archive 줄의 `ENABLE_HARDENED_RUNTIME=YES` |
| ExportOptions는 스크립트가 `.build/release-mac/ExportOptions.plist`로 만든다(내 판단) | 값이 셋(method `developer-id`, 자동 서명, teamID)이라 스크립트 안에서 읽히는 편이 낫고 저장소 파일이 늘지 않는다 | `Config/ExportOptions.plist` | 파일로 빼고 `-exportOptionsPlist` 경로만 바꾸기 |
| 키체인에 Developer ID 인증서가 없어도 `--check`가 막지 않는다(내 판단) | 실측에서 자동 서명 export가 Xcode 클라우드 관리 인증서로 `Developer ID Application: Taeho An (2FCXA77MC5)` 서명을 했다 | 인증서를 필수로 | `run_check`의 인증서 항목에 `missing=1` |
| 중간 결과는 `.build/release-mac/`, 산출물은 `dist/`(gitignore) | 평소용 설치가 읽는 `.build/release`와 겹치지 않게 | 같은 DerivedData | — |
| 만든 앱은 실행하지 않고 codesign·spctl·plutil 정적 검사만. 메인 세션 결정 | 번들 ID가 평소용과 같아 47821·저장소를 건드린다 | — | — |
| 공증 기본은 Xcode 계정: upload export로 제출하고 `-exportNotarizedApp`을 기본 300초마다(최대 180분) 다시 불러 공증·staple된 앱을 받는다. notarytool은 `--notary-profile`을 줄 때만. 사용자 지시 | 앱 전용 암호가 필요 없다. 이미 쓰는 Xcode 계정 로그인으로 된다(실측: 제출 15:18 → 약 45분 뒤 수락, spctl accepted) | notarytool 키체인 프로필(앱 암호) | `release-mac.sh` 공증 단계의 기본 분기를 notarytool로 |
| 완료 판정은 `-exportNotarizedApp`의 결과와 「is processing」 문구로만, 다른 오류는 바로 실패. 받은 앱에 서명 검증을 한 번 더. 끊기면 `--resume-notarize <xcarchive>`로 대기부터(이름은 내 판단) | 수락 뒤에도 아카이브 plist의 `processingEvent.state`가 `processing`으로 남았다. 받은 앱은 export 앱과 따로 서명된 번들이다. 첫 공증이 45분이라 끊긴 뒤 다시 제출하지 않게 | plist 상태 읽기, 재제출 | `wait_notarized_app`, `--resume-notarize` 분기 |
| CloudKit: Developer ID 앱은 Production 환경(export 엔타이틀먼트로 확인). Production 스키마 배포는 사람이 Console에서 한다. 메인 세션 결정 | 외부 사용자는 Production만 쓴다. 스키마 배포는 되돌릴 수 없는 외부 변경 | `cktool`로 자동화 | — |
| 베타 배포 빌드는 iCloud를 끈다: build setting `WAYPOINT_ICLOUD`(기본 `YES`) → macOS Info.plist `WaypointICloud` → `NO`면 `AppInstance.cloudKitContainer`가 nil. `release-mac.sh`는 기본 `NO`, `--icloud`로 켬. 엔타이틀먼트는 그대로. 사용자 결정(키를 Info.plist 파일 `Config/Waypoint-macOS-Info.plist`로 넣는 방식·키가 없으면 켬은 내 판단) | Production 스키마 배포를 보류했고 스키마 없이 켜진 앱이 어떻게 되는지 모른다. 기록은 그 Mac에만 남아도 베타 관찰에는 충분하다. 생성식 Info.plist의 `INFOPLIST_KEY_*`는 Xcode가 아는 키만 받아 사용자 키는 파일로 합친다 | 스키마를 배포하고 켜기, 엔타이틀먼트에서 iCloud 빼기(서명·프로파일이 갈라진다) | `release-mac.sh` 기본을 `--icloud`로, 또는 `project.yml`의 `WAYPOINT_ICLOUD`·`INFOPLIST_FILE[sdk=macosx*]` 빼기 |

검증: `scripts/release-mac.sh --skip-notarize` 성공(archive·export·서명 검증, `spctl`은 공증 전이라 거부), `python3 scripts/test_build_failure_report.py` 통과. 공증은 Xcode 계정 경로로 확인했다(docs/RELEASE.md 「Xcode 계정 공증 실측」). 결과 원문은 docs/RELEASE.md 「이번 실제 결과」.

## 2026-10-02 — 기록 탭 (TRK-47)

| 결정 | 이유 | 대안 | 되돌리기 |
|---|---|---|---|
| 설정 창을 탭 둘(사용량·기록)로, 기록 탭은 grouped Form 한 장에 남기는 것 · 어디에 · 백업 · 내보내기·지우기. 사용자 선택(시안 1) | — | 시안 2·3 | `SettingsView`를 사용량 Form 하나로 |
| 화면 문장은 저장 범위 표(`RecordScope`)에서만 만들고, 표는 테스트가 스키마 속성·실제 생성 지점 payload 키와 맞춘다. 메인 세션 결정 | 시안 문구(「파일 내용은 남기지 않음」)가 지침 문서 내용·판을 저장하는 사실과 달랐다. 속성을 더하면 화면이 저절로 틀리지 않게 | 화면에 문장을 직접 적기 | `RecordScopeTests` 지우기 |
| payload 키 확인은 실제 생성 지점을 돌려 모은 키 + `Shared/`의 `Event.record(` 호출 수 목록(내 판단) | 소스 문자열에서 키를 읽는 것은 깨지기 쉽다. 돌려 보는 쪽이 정확하고, 호출 수 목록이 새 생성 지점을 놓치지 않게 한다 | 소스 정규식으로 키 추출 | `eventRecordCallSitesAreKnown` |
| 남기지 않는 것 줄: 「AI 답변 · 대화 전체 · 명령 출력 · 지침 문서가 아닌 파일의 내용」(내 판단) | 코드 확인: 훅 처리는 출력에서 끝 코드·커밋 줄만 뽑고, 편집 원문은 outbox에서 크기로 줄인다. 에이전트가 도구로 남긴 메모·카드 본문은 「메모」「카드」에 든다 | 「파일 내용」 | `RecordScope.notKept` |
| 「세션」에 요청 시각을, 「요청 문장」(30일)에 문장만 둔다(내 판단) | `PromptRetention`은 문장만 비우고 이벤트·시각·`promptId`는 남긴다 | 요청 전체를 30일로 | `RecordScope.payloadKeys` |
| 지우기 전 백업은 새 까닭 `beforeDelete`(내 판단) | 목록에서 「지우기 전」으로 바로 알아본다. 이 값을 모르는 옛 앱은 이 폴더를 목록·정리에서 건너뛸 뿐(이름 해석 실패) 열기는 막지 않는다 | `manual` | `StoreBackup.Reason.beforeDelete`를 `manual`로 |
| 「지금 백업」·지우기 전 백업은 `StoreDailyBackup.runNow`로 daily와 같은 진행 중 표시를 쓴다(내 판단) | 온라인 백업 둘과 7개 정리가 겹치지 않게. 직접 뜬 백업도 daily의 「마지막 백업」이 된다 | 따로 `backupOpenStore` | `RecordsModel`이 `backup.backupOpenStore`를 바로 부르게 |
| 지우기는 한 행씩 `delete` 후 저장, 일괄 삭제(`delete(model:)`)를 쓰지 않는다(내 판단) | 일괄 삭제는 보통 저장 경로를 건너뛰어 iCloud 미러링이 지운 것을 iPhone에 보내는지 보장되지 않는다. 4,700행은 한 번에 지워도 짧다 | `delete(model:)` | `RecordWipe.deleteAll` |
| 복원 예약·지우기 뒤 앱을 다시 시작한다: 작은 셸이 지금 PID가 끝나기를 기다렸다가 `open <같은 번들>`(확인용 `WAYPOINT_RELAUNCH_HIDDEN=1`이면 `-g -j`), 앱은 `NSApp.terminate`(내 판단) | 복원은 다음 실행에서만 적용된다. 지운 뒤에는 열린 화면·처리기가 지운 행을 들고 있지 않게. 같은 번들 경로라 평소용·Dev가 자기만 다시 띄우고, `open`이 셸 환경을 넘기지 않아 저장 폴더 등은 `--env`로 넘긴다(안 넘기면 확인용 폴더로 띄운 Dev가 기본 폴더로 떠 예약이 사라진다). 사람이 누른 복원·지우기라 앞에 다시 연다(뒤에 뜨면 꺼진 줄 안다). 메인 세션 결정 | 사용자에게 다시 열라고 하기, `NSWorkspace.openApplication` | `RecordsModel.relaunch`에서 `terminate`만 |
| 지운 뒤 UserDefaults(`onboarding.completed` 등)와 저장소 밖 파일은 그대로(내 판단) | 연결 설정은 그대로라 온보딩을 다시 할 일이 아니다. 끝낸 적이 없으면 프로젝트 0개라 온보딩이 다시 뜬다(Dev 실측) | 온보딩 기록도 지우기 | `RecordWipe` 뒤에 `defaults` 지우기 |
| 내보내기는 작동 상태 값(PID·블록 확인·상태 캐시·대기 중인 도구·해시)을 넣지 않고, 카드는 표시 ID·세션은 세션 ID로 서로 가리킨다. 날짜는 밀리초까지(내 판단) | 사람이 읽고 다른 도구로 옮길 기록만. 기본 `.iso8601`은 초 아래를 버려 같은 초 이벤트 순서가 흐려진다 | 모델 그대로 전부 | `RecordExport` 레코드 필드 |
| 기록 탭 너비 520(`Theme.Records`), 높이 760에서 스크롤. 「모든 기록 지우기…」 색은 `liveText`(내 판단) | 백업 줄 「시각 · 까닭 · 크기 · 복원…」이 한 줄에 들어가게. 붉은 계열 토큰이 따로 없어 실패 표시와 같은 진한 클레이 | 시스템 빨강 | `Theme+Records.swift` |
| Debug 실행 인자로 대화상자 없이 같은 동작을 탄다(`-WaypointSettingsTab`·`-WaypointExport`·`-WaypointBackupNow`·`-WaypointRestore`·`-WaypointWipe`·`-WaypointSettingsScroll`)(내 판단) | 화면 조작 없이 Dev 실측을 하려고. Release에서는 설정 창 탭 선택 말고는 무시한다 | — | `RecordsLaunch` |

검증: `swift test` 672개 통과, macOS Debug·iOS 빌드. Dev 실측(실제 저장소 백업 사본, CloudKit 꺼짐): 기록 탭 창 캡처, 전체·프로젝트 하나 내보내기, 지금 백업, 복원 예약 → 다시 시작 → 복원 확인, 모든 기록 지우기 → 비고 `beforeDelete` 백업 남음.
