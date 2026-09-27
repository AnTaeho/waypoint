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
| 09-28 | (M2) 서브에이전트 하위 세션의 `Session.id` = 훅의 `agent_id` | 문서상 서브에이전트 안의 훅은 `session_id`가 부모와 같고 `agent_id`로 구분한다. 실측 필요 | `session_id`가 다르면 그것을 쓰기 | `HookProcessor.subagentStart` |
| 09-28 | (M2) 하위 세션은 `SubagentStart`에서 만들고, 카드 ID는 그 직전 `PreToolUse(Agent)` 프롬프트의 `[LDG-16]`에서 가져와 **같은 에이전트 종류의 가장 오래된 대기 항목**과 짝짓는다(10분 지나면 버림, 다른 종류와는 짝짓지 않음) | 문서에 두 이벤트를 잇는 키가 없다. 틀린 카드에 붙이는 것보다 안 붙이는 쪽이 보수적 | `PreToolUse`에서 바로 하위 세션을 만들기(그러면 `agent_id`를 모름) | `HookProcessor.takePending` |
| 09-28 | (M2) 프롬프트에 카드 ID가 없는 서브에이전트는 어떤 카드에도 붙이지 않는다. 다만 그 서브에이전트의 파일 변경은 부모 세션의 작업중 카드에 남긴다 | 카드 연결은 명시적일 때만. 파일 기록은 잃지 않게 | 부모 카드에 자동 연결 | `postToolUse`의 `cards.isEmpty, sub != nil` 분기 |
| 09-28 | (M2) `SessionStart` 없이 다른 훅이 먼저 와도(훅을 세션 중간에 등록한 경우) 등록 폴더면 세션을 만든다. 끝난 세션은 **끝난 시각 뒤의** 훅이 올 때만 다시 살리고(resume), 그 이전 시각의 늦은 기록은 무시 | outbox로 늦게 들어온 기록이 끝난 세션을 되살리지 않게 | SessionStart에서만 생성 | `HookProcessor.mainSession` |
| 09-28 | (M2) 카드가 없는 세션의 파일 변경·커밋은 카드 없이 프로젝트 이벤트로 남긴다 | 기록을 버리지 않는다. 화면에는 아직 안 보인다 | 버리기 | `postToolUse`의 `targets` |
| 09-28 | (M2) 줄 수: Edit=`new_string`/`old_string` 줄 수, Write=`content` 줄 수(지운 줄 0), Bash=`bashEditDiff.changedFiles`(줄 수 0). 커밋은 Bash 명령에 `git commit`이 있고 출력 첫 줄이 `[브랜치 해시] 메시지`일 때 | 문서에 있는 필드만 쓴다. 실제 `tool_response`에 더 정확한 필드가 있으면 실측 후 바꾼다 | git 명령 직접 실행(훅 경로에서 느려짐) | `HookParsing` |
| 09-28 | (M2) git 브랜치는 `.git/HEAD`만 읽어 얻는다(git을 실행하지 않음) | 서버 응답을 느리게 하지 않게. 커밋 출력의 브랜치로도 갱신 | `git rev-parse` 실행 | `GitInfo.branch` |
| 09-28 | (M2) outbox는 먼저 `outbox.processing-<ms>-<uuid>.jsonl`로 이름을 바꿔 떼어 낸 뒤 처리하고 지운다. 서버가 열린 직후 한 번 더 흡수 | 흡수 중 스크립트가 쓰는 줄을 잃지 않고, 도중에 앱이 죽어도 다음 실행에서 이어 처리 | 읽고 파일 비우기(그사이 쓴 줄 유실 위험) | `Outbox.drain`, `AppServices.start` |
| 09-28 | (M2) 샘플 모드에서는 서버를 열지 않고 outbox도 흡수하지 않는다 | 메모리 저장소에 흡수하면 outbox가 비워지면서 실제 기록을 잃는다 | — | `WaypointApp.init` |
| 09-28 | (M2) 훅 스크립트 curl에 `--noproxy '*'`, `--connect-timeout 1` 추가. 로깅 모드 파일은 `hook-log/<YYYY-MM-DD>.jsonl`, 줄 형식은 outbox와 같다. 테스트용 `WAYPOINT_SUPPORT_DIR` 환경 변수 추가 | 셸에 `http_proxy`가 있으면 127.0.0.1 요청이 프록시로 가서 앱에 닿지 않는 것을 이 컨테이너에서 실제로 확인했다 | — | `integration/hooks/waypoint-hook.sh` |
| 09-28 | (M2) 메뉴 막대: 프로젝트별 「가계부 앱 · 작업 2 · 멈춤 1」(카드와 상관없이 메인 세션 수), 받지 못할 때 한 줄, 「Waypoint 열기」, 「종료」. 아이콘 SF Symbol `signpost.right` | 카드 없는 세션도 보이는 곳이 필요했다(아래 「막힌 것」). 사실만 짧게 | — | `MenuBarContent` |
| 09-28 | (M2) 세션 상태 캐시(`stateRaw`)를 60초마다 맞춘다 | 화면 판정은 이미 `TimelineView`가 한다. 캐시는 M6 동기화용 | 타이머 없이 두기 | `AppServices.refreshInterval` |
| 09-28 | (M2) 서버는 루프백(127.0.0.1)에만 묶고, 요청 하나를 받는 데 5초·본문 1 MiB로 제한 | 외부 접속 차단, 멈춘 연결 정리 | — | `LocalServer`, `HTTPRequestParser` |

## 막힌 것

- **빌드·테스트 전부 미검증.** 위 「실행 환경」 참고. 검증된 것은 `integration/hooks/test-waypoint-hook.sh`(bash, 10개 항목 통과) 하나뿐이다.
- **Xcode 프로젝트 파일 미갱신.** 새 앱 파일을 pbxproj에 넣지 않았다. 로컬에서 `xcodegen generate` 필요.
- **M2 완료 조건 「대시보드에 세션 2개가 live로 보인다」**: 지금 대시보드 작업중 표는 (세션, 카드) 쌍만 보인다. 카드는 M3(MCP `card_start`)부터 붙으므로 M2만으로는 세션이 대시보드에 안 보인다.
  메뉴 막대에는 카드 없는 세션 수가 보이게 했다. 대시보드에 카드 없는 세션 줄을 넣을지는 SPEC 4장 「대시보드 "작업중" 목록 = (세션, 카드) 쌍」을 바꾸는 일이라 **정하지 않고 남긴다.**
  제안: (a) 카드 없는 세션을 「카드 없음」 줄로 표에 넣기, (b) M2 완료 조건을 「메뉴 막대에 세션 2개」로 읽기, (c) M3 뒤에 확인.
- **Network.framework의 Swift 6 Sendable 경고 가능성.** `NWConnection`을 `@Sendable` 콜백에서 잡는다. SDK가 Sendable로 표시하지 않으면 경고·오류가 날 수 있다. 나면 `LocalServer`를 고친다.
- **실측 필요 항목**은 `docs/SPEC.md` 5장 「실측 필요」에 모았다.

## 제안(하지 않음)

- 외부 Swift 패키지는 추가하지 않았다. MCP(M3)에서 공식 Swift SDK를 쓸지는 그때 판단.
