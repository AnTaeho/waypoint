# 기록 신뢰성 기준 (TRK-11)

작성: 2026-10-01. 로드맵 02 「기록 신뢰성 기준과 사용 효과 측정」의 기준·측정 방법·관측값을 한곳에 둔다.

## 지원 범위

| 항목 | 지원 | 지원하지 않음 |
|---|---|---|
| 기기 | macOS 14+ Mac 한 대의 로컬 앱(평소용 47821, 개발용 47822) | 여러 Mac이 같은 세션을 동시에 받기 |
| 도구 | Claude Code 로컬 CLI 훅(2.1.283 실측), Codex CLI 로컬 훅(공식 문서 기준 `doc-codex-*`) | 클라우드 실행 Codex, 전사 파일 감시 |
| 폴더 | 등록한 프로젝트 폴더와 그 하위 폴더(가장 가까운 등록 폴더) | 등록 전·미등록 폴더의 훅(기록하지 않는다), 보관한 프로젝트 |
| 전달 | 실시간 POST, 앱이 꺼졌거나 1초 안에 답하지 못한 훅의 outbox 재수신 | CloudKit 전달 시간(이 기준에 넣지 않는다) |
| 원격(TRK-53) | SSH 원격(원격 포트 포워딩)·Docker Desktop 개발 컨테이너(`host.docker.internal`)의 훅, 같은 git origin의 등록 프로젝트에 잇기, 원격 outbox replay | 웹·클라우드 세션, Docker Desktop 밖 컨테이너 런타임(확인 안 함) |

## 실패할 때의 동작

| 상황 | 동작 |
|---|---|
| 앱이 꺼짐·응답 1초 초과 | 훅 스크립트가 줄인 본문을 `outbox.jsonl`에 쓰고 exit 0. 앱이 켜질 때·10초 점검·잠자기 복귀 때 순서대로 흡수 |
| 실시간 처리가 늦어 같은 훅이 outbox에도 들어감 | 같은 세션의 같은 `tool_use_id`(파일·커밋·검증 근거), 같은 `prompt_id`/`turn_id`(요청), 같은 부모·`tool_use_id`(서브에이전트 대기)는 한 번만 남긴다. ID 없는 옛 줄의 요청은 같은 문장 10초 안이면 같은 것으로 본다 |
| 저장 실패 | 실시간: rollback 뒤 저장소 값으로 다시 읽고 연동 상태에 알림. outbox: 그 줄부터 남기고 다음 점검에서 다시 흡수(횟수 제한 없음) |
| 읽을 수 없는 outbox 줄 | 원문 그대로 `outbox.quarantine.jsonl`(0600)에 격리 |
| `SessionEnd`가 오지 않음 | PID가 있으면 프로세스가 없어질 때, 없으면 30분 무활동 뒤 추적 만료. 카드는 작업 전 상태로(완료 아님) |
| 세션이 끝난 뒤 그 이전 시각의 기록이 늦게 옴 | 무시한다(같은 기록을 이미 실시간으로 받았다). 아래 「알려진 한계」 |

## 회귀 시나리오

`Tests/WaypointKitTests/ReliabilityScenarioTests.swift`(12개). 실측 픽스처의 세션·폴더·파일만 바꿔 재생하고 outbox 줄은 실제 훅 스크립트 필터로 줄인다. 끝마다 `Reliability.verify`가 확인한다.

- 손실 0: 기대한 사실 기록(파일 변경·커밋·검증 근거·요청)이 모두 있다
- 중복 0: 각 기대 기록이 정확히 한 건, `session.start`는 세션마다 기대 수만큼, 같은 ID의 세션이 둘 없다
- 오귀속 0: 기록의 프로젝트·카드가 폴더(cwd·파일 경로) 기준 기대값과 같고, 기대 밖 기록이 없다. 세션 프로젝트가 기대값과 같다. 열린 카드 연결은 같은 프로젝트끼리만, 주인 없는 연결이 없다

| 시나리오 | 테스트 | 처음 돌렸을 때(수정 전) |
|---|---|---|
| (a) 같은 훅 실시간 두 번·실시간+outbox | `sameHookRedeliveredLiveAndThroughOutbox` | 요청 3건·파일 3건·커밋 2건으로 중복 |
| (a) ID 없는 요청 재수신 | `promptWithoutIDFallsBackToTextAndShortWindow` | — (수정과 함께 추가) |
| (a) `PreToolUse(Agent)` 재수신 | `replayedSpawnDoesNotPairNextSubagentWithOldCard` | 다음 서브에이전트가 앞 카드(PRB-1)에 붙음 — 오귀속 |
| (a) 세션 종료 뒤 outbox 재수신 | `outboxCopyAfterSessionEndIsNeitherDuplicatedNorLost` | 같은 ID의 세션이 하나 더 생기고 파일 기록 중복 |
| (b) 하위 폴더·따로 등록한 하위 프로젝트·이름 비슷한 옆 폴더·등록 전후 | `subfolderNestedSiblingAndRegistrationOrder` | 통과 |
| (c) 세션 중 `cd`로 다른 등록 프로젝트, `session_bind` 전환 | `cwdMovingIntoAnotherProjectKeepsCommitsAndChecksThere` | 다른 프로젝트에서 한 커밋·검증이 시작 프로젝트 카드에 붙음 — 오귀속 |
| (d) Claude·Codex 같은 원본 ID로 동시·교대 | `claudeAndCodexShareProjectConcurrentlyAndInTurn` | Codex 파일 기록 3중복 |
| (e) 같은 프로젝트 세션 3개 + 서브에이전트 2개 | `threeSessionsAndSubagentsInterleaved` | 통과 |
| (f) 잠자기: PID 있음(5시간 공백) | `sleepWithKnownProcessKeepsSessionAndCard` | 통과 |
| (f) 잠자기: PID 없음 | `sleepWithoutProcessExpiresThenRevivesWithoutCard` | 통과(30분 만료·카드 복귀는 설계대로) |
| (f) 깨어날 때 outbox 먼저 흡수 | `wakeAbsorbsQueuedActivityBeforeSweep` | 통과 |
| (g) 재시작: 꺼진 동안 outbox → 새 실행 흡수 → 실시간 | `restartAbsorbsOutboxThenContinuesLive` | 끄기 직전 실시간+outbox로 겹친 파일 기록 중복 |

