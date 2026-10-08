---
name: tracker
description: Waypoint 카드 보드에 프로젝트 작업을 기록한다. 코드 작업을 시작·전환할 때, 의미 있는 단위가 끝날 때마다 사용한다. 시작 폴더가 작업 대상 프로젝트와 다르거나 Waypoint 주입 블록이 없어도 실제 대상 폴더를 확인해 연결한다. 나중에 할 일 기록, 서브에이전트 위임, 세션 메모·프로젝트 상황, 정리 안 된 작업과 /tracker init에도 사용한다. MCP가 없으면 기록하지 않는다.
---

# tracker

Waypoint는 사용자의 개인 프로젝트 보드다. 너는 카드를 최신 상태로 유지한다. 기록은 짧고 사실만. 기록했다는 알림은 한 줄 이하.

## 주입 블록

세션을 시작할 때 훅이 이런 블록을 넣는다.

```
Waypoint: PRB (waypoint-probe)
sessionId: 5e1f0c2a-…
지금 상황 (3시간 전, Claude Code):
  파서 리팩터 진행 중. 다음: 오류 메시지 정리
다음 할 일:
- PRB-1 실측용 카드
다른 세션에서 작업중:
- PRB-4 파서 (sess·a1b2, 도구 작업 중) · 최근 파일: Parser.swift, Lexer.swift
직전 세션 메모 (PRB-1 실측용 카드):
  파서까지 함. 남은 것: 테스트
정리 안 된 작업:
- 어제 14:32 · Claude Code · 파일 2개: Parser.swift, note.txt · 9c3e71d2
작업을 시작·전환하거나 한 단위를 끝낼 때마다, 나중에 할 일을 들으면 tracker 스킬을 따른다.
```

- 프로젝트 키(`PRB`)는 도구의 `project`에, `sessionId`는 `card_start`·`card_create`의 `sessionId`에 그대로 넣는다.
- 시작 폴더와 실제 작업 대상 폴더를 구분한다. `Waypoint: 이 폴더는 Waypoint에 없음`이어도 작업 대상 프로젝트가 등록되어 있으면 연결하고 기록한다. 시작 폴더를 대신 등록하거나 프로젝트 이름만 보고 폴더를 추측하지 않는다.
- 다른 세션에서 작업중 줄의 최근 파일은 그 세션이 지난 1시간 안에 바꾼 파일이다. 같은 파일을 고쳐야 하면 먼저 사용자에게 한 줄로 알린다.
- 직전 세션 메모가 있으면 그 카드부터 이어갈지 사용자 요청과 맞춰 본다.
- 지금 상황은 프로젝트 전체의 흐름이다. 요청을 이해하는 데 쓰고, `오래됨`이면 이번 작업 뒤 새로 쓴다.
- 정리 안 된 작업은 카드 없이 파일을 바꾸고 끝난 지난 세션이다. 사용자 요청을 먼저 하고, 짧게 정리한다: 바뀐 파일로 맞는 카드를 알 수 있으면 `work_file(sessionId, cardId)`, 기록할 것 없는 작업이면 `cardId` 없이 넘긴다. 맞는 카드를 모르면 사용자에게 묻지 말고 넘기거나 그대로 둔다. 정리했다는 알림은 한 줄.

## 도구

MCP 서버 `waypoint`. Claude Code·Codex에서 제공된 Waypoint 도구를 쓴다(보통 `mcp__waypoint__<도구>`). Codex에서는 이 스킬을 `waypoint-tracker` 이름으로 설치한다.

- Codex 주입 블록에는 `provider: codex`가 있다. `sessionId`의 `codex:` 접두사를 포함해 그대로 전달한다. 원본 Codex ID를 추측하거나 접두사를 빼지 않는다.
- Codex의 `project_init`과 `card_create`에는 `provider: codex`도 전달한다. 연결 세션이 있으면 서버가 그 세션의 도구를 만든 곳으로 기록한다.
- 실제 세션 ID만 사용한다. 훅 블록에 없으면 Codex 실행 환경의 `CODEX_SESSION_ID` 또는 `CODEX_THREAD_ID`를 읽어 사용할 수 있다(둘 다 있으면 같은 값인지 확인). Codex 원본 ID에 `codex:`가 없으면 한 번만 붙인다. 둘 다 없으면 추측하거나 다른 세션의 ID를 찾지 않고 추적할 수 없음을 짧게 알린다.
- 블록이 없거나 프로젝트가 다를 때도 요청과 실제 수정 폴더로 작업 대상이 분명하면 `project_resolve(작업 대상 절대 경로)`를 쓴다. 등록된 프로젝트면 `session_bind(project, sessionId, provider, cwd: 세션 시작 폴더)`로 연결한다. 결과의 context와 sessionId를 이후 기록에 사용한다. 프로젝트 전환 때도 같은 절차를 따른다. `project_init`은 등록을 요청받았을 때만 쓴다.
- SSH 원격·개발 컨테이너처럼 Mac에 없는 폴더에서는 주입 블록의 `remote:` 값(없으면 `git config --get remote.origin.url`)을 `project_resolve(cwd, remote)`에 함께 보낸다.

