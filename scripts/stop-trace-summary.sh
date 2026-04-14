#!/bin/bash
# .claude/hooks/stop-trace-summary.sh
# @harness-type: portable
#
# Stop Hook: 실행 추적(CLAUDE_EXECUTION_TRACE=on) 활성 시 세션 요약 자동 출력
#
# 기존 PostToolUse 훅들이 기록한 /tmp/ 로그를 읽어
# 파일 수준 요약 + 하네스 참조(Rules/Skills/Hooks) 분류를 생성
#
# 토큰 사용: 0T (OFF) / ~80T (ON, additionalContext)

set -euo pipefail

# === 토글 확인: OFF면 즉시 종료 (0T) ===
if [ "${CLAUDE_EXECUTION_TRACE:-off}" != "on" ]; then
  exit 0
fi

# === stdin에서 세션 정보 읽기 ===
INPUT=$(cat /dev/stdin 2>/dev/null || echo "{}")

if command -v jq &>/dev/null; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .sessionId // "default"' 2>/dev/null || echo "default")
else
  SESSION_ID="${CLAUDE_SESSION_ID:-default}"
fi

# === 로그 파일 경로 ===
MODIFIED_LOG="/tmp/modified-files-${SESSION_ID}.log"
READ_LOG="/tmp/read-files-${SESSION_ID}.log"
BUILD_LOG="/tmp/build-executed-${SESSION_ID}.log"

# === 카운트 집계 ===
MOD_COUNT=0; READ_COUNT=0; BUILD_COUNT=0
[ -f "$MODIFIED_LOG" ] && MOD_COUNT=$(wc -l < "$MODIFIED_LOG" | tr -d ' ')
[ -f "$READ_LOG" ] && READ_COUNT=$(wc -l < "$READ_LOG" | tr -d ' ')
[ -f "$BUILD_LOG" ] && BUILD_COUNT=$(wc -l < "$BUILD_LOG" | tr -d ' ')

# 아무 활동 없으면 종료
if [ "$MOD_COUNT" -eq 0 ] && [ "$READ_COUNT" -eq 0 ] && [ "$BUILD_COUNT" -eq 0 ]; then
  exit 0
fi

# === 하네스 참조 분류 (read-files 로그에서 경로 패턴 추출) ===
RULES_LIST=""
SKILLS_LIST=""
HOOKS_LIST=""

if [ -f "$READ_LOG" ]; then
  RULES_LIST=$(awk -F' \\| ' '{print $2}' "$READ_LOG" | grep -o '\.claude/rules/[^/]*\.md' | sort -u | sed 's|\.claude/rules/||' | head -10 || true)
  SKILLS_LIST=$(awk -F' \\| ' '{print $2}' "$READ_LOG" | grep -o '\.claude/skills/[^/]*' | sort -u | sed 's|\.claude/skills/||' | head -10 || true)
  HOOKS_LIST=$(awk -F' \\| ' '{print $2}' "$READ_LOG" | grep -o '\.claude/hooks/[^/]*\.sh' | sort -u | sed 's|\.claude/hooks/||' | head -10 || true)
fi

RULES_COUNT=0; SKILLS_COUNT=0; HOOKS_COUNT=0
[ -n "$RULES_LIST" ] && RULES_COUNT=$(echo "$RULES_LIST" | wc -l | tr -d ' ')
[ -n "$SKILLS_LIST" ] && SKILLS_COUNT=$(echo "$SKILLS_LIST" | wc -l | tr -d ' ')
[ -n "$HOOKS_LIST" ] && HOOKS_COUNT=$(echo "$HOOKS_LIST" | wc -l | tr -d ' ')

# === 요약 생성 ===
SUMMARY="## 세션 실행 추적 요약\n"
SUMMARY="${SUMMARY}- 수정 파일: ${MOD_COUNT}개 | 읽은 파일: ${READ_COUNT}개 | 빌드/테스트: ${BUILD_COUNT}회\n"

if [ "$RULES_COUNT" -gt 0 ] || [ "$SKILLS_COUNT" -gt 0 ] || [ "$HOOKS_COUNT" -gt 0 ]; then
  SUMMARY="${SUMMARY}\n### 하네스 참조\n"
  if [ "$RULES_COUNT" -gt 0 ]; then
    FORMATTED_RULES=$(echo "$RULES_LIST" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
    SUMMARY="${SUMMARY}- Rules: ${FORMATTED_RULES} (${RULES_COUNT}개)\n"
  fi
  if [ "$SKILLS_COUNT" -gt 0 ]; then
    FORMATTED_SKILLS=$(echo "$SKILLS_LIST" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
    SUMMARY="${SUMMARY}- Skills: ${FORMATTED_SKILLS} (${SKILLS_COUNT}개)\n"
  fi
  if [ "$HOOKS_COUNT" -gt 0 ]; then
    FORMATTED_HOOKS=$(echo "$HOOKS_LIST" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
    SUMMARY="${SUMMARY}- Hooks: ${FORMATTED_HOOKS} (${HOOKS_COUNT}개)\n"
  fi
fi

if [ "$MOD_COUNT" -gt 0 ]; then
  SUMMARY="${SUMMARY}\n### 최근 수정 파일 (최대 5개)\n"
  RECENT_MOD=$(tail -5 "$MODIFIED_LOG" | awk -F' \\| ' '{gsub(/^ +| +$/, "", $2); print "- " $2}')
  SUMMARY="${SUMMARY}${RECENT_MOD}\n"
fi

SUMMARY="${SUMMARY}\n> 전체 시맨틱 분석은 \`/execution-dashboard\`를 호출하세요."

# === additionalContext로 출력 ===
if command -v jq &>/dev/null; then
  jq -n --arg summary "$(echo -e "$SUMMARY")" '{
    "additionalContext": $summary
  }'
else
  echo "{\"additionalContext\": \"실행 추적 요약: 수정 ${MOD_COUNT}개, 읽기 ${READ_COUNT}개, 빌드 ${BUILD_COUNT}회\"}"
fi

exit 0
