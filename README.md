# Waypoint — Claude Code 핸드오프 패키지

Claude Code 세션을 프로젝트 단위로 추적하는 개인용 Apple 앱(macOS + iOS)의 구현 인수인계 자료.

## 사용법

1. 새 저장소를 만들고 이 폴더 내용을 루트에 복사한다 (`CLAUDE.md`가 루트에 오도록).
2. 저장소 폴더에서 `claude` 실행 후 이렇게 시작한다:

   > `docs/SPEC.md`와 `docs/MILESTONES.md`를 읽고 M0부터 진행해줘. 각 마일스톤 끝나면 멈추고 확인받아.

3. 디자인 시안 원본(캔버스): https://claude.ai/artifact/G9JsAmHhuKb1ZLeRdoroGM

## 구성

| 경로 | 내용 |
|---|---|
| `CLAUDE.md` | 이 저장소에서 Claude Code가 따를 작업 지침 |
| `docs/SPEC.md` | 제품 정의, 아키텍처, 데이터 모델, 로컬 API·MCP 도구 명세 |
| `docs/MILESTONES.md` | 구현 순서와 각 단계의 완료 조건 |
| `docs/DESIGN.md` | 디자인 토큰, 화면 목록, 시안 파일 읽는 법 |
| `design/*.dc.html` | 시안 화면 마크업 (레이아웃·색·문구 참고용, 단독 렌더링 안 됨) |
| `integration/skills/tracker/SKILL.md` | 사용자의 모든 프로젝트에서 쓸 tracker 스킬 초안 |
| `integration/hooks/` | Claude Code 훅 설정 예시와 훅 스크립트 |
| `integration/statusline/` | 상태줄 입력의 사용량을 `usage.json`으로 남기는 중계 스크립트와 테스트 |

## 핵심 원칙 (한 줄 요약)

- 세션이 아니라 **프로젝트** 기준으로 "작업중"을 보여준다.
- 기록은 사용자가 이미 쓰는 Claude Code 세션 안에서 훅과 스킬이 남긴다. **앱은 Anthropic API를 호출하지 않는다** (크레딧 사용 없음).
- 지침 문서(CLAUDE.md 등)는 앱과 로컬 파일이 양방향 동기화된다. Claude가 수정을 제안하는 기능은 없다.