| 도구 | 쓰는 때 |
|---|---|
| `session_bind(project, sessionId, provider, cwd)` | 시작 폴더와 무관하게 실제 작업 대상 프로젝트에 세션 연결·전환. 이전 카드 연결만 풀고 과거 기록은 유지 |
| `card_list(project, status?, query?)` | 요청에 맞는 카드 찾기. status를 안 주면 done·archived는 빠진다 |
| `card_get(id)` | 카드 본문·완료 조건·최근 기록 |
| `card_create(project, title, kind?, status?, body?, parentId?, criteria?, sessionId?)` | 새 카드. 기본 kind task, status next(kind idea면 idea) |
| `card_start(id, sessionId)` | 이 세션을 카드에 붙여 작업중으로 |
| `card_update(id, title?, body?, status?, criteria?)` | 수정. criteria는 전체를 새로 보낸다(`[{text, done}]`) |
| `card_note(id, text)` | 결정·막힌 점 한 줄 |
| `card_handoff(id, nextSessionNote)` | 다음 세션 메모 |
| `card_evidence(id, criterion?, command, outcome, detail?, sessionId?)` | 완료 조건을 확인하려고 실행한 명령과 결과. criterion은 1부터, outcome은 pass·fail·skipped |
| `project_status(project, text?, sessionId?)` | 프로젝트 지금 상황 갱신(600자·8줄 이내, 전체를 새로 쓴다). text를 빼면 읽기 |
| `work_file(sessionId, cardId?)` | 정리 안 된 작업 정리. 블록의 짧은 ID 그대로. cardId를 빼면 넘김 |
| `github_issue_create(project, title, body?, labels?, cardId?, sessionId?)` | 사용자가 GitHub 이슈를 열어 달라고 할 때. 작업 카드가 있으면 `cardId`로 잇는다 |
| `github_pr_create(project, title, body?, base?, head?, draft?, cwd?, cardId?, sessionId?)` | 사용자가 PR을 열어 달라고 할 때. push하지 않으므로 브랜치를 먼저 push한 뒤 부른다. `cardId`로 잇는다 |
| `project_resolve(cwd, remote?)` | 폴더 → 프로젝트(주입 블록이 없을 때 확인용). 원격·컨테이너 폴더는 git origin 주소를 `remote`로 |
| `project_init(cwd, name, key?, summary?, stack?, guideFiles?, seedCards?)` | `/tracker init`에서만. 앱에 등록 확인 창을 띄운다 |

카드 ID는 `PRB-1` 꼴이다.

## 작업을 시작할 때

1. 실제 작업 대상 프로젝트를 확인한다. 주입 블록의 프로젝트와 다르거나 블록이 없으면 위의 project_resolve·session_bind 절차로 연결한다. 그 뒤 요청이 기존 카드에 해당하는지 본다. 주입 블록의 다음 할 일에 있으면 그 ID, 없으면 `card_list`(필요하면 `query`).
2. 맞는 카드가 있으면 `card_start(id, sessionId)`. 없고 몇 분 이상 걸릴 일이면 `card_create`(status next) 뒤 `card_start`.
3. `card_start` 결과의 `otherSessions`가 비어 있지 않으면 다른 세션이 같은 카드를 작업중이다. 시작 전에 사용자에게 한 줄로 알린다.
4. 한 줄로 알린다: `PRB-1 작업중으로 표시했어요.`

사소한 질문, 설명 요청, 한두 줄 수정에는 카드를 만들지 않는다.

## 작업 중에

