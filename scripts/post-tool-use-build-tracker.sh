#!/bin/bash
# .claude/hooks/post-tool-use-build-tracker.sh
# @harness-type: portable
#
# PostToolUse(Bash) 시 빌드/테스트 명령 실행 여부를 마커 파일에 기록
# stop-guard.sh에서 빌드 실행 여부 판단 근거로 활용
#
# 실행 시점: Claude가 Bash 도구 사용 직후
# 토큰 사용: 0T

set -euo pipefail

SESSION_ID="${CLAUDE_SESSION_ID:-default}"
BUILD_MARKER="/tmp/build-executed-${SESSION_ID}.log"

# stdin에서 tool use 정보 읽기
INPUT=$(cat /dev/stdin 2>/dev/null || echo "{}")

# Bash 도구의 command 추출
if command -v jq &>/dev/null; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
else
  COMMAND=$(echo "$INPUT" | node -e "
    const c=[]; process.stdin.on('data',d=>c.push(d));
    process.stdin.on('end',()=>{try{const d=JSON.parse(Buffer.concat(c).toString());
    process.stdout.write(d.tool_input?.command||'')}catch{process.stdout.write('')}})
  " 2>/dev/null || echo "")
fi

# 빌드/테스트 명령 감지 (다양한 패키지 매니저 지원)
if echo "$COMMAND" | grep -qE '(pnpm|npm|npx|yarn|bun)\s+(build|test|tsc|lint)'; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $COMMAND" >> "$BUILD_MARKER"

  # exit code로 빌드 실패 감지
  EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_output.exit_code // .tool_result.exit_code // "0"' 2>/dev/null || echo "0")
  ERROR_MARKER="/tmp/build-error-${SESSION_ID}.count"
  if [ "$EXIT_CODE" != "0" ]; then
    CURRENT=$(cat "$ERROR_MARKER" 2>/dev/null || echo "0")
    echo $((CURRENT + 1)) > "$ERROR_MARKER"
  else
    rm -f "$ERROR_MARKER"
  fi
fi

# Python 프로젝트용 빌드/테스트 명령 감지
if echo "$COMMAND" | grep -qE '(pytest|python -m pytest|uv run pytest|poetry run pytest|make test|make build)'; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $COMMAND" >> "$BUILD_MARKER"
fi

# 7일 이상 된 마커 파일 정리
find /tmp -name "build-executed-*.log" -mtime +7 -delete 2>/dev/null

exit 0
