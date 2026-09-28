---
name: tracker
description: Waypoint 카드 보드에 작업을 기록한다. 세션 컨텍스트에 "Waypoint:"로 시작하는 블록(세션 시작 때, 또는 등록 전에 시작한 세션이면 대화 중 한 번)이 있는 폴더에서 작업을 시작·전환·마무리할 때, 사용자가 "나중에", "언젠가", "이것도 있으면 좋겠다"처럼 지금 하지 않을 일을 말할 때, 서브에이전트에 일을 맡길 때, 세션을 마칠 때 사용한다. 사용자가 /tracker init을 청할 때도.
---

# tracker

Waypoint는 사용자의 개인 프로젝트 보드다. 너는 카드를 최신 상태로 유지한다. 기록은 짧고 사실만. 기록했다는 알림은 한 줄 이하.

## 주입 블록

세션을 시작할 때 훅이 이런 블록을 넣는다.

```
Waypoint: PRB (waypoint-probe)
sessionId: 5e1f0c2a-…
다음 할 일:
- PRB-1 실측용 카드
다른 세션에서 작업중:
- PRB-4 파서 (sess·a1b2)
직전 세션 메모 (PRB-1 실측용 카드):
  파서까지 함. 남은 것: 테스트
작업을 시작·전환·마무리하거나 나중에 할 일을 들으면 tracker 스킬을 따른다.
```

- 프로젝트 키(`PRB`)는 도구의 `project`에, `sessionId`는 `card_start`·`card_create`의 `sessionId`에 그대로 넣는다.
- 블록이 없거나 `Waypoint: 이 폴더는 Waypoint에 없음`이면 등록되지 않은 폴더다. `/tracker init` 말고는 아무것도 기록하지 않는다.
- 직전 세션 메모가 있으면 그 카드부터 이어갈지 사용자 요청과 맞춰 본다.

## 도구

MCP 서버 `waypoint`. Claude Code에서의 이름은 `mcp__waypoint__<도구>`.

| 도구 | 쓰는 때 |
|---|---|
| `card_list(project, status?, query?)` | 요청에 맞는 카드 찾기. status를 안 주면 done·archived는 빠진다 |
| `card_get(id)` | 카드 본문·완료 조건·최근 기록 |
| `card_create(project, title, kind?, status?, body?, parentId?, criteria?, sessionId?)` | 새 카드. 기본 kind task, status next(kind idea면 idea) |
| `card_start(id, sessionId)` | 이 세션을 카드에 붙여 작업중으로 |
| `card_update(id, title?, body?, status?, criteria?)` | 수정. criteria는 전체를 새로 보낸다(`[{text, done}]`) |
| `card_note(id, text)` | 결정·막힌 점 한 줄 |
| `card_handoff(id, nextSessionNote)` | 다음 세션 메모 |
| `project_resolve(cwd)` | 폴더 → 프로젝트(주입 블록이 없을 때 확인용) |
| `project_init(cwd, name, key?, summary?, stack?, guideFiles?, seedCards?)` | `/tracker init`에서만. 앱에 등록 확인 창을 띄운다 |

카드 ID는 `PRB-1` 꼴이다.

## 작업을 시작할 때

1. 요청이 기존 카드에 해당하는지 본다. 주입 블록의 다음 할 일에 있으면 그 ID, 없으면 `card_list`(필요하면 `query`).
2. 맞는 카드가 있으면 `card_start(id, sessionId)`. 없고 몇 분 이상 걸릴 일이면 `card_create`(status next) 뒤 `card_start`.
3. `card_start` 결과의 `otherSessions`가 비어 있지 않으면 다른 세션이 같은 카드를 작업중이다. 시작 전에 사용자에게 한 줄로 알린다.
4. 한 줄로 알린다: `PRB-1 작업중으로 표시했어요.`

사소한 질문, 설명 요청, 한두 줄 수정에는 카드를 만들지 않는다.

## 작업 중에

- 주제가 바뀌면 새 카드로 `card_start`한다. 이 세션에 붙어 있던 이전 카드는 서버가 연결을 풀고 원래 상태(next·idea 등)로 돌린다. 이전 카드를 done으로 만들지 않는다.
- 사용자가 "나중에", "언젠가", "다음엔", "이것도 있으면 좋겠다"처럼 **지금 하지 않을 일**을 말하면 `card_create(kind: idea, status: idea, sessionId)`로 남기고 한 줄로 알린다: `PRB-5 아이디어로 남겼어요.` 지금 하던 작업은 계속한다. 당장 할 게 확실한 후속 작업은 `status: next`.
- 의미 있는 결정이나 막힌 점은 `card_note`로 짧게.
- 완료 조건을 달성하면 `card_update`로 criteria 전체를 체크 상태로 다시 보낸다.
- `status: active`는 `card_update`로 줄 수 없다. 작업중은 `card_start`로만.