수정 뒤 12개 모두 오귀속·중복·손실 0건이다. 커밋 `b741cb3`이 고쳤다.

## 수신 → 저장/표시 지연

### 측정 방법

- 앱 안(`ReliabilityMonitor`): 훅 요청마다 **수신**(로컬 서버가 연결을 받은 시각) → **저장**(처리기 저장 끝) → **화면**(데이터 변경 알림을 낸 뒤 메인 큐가 한 번 돈 시각. 화면 갱신이 같은 메인 큐에서 일어난다). 최근 1000건을 밀리초로 보관한다. outbox 흡수는 일부러 늦게 받은 것이라 넣지 않는다. CloudKit 전달 시간은 넣지 않는다.
- 스크립트 쪽: 요청마다 보내고 응답을 받을 때까지(연결 대기 포함). 앱의 수신 시각은 메인 큐가 연결을 받을 때라 그 전의 대기를 놓칠 수 있어 함께 본다.
- 판정: 앱 수신→화면 p95와 스크립트 왕복 p95가 모두 2초 미만이면 통과. 백분위는 nearest-rank.
- 실행: `scripts/measure-latency.py`. Dev(Debug, 47822)를 `open -g -j <Debug 앱 경로>`로 띄우고, Dev에 등록된 PRB(`~/workspace/waypoint-probe`)에 실측 픽스처 형식 훅 500건을 보낸다. 세션 6개(Claude 4, Codex 2)가 동시에, 턴마다 요청 → 도구 1~5번(Pre/Post 3~60 ms 간격, 30%는 쉬지 않음) → Stop(턴 사이 0.2~0.8초). 세션 ID·`tool_use_id`·요청 ID는 매번 새로 만들고 PID 머리는 보내지 않는다. 모든 세션은 `SessionEnd`로 닫는다. 끝나면 `/integration/status`의 `metrics`에서 이번 표본을 읽는다. Dev는 번들 ID로 끈다.

### 관측값 (2026-10-01)

환경: MacBook(Apple M4, 16 GB), macOS 26.6.2, Xcode 27.0, Waypoint Dev Debug 빌드(`trk-11-reliability`), Dev 저장소 이벤트는 첫 실행 전 54건, 넷째 실행 전 1,072건, 끝난 뒤 1,635건(세션 51개, 모두 닫힘). 평소용 앱은 47821에서 그대로 돌고 있었다.

| 실행 | 앱 수신→저장 p50 / p95 / 최대 | 앱 수신→화면 p50 / p95 / 최대 | 스크립트 왕복 p50 / p95 / 최대 |
|---|---|---|---|
| 기본(세션 6, 500건, 32초, CloudKit 켬) — **기록값** | 151 / 228 / 278 ms | 319 / 442 / 484 ms | 302 / 417 / 494 ms |
| 같은 조건 다시(저장소가 커진 뒤, CloudKit 켬) | 180 / 254 / 306 ms | 377 / 479 / 550 ms | 358 / 446 / 533 ms |
| CloudKit 끔(`--env WAYPOINT_CLOUDKIT=0`) | 203 / 322 / 493 ms | 410 / 622 / 812 ms | 388 / 611 / 811 ms |
| 세션 1개, 100건 | 67 / 88 / 92 ms | 183 / 221 / 279 ms | 163 / 221 / 259 ms |
| 부하(세션 12, 간격 0.3배, 500건, 24초) | 266 / 376 / 488 ms | 554 / 729 / 758 ms | 545 / 691 / 798 ms |

판정: 모든 실행에서 p95 2초 목표 **통과**. 실패(형식·저장·서버) 0건.

읽을 것:
- 지연의 대부분은 훅 한 건의 메인 액터 처리(Debug 빌드에서 수십 ms)와 그 뒤 화면 갱신이고, 동시 세션이 많으면 메인 큐에서 줄을 선다. CloudKit을 끈 실행이 더 느린 것은 저장소가 실행마다 커진 탓으로 보이며 CloudKit이 원인이라는 근거는 없다.
- 같은 스크립트로 변경 전 main(`8ae517f`) Dev를 재면 스크립트 왕복이 세션 1개 147 / 205 ms(p50 / p95), 기본 조건 381 / 487 ms였다. 이번 중복 판정이 지연을 늘리지 않았다.
- 훅 스크립트의 응답 기한은 1초다. 부하 실행의 최대 왕복이 0.8초까지 올랐다. 1초를 넘으면 같은 훅이 outbox에도 쓰이는데, 이제 한 번만 남는다. `SessionStart` 응답이 1초를 넘으면 그 세션은 처음 블록을 받지 못하고, 스크립트가 출력 뒤 보내는 확인이 없으므로 다음 프롬프트에 블록을 다시 받는다(TRK-35, SPEC 5장 「수신 확인」).

## 로컬 지표와 진단 내보내기

`ReliabilityMetrics`(숫자와 시각만, 문자열 필드 없음). 저장 폴더 `metrics.json`(0600)에 10초 점검 때 쓰고 CloudKit에 올리지 않는다.

| 지표 | 정의 |
|---|---|
| 수신→저장, 수신→화면 | 위 측정 방법. 최근 1000건(ms) |
| 재개 시간 | 카드의 재개 문맥을 처음 복사한 시각 → 그 카드에 같은 도구의 새 메인 세션이 연결된 시각(`CardResumeAttempt` 판정, 연결이 붙은 시각. 10초 점검이 알아챈 시각은 쓰지 않는다). 최근 100건(초). 24시간 안에 연결되지 않거나 카드가 완료·보관되면 버린다. 대기 목록은 메모리에만 있어 앱을 끄면 사라진다 |
| 연동 실패 | 로컬 서버 시작 실패, 훅 형식 오류, 실시간 저장 실패 횟수 |
| 복구 | outbox 흡수 줄, 저장 실패로 남긴 횟수, 격리한 줄, `SessionEnd` 없이 정리한 세션 |

- 연동 상태 패널: 「수신 → 화면 · p95 0.44초 · 최근 500건」, 「재개 · 중앙값 45초 · 3회」, 실패·복구 횟수(값이 있을 때만).
- 진단 정보 복사(사용자가 누를 때만): 위 숫자를 더한다. 프로젝트명·경로·세션 ID·대화·오류 원문은 넣지 않는다(`IntegrationDiagnosticTests`, `ReliabilityMetricsTests`가 고정).
- `/integration/status`(루프백 전용)가 같은 숫자를 `metrics`로 돌려준다. 측정 스크립트가 쓴다.

