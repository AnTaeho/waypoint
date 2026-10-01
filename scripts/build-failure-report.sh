#!/bin/bash
# install-local.sh에서 source한다. 로그 끝의 직접 오류를 우선하고 전체 로그는 유지한다.
report_build_failure() {
  local build_log="$1"
  if [ ! -r "$build_log" ]; then
    echo "빌드 로그를 읽을 수 없음: $build_log" >&2
    return
  fi
  awk '
    /(^|[[:space:]])error: |fatal error:|Operation not permitted|Permission denied|Read-only file system/ {
      errors[++count] = $0
    }
    { tail[NR % 12] = $0 }
    END {
      if (count) {
        print "마지막 빌드 오류:"
        first = count > 12 ? count - 11 : 1
        for (i = first; i <= count; i++) print errors[i]
      } else {
        print "직접 오류 문구가 없어 로그 마지막 부분을 표시합니다:"
        first = NR > 12 ? NR - 11 : 1
        for (i = first; i <= NR; i++) print tail[i % 12]
      }
    }
  ' "$build_log" >&2
  if grep -Eq 'Operation not permitted|Permission denied|Read-only file system' "$build_log"; then
    echo "로그에 파일 접근 거부가 있습니다. 실행 환경의 sandbox와 해당 경로의 쓰기 권한을 확인하세요." >&2
    echo "Codex에서 실행했다면 설치 명령에 필요한 권한 승인을 받은 뒤 다시 실행하세요." >&2
  fi
}
