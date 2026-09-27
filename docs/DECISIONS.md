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
