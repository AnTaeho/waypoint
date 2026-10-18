# 기록 신뢰성 기준

기록 신뢰성의 지원 범위·실패 동작·회귀 시나리오·지연 기준과 측정 방법, 기능별 확인 결과와 알려진 한계를 둔다.

## 지원 범위

| 항목 | 지원 | 지원하지 않음 |
|---|---|---|
| 기기 | macOS 14+ Mac 한 대의 로컬 앱(평소용 47821, 개발용 47822) | 여러 Mac이 같은 세션을 동시에 받기 |
| 도구 | Claude Code 로컬 CLI 훅(2.1.283 실측), Codex CLI 로컬 훅(공식 문서 기준 `doc-codex-*`) | 클라우드 실행 Codex, 전사 파일 감시 |
| 폴더 | 등록한 프로젝트 폴더와 그 하위 폴더(가장 가까운 등록 폴더) | 등록 전·미등록 폴더의 훅(기록하지 않는다), 보관한 프로젝트 |
| 전달 | 실시간 POST, 앱이 꺼졌거나 1초 안에 답하지 못한 훅의 outbox 재수신 | CloudKit 전달 시간(이 기준에 넣지 않는다) |
| 원격 | SSH 원격(원격 포트 포워딩)·Docker Desktop 개발 컨테이너(`host.docker.internal`)의 훅, 같은 git origin의 등록 프로젝트에 잇기, 원격 outbox replay | 웹·클라우드 세션, Docker Desktop 밖 컨테이너 런타임(확인 안 함) |

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

| 시나리오 | 테스트 |
|---|---|
| (a) 같은 훅 실시간 두 번·실시간+outbox | `sameHookRedeliveredLiveAndThroughOutbox` |
| (a) ID 없는 요청 재수신 | `promptWithoutIDFallsBackToTextAndShortWindow` |
| (a) `PreToolUse(Agent)` 재수신 | `replayedSpawnDoesNotPairNextSubagentWithOldCard` |
| (a) 세션 종료 뒤 outbox 재수신 | `outboxCopyAfterSessionEndIsNeitherDuplicatedNorLost` |
| (b) 하위 폴더·따로 등록한 하위 프로젝트·이름 비슷한 옆 폴더·등록 전후 | `subfolderNestedSiblingAndRegistrationOrder` |
| (c) 세션 중 `cd`로 다른 등록 프로젝트, `session_bind` 전환 | `cwdMovingIntoAnotherProjectKeepsCommitsAndChecksThere` |
| (d) Claude·Codex 같은 원본 ID로 동시·교대 | `claudeAndCodexShareProjectConcurrentlyAndInTurn` |
| (e) 같은 프로젝트 세션 3개 + 서브에이전트 2개 | `threeSessionsAndSubagentsInterleaved` |
| (f) 잠자기: PID 있음(5시간 공백) | `sleepWithKnownProcessKeepsSessionAndCard` |
| (f) 잠자기: PID 없음(30분 만료·카드 복귀) | `sleepWithoutProcessExpiresThenRevivesWithoutCard` |
| (f) 깨어날 때 outbox 먼저 흡수 | `wakeAbsorbsQueuedActivityBeforeSweep` |
| (g) 재시작: 꺼진 동안 outbox → 새 실행 흡수 → 실시간 | `restartAbsorbsOutboxThenContinuesLive` |

## 수신 → 저장/표시 지연

