#!/bin/bash
# install-local.sh·release-mac.sh에서 source한다. 버전·빌드 번호 규칙을 한 곳에 둔다(docs/RELEASE.md 「버전과 빌드 번호」).
#   빌드 번호 = 저장소 HEAD까지의 커밋 수(`git rev-list --count HEAD`). 커밋할 때마다 늘어서 새 빌드를 설치하면
#   앱이 store-version.json의 빌드가 바뀐 것을 보고 열기 전에 백업한다(TRK-46).
#   마케팅 버전 = project.yml의 MARKETING_VERSION(원본). 배포 스크립트의 --version이 있으면 그것으로 덮는다.

# 빌드 번호를 출력한다. git 저장소가 아니거나 커밋이 없으면 이유를 stderr에 쓰고 1.
waypoint_build_number() {
  local root="$1" count
  if ! count="$(git -C "$root" rev-list --count HEAD 2>/dev/null)" || [ -z "$count" ]; then
    echo "빌드 번호를 정할 수 없음: $root 가 커밋이 있는 git 저장소가 아님" >&2
    return 1
  fi
  echo "$count"
}

# project.yml의 MARKETING_VERSION을 출력한다(따옴표 제거). 없으면 1.
waypoint_marketing_version() {
  local root="$1" version
  version="$(sed -n -E 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' "$root/project.yml" | head -1)"
  if [ -z "$version" ]; then
    echo "project.yml에 MARKETING_VERSION이 없음" >&2
    return 1
  fi
  echo "$version"
}

# X.Y.Z(숫자 셋)인지 본다.
waypoint_valid_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
