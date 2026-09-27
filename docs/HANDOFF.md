# 클라우드 세션 인수인계 — M1 3·4단계와 M2

이 문서는 로컬 세션에서 하던 작업을 클라우드 세션이 이어받기 위한 지시문이다. 저장소의 `CLAUDE.md`, `docs/SPEC.md`, `docs/MILESTONES.md`, `docs/DESIGN.md`를 먼저 읽고, 이 문서의 규칙을 함께 따른다.

## 0. 먼저 할 일: 환경 확인

```
uname -a; sw_vers 2>/dev/null; xcodebuild -version 2>/dev/null; swift --version 2>/dev/null; which xcodegen
```

- **macOS + Xcode가 있으면**: 아래 「검증」 명령을 그대로 돌린다.
- **Linux이거나 Xcode가 없으면**: 이 앱은 SwiftUI·SwiftData를 쓰므로 빌드도 `swift test`도 돌지 않는다. 코드를 쓰되, 검증할 수 없었다는 사실을 PR 본문과 보고에 분명히 적는다. 통과했다고 쓰지 않는다. 빌드를 흉내 내는 우회(모델을 SwiftData 없이 다시 짜기 등)는 하지 않는다.

어느 쪽인지 `docs/DECISIONS.md` 맨 위와 최종 보고에 적는다.

## 1. 지금 상태 (main, 2026-09-28)

| 커밋 | 내용 |
|---|---|
| `512b6b2` | M0 뼈대: XcodeGen(`project.yml` → `Waypoint.xcodeproj`), 로컬 패키지 `WaypointKit`(`Shared/`, 테스트 `Tests/`) |
| `c0ac40a` | 대시보드 시안을 Mac 기본 틀로 교체(`design/Dashboard.dc.html`), `DESIGN.md`에 「Mac 창 틀」「화면 문구」 규칙, `SPEC.md`에 `statusBeforeActive`와 CloudKit 호환 규칙 |
| `3d298c8` | 모델·파생 규칙·샘플 데이터·테스트 35개 |
| `409a1c8` | Theme, Mac 창 틀(사이드바·툴바 검색·인스펙터), 대시보드. 테스트 48개 통과, macOS·iOS 빌드 경고 0 |

M1 완료 조건 중 남은 것: 프로젝트 보드와 카드 상세 화면, 카드 드래그 이동 저장.

### 코드 지도

- `Shared/Models/` — Project, Card(+Criterion), Session, CardSession, Event(+EventValue), GuideDoc/GuideVersion. enum은 `statusRaw` 같은 원시 문자열로 저장하고 타입 있는 계산 속성을 둔다. `@Attribute(.unique)` 금지(CloudKit).
- `Shared/Rules/` — `SessionRules.state`, `CardRules.workState`(`.none/.live/.stalled`), `CardLifecycle.attach/detach/detachAll/move`(`move(.active)`는 `CardLifecycleError.cannotMoveToActive`), `DashboardQuery.groups/rows/summary`. 규칙 함수는 `save()`를 부르지 않는다.
- `Shared/Store/WaypointStore.swift` — `~/Library/Application Support/Waypoint/Waypoint.store`, 샘플은 `Sample.store`. SwiftData 기본 `default.store`는 쓰지 않는다(비샌드박스 앱).
- `Shared/Sample/SampleData.swift` — `seedIfEmpty(context, now:)`.
- `Shared/Format/` — `TimeFormat`, `SessionFormat`, `RecentEventFormat`.
- `App/Theme.swift` — 색·폰트·간격·열 폭 토큰. 모든 뷰는 여기서만 가져온다.
- `App/Components/` — `LiveDot`, `StalledDot`, `FilledDot`, `IdeaDot`, `WorkStateDot`, `TableHeader`.
- `macOS/RootView.swift` — `NavigationSplitView`. 선택 `SidebarSelection.dashboard | .project(PersistentIdentifier)`. 본문은 `NavigationStack(path:)` + `.navigationDestination(for: Card.self) { CardDetailView(card:) }`. 인스펙터·검색도 여기.
- `macOS/ProjectBoardView.swift`, `macOS/CardDetailView.swift` — **자리만 잡아 둔 최소 뷰**. 3·4단계에서 채운다.
- 실행 인자 `-WaypointSampleData`면 샘플 저장소를 쓴다.

### 이미 알게 된 함정