### 첫 연결 지표 (TRK-45)

`ReliabilityMetrics.onboarding`(`OnboardingMetrics`, `Shared/Onboarding/OnboardingMetrics.swift`). 온보딩을 한 번 연 것(열기 → 「끝」 또는 닫기)이 한 시도다. 최근 20회만 남긴다. 같은 `metrics.json`에 들어가므로 숫자·시각·정수 값만 있다(`OnboardingMetricsTests`가 문자열 값이 없음과 키 이름을 고정한다). 시각은 Foundation 기본 인코딩(2001-01-01부터 초).

| 필드 | 뜻 |
|---|---|
| `attempts[].startedAt` | 온보딩을 연 시각. 시도를 가리는 키 |
| `lastStage` / `furthestStage` | 마지막으로 보인 단계 / 가장 멀리 간 단계. 0 도구 · 1 연결 · 2 프로젝트 · 3 첫 기록 · 4 끝 |
| `installed.claude` / `installed.codex` | 연결 적용 성공 시각(이미 연결돼 있던 것을 화면이 확인한 시각 포함). 처음 한 번 |
| `projectAt` | 프로젝트를 고르고 등록까지 된 시각(이미 등록된 프로젝트로 넘어간 시각 포함) |
| `firstRecord.claude` / `firstRecord.codex` | 시작 이후 활동이고 프로젝트에 연결된 첫 기록을 받은 시각(`receivedAt`) |
| `finishedAt` / `closedAt` | 「끝」 / 닫기(Esc·창 닫힘 포함). 둘 다 없으면 앱이 꺼진 것 |
| `retries` | 연결 「다시 시도」와 첫 기록 단계의 서버 「다시 시도」 횟수 |
| `failures[]` | `{stage, reason, tool?, at, count}`. 같은 (단계, 까닭, 도구)는 한 줄에 횟수로 모은다. 화면 막힘은 바로 앞 판정과 다를 때만 센다. 계획 단계 오류(설정 겹침 등)는 연결 단계에 들어올 때마다 다시 센다 |

`reason` 값: 0 기타 · 1 설정 읽기 실패 · 2 설정 겹침 · 3 앱 연결 파일 없음 · 4 확인 중 파일 바뀜 · 5 백업 실패 · 6 쓰기 실패 · 7 등록 명령 실패(부분 실패) · 8 claude 실행 파일 없음(부분 실패) · 9 설치 준비 실패 · 10 Dev 차단 · 11 확인 필요(다른 포트·꺼짐) · 12 보관된 프로젝트 · 13 서버 안 뜸 · 14 등록 밖 폴더. `tool`: 0 Claude · 1 Codex. 모르는 값은 0(기타)·0(도구 단계)으로 읽고, `onboarding`을 못 읽으면 그것만 버리고 나머지 지표는 살린다.

- 파일은 10초 점검 때만 쓴다. 「끝」 뒤 10초 안에 앱을 끄면 `finishedAt`을 잃는다(종료 때 쓰기는 아직 없음).
- 요약: 마지막 시도의 시작→첫 기록(도구별), 「끝」낸 시도들의 시작→첫 기록(어느 도구든 먼저) 중앙값, 미완 시도가 가장 많이 멈춘 단계(`lastStage`, 같으면 앞 단계. 마지막 시도가 열려 있으면 진행 중으로 보고 뺀다).
- 연동 상태 패널: 「첫 기록까지 · 최근 1분 5초 · 중앙값 1분 20초 (3회)」, 「자주 멈춘 단계 · 연결 (2회)」(시도가 있을 때만).
- 진단 정보 복사: 「첫 연결: 시도 N회 · 끝냄 M회」부터 마지막 시도의 단계별 시간·실패 종류까지 7줄.

## 깨끗한 환경 첫 설정 (TRK-45)

2026-10-02, Claude Code 2.1.287, codex-cli 0.159.2, Waypoint Dev Debug(브랜치 `trk-45-first-setup`). 설정이 하나도 없는 임시 홈(`WAYPOINT_INTEGRATION_HOME`)과 임시 저장 폴더로 Dev를 `open -g -j`로 띄우고 `-WaypointOnboarding apply -WaypointOnboardingFolder <임시 프로젝트>`로 연결 적용·프로젝트 등록까지 한 번에 했다. 도구는 `env -i HOME=<임시 홈>`으로 한 번씩만 돌렸다. 인증 정보는 임시 홈에 옮기지 않았다. 절차는 `docs/DEVELOPMENT.md` 「깨끗한 환경 첫 설정」.

| 시각(UTC) | 시작부터 | 일 |
|---|---|---|
| 03:10:09.65 | 0 | 온보딩 시작(`startedAt`) |
| 03:10:10.31 | 0.66초 | 프로젝트 등록(`projectAt`) |
| 03:10:11.58 | 1.93초 | Claude 연결 적용 성공. 임시 홈에 `settings.json` 훅(47822)·상태줄 중계·`.claude.json` MCP(47822)·`/tracker` 스킬 |
| 03:10:11.59 | 1.94초 | Codex 연결 적용 성공. `config.toml` MCP·`hooks.json`·스킬 |
| 03:10:42 | | `claude -p "ok" --model haiku` 실행(임시 프로젝트 폴더) |
| 03:10:44.78 | 35.1초 | Claude 첫 기록(`firstRecord.claude`). 실행부터 2.8초. 앞의 30초는 사람 대신 확인하느라 쉰 시간 |
| 03:11:15 | | `codex exec --skip-git-repo-check "ok"` 실행(`CODEX_HOME=<임시 홈>/.codex`) |

결과:

- **Claude: 설정·수신 성공, 모델 호출은 인증에서 멈춤.** 임시 홈 설정의 `SessionStart`·`SessionEnd` 훅이 Dev(47822)로 갔고 Dev DB에 세션이 임시 프로젝트로 생겼다(시작·끝 시각 모두). `SessionStart` 응답으로 Dev의 블록(「Waypoint: <키> (<이름>)」)이 들어갔고 MCP도 47822에 연결됐다(`lastMCPAt`). 온보딩은 첫 기록을 받아 끝 단계(`lastStage` 4)로 넘어갔다. 그 뒤 모델 호출은 「Not logged in · Please run /login」으로 끝났다(종료 코드 1, 3초). 임시 홈에는 로그인 정보가 없다.
- **Codex: 설정 성공, 수신 없음.** 실행은 인증 없이 `401 Unauthorized`로 끝났다(종료 코드 1, 17초, 재연결 10회). 훅은 한 번도 오지 않았다. 새 홈의 Codex 훅은 `/hooks`에서 신뢰해야 도는데 그 승인은 대화형뿐이라, 인증이 있었어도 이 실행에서 받았을지는 확인하지 못했다.
- 지표: `metrics.json`(0600)에 위 시각이 그대로 남았다. 실패 0, 다시 시도 0. 「끝」 단추는 화면 자동 조작 금지라 누르지 않았다(`finishedAt`·「끝」 경로는 단위 테스트만). 앱을 끄면 시도는 열린 채 남는다(다음 시도부터 앱이 꺼진 미완으로 센다).
- 실제 홈(`~/.claude/settings.json`·스킬·`~/.codex/config.toml`·`hooks.json`·`~/.agents`)은 수정 시각·해시가 그대로였고 `~/.claude.json`의 `mcpServers`도 같았다.

사람이 해야 할 일:

1. 깨끗한 계정에서 Claude 실제 대화까지: 임시 홈에서 `HOME=<임시 홈> claude`로 `/login`을 한 번 하고 같은 실측을 다시 한다(모델 응답 뒤 `UserPromptSubmit`·`Stop` 수신과 MCP `card_start`까지).
2. Codex: `HOME=<임시 홈> CODEX_HOME=<임시 홈>/.codex codex login` 뒤, 대화형 `codex`에서 `/hooks`를 열어 Waypoint 훅을 신뢰하고 한 번 대화한다. 첫 기록이 오면 `firstRecord.codex`가 남는다.
3. 「끝」을 눌러 `finishedAt`과 중앙값이 생기는지 화면으로 본다.

## 저장소 백업·복구(TRK-46)

2026-10-02, Waypoint Dev Debug(브랜치 `trk-46-store-backup`, 0.0.1 빌드 1). 명세는 docs/SPEC.md 「저장소 백업·복구」.
스크래치 저장 폴더를 `WAYPOINT_SUPPORT_DIR`로 주고 `WAYPOINT_CLOUDKIT=0`으로 Dev를 `open -g -j`로 띄웠다. 저장소는 이 Mac 평소용 저장소를 `cp`로 복사한 사본(복사본 `quick_check` ok, 프로젝트 4·카드 110·이벤트 4628). 단계마다 47822 대기 → `/integration/status`의 `storeRestore` → MCP `project_resolve`(HTTP로 데이터 확인) → 저장소를 읽기 전용 `sqlite3`로 세기 → `quit app id` → 폴더 확인.

| 단계 | 한 일 | 결과 |
|---|---|---|
| ①-a | 빈 폴더 첫 실행 | 47822 수신. 저장소 생성, `store-version.json`(0.0.1·1·1.0.0, 0600), 백업 없음 |
| ① | 판 기록 없는 기존 저장소(사본) 첫 실행 | 열기 전 `…035452.961Z-upgrade`(store 30,285,824 B·-wal·-shm·info.json, 폴더 0700·파일 0600, `appVersion: unknown`). 47822 수신, `project_resolve` → TRK. 프로젝트 4·카드 110·이벤트 4629(세션 정리 기록 1). `store-version.json` 기록 |
| ②-a | 같은 판으로 다시 실행 | 새 백업 없음(1개 그대로) |
| ②-b | `store-version.json`의 빌드를 0으로 고치고 실행 | 열기 전 `…035501.863Z-upgrade`(`build: "0"` = 백업한 저장소를 마지막으로 연 빌드, -wal 148,352 B 포함). 판 기록은 다시 빌드 1 |
| ③ | 저장소 본 파일을 0x41 64 KB로 덮어씀(-wal·-shm 그대로) 뒤 실행 | 열기 실패(`SwiftDataError.loadIssueModelContainer`) → store·-wal·-shm을 `store-failed/20261002T035510.540Z/`(0700)로 옮김, `failure.json`(`quickCheck: failed`) → 최신 백업 `…035501.863Z-upgrade` 복원 → 열림. 47822 수신, `storeRestore` = `{"kind":"automatic","backupID":"20261002T035501.863Z-upgrade","failedFolder":"20261002T035510.540Z",…}`, `project_resolve` → TRK, 프로젝트 4·카드 110·이벤트 4629. 깨진 64 KB 파일은 보존 폴더에 그대로 |

- CloudKit을 켠 첫 열기: 환경 변수 없이 Dev를 Dev 자기 폴더(`Waypoint-Dev/`, 컨테이너 `iCloud.dev.antaeho.waypoint.dev`)로 띄웠다. 판 기록이 없어 열기 전 `20261002T040002.275Z-upgrade`, 판을 붙인 스키마·옮기기 계획으로 열림, Core Data 로그 「Successfully set up CloudKit integration」과 가져오기 「Success」 여러 번. `NSCocoaErrorDomain 134417`이 두 번 있었는데 바로 앞 줄이 「Failed to enqueue request」(요청 넣기 실패)이고 그 뒤 가져오기가 성공했다. 원인은 더 보지 않았다.
- 실측 중 처음 구현이 저장 폴더 자체를 0700으로 바꾸는 것을 보고 고쳤다(만들기만 한다, 테스트 추가).
- 사람이 확인할 것: 연동 상태 패널의 「기록을 열지 못해 … 백업으로 되돌림」 줄과 「알림 확인」(③ 상태의 Dev에서). 화면 캡처는 하지 않았다.
- 하지 않은 것: CloudKit을 켠 상태의 복원(동기화가 이후 변경을 다시 받는지), iPhone 기기 실행(빌드만), 수동 예약 복원의 앱 실측(단위 테스트만, 화면은 TRK-47).

## 동시 작업 겹침 (TRK-17)

규칙은 SPEC 4장 「같은 파일 작업 중」. 2026-10-02 Dev(Debug, 47822, 브랜치 `trk-17-overlap`)·실측 폴더 PRB(`~/workspace/waypoint-probe`, git 저장소)에서 실측 픽스처 형식 훅(`real-SessionStart`·`real-PostToolUse-Edit`·`doc-codex-*`)과 MCP 호출을 직접 보냈다. 실제 `claude -p`는 쓰지 않았다. 앱은 `open -g -j`로 띄우고 결과는 MCP 응답·`card_get` 기록·시작 블록·창 하나 캡처(`screencapture -l`)로 봤다.

