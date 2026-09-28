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
             startedAt, lastSeenAt, endedAt?, claudePid:Int?,   // claudePid: 메인 세션만, 훅 스크립트가 보낸 Claude Code PID
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
- 대시보드 "작업중" 목록 = 프로젝트별로 묶은 (세션, 카드) 쌍 + 카드가 붙지 않은 끝나지 않은 메인 세션 한 줄씩(카드 칸 비움, 제목 자리 「카드 없음」, 최근 파일은 그 세션과 서브에이전트가 카드 없이 남긴 `file.changed`). 같은 프로젝트에 세션 2개가 서로 다른 카드를 작업하면 그 프로젝트 아래 2줄. 세션에 카드가 붙으면 카드 없는 줄은 카드 줄로 바뀐다(중복 없음). 카드 없는 서브에이전트는 줄을 만들지 않는다. 제목의 「작업 N개」는 live 줄 수, 사이드바·프로젝트 표의 작업중·멈춤 수는 카드 수 + 카드 없는 메인 세션 수.

## 5. 훅 → 기록 매핑

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
| `SessionStart` | `source`(startup/resume/clear/compact/fork), `model?` | `cwd`로 프로젝트 조회 → 세션 생성(이미 있으면 다시 살림). 응답 본문을 stdout으로 출력해 **대화 컨텍스트에 주입** | 주입 내용: 프로젝트 키, 세션 ID, 다음 할 일 상위 5개, 이 프로젝트의 다른 작업중 카드, 직전 세션 메모. command 훅만 지원 |
| `UserPromptSubmit` | `prompt` | `lastSeenAt` 갱신 | heartbeat |
| `PreToolUse` (`Agent`) | `tool_name`=`Agent`, `tool_input.prompt/description/subagent_type`, `tool_use_id` | 부모 세션 heartbeat. 프롬프트의 `[LDG-16]` 같은 카드 ID와 `subagent_type`을 **대기 목록**에 올린다 | 서브에이전트 도구 이름은 `Agent`(옛 이름 `Task`도 matcher에 남겨 둔다) |
| `SubagentStart` | `agent_id`, `agent_type` | 하위 세션 생성(`id`=`agent_id`, `agentName`=`agent_type`, 부모=`session_id` 세션). 대기 목록에서 같은 `agent_type`의 가장 오래된 항목을 꺼내 카드가 있으면 연결 | 두 이벤트를 잇는 키는 실측에도 없다(`SubagentStart`에 `tool_use_id` 없음, 같은 `prompt_id`만 공유) → 순서·종류로 짝짓는다 |
| `PostToolUse` (Edit/Write/Bash 등) | `tool_name`, `tool_input`, `tool_response` | `lastSeenAt` 갱신(서브에이전트면 그 하위 세션도), 변경 파일을 현재 작업중 카드 이벤트로. `Bash`의 `tool_response.gitOperation.commit`(없으면 `git commit` 출력 `[브랜치 해시] 메시지`)에서 commit 이벤트 | 줄 수는 `structuredPatch`·`bashEditDiff.files[].hunks`의 `+`/`-` 줄. 조각이 없으면 `Edit`은 `old_string/new_string`, `Write`는 `content`로 추정. `bashEditDiff.changedFiles`에만 있는 파일은 줄 수 0 |
| `SubagentStop` | `agent_id`, `agent_type`, `last_assistant_message` | 하위 세션 종료, 연결 해제 | 앱 내부 에이전트(`agent_type` 빈 값)에도 불린다 → 모르는 `agent_id`면 무시 |
| `Stop` | `stop_hook_active`, `last_assistant_message` | `lastSeenAt` 갱신 | 턴 종료일 뿐 세션 종료 아님 |
| `SessionEnd` | `reason`(clear/resume/logout/prompt_input_exit/other) | 세션 종료, 모든 연결 해제(하위 세션 포함) | 기본 타임아웃 1.5초. 가끔 오지 않는다 → 아래 「종료 판정」 |

