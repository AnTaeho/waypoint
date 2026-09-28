# Waypoint — Claude 작업 지침

## 개요

Claude Code 세션을 프로젝트 단위로 추적하는 개인용 macOS + iOS 앱. 명세는 `docs/SPEC.md`, 순서는 `docs/MILESTONES.md`, 디자인은 `docs/DESIGN.md`.

## 절대 규칙

- 앱은 Anthropic API나 어떤 LLM API도 호출하지 않는다. 요약·추천·자동 분류 기능을 추가하지 않는다.
- 훅 스크립트는 Claude Code를 절대 막으면 안 된다: 타임아웃 1초, 실패해도 exit 0, stdout은 `SessionStart`에서만 사용.
- 카드를 자동으로 done 처리하지 않는다.
- 마일스톤 하나가 끝나면 멈추고 완료 조건 충족 여부를 보고한다.

## 개발 규칙: 평소용과 개발용

- 평소용 Waypoint(`/Applications/Waypoint.app`, 47821)는 개발 중 건드리지 않는다. 종료·교체·실측 금지, 새 버전은 `scripts/install-local.sh`로만.
- 개발·실측은 Waypoint Dev(Debug 빌드, 47822, `Waypoint-Dev/` 저장소)와 `scripts/dev-probe-setup.sh`로 이은 실측 폴더에서만. 절차는 `docs/DEVELOPMENT.md`.

## 스택

- Swift 6, SwiftUI, SwiftData, CloudKit. macOS 14+, iOS 17+.
- 외부 의존성은 필요할 때만, 추가 전 이유를 말하고 확인받는다.
- 로컬 서버는 Network.framework 기반을 우선 검토.

## 코드 스타일

- 모델·동기화·서버 로직은 `Shared/`, 화면은 플랫폼별 폴더.
- View 파일이 150줄을 넘으면 하위 View로 분리.
- 색·폰트·간격은 `DESIGN.md` 토큰을 코드 상수(`Theme`)로 한 곳에 정의하고 하드코딩하지 않는다.
- 한국어 UI 문구, 한국어 주석 허용.

## 테스트

- 파생 규칙(작업중·멈춤 판정, 상태 복귀)은 단위 테스트 필수.
- 훅 수신은 실제 Claude Code 훅 입력을 저장한 JSON 픽스처(`Tests/Fixtures/hooks/`)로 테스트.

## 확인이 필요한 외부 사항

Claude Code의 훅 이벤트 이름, 입력 필드, MCP 등록 명령, 서브에이전트 도구 이름은 버전에 따라 바뀔 수 있다. 구현 전 최신 문서를 확인하고, 다르면 `docs/SPEC.md`를 먼저 고친다.