| 단계 | 한 일 | 결과 |
|---|---|---|
| ① 같은 폴더 두 세션 | Claude 세션 A(PRB-13)가 `notes.txt`·`hello.txt`, Codex 세션 B(PRB-14)가 `apply_patch`로 `notes.txt` | 둘 다 `checkout` = `/Users/antaeho/workspace/waypoint-probe`. A의 `card_note`에 `overlaps [{sessionId: codex:be262243, provider: codex, cards: [PRB-14], files: [notes.txt], fileCount: 1}]`, B의 `card_evidence`에 A 쪽 같은 항목. 대시보드 두 타일에 `같은 파일 1개 · PRB-14`/`· PRB-13`, 상황판 진행 중 줄에 `같은 파일 1`, PRB-13 인스펙터 세션 상자에 같은 표시 |
| ② worktree | PRB 안에 `git worktree add .claude/worktrees/trk17`, Claude 세션 C(PRB-15)가 worktree의 `notes.txt`·`hello.txt` | C 기록 `path` = `.claude/worktrees/trk17/notes.txt`, `checkout` = worktree 폴더. C·A·B의 MCP 응답에 `overlaps` 없음, C 타일에 표시 없음(A·B는 그대로). 등록 폴더 **밖**에 만든 worktree(스크래치 폴더)의 편집은 세션도 `file.changed`도 남지 않았다(DB 0건) |
| ③ 한쪽 종료 | B에 `SessionEnd`(앱을 다시 켠 직후라 억제 기억 없음) | 대시보드에서 B 타일과 함께 A의 표시가 사라짐, A `card_note`에 `overlaps` 없음, 상황판 진행 중 줄 표시 없음 |
| ④ 반복 호출 | 앱을 다시 켠 뒤 A가 `card_note`·`card_note`·`card_handoff`·`card_update`·`card_start`·`card_evidence`·`project_status`, B가 `card_note` 두 번 | A는 첫 `card_note`에만 `overlaps`, 나머지 6번 없음. B도 첫 번째만 |
| ⑤ 새 파일 | B가 `hello.txt`도 고침 | A 다음 `card_note`에 `files [hello.txt, notes.txt]`(2개)로 다시, 그다음은 없음. B `card_handoff`에도 A 쪽 2개 |

근거: 겹침 표시는 `file.changed`의 `checkout`·`path`가 같고 두 작업 단위가 모두 끝나지 않았을 때만 나온다. MCP 응답 원문은 PR 설명에, 창 캡처는 작업 보고에 경로로 남겼다.

누락 범위(경고하지 않는 쪽으로 빠지는 경우):
- TRK-17 전 기록과 git 밖 파일(`checkout` 없음). 업데이트 직후 한 시간은 옛 기록과 새 기록이 겹쳐도 알리지 않는다.
- 등록 폴더 밖 worktree의 파일은 기록 자체가 없다(기존 규칙: 등록 밖 절대 경로는 남기지 않는다). 그 worktree와 본 작업 트리의 겹침은 원래 생기지 않으므로 오탐도 없다.
- 셸 명령으로 바꾼 파일 중 훅이 파일 이름을 주지 않는 것(`bashEditDiff`에 없는 변경), 앱이 꺼진 동안 outbox로 늦게 온 변경의 시각은 원래 시각이라 60분 안이면 들어간다.
- 같은 부모의 서브에이전트끼리, 부모와 서브에이전트는 알리지 않는다(같은 작업 단위).
- 한 카드에 같은 작업 트리의 세션 둘이 붙어 같은 파일을 고치면, 세션을 받지 않는 도구(`card_note` 등)는 두 세션 모두의 눈으로 보아 부른 쪽이 자기 자신을 상대로 받을 수 있다. 같은 카드의 다른 세션은 `card_start`의 `otherSessions`가 이미 알린다.
- 60분보다 오래 손대지 않은 파일은 지금 같이 만지는 파일로 보지 않는다.

알림 빈도: MCP `overlaps`는 같은 상대·같은 파일 집합이면 한 번, 새 파일이 끼면 한 번 더(④·⑤). 앱을 다시 켜면 기억이 지워져 남은 겹침을 다음 응답에 한 번 더 붙인다. 화면 표시는 겹침이 있는 동안 늘 보인다(알림 소리·배너 없음). 시작 블록은 겹침을 판정하지 않고 다른 세션 줄에 최근 파일을 붙일 뿐이다.

지연(같은 Dev 저장소, 사이드바 「지침」으로 띄워 대시보드 계산을 빼고 잼):
- 시작 블록 왕복(`SessionStart` 새 세션 → 끝 30회, main과 번갈아 3회씩): main p50 522·866·829 / p95 887·1344·906 ms, 이 변경 p50 622·827·868 / p95 994·1275·1392 ms. 회차마다 수백 ms씩 흔들려 차이는 잡음 안이다. 블록은 다른 세션 두 줄에 파일이 붙어 523 → 631 바이트(18줄 그대로). 표본을 떠 보니 시간 대부분은 사이드바 `DashboardQuery.summary`와 블록의 `DashboardQuery.rows`가 끝난 세션 1,600여 개를 읽는 데 쓰였고 `WorkOverlap`은 잡히지 않았다.
- `measure-latency.py` 기본(500건): 번갈아 네 번 — main 수신→저장 p50/p95 612/830, 247/373, 258/377 ms, 이 변경 636/1041, 597/765, 274/378 ms. 저장소가 측정마다 커지고 회차 사이 흔들림이 커서, 마지막처럼 조건이 같은 쌍은 같다. p95 2초 목표 모두 통과, 실패 0건.
- 색인만(저장소 사본, swift test Debug, `WorkOverlapTimingTests`): 실제 저장소 백업 사본(프로젝트 4·세션 115·이벤트 6150) 프로젝트 전부 5 ms, Dev 저장소 사본(세션 1620·이벤트 7369, 최근 1시간에 측정용 변경 수천 건) 20 ms. 대시보드는 다시 그릴 때마다 진행 작업·상황판에서 한 번씩 만든다.