모든 훅: 스크립트가 보낸 Claude Code PID(6장)가 있으면 메인 세션 `claudePid`에 적는다. 비어 있거나 이 훅이 지금까지 받은 것 중 가장 새것(`at >= lastSeenAt`)일 때만 바꾼다(`--resume`은 같은 `session_id`를 새 프로세스로 이어 가고, outbox로 늦게 온 옛 훅은 되돌리지 않는다). 서브에이전트 훅의 PID는 부모와 같은 프로세스라 메인 세션에만 적는다.

등록되지 않은 폴더의 세션은 무시한다 (단, `SessionStart` 컨텍스트로 "이 폴더는 Waypoint에 없음, `/tracker init` 가능"을 한 줄 알린다). 하위 폴더에서 연 세션은 가장 가까운 상위 `rootPath` 프로젝트로 매칭한다.

### 실측 결과 (2026-09-28, Claude Code 2.1.283, `claude -p`)

`~/workspace/waypoint-probe`에서 `claude -p`로 돌린 세션의 훅 입력을 로깅 모드로 받았다. 실제 입력은 `Tests/Fixtures/hooks/real-*.json`(문서 예시로 만든 `doc-*.json`은 그대로 둔다. 실측과 모순되는 필드는 없었다).

- **서브에이전트**: 서브에이전트 안의 훅(`PostToolUse` 등)과 `SubagentStart`/`SubagentStop`의 `session_id`는 부모 세션과 같다. `agent_id`는 17자 16진(`ad5a8ca20b7faa5f7`), `agent_type`은 `subagent_type` 값(`general-purpose`). 그래서 하위 세션 `Session.id` = `agent_id`로 확정.
- **도구 이름**: `Agent`. `tool_input`은 `description`, `prompt`, `subagent_type`, `run_in_background`. 프롬프트 첫 줄 `[PRB-1]`이 그대로 온다.
- **순서**: 포그라운드·백그라운드(`run_in_background: true`) 모두 `PreToolUse(Agent)` → `SubagentStart`(1~2초 뒤) → 서브에이전트의 `PostToolUse` → `SubagentStop`. 백그라운드는 그사이 부모의 `Stop`·`UserPromptSubmit`이 섞인다. 서브에이전트가 끝나면 부모에 `UserPromptSubmit`(`prompt`가 `<agent-message from="<agent_id>">…`)이 한 번 더 온다 — heartbeat로만 쓴다.
- **앱 내부 에이전트**: `agent_type`이 빈 값인 `SubagentStop`이 `SubagentStart` 없이 온다(대화 요약 같은 내부 작업). 모르는 `agent_id`라 무시한다.
- **`SessionStart`**: `source`와 공통 필드만 온다(`model` 없음). `--resume`은 **같은 `session_id`**에 `source: resume`, `--fork-session`은 **새 `session_id`**에 `source: fork`. resume/fork에는 `context_tokens`, `seconds_since_last_response`, `prompt_cache_likely_expired`, `estimated_cache_write_usd`가 더 붙는다. `clear`/`compact`는 대화형에서만 나서 이번에 재지 못했다.
- **`SessionEnd`**: `-p` 모드에서도 `reason: "other"`로 온다. 단 **늘 오지는 않는다**: 20개 세션 중 17개에서 왔고, 도구를 쓰는 `-p` 세션 2개를 동시에 끝냈을 때 두 번 다 하나가 빠졌고, 서브에이전트를 쓴 단독 세션 하나도 빠졌다. 사용자의 다른 `SessionEnd` 훅(`cc-hook.sh end`)도 같은 세션에서 불리지 않아, Waypoint 스크립트 문제가 아니라 Claude Code가 훅을 부르지 않았거나 끝내기 전에 프로세스를 닫은 것으로 본다. 빠진 세션은 Claude Code 프로세스가 사라지면 앱이 끝낸다(아래 「종료 판정」).
- **공통 필드**: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, 대부분 `prompt_id`, `permission_mode`(`auto` 등). `effort`는 문자열이 아니라 `{"level": "medium"}` 객체다(Waypoint는 안 쓴다). `Stop`·`SubagentStop`에 `background_tasks`, `session_crons`가 붙는다.
- **`Edit`의 `tool_response`**: `filePath`, `oldString`, `newString`, `originalFile`, `structuredPatch`(`[{oldStart, oldLines, newStart, newLines, lines:[" a","-b","+B1"]}]`), `replaceAll`, `userModified`. 줄 수는 `structuredPatch`의 `+`/`-` 줄로 센다(`replace_all`도 정확).
- **`Write`의 `tool_response`**: `type`(`create`/`update`), `filePath`, `content`, `structuredPatch`(새 파일이면 빈 배열), `originalFile`. 새 파일은 `content` 줄 수, 덮어쓰기는 `structuredPatch`로 센다.
- **`Bash`의 `tool_response`**: `stdout`, `stderr`, `interrupted`, `isImage`, `noOutputExpected`. 파일을 바꾸면 `bashEditDiff`: `files:[{filePath, hunks:[…lines], created}]`, `moreFiles`, `changedFiles`. 커밋하면 `gitOperation.commit`: `{sha, kind: "committed", branch}`. 커밋은 이것을 먼저 쓰고, 메시지는 출력 첫 줄 `[브랜치 해시] 메시지`에서 얻는다.
- **`MultiEdit`**: 실측 세션의 도구 목록에 없다. 바이너리에는 권한 규칙 호환용으로 이름이 남아 있어 matcher와 파서는 그대로 둔다.
- **속도**: 훅 한 번 실행에 수십 ms(전사의 `stop_hook_summary`에서 Waypoint `Stop` 32 ms). `claude -p "hi"` 전체 9초로 눈에 띄는 지연 없음.
- **`PostToolUse` matcher**(`Edit|MultiEdit|Write|Bash`) 밖의 도구만 오래 쓰면 heartbeat가 없다. `Bash`가 45초 걸리는 동안에도 `PostToolUse`는 끝난 뒤에야 온다. 멈춤 판정 15분에는 문제없다.