- 앱 안(`ReliabilityMonitor`): 훅 요청마다 **수신**(로컬 서버가 연결을 받은 시각) → **저장**(처리기 저장 끝) → **화면**(데이터 변경 알림을 낸 뒤 메인 큐가 한 번 돈 시각. 화면 갱신이 같은 메인 큐에서 일어난다). 최근 1000건을 밀리초로 보관한다. outbox 흡수는 일부러 늦게 받은 것이라 넣지 않는다. CloudKit 전달 시간은 넣지 않는다.
- 스크립트 쪽: 요청마다 보내고 응답을 받을 때까지(연결 대기 포함). 앱의 수신 시각보다 앞의 대기를 잡으려고 함께 본다.
- 판정: 앱 수신→화면 p95와 스크립트 왕복 p95가 모두 2초 미만이면 통과. 백분위는 nearest-rank.
- 실행: `scripts/measure-latency.py`. Dev(Debug, 47822)를 `open -g -j <Debug 앱 경로>`로 띄우고, Dev에 등록된 실측 폴더(PRB)에 실측 픽스처 형식 훅 500건을 보낸다. 세션 6개(Claude 4, Codex 2)가 동시에, 턴마다 요청 → 도구 1~5번(Pre/Post 3~60 ms 간격, 30%는 쉬지 않음) → Stop(턴 사이 0.2~0.8초). 세션 ID·`tool_use_id`·요청 ID는 매번 새로 만들고 PID 머리는 보내지 않는다. 모든 세션은 `SessionEnd`로 닫는다. 끝나면 `/integration/status`의 `metrics`에서 이번 표본을 읽는다. Dev는 번들 ID로 끈다.
- 기준값(Apple M4, Dev Debug): 기본 조건 수신→화면 p95 442 ms·왕복 p95 417 ms, 부하(세션 12, 간격 0.3배) 수신→화면 p95 729 ms. 지연의 대부분은 훅 한 건의 메인 액터 처리와 그 뒤 화면 갱신이고, 동시 세션이 많으면 메인 큐에서 줄을 선다.
- 훅 스크립트의 응답 기한은 1초다. 넘으면 같은 훅이 outbox에도 쓰이고 한 번만 남는다. `SessionStart` 응답이 1초를 넘으면 그 세션은 처음 블록을 받지 못하고 다음 프롬프트에 블록을 다시 받는다(SPEC 5장 「수신 확인」).

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

### 첫 연결 지표

`ReliabilityMetrics.onboarding`(`Shared/Onboarding/OnboardingMetrics.swift`). 온보딩을 한 번 연 것(열기 → 「끝」 또는 닫기)이 한 시도이고 최근 20회만 남긴다. 시도마다 연 시각, 마지막·가장 멀리 간 단계(도구 · 연결 · 프로젝트 · 첫 기록 · 끝), 도구별 연결 성공·첫 기록 시각, 프로젝트 등록 시각, 끝·닫기 시각, 다시 시도 횟수, 단계·까닭별 실패 횟수를 숫자와 시각으로만 둔다(`OnboardingMetricsTests`가 키 이름과 문자열 값 없음을 고정).

- 연동 상태 패널: 「첫 기록까지 · 최근 1분 5초 · 중앙값 1분 20초 (3회)」, 「자주 멈춘 단계 · 연결 (2회)」(시도가 있을 때만).
- 진단 정보 복사: 「첫 연결: 시도 N회 · 끝냄 M회」부터 마지막 시도의 단계별 시간·실패 종류까지.
- 파일은 10초 점검 때만 쓴다. 「끝」 뒤 10초 안에 앱을 끄면 `finishedAt`을 잃는다.

## 저장소 백업·복구

명세는 SPEC 「저장소 백업·복구」. Dev를 스크래치 저장 폴더(평소용 저장소 사본, `WAYPOINT_CLOUDKIT=0`)로 띄워 확인했다.

- 판 기록(`store-version.json`)이 없거나 빌드가 바뀐 저장소는 열기 전에 `-upgrade` 백업을 만든다. 같은 판으로 다시 열면 백업이 생기지 않는다.
- 깨진 저장소는 열기 실패 → store·-wal·-shm을 `store-failed/<시각>/`로 옮기고 `failure.json` → 최신 백업 복원 → 열림. `/integration/status`의 `storeRestore`에 복원 내용이 남는다.
- CloudKit을 켠 채 판을 붙인 스키마로 여는 것은 Dev 자기 폴더에서 확인했다.
- 확인 못 함: CloudKit을 켠 상태의 복원(동기화가 이후 변경을 다시 받는지), 연동 상태 패널의 복원 알림 줄 화면.