- 표처럼 최소 폭이 큰 본문을 `NavigationSplitView`에 넣으면 사이드바·인스펙터가 눌려 글자가 잘리고 툴바가 넘친다. `DashboardView`처럼 `GeometryReader`로 감싸 본문이 최소 폭을 요구하지 않게 한다.
- 샘플 데이터는 처음 채운 시각이 저장돼 15분 뒤 모든 행이 「멈춤」이 된다(아래 3단계에서 고친다).
- `DashboardGroup`에 public init이 없다.
- 실행 Mac은 macOS 26(Liquid Glass). 사이드바가 떠 있는 유리 패널이다.

## 2. 규칙 (저장소 밖 지침에서 옮긴 것 — 반드시 지킨다)

### 제품
- 앱은 Anthropic API나 어떤 LLM API도 호출하지 않는다. 요약·추천·자동 분류 없음.
- 카드를 자동으로 done 처리하지 않는다.
- 훅 스크립트는 Claude Code를 막지 않는다: 타임아웃 1초, 실패해도 exit 0, stdout은 `SessionStart`에서만.
- 외부 Swift 패키지는 추가하지 않는다. 필요해 보이면 `docs/DECISIONS.md`에 제안으로만 남긴다.

### 코드
- 모델·동기화·서버 로직은 `Shared/`, 화면은 `macOS/`·`iOS/`. View 파일 150줄 초과 금지.
- 색·폰트·간격 하드코딩 금지(`Theme` 경유).
- Swift 6 strict concurrency 경고 0.
- 파생 규칙과 상태 전이는 단위 테스트 필수(Swift Testing). 훅 수신은 `Tests/Fixtures/hooks/`의 JSON 픽스처로 테스트.

### 화면 문구
- 설명서 말투, 동작 규칙, 만든 쪽 용어(훅·MCP·스킬·세션 요약 등)를 화면에 쓰지 않는다. 조작법 안내 문구도 넣지 않는다. 컨트롤이 스스로 설명하게 한다.
- 시안의 「대화에서 감지」「세션 종료 시 자동 작성」「새 세션을 열어 …」 같은 문구는 옮기지 않는다.
- 「A가 아니라 B」 문장 꼴을 쓰지 않는다(화면·문서·PR 모두).

### git
- 커밋 메시지는 한국어, 「무엇을 했다 — 왜」 한 줄. `Co-Authored-By` 줄과 세션 링크를 넣지 않는다(PR 본문 포함).
- 커밋은 갈래별로 나눈다(기능/버그/리팩터링/도구·설정/문서). 단계 하나 = 커밋 하나가 기본.
- main에 직접 푸시하지 않는다. 브랜치에서 작업하고 PR을 연다.

### 진행 — 이번 실행은 무인 진행

사용자는 자리에 없다(자는 동안 진행). **이번 실행에 한해 사용자가 다음을 승인했다.** 저장소 `CLAUDE.md`의 「마일스톤이 끝나면 멈추고 확인받는다」보다 이 절이 우선한다.

- **멈추지 않는다.** M1이 끝나면 PR을 열고 바로 M2로 넘어간다. 질문으로 대기하지 않는다.
- **판단은 스스로 한다.** 정책·설계·UX 결정도 명세·`DESIGN.md`·기존 코드의 결에 맞춰 가장 보수적인 쪽으로 정하고 진행한다. 결정마다 `docs/DECISIONS.md`에 한 줄씩 남긴다: 날짜, 무엇을, 왜, 대안, 되돌리는 방법. 사용자가 아침에 이 파일만 읽고 뒤집을 수 있어야 한다.
- **막히면 건너뛴다.** 지시대로 안 되거나 명세와 실제가 다르면 우회 구현으로 덮지 말고, 그 항목을 `docs/DECISIONS.md`의 「막힌 것」에 기록한 뒤 다음 항목으로 넘어간다. 전체가 막혀야만 멈춘다.
- **넘지 않는 선** (승인 범위 밖):
  - main에 푸시·머지하지 않는다. PR을 머지하지 않는다.
  - 외부 Swift 패키지를 추가하지 않는다. 필요해 보이면 `DECISIONS.md`에 제안으로만 남긴다.
  - 저장소 밖(사용자 전역 설정 등)을 바꾸지 않는다.
  - 제품 절대 규칙(LLM API 호출 금지, 자동 done 금지, 훅이 Claude Code를 막지 않음)은 어떤 판단으로도 넘지 않는다.
  - 테스트를 지우거나 약하게 바꿔 통과시키지 않는다.