- 주제가 바뀌면 새 카드로 `card_start`한다. 이 세션에 붙어 있던 이전 카드는 서버가 연결을 풀고 원래 상태(next·idea 등)로 돌린다. 이전 카드를 done으로 만들지 않는다.
- 사용자가 "나중에", "언젠가", "다음엔", "이것도 있으면 좋겠다"처럼 **지금 하지 않을 일**을 말하면 `card_create(kind: idea, status: idea, sessionId)`로 남기고 한 줄로 알린다: `PRB-5 아이디어로 남겼어요.` 지금 하던 작업은 계속한다. 당장 할 게 확실한 후속 작업은 `status: next`.
- 완료 조건을 확인하려고 명령(테스트·빌드 등)을 실행했으면 `card_evidence(id, criterion, command, outcome, sessionId)`로 조건 번호(1부터, `card_get`의 criteria 순서)와 결과를 남긴다. `command`는 실행한 명령 그대로, 실패면 `fail`. 실행하지 않은 조건은 남기지 않는다. `skipped`는 일부러 건너뛴 조건에만 쓴다. 특정 조건이 아닌 검증은 `criterion`을 뺀다. 앱은 실행을 직접 본 기록과 맞춰 보고, 근거 뒤에 파일이 바뀌면 다시 미검증으로 보인다.
- 사용자가 이슈·PR을 열어 달라고 하면 `github_issue_create`·`github_pr_create`를 쓰고 작업 카드에 잇는다(`cardId`). PR은 브랜치를 push한 뒤에 연다. 결과의 `url`을 한 줄로 알린다.
- `status: active`는 `card_update`로 줄 수 없다. 작업중은 `card_start`로만.
- 도구 응답에 `overlaps`가 있으면 다른 세션(`sessionId`·`cards`·`provider`)이 같은 작업 트리의 그 `files`를 최근 1시간 안에 바꿨다. 그 파일을 고치기 전에 사용자에게 한 줄로 알리고(`note.txt를 PRB-3 세션도 고치고 있어요.`), 같은 파일을 계속 만질지 확인한다. 같은 겹침은 한 번만 온다.

## 서브에이전트를 쓸 때

1. 맡길 일을 하위 카드로 만든다: `card_create(project, title, parentId: 지금 카드, sessionId)`.
2. 서브에이전트 프롬프트 **첫 줄**을 대괄호 카드 ID로 시작한다: `[PRB-6] 파서 단위 테스트 작성`. 훅이 이 줄을 보고 서브에이전트를 그 카드에 붙여 작업중으로 표시한다. 서브에이전트에게 `card_start`를 시키지 않는다.

## 단위가 끝날 때마다

세션은 예고 없이 끝난다. 세션 끝까지 미루지 말고, 의미 있는 단위(기능 하나, 버그 하나, 검증 한 번)가 끝나 응답을 마치기 전에 갱신한다.

- 달성한 완료 조건은 `card_update`로 criteria 전체를 체크 상태로 다시 보낸다. 결정·막힌 점이 있었으면 `card_note`로 짧게.
- 남은 일이 있으면 `card_handoff`로 다음 세션 메모를 새로 쓴다: 어디까지 했는지, 남은 것, 다음에 먼저 볼 파일. 3줄 이내.
- 프로젝트 흐름이 바뀌었으면(큰 작업이 끝남, 다음 우선순위가 바뀜, 막힘) `project_status`로 지금 상황을 새로 쓴다: 진행 중인 것, 다음 할 것, 막힌 것. 카드 하나의 세부는 넣지 않는다.
- 작업이 끝났다고 판단되면 사용자에게 완료 처리할지 묻고, 동의하면 `card_update(status: done)`. 묻지 않고 done으로 만들지 않는다. 카드 연결은 세션이 끝나면 서버가 푼다.

## /tracker init

Codex에서는 `$waypoint-tracker init`도 같은 프로젝트 등록 요청으로 처리한다.

사용자가 `/tracker init`을 청하면 지금 폴더를 Waypoint 프로젝트로 등록하는 초안을 앱에 띄운다. 등록은 사용자가 앱에서 확인하고 한다.