## 큰 기록 성능 (TRK-66)

2026-10-02 저장소 **사본** 두 개로 쟀다: Dev 사본(프로젝트 1·세션 1,619·이벤트 7,369, 끝난 세션 대부분이 측정용), 실제 저장소 사본(프로젝트 4·세션 116·이벤트 6,244, 실제 저장소는 `sqlite3 .backup`으로 읽기만). Dev Debug 빌드를 사본 폴더로 `open -g -j`(`WAYPOINT_SUPPORT_DIR`, `WAYPOINT_CLOUDKIT=0`)로 띄우고, 대시보드가 보이는 상태에서 `SessionStart`→`SessionEnd` 30쌍과 메인 큐 핑(`GET /ping`, 받을 때마다 화면을 다시 계산하게 한다) 80번을 보냈다. 핑 왕복의 최대 ≈ 메인 스레드 최장 점유. 기계 부하(평균 5~18)가 커서 같은 빌드도 회차마다 수백 ms씩 흔들렸다.

| | 전(main) | 후 |
|---|---|---|
| Dev 사본 `SessionStart` p50/p95 | 2,472 / 8,016 ms | 98 / 106 ms |
| Dev 사본 메인 큐 핑 p50/p95/최대 | 4,572 / 7,662 / 8,417 ms | 2 / 3 / 151 ms |
| Dev 사본 대시보드 한 번 계산(테스트, CPU) | 1,485~3,073 ms | 13 ms |
| 실제 사본 `SessionStart` p50/p95 | 504 / 559 ms(같은 시각 재측정 1,001 / 1,518) | 197 / 429 ms |
| 실제 사본 메인 큐 핑 p50/p95/최대 | 1 / 20 / 443 ms | 6 / 113 / 295 ms |
| 실제 사본 대시보드 한 번 계산(테스트, CPU) | 13 ms | 50~90 ms |

원인(`sample`): 대시보드를 그릴 때마다 상황판의 `UnfiledWork.count`가 끝난 메인 세션(1,617개)마다 `fetchCount`를 불렀다. 메인 스레드 표본 6,053개 중 5,751개. 훅은 메인 큐에서 처리되므로 시작 블록도 이 계산이 끝나기를 기다렸다. 이것만 고친 빌드도 Dev 사본 `SessionStart` p50/p95 976 / 1,400 ms였다. 나머지는 `DashboardQuery.rows`·`summary`·`lastActivityAt`이 `project.sessions` 관계로 끝난 세션 전체를 읽은 것이다.

바꾼 것:
- `UnfiledWork`: 조건(끝난 메인 세션·14일·카드 없는 파일 변경(서브에이전트 포함)·카드에 붙은 적 없음)을 하위 질의 두 번으로 넘기고 ID만 받는다. 넘김 기록은 한 번 더 빼고, 파일 목록은 블록에 보이는 세션 것만 읽는다.
- `DashboardQuery`: 끝나지 않은 세션만 질의로 읽는다(하위 세션은 같이 가져옴). 마지막 활동은 가장 늦은 세션 하나만 읽고 저장 전 변경은 메모리 값으로 더한다.
- `SessionFormat.recentFileName`: 세션을 매번 새로 읽게 되자 긴 세션(이벤트 1,072건)의 이벤트를 그릴 때마다 하나씩 다시 읽었다(메인 스레드 표본 3,788개). 가장 늦은 변경 하나만 질의한다.
- 결과 동일성: `LargeStoreEquivalenceTests`가 바꾸기 전 구현을 옮겨 두고 경계(14일·60분·끝난 세션·보관 프로젝트·서브에이전트·저장 전 변경) 픽스처와 두 사본에서 같은 결과인지 본다. 같은 시각의 파일 변경이 여럿이면 전 구현도 순서가 정해지지 않았으므로, 정리 안 된 작업은 ID순으로 맞추고 최근 파일 이름은 그 시각의 이름 중 하나면 같다고 본다. 시작 블록도 두 빌드가 같은 글을 냈다(세션 ID 줄만 다름).

남은 한계:
- 실제 사본처럼 작은 저장소에서는 대시보드 한 번 계산이 13 → 50~90 ms(CPU)로 늘었다. 전에는 `project.sessions`로 읽은 세션 그래프가 메모리에 남아 다음 계산이 거의 공짜였고, 이제는 계산마다 질의한다. 목표 100 ms 안이지만 앱 핑 p95가 20 → 113 ms가 됐다. 같은 계산을 한 번 그리는 동안 여러 번(통합 집계·상황판·사이드바) 하므로 저장 때 비우는 짧은 캐시로 줄일 수 있다.
- SwiftData가 `$0.session?.…` 같은 선택적 관계 비교를 `CASE … END = ?`로 바꿔 색인을 쓰지 못한다. 이벤트 표를 훑는 질의(최근 파일·겹침 색인·지금 상황)는 이벤트 수에 비례한다. 지금 6~7천 건에서 한 번에 1~3 ms. 두 단계 관계(`$0.session?.parent?.…`)는 틀린 SQL을 만들거나 예외로 멈춰서 쓰지 않는다.
- 이벤트·세션이 쌓이는 것 자체(보관 정책)는 이번에 다루지 않았다.

## 원격·컨테이너 (TRK-53)

2026-10-03, Dev(47822) Debug, Docker Desktop 29.6, 원격 역할은 Ubuntu 24.04 컨테이너(curl 8.5, jq, sshd). 훅은 실제 스크립트에 실측 픽스처(`real-*`)의 `cwd`·파일 경로를 원격 폴더로 바꿔 넣었다. 실제 `claude`·`codex`는 컨테이너에서 돌리지 않았다. 실측 폴더 `~/workspace/waypoint-probe`(PRB)에는 origin이 없어 임시 bare 저장소를 origin으로 붙이고 컨테이너 안 클론도 같은 주소로 맞췄다(끝난 뒤 지웠다). 기록은 Dev 저장소를 읽기 전용(`sqlite3 -readonly`)으로 확인했다.

