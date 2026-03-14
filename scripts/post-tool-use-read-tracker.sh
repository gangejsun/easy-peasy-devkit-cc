#!/bin/bash
# scripts/post-tool-use-read-tracker.sh
# @harness-type: portable
# PostToolUse(Read) 시 읽은 파일을 추적 기록
# pre-tool-use-guard.mjs의 도메인 패턴 체크에서 참조
#
# 실행 시점: Claude가 Read 도구 사용 직후
# 토큰 사용: 0T

set -euo pipefail

SESSION_ID="${CLAUDE_SESSION_ID:-default}"
LOG_FILE="/tmp/read-files-${SESSION_ID}.log"

# stdin에서 tool use 정보 읽기
INPUT=$(cat /dev/stdin 2>/dev/null)

# tool_input.file_path 추출
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

if [ -n "$FILE_PATH" ]; then
  # 상대 경로로 정규화
  # Runtime plugin: PROJECT_ROOT = pwd
  PROJECT_ROOT="$(pwd)"
  REL_PATH="${FILE_PATH#$PROJECT_ROOT/}"

  echo "$(date '+%Y-%m-%d %H:%M:%S') | $REL_PATH" >> "$LOG_FILE"
fi

# 7일 이상 된 로그 파일 정리
find /tmp -name "read-files-*.log" -mtime +7 -delete 2>/dev/null

exit 0
