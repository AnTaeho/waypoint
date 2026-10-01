# 기록 신뢰성 기준 (TRK-11)

작성: 2026-10-01. 로드맵 02 「기록 신뢰성 기준과 사용 효과 측정」의 기준·측정 방법·관측값을 한곳에 둔다.

## 지원 범위

| 항목 | 지원 | 지원하지 않음 |
|---|---|---|
| 기기 | macOS 14+ Mac 한 대의 로컬 앱(평소용 47821, 개발용 47822) | 여러 Mac이 같은 세션을 동시에 받기 |
| 도구 | Claude Code 로컬 CLI 훅(2.1.283 실측), Codex CLI 로컬 훅(공식 문서 기준 `doc-codex-*`) | 클라우드 실행 Codex, 전사 파일 감시 |
| 폴더 | 등록한 프로젝트 폴더와 그 하위 폴더(가장 가까운 등록 폴더) | 등록 전·미등록 폴더의 훅(기록하지 않는다), 보관한 프로젝트 |
| 전달 | 실시간 POST, 앱이 꺼졌거나 1초 안에 답하지 못한 훅의 outbox 재수신 | CloudKit 전달 시간(이 기준에 넣지 않는다) |

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

환경: MacBook(Apple M4, 16 GB), macOS 26.6.2, Xcode 27.0, Waypoint Dev Debug 빌드(`trk-11-reliability`), Dev 저장소 이벤트 약 1천~2.5천 건. 평소용 앱은 47821에서 그대로 돌고 있었다.

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
- 훅 스크립트의 응답 기한은 1초다. 부하 실행의 최대 왕복이 0.8초까지 올랐다. 1초를 넘으면 같은 훅이 outbox에도 쓰이는데, 이제 한 번만 남는다. `SessionStart` 응답이 1초를 넘으면 그 세션은 처음 블록을 받지 못한다(아래 「알려진 한계」).

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

## 알려진 한계

- 세션이 끝난 뒤 그보다 이른 시각의 기록이 실시간으로 처리되지 않고 outbox로만 오면 버린다. 실시간 서버가 그 훅을 받지 못했는데 뒤의 `SessionEnd`는 받은 경우뿐이라 실제로는 드물다. 끝난 세션에 늦은 사실 기록을 붙이는 것은 명세를 바꾸는 일이라 이번에 하지 않았다.
- `tool_use_id`가 없는 도구 훅은 재수신을 거르지 못한다(Claude 실측·Codex 문서 모두 있다).
- 서브에이전트 대기 항목과 재수신 표시는 메모리에만 있다. `PreToolUse(Agent)`를 실시간으로 받은 직후 앱이 꺼지면 그 서브에이전트는 카드 없이 시작한다(파일은 부모 카드로 간다).
- 설치된 훅 스크립트를 이번 버전으로 바꾸기 전까지 outbox 줄에 `prompt_id`·`turn_id`가 없다. 그동안 요청 재수신은 같은 문장 10초 기준으로 거른다.
- `SessionStart` 응답이 1초를 넘으면 스크립트가 블록을 출력하지 못하지만 앱은 블록을 건넨 것으로 적어 늦은 주입도 하지 않는다. 이번 측정 최대 0.8초.
- 재개 시간은 앱이 볼 수 있는 복사→연결까지다. 실제 작업 재개는 관찰로 따로 잰다(로드맵 「측정 방법」).