| 단계 | 결과 |
|---|---|
| 컨테이너 → `127.0.0.1`에만 열린 앱 | `curl http://host.docker.internal:47822/integration/status` → `200`. 앱 서버를 다른 인터페이스로 열지 않았다 |
| 개발 컨테이너(`WAYPOINT_URL=http://host.docker.internal:47822`, `/workspaces/waypoint-probe`, 브랜치 `ctr-branch`) | `SessionStart` stdout `Waypoint: PRB (waypoint-probe)`. 세션: 프로젝트 PRB, 폴더 `/workspaces/waypoint-probe`, 브랜치 `ctr-branch`. `user.prompt` 1, `file.changed` `notes.txt` +2 −1 `checkout` `<컨테이너 ID>:/workspaces/waypoint-probe`, `session.end`. 훅 다섯 개 모두 exit 0, 157~237 ms(파이썬 실행·앱 처리 포함) |
| SSH ① `remote-setup.sh --dev` | 원격 `settings.json`(사용자 훅 `echo user-hook`과 `model` 유지)에 Waypoint 훅 10개, 훅 스크립트·상태줄 중계(0755)·tracker 스킬. 바뀌기 전 `settings.json`을 `~/.waypoint-backups/<시각>.tgz`로. 다시 돌리면 「이미 맞음」. `--dry-run`은 쓰지 않음 |
| SSH ② MCP | 원격에 `claude`가 없으면 명령만 보인다. 가짜 `claude`(인자 기록)를 두면 `mcp remove waypoint -s user` → `mcp add --transport http --scope user waypoint http://127.0.0.1:47822/mcp`. 컨테이너에서 `project_resolve(cwd: 원격 폴더, remote: origin)` → PRB, `remote` 없이 → `null` |
| SSH ③ 터널(`ssh -N -R 47822:127.0.0.1:47822`)로 설치된 훅 명령 실행 | `SessionStart` stdout `Waypoint: PRB …`, 세션 폴더 `/home/dev/waypoint-probe`, 브랜치 `ssh-branch`, `file.changed` `notes.txt`. 163~271 ms |
| SSH ④ 터널 끊고 훅 4개 | 각 28~38 ms에 exit 0, 원격 `~/Library/Application Support/Waypoint-Dev/outbox.jsonl`(설치기 Dev 접두사) 4줄, 줄마다 `waypoint_remote`. Dev에는 아무것도 없음 |
| SSH ④ 다시 연결 후 `Stop` 한 번 | 훅 125~133 ms(replay를 기다리지 않음). 2초 뒤 원격 outbox·pending·잠금 없음. Dev: 세션 PRB, `session.start`(`source: startup`, 원래 시각), `user.prompt`, `file.changed` — 시작 시각은 가장 이른 훅 |

| SSH ④′ 끊긴 동안 훅 4개 → 다시 연결 뒤 첫 훅이 **같은 세션의 `SessionEnd`**(가장 나쁜 순서, 스크립트·앱 순서 규칙 뒤) | 끊긴 동안 15~18 ms. `SessionEnd`는 쌓인 줄 뒤에 서고(실시간으로 보내지 않음) replay가 다섯 줄을 차례로 보낸다. Dev: `session.start`(`startup`, 원래 시각) → `user.prompt` → `file.changed` → `session.end`, 세션 끝남. 원격 outbox·pending·잠금 없음. 쌓인 줄이 있을 때 훅 하나 22~30 ms |
| 500줄 replay와 동시에 로컬 `SessionStart`(Mac, Dev) | 아래 표 |

처음 실측에서 ④의 시작 기록이 다시 이어진 뒤 첫 훅(`Stop`) 시각에 `source` 없이 남았다. 실시간 훅이 세션을 먼저 만들고 쌓인 이른 줄이 뒤에 들어오기 때문이다. 이른 훅이 늦게 오면 시작 시각·시작 기록을 당기게 고친 뒤(`HookProcessor.moveStart`) 다시 재서 위 결과를 얻었다.

지연:

| 측정 | 값 |
|---|---|
| Mac 로컬 `SessionStart` 훅 전체(Dev, n=30, 두 번씩 번갈아) | 바꾸기 전 중앙값 289.8 / 299.2 ms, 바꾼 뒤 295.3 / 302.8 ms(p95 313~329 / 305~316). 차이는 측정 흔들림 안. 로컬은 원격 모드가 꺼져 하는 일이 같다. 원격 모드를 Mac에서 강제로 켜면 307.1 ms |
| git 원격 정보 읽기(`remote_field` 1,000번 평균) | Ubuntu 컨테이너 0.30 ms, Mac(bash 3.2) 1.7 ms. 같은 정보를 git 명령 두 번으로 읽으면 컨테이너 22 ms |

500줄 replay(한 세션의 `SessionStart` 1 + `PostToolUse` 499, Mac에서 `curl`로 `/hooks/replay`)를 보내고 1초 간격으로 로컬 `SessionStart` 훅을 실제 스크립트로 보냈다. 이 Dev 저장소는 큰 기록 사본이라 평소에도 `SessionStart` 하나가 약 300 ms다.

| 구현 | replay 응답 | 동시 로컬 `SessionStart` | 500줄 처리 |
|---|---|---|---|
| 처음: Mac outbox에 붙이고 그 자리에서 흡수(`absorbOutbox`) | 68.6초 | 1,198 ms, 시간 초과로 블록 없이 outbox로 | 68초(메인 액터를 내내 잡음) |
| 응답 먼저, 흡수는 0.25초씩 조각(`absorbOutbox` + 다시 읽기) | 0.04초 | 717~1,402 ms, 6번 중 2번 시간 초과 | 215초(조각마다 다시 읽기가 비쌌다) |
| 지금: `replay/`에 붙이고 실시간 경로로 0.1초씩 | 0.03~0.06초 | 348~626 ms, 14번 모두 블록 받음 | 141~160초(한 세션에 기록이 쌓일수록 줄마다 느려진다) |

replay로 들어온 줄은 앱의 outbox 흡수 지표(`recordAbsorb`)에 함께 센다. 실시간 수신 지연 지표에는 들지 않는다.

## GitHub 이슈·PR 열기 (TRK-68)

2026-10-08, gh 2.96.0(`AnTaeho` 로그인), Waypoint Dev Debug(브랜치 `trk-68-github`, 47822, `WAYPOINT_SUPPORT_DIR`=임시 폴더, `WAYPOINT_CLOUDKIT=0`, `open -g -j`). 비공개 실측 저장소 `AnTaeho/waypoint-gh-probe`를 스크래치에 클론해 `-WaypointOnboarding project -WaypointOnboardingFolder <클론>`으로 등록(WGP)하고 MCP를 `curl`로 직접 불렀다. 실제 `claude -p`는 쓰지 않았다.