- 검증하지 못한 것은 「미검증」으로 적는다. 통과했다고 쓰지 않는다.

## 3. M1 나머지 — 브랜치 `m1-board-card`

### 3단계: 프로젝트 보드 (커밋 1개)
- `ProjectBoardView(project:)`를 채운다. 시안 `design/Project.dc.html`의 **본문 구조만** 가져오고 창 틀은 `DESIGN.md` 「Mac 창 틀」을 따른다(시안의 HTML 사이드바·헤더는 옮기지 않는다).
- 헤더: 프로젝트 이름(세리프 26), 키, 요약, 폴더 경로(모노).
- 네 칸: 아이디어·나중에(idea) / 다음 할 일(next) / 작업중(active) / 완료(done, 최근 7일). archived는 보드에 안 보인다. 칸마다 개수.
- 카드 모양은 `DESIGN.md` 「상태 표현 규칙」: 아이디어 점선 테두리+`bgPanel`, 다음 흰 카드, 작업중 1.5pt `live` 테두리+펄스 점+세션 정보 박스(세션 종류·ID·최근 파일), 멈춤은 속 빈 점+「멈춤 N분」, 완료 불투명도 0.85+날짜·세션 횟수. 서브에이전트가 붙은 하위 카드는 부모 아래 14pt 들여쓰기.
- 드래그로 상태 이동: `CardLifecycle.move(_:to:at:in:)` 후 `save()`. **작업중 칸으로는 떨어뜨릴 수 없다**(세션이 붙어야 작업중). 작업중 카드를 완료로 옮기는 건 된다. 드롭 불가 칸은 드래그 중 강조하지 않는다.
- 카드 클릭 → `NavigationLink(value: card)`로 카드 상세.
- 아이디어 칸이 길면 몇 개만 보이고 나머지는 펼치기(시안의 「3개 더 보기」).
- 시안의 「카드 추가」 버튼, 「보드/활동 기록/지침 문서/개요」 탭은 이번 범위 밖. 넣지 않는다.
- 같은 단계에서 고칠 것: 샘플 모드를 **실행할 때마다 메모리 저장소에 새로 채우는** 방식으로 바꾼다(`WaypointStore.makeContainer(inMemory: true)` + `seedIfEmpty`). 그러면 드래그 이동이 재실행 후 남는지는 기본 저장소로 확인해야 하므로, 이동 저장은 in-memory 컨테이너 테스트로 검증한다: `move` 후 `save`, 새 `ModelContext`로 다시 읽어 상태 확인. 샘플 모드 변경은 별도 커밋(버그 갈래).

### 4단계: 카드 상세 (커밋 1개)
- `CardDetailView(card:)`를 채운다. 시안 `design/Card.dc.html` 본문 구조:
  - 본문: 경로(프로젝트 / 카드 ID), 상태 배지(작업중이면 경과), 종류, 제목(세리프), 본문(Markdown — macOS 14의 `AttributedString(markdown:)` 수준이면 충분), 완료 조건 체크리스트(완료 수 / 전체, 체크하면 저장), 히스토리(이 카드의 Event 시간 역순: 상태 변경·연결·파일 변경·커밋·메모).
  - 인스펙터(기존 `RootView` 인스펙터를 카드 선택 시 카드 정보로 바꾸거나 본문 오른쪽 칸 — 네 판단, 이유 보고): 프로젝트, 상태, 만든 곳(origin), 누적 작업(세션 수·서브에이전트 수), 지금 연결된 세션(종류·ID·브랜치), 변경된 파일(`file.changed` payload의 경로와 +/− 줄 수), 연결된 카드(상위·하위만 — 「파생」 관계는 모델에 없으므로 넣지 않는다), 다음 세션을 위한 메모(`nextSessionNote`).
- 「Claude에서 이어서 작업」 버튼은 넣지 않는다(동작이 명세에 없다). 「완료로 옮기기」 버튼은 `CardLifecycle.move(.done)`으로 넣는다.
- 완료 조건 체크 변경은 `card.updatedAt` 갱신과 이벤트(`note`나 별도 타입 — 네 판단, SPEC 이벤트 타입 안에서) 기록.

### M1 마무리
- 두 단계가 끝나면 main으로 PR을 연다(제목 예: 「M1 프로젝트 보드와 카드 상세」). 멈추지 않고 M2로 간다.
- PR 본문: 완료 조건 3개(세 화면이 시안과 같은 구조로 보인다 / 카드 이동이 저장된다 / 샘플 데이터로 보인다) 각각 충족·미검증과 근거, 「로컬에서 확인할 것」 목록.

