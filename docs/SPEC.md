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
| 멈춤 | 세션이 끝났다는 신호 없이 일정 시간 활동이 없는 상태 |

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
  (명령 형식은 구현 시점 Claude Code 문서로 확인)
- iOS는 CloudKit 동기화로 같은 데이터를 본다. 로컬 서버는 macOS에만 있다.

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
             startedAt, lastSeenAt, endedAt?, 
             state: live | stalled | ended          // 파생값, 저장 캐시

CardSession  card, session, attachedAt, detachedAt?

Event        id, project, card?, session?, at,
             type: session.start | session.end | card.created | card.status |
                   card.attached | card.detached | file.changed | commit |
                   note | guide.synced,
             payload: JSON(Data)

GuideDoc     id, project, relPath, content, contentHash, lastSyncedAt
GuideVersion doc, content, at, source: app | local
```

CloudKit(M6) 호환을 위해 처음부터 다음을 지킨다: `@Attribute(.unique)`를 쓰지 않고 키·ID 중복은 코드에서 막는다. 모든 속성은 기본값이 있거나 옵셔널, 관계는 옵셔널이고 역관계를 둔다. enum은 원시 문자열로 저장한다.

### 파생 규칙

- 카드가 **작업중** = 열린 `CardSession` 중 세션 `state == live`인 것이 1개 이상.
- 세션 `stalled` = `endedAt == nil` 이고 `now - lastSeenAt > stallTimeout` (설정값, 기본 15분).
- 마지막 live 세션이 떨어지면 카드 `status`는 작업 시작 전 상태(`statusBeforeActive`)로 돌아간다. 그사이 사용자가 상태를 바꿨으면(`status != active`) 그대로 둔다. **자동으로 done이 되지 않는다.** 완료는 스킬이 사용자 확인 후 `card_update(status: done)` 하거나 사용자가 앱에서 옮긴다.
- 대시보드 "작업중" 목록 = 프로젝트별로 묶은 (세션, 카드) 쌍. 같은 프로젝트에 세션 2개가 서로 다른 카드를 작업하면 그 프로젝트 아래 2줄.

## 5. 훅 → 기록 매핑

설정 예시: `integration/hooks/settings.example.json`. 사용자 전역(`~/.claude/settings.json`)에 둔다.
**이벤트 이름과 입력 JSON 필드는 구현 시점의 Claude Code hooks 문서로 반드시 확인할 것.**

| 훅 | 서버 동작 | 비고 |
|---|---|---|
| `SessionStart` | `cwd`로 프로젝트 조회 → 세션 생성. 응답 본문을 stdout으로 출력해 **대화 컨텍스트에 주입** | 주입 내용: 프로젝트 키, 세션 ID, 다음 할 일 상위 5개, 이 프로젝트의 다른 작업중 카드, 직전 세션 메모 |
| `UserPromptSubmit` | `lastSeenAt` 갱신 | heartbeat |
| `PreToolUse` (서브에이전트 도구) | 하위 세션 생성. 프롬프트에 `[LDG-16]` 같은 카드 ID가 있으면 그 카드에 연결 | 도구 이름은 버전에 따라 다를 수 있음 |
| `PostToolUse` (Edit/Write/Bash 등) | `lastSeenAt` 갱신, 변경 파일을 현재 작업중 카드 이벤트로 | `git commit` 감지 시 commit 이벤트 |
| `SubagentStop` | 하위 세션 종료, 연결 해제 | |
| `Stop` | `lastSeenAt` 갱신 | 턴 종료일 뿐 세션 종료 아님 |
| `SessionEnd` | 세션 종료, 모든 연결 해제 | |

등록되지 않은 폴더의 세션은 무시한다 (단, `SessionStart` 컨텍스트로 "이 폴더는 Waypoint에 없음, `/tracker init` 가능"을 한 줄 알린다). 하위 폴더에서 연 세션은 가장 가까운 상위 `rootPath` 프로젝트로 매칭한다.

## 6. 로컬 HTTP API (훅용)

모두 `POST http://127.0.0.1:47821/hooks/<EventName>`, 본문은 Claude Code가 훅에 넘긴 JSON 그대로. 응답:

- `SessionStart`: `200 text/plain` — 컨텍스트로 주입할 짧은 텍스트 (없으면 빈 본문)
- 나머지: `204`

outbox 형식: 한 줄에 `{"event":"<EventName>","receivedAt":<unix>,"payload":<원본 JSON>}`. 앱은 실행 시 순서대로 흡수하고 파일을 비운다.

## 7. MCP 도구 (스킬용)

스킬이 호출한다. 모두 `project`는 키 또는 `cwd`로 지정 가능.

| 도구 | 입력 | 설명 |
|---|---|---|
| `project_resolve` | `cwd` | 폴더 → 프로젝트 요약 (없으면 null) |
| `project_init` | `cwd, name, key, summary, stack[], guideFiles[], seedCards[]` | 초안 생성. 앱에 확인 시트를 띄우고, 사용자가 **등록**을 눌러야 확정 |
| `card_list` | `project, status?, query?` | 카드 목록 |
| `card_get` | `id` | 카드 상세 + 최근 이벤트 |
| `card_create` | `project, title, kind, status, body?, parentId?, criteria[]?` | 생성 (origin=claude) |
| `card_start` | `id, sessionId` | 세션을 카드에 연결 → 작업중 |
| `card_update` | `id, title?, body?, status?, criteria?` | 수정. `status: done`은 사용자 확인 후에만 |
| `card_note` | `id, text` | 히스토리에 메모 |
| `card_handoff` | `id, nextSessionNote` | 다음 세션을 위한 메모 저장 |

`sessionId`는 `SessionStart` 훅이 주입한 컨텍스트에서 Claude가 읽어 전달한다.

## 8. 지침 문서 동기화

- init 시 선택한 파일(예: `CLAUDE.md`, `docs/ARCHITECTURE.md`)을 `GuideDoc`으로 등록.
- 로컬 변경: FSEvents로 감지 → 내용 반영, `GuideVersion(source: local)`.
- 앱 편집 저장: 로컬 파일에 원자적 쓰기 → `GuideVersion(source: app)`.
- 양쪽이 마지막 동기화 이후 모두 바뀐 경우: 자동 병합하지 않고 비교 화면(좌: 로컬, 우: 앱)에서 사용자가 선택.
- 샌드박스 앱이면 폴더 접근은 security-scoped bookmark로 유지.
- 렌더링: 제목·목록·코드블록·표·인라인 코드를 지원하는 Markdown 뷰. 편집은 원문 텍스트 편집.

## 9. 화면

`docs/DESIGN.md` 참조. 대시보드 / 프로젝트 보드 / 카드 상세 / 지침 문서 / 프로젝트 init 시트 / iPhone 작업중.

## 10. 열린 질문 (구현 중 결정)

- 앱 샌드박스 여부 (로컬 서버·파일 감시 편의 vs 배포 방식). 개인용이면 비샌드박스 + 직접 서명도 가능.
- Swift MCP 서버 구현: 공식 Swift SDK 사용 가능 여부 확인, 안 되면 Streamable HTTP의 필요한 부분만 직접 구현.
- 서브에이전트의 `session_id`가 부모와 같은지 별도인지 — 실제 훅 입력을 로깅해서 확인 후 `Session` 매핑 확정.