- 이슈: `github_issue_create(project: WGP, cardId: WGP-1)` → `{number: 1, state: open, url: …/issues/1, cardId: WGP-1}`, 1.28초. GitHub의 본문은 보낸 글 그대로.
- 대기 중 다른 요청: 위 호출이 도는 동안 보낸 `ping` 0.004초, `card_list` 정상 응답(이슈 응답보다 먼저 끝남).
- push 전 PR: `브랜치가 원격에 없음 — 먼저 push: probe/trk-68`(0.008초, `gh`를 부르지 않음).
- push 뒤 PR: `github_pr_create(draft: true)` → `{number: 2, state: draft, url: …/pull/2}`, 2.40초. GitHub에서 `isDraft: true`, base `main`, head `probe/trk-68`.
- 기록: `card_get(WGP-1)`의 최근 기록에 `github.issue`·`github.pr`(payload `number`·`url`·`title`·`state`·`repo`·`branch`).
- 화면(창 하나 캡처): 카드 인스펙터 「GitHub」 구역(#2 초안, #1 열림, 버튼 둘), 카드 기록 「PR #2 열림 · …」「이슈 #1 열림 · …」, 보드 머리 「이슈 1 · PR 1」, 상황판 타일 아래 줄 「이슈 1 · PR 1」, 열기 시트(이슈·PR, 브랜치 `probe/trk-68`, 합칠 곳 자리 글 `main`). 보드 머리 목록은 숨긴 채 띄운 앱에서 팝오버가 뜨지 않아 같은 목록을 시트로 찍었다 — 팝오버 자체는 사람이 눌러 확인할 것.
- 상태 갱신: `gh issue close 1`·`gh pr close 2` 뒤, 마지막 확인에서 5분이 지나기 전에 연 인스펙터는 그대로(캐시 `checkedAt` 변화 없음), 5분 뒤에 열자 `github-cache.json`(0600)이 둘 다 `closed`로 바뀌고 알약이 「닫힘」, 보드 머리 「이슈 0 · PR 0」. 카드 상태(`next`)와 이벤트 payload는 그대로.
- 훅 지연(`scripts/measure-latency.py`, 500건, 세션 6, 실측 저장소라 기록이 적다): 대시보드가 보이는 상태에서 앱 수신→저장 p50 56 / p95 88 ms, 왕복 p50 57 / p95 89 ms. 같은 날 main과 번갈아 재지는 않았다.
- 실측하지 않은 것: 시트의 「열기」 버튼(사람 조작이 필요하다 — 시트는 도구와 같은 `GitHubPlanner`·`GitHubJob`·`GitHubLog`를 쓴다), 줄을 눌러 브라우저로 열기, 병합된 PR의 「병합됨」 알약(단위 테스트만).
- 끝난 뒤: 이슈 #1·PR #2는 닫힌 채, 저장소는 남겨 둠.

## 알려진 한계

- 큰 기록 저장소에서 replay 처리는 초당 3~4줄이다(위 표). 수백 줄이면 몇 분 걸리고, 그동안 원격 세션의 블록이 필요 없는 훅은 그 뒤에 서서 늦게 보인다.
- 원격 outbox는 원격 쪽 훅이 앱에 닿을 때만 비운다. 터널을 다시 열어도 다음 훅이 오기 전에는 들어오지 않는다. 컨테이너를 앱이 꺼진 채로 지우면 그 안에 쌓인 기록은 잃는다.
- 원격의 같은 저장소 클론이 Mac에 둘 이상 등록돼 있으면(서로 다른 작업 트리) 원격 세션을 잇지 않는다.
- 원격 `curl`이 7.84 미만이면 시작 블록 수신 확인(TRK-35)을 보내지 못해 블록이 다음 프롬프트에 한 번 더 붙을 수 있다. `remote-setup.sh`가 알린다.

- 세션이 끝난 뒤 그보다 이른 시각의 기록이 실시간으로 처리되지 않고 outbox로만 오면 버린다. 실시간 서버가 그 훅을 받지 못했는데 뒤의 `SessionEnd`는 받은 경우뿐이라 실제로는 드물다. 끝난 세션에 늦은 사실 기록을 붙이는 것은 명세를 바꾸는 일이라 이번에 하지 않았다.
- `tool_use_id`가 없는 도구 훅은 재수신을 거르지 못한다(Claude 실측·Codex 문서 모두 있다).
- 서브에이전트 대기 항목과 재수신 표시는 메모리에만 있다. `PreToolUse(Agent)`를 실시간으로 받은 직후 앱이 꺼지면 그 서브에이전트는 카드 없이 시작한다(파일은 부모 카드로 간다).
- 설치된 훅 스크립트를 이번 버전으로 바꾸기 전까지 outbox 줄에 `prompt_id`·`turn_id`가 없다. 그동안 요청 재수신은 같은 문장 10초 기준으로 거른다.
- 블록 수신 확인(TRK-35)은 스크립트가 블록을 출력한 뒤 확인 요청을 하나 더 보낸다. 앱은 서버 큐에서 바로 답하므로 `SessionStart`·늦은 주입 훅이 Dev Debug에서 중앙값 10~45 ms 늘어난다(curl 한 번). 확인을 잃거나 받아 둔 확인을 앱 재시작으로 잃으면(블록은 출력됨) 다음 프롬프트에 같은 블록을 한 번 더 받는다. 설치된 스크립트를 바꾸기 전까지는 예전처럼 응답 시간 초과 때 블록을 잃는다.
- 수신 지연 지표의 출발점은 서버 큐가 연결을 받은 시각이다(TRK-35부터). 그전 측정은 메인 큐 대기를 빼고 쟀다.
- 재개 시간은 앱이 볼 수 있는 복사→연결까지다. 실제 작업 재개는 관찰로 따로 잰다(로드맵 「측정 방법」).
- 앱 버전·빌드는 `project.yml`의 고정값(0.0.1, 빌드 1)이고 설치 스크립트가 올리지 않는다. 그래서 지금은 새 빌드를 깔아도 `upgrade` 백업이 뜨지 않고, 판이 바뀔 때와 판 기록이 없던 첫 실행에만 뜬다. 빌드 번호 올리기는 배포 스크립트(TRK-48) 몫.