## 4. M2 — 브랜치 `m2-hooks` (`m1-board-card` 위에서 시작)

M1 PR이 아직 머지되지 않았으므로 `m2-hooks`는 `m1-board-card`에서 분기하고, PR의 base도 `m1-board-card`로 한다(M1이 머지되면 사용자가 base를 main으로 바꾼다).

M2는 실제 Mac에서 Claude Code 훅과 앱을 함께 돌려야 끝난다. 클라우드에서는 아래 **코드 부분**만 하고, 실측이 필요한 부분은 로컬 작업으로 남긴다.

1. **훅 입력 확인(문서 기반)**: 최신 Claude Code hooks 문서에서 이벤트 이름·입력 필드를 확인해 `docs/SPEC.md` 5장을 갱신한다. 서브에이전트 도구 이름, 서브에이전트의 `session_id`가 부모와 같은지, `SessionEnd` 존재 여부를 특히 본다. 문서에 없는 것은 「실측 필요」로 표시. 문서 예시로 만든 픽스처는 `Tests/Fixtures/hooks/doc-*.json`처럼 이름으로 구분한다(실측 픽스처는 로컬에서 따로 추가).
2. **로깅 모드 스크립트**: `integration/hooks/waypoint-hook.sh`에 모든 입력을 그대로 파일(`~/Library/Application Support/Waypoint/hook-log/`)에 남기는 모드(환경 변수로 켬). curl 1초 타임아웃, 앱 무응답 시 `outbox.jsonl` 적재(SPEC 6장 형식), 항상 exit 0, stdout은 `SessionStart`에서만.
3. **로컬 서버** (`Shared/Server/`): Network.framework 기반 `127.0.0.1:47821` HTTP/1.1. `POST /hooks/<EventName>`, 본문 JSON. `SessionStart`는 `200 text/plain`, 나머지 `204`. 요청 파싱·라우팅은 소켓 없이 테스트할 수 있게 분리.
4. **훅 처리** (`Shared/Hooks/`): SPEC 5장 표대로 세션 생성·heartbeat·하위 세션·파일 변경·커밋 감지·종료. `cwd`로 가장 가까운 상위 `rootPath` 프로젝트 매칭, 미등록 폴더 무시(`SessionStart`만 한 줄 안내). 카드 연결 해제는 `CardLifecycle` 사용. 픽스처 기반 테스트.
5. **outbox 흡수**: 앱 시작 시 순서대로 처리하고 파일을 비운다. 테스트.
6. **stalled 타이머와 메뉴 막대 상주**: `MenuBarExtra`, 창을 닫아도 서버 유지.

M2는 단계마다 커밋, 끝나면 PR을 열고 작업을 마친다. PR 본문과 최종 보고에는 「로컬에서 할 것」을 분리해 적는다: 훅을 `~/.claude/settings.json`에 등록(사용자 전역 설정이라 사용자가 직접), 로깅 모드로 실제 입력 수집 → 픽스처·SPEC 보정, 완료 조건(세션 2개 live 표시, 앱 꺼진 동안의 기록 반영) 확인.

## 5. 검증 (macOS + Xcode 환경일 때)

```
xcodegen generate    # 폴더를 새로 만들었을 때만
swift test 2>&1 | tail -5
xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -destination 'platform=macOS' -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- build 2>&1 | grep -E "warning:|error:|BUILD" | grep -v appintents | tail -20
xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "warning:|error:|BUILD" | grep -v appintents | tail -20
```

기대: 테스트 전부 통과, 두 빌드 `** BUILD SUCCEEDED **`, Swift 경고 0. 결과는 원문을 PR과 보고에 붙인다.

## 6. 보고 형식 (PR 본문과 최종 보고)

- 바꾼 것 요약(파일별 한 줄)
- 검증 결과 원문, 또는 검증하지 못한 이유
- 내가 정한 것(사용자가 뒤집을 수 있게)
- 로컬에서 확인할 것
- 범위 밖에서 발견한 것(고치지 않고 보고만)

마지막으로 `docs/DECISIONS.md`를 M2 브랜치에 커밋해 두고, 최종 보고 첫머리에 두 PR 링크와 「아침에 먼저 볼 것」 3줄을 적는다.
