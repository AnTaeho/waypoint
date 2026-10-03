# SSH 원격·개발 컨테이너에서 쓰기 (TRK-53)

Mac에서 Waypoint가 켜져 있고, Claude Code·Codex는 SSH로 접속한 리눅스 서버나 개발 컨테이너 안에서 도는 경우. 원격 세션의 훅이 Mac 앱에 닿게 하고, 원격 폴더를 같은 git 저장소의 등록 프로젝트에 잇는다. 동작 규칙은 [`SPEC.md`](SPEC.md) 「원격·컨테이너 수집」, 실측은 [`RELIABILITY.md`](RELIABILITY.md) 「원격·컨테이너 (TRK-53)」.

## 무엇이 이어지나

- 원격 폴더는 Mac에 없으므로 경로로는 등록 프로젝트를 찾지 못한다. 대신 훅이 그 폴더의 git `origin` 주소를 함께 보내고, 앱은 **같은 `origin`을 가진 등록 프로젝트**에 세션을 잇는다. `git@github.com:me/app.git`과 `https://github.com/me/app`은 같은 주소로 본다.
- 그래서 Mac의 등록 폴더와 원격 폴더가 같은 저장소의 클론이어야 한다. 원격 주소가 같은 등록 폴더가 서로 다른 클론으로 둘 이상이면 잇지 않는다(어느 쪽인지 모른다).
- 파일 변경은 원격 작업 트리 최상위 기준 상대 경로로 남는다(`/home/me/app/src/a.swift` → `src/a.swift`). 세션의 폴더·브랜치는 원격 값이다.
- 앱에 닿지 못하는 동안(터널이 끊김, Mac이 잠듦)의 기록은 원격의 outbox에 쌓였다가, 다음에 훅이 앱에 닿을 때 뒤에서 한 번에 최대 500줄씩 들어간다. 훅은 그 전송을 기다리지 않는다. 쌓인 기록이 있는 동안의 새 기록은 순서를 지키려고 그 뒤에 선다. 수백 줄이면 앱이 다 들이기까지 몇 분 걸릴 수 있다.

## SSH 원격

Mac 쪽: Waypoint 앱이 이 기능이 들어간 버전이어야 한다(옛 앱은 원격 주소를 모르고 쌓인 기록을 받지 않는다). SSH는 비밀번호 없이 접속돼야 한다(`BatchMode` — 암호가 걸린 키는 `ssh-agent`에 올려 둔다). `swift`(Xcode 명령행 도구)가 있어야 한다(설치기를 빌드한다).

원격 요구: `bash`, `curl` 7.84 이상(그보다 낮으면 시작 블록 수신 확인을 보내지 못해 블록이 다음 요청에 한 번 더 붙을 수 있다), `tar`. `jq`가 있으면 앱에 못 닿는 동안의 기록을 줄여서 남긴다(없으면 세션·폴더만 남는다). `git` 명령은 필요 없다.

1. Mac에서 설정 도우미를 돌린다.

   ```sh
   scripts/remote-setup.sh myserver            # 평소용(47821)
   scripts/remote-setup.sh --dry-run myserver  # 바뀔 파일만 보기
   ```

   원격의 `~/.claude/settings.json`·`~/.claude/waypoint/`·tracker 스킬(`~/.codex/`가 있으면 Codex 설정도)을 받아 앱과 같은 설치기로 고친 뒤 되돌려 놓는다. 바뀌기 전 원격 파일은 원격 `~/.waypoint-backups/<시각>.tgz`에 먼저 묶어 둔다. 원격에 `claude`가 있으면 MCP를 `http://127.0.0.1:47821/mcp`로 등록하고, 없으면 원격에서 칠 명령을 보여 준다. 여러 번 돌려도 된다.