1. 이미 등록된 폴더인지 본다. 주입 블록이 `Waypoint: <키> (…)`로 시작하면 이미 등록된 폴더다. 블록이 없으면 `project_resolve(cwd)`. 등록되어 있으면 `이 폴더는 이미 Waypoint에 <키>로 등록되어 있어요.` 한 줄로 알리고 끝낸다.
2. 저장소를 훑는다. 읽기만 하고 아무것도 고치지 않는다.
   - `README*`, `AGENTS.md`, `CLAUDE.md`, `.claude/CLAUDE.md`, `docs/` 아래 문서(많으면 이름과 첫 부분만)
   - `git log --oneline -20`
   - `TODO`·`FIXME` 검색(개수와 대표 몇 줄)
3. `project_init`을 한 번 부른다.
   - `cwd`: 지금 폴더 절대 경로
   - `name`: 사람이 부르는 짧은 이름(README 제목 등)
   - `key`: 영문 대문자 2–5자, 이름에서 딴 것(예: `ledger` → `LDG`). 다른 프로젝트와 겹치면 결과의 `warnings`에 나오고, 사용자가 앱에서 고친다.
   - `summary`: 무엇을 하는 프로젝트인지 한두 문장
   - `stack`: 주요 언어·프레임워크 몇 개
   - `guideFiles`: 지침 문서 후보(cwd 기준 상대 경로). `AGENTS.md`, `CLAUDE.md`, `.claude/CLAUDE.md`, `docs/`의 설계·규칙 문서처럼 작업 지침이 되는 `.md`. README는 지침이 담겨 있을 때만.
   - `seedCards`: 초기 카드 후보 최대 8개. 할 일이 분명한 것(최근 커밋에서 이어지는 일, 문서의 남은 일)은 `status: next`, TODO·FIXME나 막연한 것은 `status: idea`(버그면 `kind: bug`). 제목은 짧게, 근거는 `body` 한 줄.
4. 결과가 `status: pending`이면 `Waypoint 앱에서 확인하고 등록해 주세요.` 한 줄을 말한다. 사용자의 등록을 기다리거나 다시 확인하지 않는다. `missingGuideFiles`가 있으면 그 줄 뒤에 없는 파일 이름을 한 줄 덧붙인다.
5. 지침 파일(`guideFiles` 중 이 저장소 안에 있는 것) 가운데 아래 「지침 꼴」이 아닌 것이 있으면 **한 번만** 묻고 멈춘다. 모두 그 꼴이면 묻지 않는다. 물을 때 보여 줄 것:
   - 대상 파일과 줄 수(예: `CLAUDE.md 240줄, AGENTS.md 30줄`)
   - 그 파일에서 실제로 바뀔 대표 부분 하나의 전/후(각 5줄 이내)
   - 질문 한 줄: `지침 파일을 한 줄에 지침 하나 꼴로 다듬을까요? 뜻은 바꾸지 않고, 바뀐 내용을 보여 드린 뒤 커밋해요.`
6. 거절하거나 답이 없으면 아무것도 바꾸지 않는다. 동의하면 지침 꼴로 다듬고 diff를 보여 확인받은 뒤에만 그 저장소의 커밋 규칙대로 커밋한다. 다른 세션이 같은 파일을 고치고 있으면(작업 트리에 그 파일 변경이 있으면) 건드리지 않고 알린다.

지침 꼴(Waypoint가 항목 단위로 고치고 지울 수 있는 꼴):
- 주제마다 절 머리(`##`·`###`), 그 아래 `- ` 한 줄에 지침 하나. 굵은 글씨 제목 문단은 절 머리로 바꾼다.
- 긴 문단은 지침 단위로 나눈다. 뜻·조건·예외·숫자는 그대로 두고 말을 보태지 않는다.
- 중복 줄은 하나만 남기고, 서로 어긋나는 줄은 고치지 말고 사용자에게 알린다. 빈 절은 지운다.
- 표·코드 블록·명세 문서(설계·규칙 설명)는 그대로 둔다. 다듬는 대상은 작업 지침 줄이다.
7. 오류(`isError`)면 이유를 한 줄로 전한다. 「이미 등록된 폴더」·「보관된 프로젝트」면 그대로 알리고 끝낸다.

init에서는 카드를 `card_create`로 만들지 않는다. 초기 카드는 `seedCards`로만 넘긴다.

## 하지 말 것

- 사용자가 요청하지 않은 지침 문서(CLAUDE.md 등) 수정.
- 카드 본문에 코드나 긴 로그 붙이기.
- 기록 때문에 사용자 작업 흐름을 끊는 질문(완료 확인과 카드 충돌 알림만 예외).
