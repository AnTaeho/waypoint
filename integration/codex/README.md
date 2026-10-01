# Codex 연결

공식 근거(2026-09-30): [훅](https://learn.chatgpt.com/docs/hooks), [MCP](https://developers.openai.com/codex/mcp), [스킬](https://developers.openai.com/codex/skills).

## 설치

저장소 루트에서 `python3 scripts/install-codex.py`를 실행한다(Python 3.11+). 개발용은 `--dev`로 47822에 연결한다. 기존 훅은 함께 유지하고, MCP는 Waypoint가 관리하는 블록만 추가·갱신한다. 설정 백업은 `~/.codex/waypoint/backups/`에 남긴다. 개인 설정·신뢰를 우회하는 옵션은 쓰지 않는다.

Codex를 새로 시작해 `/hooks`에서 각 Waypoint 훅을 검토·신뢰한다. 플러그인/프로젝트 훅과 중복 설치하지 않는다. `/mcp`에서 waypoint가 연결돼 있는지 확인한다. `features.hooks=false`이면 설치기가 멈추므로 사용자가 해당 설정을 먼저 확인한다.

등록된 폴더에서 시작하면 시작 훅이 `Waypoint:` 블록과 접두사를 포함한 세션 ID를 준다. 새 폴더는 `$waypoint-tracker init`을 요청하고 앱에서 프로젝트를 등록한다. 그 뒤 첫 요청에서 컨텍스트를 한 번 늦게 전달한다. Claude Code로 등록한 폴더를 다시 등록할 필요는 없다.

시작 폴더가 부모 워크스페이스여도 작업 대상이 등록된 프로젝트라면 tracker가 `project_resolve(작업 대상 폴더)` 후 `session_bind`로 연결한다. 실제 ID는 훅 블록 또는 Codex 실행 환경의 CODEX_SESSION_ID/CODEX_THREAD_ID에서 읽는다. 한 대화에서 프로젝트를 전환해도 같은 절차를 쓰며 이전 카드 연결만 풀고 기록은 이동하지 않는다. 세션 ID를 얻을 수 없는 실행 환경에서는 실시간 추적을 지원한다고 표시하지 않는다.

파일 변경은 실제 파일 경로의 등록 프로젝트에 기록한다. 한 번의 도구 호출에서 여러 프로젝트를 바꾸면 각각에 기록하고, 다른 프로젝트의 작업중 카드에 섞지 않는다. Codex에서 셸로 직접 작성한 파일은 구조화된 변경 결과가 없으면 파일 로그를 추정하지 않는 기존 제한이 있다.

## 지원 범위

- 로컬 Codex CLI부터 지원한다. Codex CLI 0.159.2에서 설치 설정을 확인한다. 클라우드 오케스트레이션의 개인 로컬 훅은 지원 범위 밖이다.
- `/hooks/codex/<Event>`와 기존 `/hooks/<Event>`가 동일한 처리기로 이어진다. Codex ID는 `codex:`로 분리한다. 기존 Claude ID·데이터는 유지한다.
- SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, SubagentStart, SubagentStop, Stop, Interrupt, SessionEnd를 연결한다. 도구별 명령 입력과 문자열 응답을 정규화한다.
- 성공한 apply_patch만 파일 변경으로 기록한다. 파일 삭제에서 기존 전체 줄 수는 입력으로 알 수 없어 0으로 기록한다. Bash로 직접 수정한 파일은 구조화된 변경 정보가 없는 한 추정하지 않는다. 커밋은 git commit 명령과 성공 출력에서 읽는다.
- 하위 에이전트의 명시적 카드 연결은 Agent/spawn_agent message 첫 줄의 `[KEY-N]`와 agent_type으로 매칭한다. 같은 종류의 동시 생성은 기존 Claude 처리와 같이 FIFO로 매칭하므로 실제 동시 실행에서 추가 확인이 필요하다.
- HTTP는 1초 타임아웃, 실패 시 outbox, exit 0을 유지한다. 컨텍스트 stdout은 SessionStart와 늦은 UserPromptSubmit에만 나온다. Stop·Interrupt·세션 종료는 done으로 옮기지 않는다.
- Codex의 SessionEnd는 정상 닫기·보관/삭제·닫힌 대화의 장시간 유휴에서 발생한다. 대화를 다른 것으로 전환했다고 즉시 종료되지는 않는다. PID가 없어졌으면 앱이 다음 정리 주기에 닫는다.
- 앱은 LLM API를 추가로 호출하지 않는다. MCP 도구/스킬/주입 컨텍스트는 사용 중인 Codex의 컨텍스트와 도구 호출 사용량에 포함된다.

## 자동 검증

```sh
swift test
python3 integration/codex/test_codex_integration.py
bash integration/hooks/test-waypoint-hook.sh
```

doc-codex-* 픽스처는 문서 기반이다. 실제 입력을 채집하면 real-codex-*로 구분한다. 설치 테스트는 임시 홈과 임시 포트만 쓴다.

## 신뢰 후 확인

1. 등록된 폴더에서 Codex를 열어 Waypoint 블록·provider codex·sessionId codex:…가 전달되는지 확인한다.
2. 기존 카드 작업을 요청해 Codex 세션이 연결되는지, apply_patch 뒤 파일 기록이 남는지 확인한다.
3. 나중에 할 일을 말해 만든 곳이 Codex인 아이디어가 생기는지 확인한다.
4. 메모를 남기고 CLI를 정상 종료해 카드가 작업 전 상태로 돌아오는지 확인한다. Claude Code에서 같은 카드의 메모를 이어 받는지 확인한다.
5. 앱을 끈 동안의 기록이 다음 실행에서 흡수되는지 확인한다.
6. iPhone에 새 앱을 설치한 뒤 Codex 표시와 CloudKit으로 providerRaw/processPid가 전달되는지 확인한다. 기존 iPhone 앱은 새 도구 정보를 표시하지 못할 수 있다.

해제는 `python3 scripts/install-codex.py --remove`. 설정이 직접 수정된 스킬은 보존한다. 훅 명령이 바뀌면 Codex에서 다시 신뢰 검토가 필요하다.