2. 출력된 한 줄을 Mac의 `~/.ssh/config`에 넣는다(도우미는 이 파일을 고치지 않는다).

   ```
   Host myserver
       RemoteForward 47821 127.0.0.1:47821
   ```

   한 번만 쓸 때는 `ssh -R 47821:127.0.0.1:47821 myserver`. 원격의 `127.0.0.1:47821`이 Mac 앱으로 이어지므로 훅·MCP 주소는 로컬과 같다.

3. 원격에서 Claude Code를 연다. 시작 블록이 `Waypoint: <키> (…)`로 시작하면 이어진 것이다. `Waypoint: 이 폴더는 Waypoint에 없음`과 `remote: <주소>` 줄이 보이면 같은 원격 주소의 등록 프로젝트가 없거나 둘 이상이다.

되돌리기: 원격에서 `tar xzf ~/.waypoint-backups/<시각>.tgz -C ~`, MCP는 `claude mcp remove waypoint -s user`. 원격의 쌓인 기록은 `~/.local/state/waypoint/`(설치기가 Dev로 이었다면 `~/Library/Application Support/Waypoint-Dev/`).

## 개발 컨테이너

Docker Desktop의 `host.docker.internal`은 Mac의 `127.0.0.1`에만 열린 앱 서버에도 닿는다(2026-10-03 실측, Docker 29.6). 앱 서버를 다른 인터페이스로 열 필요가 없다. 훅에 앱 주소만 알려 주면 된다.

`.devcontainer/devcontainer.json` 예:

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu-24.04",
  "containerEnv": {
    // 훅이 Mac 앱으로 보낸다. 있으면 원격 모드(원격 주소 붙이기·쌓인 기록 다시 보내기)도 켜진다
    "WAYPOINT_URL": "http://host.docker.internal:47821"
  },
  "mounts": [
    // Mac에 설치된 훅 스크립트를 그대로 쓴다(읽기 전용, 앱이 갱신하면 따라온다). 이 기능 전의 스크립트는 WAYPOINT_URL을 모른다 —
    // Mac 앱의 연결 설정으로 스크립트를 새로 깔았는지 먼저 확인하거나, 저장소의 integration/hooks/waypoint-hook.sh를 넣는다
    "source=${localEnv:HOME}/.claude/waypoint,target=/home/vscode/.claude/waypoint,type=bind,readonly"
  ],
  // 컨테이너의 Claude Code에 훅과 MCP를 잇는다(사용자 설정이 이미 있으면 두고, MCP 등록은 claude가 있을 때만)
  "postCreateCommand": "mkdir -p ~/.claude && ([ -f ~/.claude/settings.json ] || cp .devcontainer/waypoint-settings.json ~/.claude/settings.json) && (command -v claude >/dev/null && claude mcp add --transport http --scope user waypoint http://host.docker.internal:47821/mcp || true)"
}
```

`.devcontainer/waypoint-settings.json`은 `integration/hooks/settings.example.json`에서 `_comment`만 뺀 것이다. 컨테이너에 이미 `~/.claude/settings.json`이 있으면 그 파일의 `hooks`에 같은 항목을 합친다.

- 컨테이너 안 저장소의 `origin`이 Mac 등록 폴더의 `origin`과 같아야 이어진다(보통 같은 저장소를 열면 같다).
- 컨테이너 안 쌓인 기록은 `~/.local/state/waypoint/`. 컨테이너를 지우면 같이 사라진다(앱이 꺼진 채로 컨테이너를 지우면 그동안의 기록은 잃는다).
- Docker Desktop만 확인했다. Colima·OrbStack 같은 다른 런타임은 `host.docker.internal`이 Mac 루프백에 닿는지 확인하지 않았다.

## 지원하지 않는 것

- 웹·클라우드에서 도는 세션(claude.ai의 Claude Code, Codex 클라우드): Mac 앱에 닿을 길이 없다. 방식은 아직 정하지 않았다.
- 원격 사용량 게이지: 상태줄 중계는 설치되지만 Mac의 사용량 게이지에는 들어가지 않는다.