## 서브에이전트를 쓸 때

1. 맡길 일을 하위 카드로 만든다: `card_create(project, title, parentId: 지금 카드, sessionId)`.
2. 서브에이전트 프롬프트 **첫 줄**을 대괄호 카드 ID로 시작한다: `[PRB-6] 파서 단위 테스트 작성`. 훅이 이 줄을 보고 서브에이전트를 그 카드에 붙여 작업중으로 표시한다. 서브에이전트에게 `card_start`를 시키지 않는다.

## 마무리할 때

- 작업이 끝났다고 판단되면 사용자에게 완료 처리할지 묻고, 동의하면 `card_update(status: done)`. 묻지 않고 done으로 만들지 않는다.
- 세션을 끝내거나 사용자가 자리를 뜨는 흐름이면(또는 사용자가 마무리하자고 하면) 작업한 카드마다 `card_handoff`로 다음 세션 메모를 남긴다: 어디까지 했는지, 남은 것, 다음에 먼저 볼 파일. 3줄 이내.
- 세션이 끝나면 카드 연결은 서버가 푼다. 따로 할 일은 없다.

## /tracker init

사용자가 `/tracker init`을 청하면 지금 폴더를 Waypoint 프로젝트로 등록하는 초안을 앱에 띄운다. 등록은 사용자가 앱에서 확인하고 한다.

1. 이미 등록된 폴더인지 본다. 주입 블록이 `Waypoint: <키> (…)`로 시작하면 이미 등록된 폴더다. 블록이 없으면 `project_resolve(cwd)`. 등록되어 있으면 `이 폴더는 이미 Waypoint에 <키>로 등록되어 있어요.` 한 줄로 알리고 끝낸다.
2. 저장소를 훑는다. 읽기만 하고 아무것도 고치지 않는다.
   - `README*`, `CLAUDE.md`, `.claude/CLAUDE.md`, `docs/` 아래 문서(많으면 이름과 첫 부분만)
   - `git log --oneline -20`
   - `TODO`·`FIXME` 검색(개수와 대표 몇 줄)
3. `project_init`을 한 번 부른다.
   - `cwd`: 지금 폴더 절대 경로
   - `name`: 사람이 부르는 짧은 이름(README 제목 등)
   - `key`: 영문 대문자 2–5자, 이름에서 딴 것(예: `ledger` → `LDG`). 다른 프로젝트와 겹치면 결과의 `warnings`에 나오고, 사용자가 앱에서 고친다.
   - `summary`: 무엇을 하는 프로젝트인지 한두 문장
   - `stack`: 주요 언어·프레임워크 몇 개
   - `guideFiles`: 지침 문서 후보(cwd 기준 상대 경로). `CLAUDE.md`, `.claude/CLAUDE.md`, `docs/`의 설계·규칙 문서처럼 작업 지침이 되는 `.md`. README는 지침이 담겨 있을 때만.
   - `seedCards`: 초기 카드 후보 최대 8개. 할 일이 분명한 것(최근 커밋에서 이어지는 일, 문서의 남은 일)은 `status: next`, TODO·FIXME나 막연한 것은 `status: idea`(버그면 `kind: bug`). 제목은 짧게, 근거는 `body` 한 줄.
4. 결과가 `status: pending`이면 `Waypoint 앱에서 확인하고 등록해 주세요.` 한 줄만 말하고 멈춘다. 사용자의 등록을 기다리거나 다시 확인하지 않는다. `missingGuideFiles`가 있으면 그 줄 뒤에 없는 파일 이름을 한 줄 덧붙인다.
5. 오류(`isError`)면 이유를 한 줄로 전한다. 「이미 등록된 폴더」·「보관된 프로젝트」면 그대로 알리고 끝낸다.

init에서는 카드를 `card_create`로 만들지 않는다. 초기 카드는 `seedCards`로만 넘긴다.

## 하지 말 것

- 사용자가 요청하지 않은 지침 문서(CLAUDE.md 등) 수정.
- 카드 본문에 코드나 긴 로그 붙이기.
- 기록 때문에 사용자 작업 흐름을 끊는 질문(완료 확인과 카드 충돌 알림만 예외).