## 동시 작업 겹침

규칙은 SPEC 4장 「같은 파일 작업 중」. 겹침 표시는 `file.changed`의 `checkout`·`path`가 같고 두 작업 단위가 모두 끝나지 않았을 때만 나온다.

경고하지 않는 쪽으로 빠지는 경우(SPEC의 누락 외):
- 업데이트 직후 한 시간은 옛 기록과 새 기록이 겹쳐도 알리지 않는다.
- 셸 명령으로 바꾼 파일 중 훅이 파일 이름을 주지 않는 것(`bashEditDiff`에 없는 변경).
- 앱이 꺼진 동안 outbox로 늦게 온 변경은 원래 시각이라 60분 안이면 들어간다.
- 같은 부모의 서브에이전트끼리, 부모와 서브에이전트는 알리지 않는다(같은 작업 단위).
- 한 카드에 같은 작업 트리의 세션 둘이 붙어 같은 파일을 고치면, 세션을 받지 않는 도구(`card_note` 등)는 두 세션 모두의 눈으로 보아 부른 쪽이 자기 자신을 상대로 받을 수 있다. 같은 카드의 다른 세션은 `card_start`의 `otherSessions`가 이미 알린다.

알림 빈도: MCP `overlaps`는 같은 상대·같은 파일 집합이면 한 번, 새 파일이 끼면 한 번 더. 앱을 다시 켜면 기억이 지워져 남은 겹침을 다음 응답에 한 번 더 붙인다. 화면 표시는 겹침이 있는 동안 늘 보인다(알림 소리·배너 없음). 시작 블록은 겹침을 판정하지 않고 다른 세션 줄에 최근 파일을 붙일 뿐이다.

## 큰 기록 성능

끝난 세션 1,600여 개인 Dev 저장소 사본에서 `SessionStart` p95가 8초 → 106 ms, 메인 큐 최장 점유가 8.4초 → 151 ms가 됐다. 대시보드·상황판 질의가 끝난 세션 전체를 읽지 않게 한 결과다. `LargeStoreEquivalenceTests`가 바꾸기 전 구현과 결과가 같은지 본다.

남은 한계:
- 작은 저장소에서는 대시보드 한 번 계산이 13 → 50~90 ms(CPU)로 늘었다. 계산마다 질의하기 때문이다. 목표 100 ms 안이다. 한 번 그리는 동안 같은 계산을 여러 번(통합 집계·상황판·사이드바) 하므로 저장 때 비우는 짧은 캐시로 줄일 수 있다.
- SwiftData가 `$0.session?.…` 같은 선택적 관계 비교를 `CASE … END = ?`로 바꿔 색인을 쓰지 못한다. 이벤트 표를 훑는 질의(최근 파일·겹침 색인·지금 상황)는 이벤트 수에 비례한다(6~7천 건에서 1~3 ms). 두 단계 관계(`$0.session?.parent?.…`)는 틀린 SQL을 만들거나 예외로 멈춰서 쓰지 않는다.
- 이벤트·세션이 쌓이는 것 자체(보관 정책)는 다루지 않았다.

## 원격·컨테이너

사용자 절차는 [REMOTE.md](REMOTE.md). Dev(47822)와 Ubuntu 24.04 컨테이너(curl 8.5, jq, sshd)로 확인했다. 실제 `claude`·`codex`는 컨테이너에서 돌리지 않고 실측 픽스처를 원격 폴더 기준으로 바꿔 넣었다.