### 종료 판정 (`SessionEnd`가 오지 않은 세션)

앱이 60초마다, 그리고 시작할 때 outbox를 흡수한 직후 한 번, 끝나지 않은 **메인 세션**을 검사한다(`SessionSweep`, `AppServices.refreshStates`).

- `claudePid`가 있으면 그 프로세스를 본다(`sysctl KERN_PROC_PID`). 없거나 좀비면 끝낸다(`reason: "process-gone"`). 프로세스 시작 시각(`p_starttime`)이 `lastSeenAt`보다 2초 넘게 늦으면 PID를 재사용한 다른 프로세스로 보고 끝낸다(마지막 훅 뒤에 시작한 프로세스는 그 훅을 보냈을 수 없다. 2초는 outbox `receivedAt`이 초 단위로 잘리는 몫). 프로세스가 살아 있으면 오래 조용해도 둔다.
- `claudePid`가 없으면(옛 스크립트, PID를 못 찾은 경우) `lastSeenAt`에서 24시간이 지나면 끝낸다(`reason: "inactive-24h"`).
- 끝내는 경로는 `SessionEnd`와 같다(`HookProcessor.finish`): 끝나지 않은 하위 세션부터 닫고, 카드 연결을 모두 해제해 카드를 작업 전 상태로 돌리고(done으로 바꾸지 않는다), `session.end`에 `reason`을 남긴다. 끝낸 시각은 검사 시각, `lastSeenAt`은 그대로 둔다.
- 끝낸 뒤 그 시각보다 늦은 훅이 오면(resume 등) 세션은 다시 살아난다(기존 규칙). 그 이전 시각의 늦은 outbox 기록은 무시한다.
- 실측(2026-09-28): 도구를 쓰는 `claude -p` 2개를 동시에 돌리다 `kill -9`로 죽이자 두 세션 모두 28초 뒤 `process-gone`으로 끝났다. 같은 날 정상 종료한 동시 세션 12개는 모두 `SessionEnd`가 왔다.

### 남은 문제

- `SessionStart(source: clear/compact)`의 `session_id`는 대화형 세션에서 따로 확인해야 한다.

## 6. 로컬 HTTP API (훅용)

모두 `POST http://127.0.0.1:47821/hooks/<EventName>`, 본문은 Claude Code가 훅에 넘긴 JSON 그대로. 스크립트가 훅을 부른 Claude Code 프로세스를 찾으면 머리 `X-Waypoint-Claude-PID: <PID>`를 더한다(없으면 뺀다). 응답:

- `SessionStart`: `200 text/plain` — 컨텍스트로 주입할 짧은 텍스트 (없으면 빈 본문)
- 나머지: `204`

outbox 형식: 한 줄에 `{"event":"<EventName>","receivedAt":<unix>,"claudePid":<PID>,"payload":<원본 JSON>}`. `claudePid`는 PID를 찾았을 때만 있다. `payload`는 원본 그대로 둔다. 앱은 실행 시 순서대로 흡수하고 파일을 비운다.

Claude Code PID 찾기(스크립트): 조상 프로세스를 4단계까지 올라가며(`ps -o ppid=,comm= -p`) 실행 파일 이름(`comm`의 마지막 경로 조각)이 `claude`인 첫 프로세스. 인자(`args`)로는 비교하지 않는다 — 이 스크립트 경로 `~/.claude/waypoint/…`가 셸 인자에 들어 있다. 2.1.283 실측에서는 스크립트 바로 위 부모가 `claude`라 `ps`를 한 번 부르고, 훅 한 번에 약 3 ms가 늘었다(중앙값 15.9 → 18.7 ms).

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

## 9. 사용량 게이지

Claude 사용량(5시간·7일 한도의 사용 비율)을 사이드바 아래와 메뉴 막대 메뉴에 보인다. 앱은 파일만 읽고 API를 호출하지 않는다.

- 출처: Claude Code가 상태줄 명령 stdin에 넘기는 JSON의 `rate_limits.five_hour` / `rate_limits.seven_day`(`used_percentage` 0–100, `resets_at` 유닉스 초). 사용자의 상태줄 명령 앞에 중계 스크립트 `integration/statusline/waypoint-statusline-tap.sh`를 끼운다. 스크립트는 입력에 `rate_limits` 객체가 있으면 저장 폴더에 `usage.json`을 원자적으로 쓰고(임시 파일 → `mv`, jq 필요), 같은 입력을 원래 명령에 넘겨 출력을 그대로 내보낸다. jq가 없거나 쓰기에 실패해도 상태줄 출력은 그대로 나온다. 추가 시간은 약 8 ms.
- 파일: `~/Library/Application Support/Waypoint/usage.json`(`WAYPOINT_SUPPORT_DIR`로 바꿀 수 있음), 한 줄 `{"capturedAt":<unix 초>,"rateLimits":<rate_limits 원본>}`.
- 설치: 스크립트를 `~/.claude/waypoint/`에 복사하고 `chmod +x`, `~/.claude/settings.json`의 `statusLine.command`를 `bash ~/.claude/waypoint/waypoint-statusline-tap.sh <원래 명령>`으로 바꾼다(예: `bash ~/.claude/waypoint/waypoint-statusline-tap.sh bash ~/.claude/awesome-statusline.sh`). 원래 명령은 인자 대신 환경 변수 `WAYPOINT_STATUSLINE_NEXT`(셸 명령 문자열)로 줘도 된다. 되돌리려면 `statusLine.command`를 원래 명령으로 돌린다.
- 앱(macOS): 30초마다 파일 수정 시각을 보고 바뀌었을 때만 다시 읽는다(`UsageMonitor`). 파서는 숫자·숫자 문자열, 초·밀리초·ISO 8601 시각, 한쪽 창만 있는 경우를 받는다. 초기화 시각이 지난 창은 0%로 보인다. 30분보다 오래된 기록은 흐리게, 파일이 없으면 게이지를 숨긴다. iOS에는 없다.

## 10. 화면

`docs/DESIGN.md` 참조. 대시보드 / 프로젝트 보드 / 카드 상세 / 지침 문서 / 프로젝트 init 시트 / iPhone 작업중.

## 11. 열린 질문 (구현 중 결정)

- 앱 샌드박스 여부 (로컬 서버·파일 감시 편의 vs 배포 방식). 개인용이면 비샌드박스 + 직접 서명도 가능.
- Swift MCP 서버 구현: 공식 Swift SDK 사용 가능 여부 확인, 안 되면 Streamable HTTP의 필요한 부분만 직접 구현.
- 서브에이전트의 `session_id`가 부모와 같은지 별도인지 — 실제 훅 입력을 로깅해서 확인 후 `Session` 매핑 확정.
