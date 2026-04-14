#!/bin/bash
# .claude/hooks/stop-guard.sh
# @harness-type: portable
#
# Stop Hook (command): 코드 변경 시 build/test 실행 여부를 결정론적으로 검증
#
# 검증 항목:
#   1. 코드 변경 여부 (수정 파일 로그 존재)
#   2. 코드 변경 시 build/test 명령 실행 여부 (transcript 분석)
#
# 소스 코드 경로 판단:
#   epcc.config.json의 domains.sourceDir 참조하거나,
#   기본값으로 .ts/.tsx/.js/.jsx/.py 확장자를 가진 파일을 코드로 간주
#
# 실행 시점: Stop Hook (persistent-loop.sh 이후)
# 토큰 사용: 0T (통과) / ~50T (차단 시 additionalContext)

set -euo pipefail

# === stdin에서 세션 정보 읽기 ===
INPUT=$(cat /dev/stdin 2>/dev/null || echo "{}")

if command -v jq &>/dev/null; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .sessionId // "default"' 2>/dev/null || echo "default")
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .transcriptPath // ""' 2>/dev/null || echo "")
  USER_REQUESTED=$(echo "$INPUT" | jq -r '.user_requested // .userRequested // false' 2>/dev/null || echo "false")
  STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // .stopReason // ""' 2>/dev/null || echo "")
else
  SESSION_ID="default"
  TRANSCRIPT_PATH=""
  USER_REQUESTED="false"
  STOP_REASON=""
fi

# === 사용자 중단 → 무조건 허용 ===
if [ "$USER_REQUESTED" = "true" ]; then
  exit 0
fi

# === 컨텍스트 한계 → 허용 (데드락 방지) ===
if [ "$STOP_REASON" = "context_limit" ] || [ "$STOP_REASON" = "max_tokens" ]; then
  exit 0
fi

# === 수정 파일 로그 확인 ===
LOG_FILE="/tmp/modified-files-${SESSION_ID}.log"

# 수정 파일 로그가 없으면 → 코드 변경 없음 → 통과 (문서/분석/설정 작업)
if [ ! -f "$LOG_FILE" ]; then
  exit 0
fi

# 수정 파일 수 확인
MODIFIED_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ' || echo "0")

# 수정 파일 없으면 통과
if [ "$MODIFIED_COUNT" -eq 0 ]; then
  exit 0
fi

# === 코드 변경 존재: build/test 실행 여부 확인 ===
# epcc.config.json에서 소스 디렉토리 읽기 (없으면 확장자 기반 판단)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_PATH="${EPCC_CONFIG_PATH:-${PROJECT_ROOT}/epcc.config.json}"

SOURCE_DIR=""
BUILD_CMD=""
TEST_CMD=""

if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  SOURCE_DIR=$(jq -r '.domains.sourceDir // ""' "$CONFIG_PATH" 2>/dev/null || echo "")
  BUILD_CMD=$(jq -r '.techStack.commands.build // ""' "$CONFIG_PATH" 2>/dev/null || echo "")
  TEST_CMD=$(jq -r '.techStack.commands.test // ""' "$CONFIG_PATH" 2>/dev/null || echo "")
fi

# 소스 코드 변경인지 확인
SOURCE_CODE_CHANGED=false
while IFS='|' read -r _ filepath; do
  filepath=$(echo "$filepath" | sed 's/^ *//;s/ *$//')

  if [ -n "$SOURCE_DIR" ]; then
    # config에 소스 디렉토리가 있으면 해당 경로의 코드 파일만 체크
    if [[ "$filepath" =~ ^${SOURCE_DIR}/.+(\.ts|\.tsx|\.js|\.jsx|\.py|\.go|\.rs)$ ]]; then
      SOURCE_CODE_CHANGED=true
      break
    fi
  else
    # config 없으면 확장자 기반 판단 (일반적인 소스 코드 확장자)
    if [[ "$filepath" =~ \.(ts|tsx|js|jsx|py|go|rs|java|kt|swift|rb|php)$ ]]; then
      # 설정 파일 제외
      if [[ ! "$filepath" =~ (\.config\.|\.json$|\.yaml$|\.yml$|\.toml$|\.md$) ]]; then
        SOURCE_CODE_CHANGED=true
        break
      fi
    fi
  fi
done < "$LOG_FILE"

# 소스 코드 변경이 아니면 통과 (설정, 문서, 스킬 등)
if [ "$SOURCE_CODE_CHANGED" = false ]; then
  exit 0
fi

# === build/test 실행 여부 확인 ===
BUILD_TEST_RAN=false

# 빌드/테스트 명령 패턴 구성
BUILD_PATTERN="(build|test)"
if [ -n "$BUILD_CMD" ] || [ -n "$TEST_CMD" ]; then
  # config에서 읽은 명령어로 구체적 패턴 구성
  CMDS=""
  [ -n "$BUILD_CMD" ] && CMDS="$BUILD_CMD"
  [ -n "$TEST_CMD" ] && CMDS="${CMDS:+$CMDS|}$TEST_CMD"
  # 패키지 매니저 명령을 정규식 이스케이프 없이 간단하게 검색
  BUILD_PATTERN="(${CMDS}|build|test)"
fi

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  if tail -200 "$TRANSCRIPT_PATH" 2>/dev/null | grep -qE "$BUILD_PATTERN"; then
    BUILD_TEST_RAN=true
  fi
fi

# transcript 접근 불가 시 프로세스 히스토리 확인
if [ "$BUILD_TEST_RAN" = false ]; then
  if ps aux 2>/dev/null | grep -qE '[p]npm (build|test)|[n]pm run (build|test)|[u]v run|[p]ytest|[c]argo (build|test)'; then
    BUILD_TEST_RAN=true
  fi
fi

if [ "$BUILD_TEST_RAN" = false ]; then
  # 차단: build/test 미실행
  HINT=""
  if [ -n "$BUILD_CMD" ] && [ -n "$TEST_CMD" ]; then
    HINT="$BUILD_CMD && $TEST_CMD"
  else
    HINT="빌드 및 테스트 명령"
  fi

  if command -v jq &>/dev/null; then
    MODIFIED_LIST=$(tail -5 "$LOG_FILE" | awk -F'|' '{gsub(/^ +| +$/, "", $2); print "  - " $2}' | tr '\n' '\\' | sed 's/\\/\\n/g')
    jq -n --arg files "$MODIFIED_LIST" --argjson count "$MODIFIED_COUNT" --arg hint "$HINT" '{
      "decision": "block",
      "reason": ("소스 코드 " + ($count | tostring) + "개 파일 수정됨. " + $hint + " 실행이 필요합니다.\n\n수정된 파일 (최근 5개):\n" + $files)
    }'
  else
    echo "{\"decision\":\"block\",\"reason\":\"소스 코드 수정 후 빌드 및 테스트를 실행하세요.\"}"
  fi
  exit 0
fi

# === 모든 검증 통과 ===
exit 0