- 컨테이너에서 `host.docker.internal:47822`로 `127.0.0.1`에만 열린 앱에 닿는다.
- 개발 컨테이너(`WAYPOINT_URL`)와 SSH 터널(`ssh -N -R`) 모두 시작 블록·세션(원격 폴더·브랜치)·`file.changed`(원격 `checkout`)가 등록 프로젝트에 이어진다.
- `remote-setup.sh`는 원격 사용자 훅·설정을 지키고, 바뀌기 전 파일을 백업하고, 다시 돌리면 「이미 맞음」이다.
- 터널이 끊긴 동안 훅은 원격 outbox에 쌓이고(훅마다 수십 ms, exit 0), 다시 이어진 뒤 첫 훅이 replay를 뒤에서 보낸다. 첫 훅이 같은 세션의 `SessionEnd`여도 순서가 지켜진다. 이른 훅이 늦게 오면 시작 시각·시작 기록을 당긴다(`HookProcessor.moveStart`).
- replay 500줄을 받는 동안에도 로컬 `SessionStart`는 블록을 받는다(348~626 ms). replay로 들어온 줄은 outbox 흡수 지표(`recordAbsorb`)에 센다. 실시간 수신 지연 지표에는 들지 않는다.

원격 쪽 한계(curl 7.84 미만, 컨테이너 삭제, 클론 둘)는 REMOTE.md. 큰 기록 저장소에서 replay 처리는 초당 3~4줄이라 수백 줄이면 몇 분 걸리고, 그동안 블록이 필요 없는 원격 훅은 그 뒤에 서서 늦게 보인다.

## GitHub 이슈·PR 열기

비공개 실측 저장소(`AnTaeho/waypoint-gh-probe`)를 Dev에 등록하고 MCP를 직접 불러 확인했다. 이슈·초안 PR 열기, push 전 PR 거절(`gh`를 부르지 않음), 호출 중 다른 MCP 요청이 밀리지 않음, 카드 기록 `github.issue`·`github.pr`, 5분 캐시 뒤 닫힘 상태 반영.

사람이 확인할 것:
- 시트의 「열기」 버튼, 줄을 눌러 브라우저로 열기.
- 보드 머리 목록 팝오버(숨긴 채 띄운 앱에서는 뜨지 않아 같은 목록을 시트로만 봤다).
- 병합된 PR의 「병합됨」 알약(단위 테스트만).

## 알려진 한계

- 세션이 끝난 뒤 그보다 이른 시각의 기록이 실시간으로 처리되지 않고 outbox로만 오면 버린다. 실시간 서버가 그 훅을 받지 못했는데 뒤의 `SessionEnd`는 받은 경우뿐이라 실제로는 드물다. 끝난 세션에 늦은 사실 기록을 붙이는 것은 명세를 바꾸는 일이다.
- `tool_use_id`가 없는 도구 훅은 재수신을 거르지 못한다(Claude 실측·Codex 문서 모두 있다).
- 서브에이전트 대기 항목과 재수신 표시는 메모리에만 있다. `PreToolUse(Agent)`를 실시간으로 받은 직후 앱이 꺼지면 그 서브에이전트는 카드 없이 시작한다(파일은 부모 카드로 간다).
- 설치된 훅 스크립트가 옛 판이면 outbox 줄에 `prompt_id`·`turn_id`가 없다. 그동안 요청 재수신은 같은 문장 10초 기준으로 거른다.
- 블록 수신 확인은 스크립트가 블록을 출력한 뒤 확인 요청을 하나 더 보낸다. 앱은 서버 큐에서 바로 답하므로 `SessionStart`·늦은 주입 훅이 Dev Debug에서 중앙값 10~45 ms 늘어난다(curl 한 번). 확인을 잃거나 받아 둔 확인을 앱 재시작으로 잃으면(블록은 출력됨) 다음 프롬프트에 같은 블록을 한 번 더 받는다. 옛 판 스크립트는 응답 시간 초과 때 블록을 잃는다.
- 재개 시간은 앱이 볼 수 있는 복사→연결까지다. 실제 작업 재개는 관찰로 따로 잰다.
