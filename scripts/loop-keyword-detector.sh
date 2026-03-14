#!/bin/bash
# scripts/loop-keyword-detector.sh
# @harness-type: portable
#
# UserPromptSubmit Hook: "loop start" / "loop stop" 키워드를 감지하여
# Persistent Loop 상태 파일을 생성/삭제
#
# 설계 원칙:
#   - 키워드를 최소화 (2개만) → 오탐 리스크 거의 0
#   - 스킬 라우팅은 기존 `/` 명령 체계를 그대로 유지
#   - "loop start"는 일반 대화에서 우연히 나올 확률이 극히 낮음
#
# 실행 시점: 사용자가 프롬프트 제출 시
# 토큰 사용: 0T (키워드 미감지) / ~30T (additionalContext)

set -euo pipefail

# === stdin에서 프롬프트 읽기 ===
INPUT=$(cat /dev/stdin 2>/dev/null || echo "{}")

# 세션 ID 추출
if command -v jq &>/dev/null; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .sessionId // "default"' 2>/dev/null || echo "default")
  PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || echo "")
else
  SESSION_ID="default"
  PROMPT=""
fi

# 프롬프트가 비어있으면 종료
if [ -z "$PROMPT" ]; then
  exit 0
fi

# === 상태 파일 경로 ===
STATE_FILE="/tmp/epc-loop-${SESSION_ID}.json"
# Runtime plugin: PROJECT_ROOT = pwd
PROJECT_ROOT="$(pwd)"

# === 소문자 변환 후 키워드 감지 ===
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# --- "loop stop" / "loop end" / "루프 종료" / "루프 중지" 감지 ---
if echo "$PROMPT_LOWER" | grep -qE '(loop\s*(stop|end|cancel|off))|(루프\s*(종료|중지|끝|취소))'; then
  if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
    # 종료 알림
    if command -v jq &>/dev/null; then
      jq -n '{
        "hookSpecificOutput": {
          "hookEventName": "UserPromptSubmit",
          "additionalContext": "[Loop 비활성화] Persistent Loop이 종료되었습니다. 이후부터 일반 모드로 동작합니다."
        }
      }'
    fi
  fi
  exit 0
fi

# --- "loop start" / "loop on" / "루프 시작" 감지 ---
if echo "$PROMPT_LOWER" | grep -qE '(loop\s*(start|on|begin))|(루프\s*(시작|켜|활성화))'; then
  NOW_ISO=$(date -u "+%Y-%m-%dT%H:%M:%S.000Z")

  # dev/active 에서 현재 작업 디렉토리 탐색
  ACTIVE_TASK_DIR=""
  if [ -d "$PROJECT_ROOT/dev/active" ]; then
    FIRST_DIR=$(find "$PROJECT_ROOT/dev/active" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
    if [ -n "$FIRST_DIR" ]; then
      ACTIVE_TASK_DIR="dev/active/$(basename "$FIRST_DIR")"
    fi
  fi

  # 상태 파일 생성
  if command -v jq &>/dev/null; then
    jq -n \
      --arg sid "$SESSION_ID" \
      --arg now "$NOW_ISO" \
      --arg dir "$ACTIVE_TASK_DIR" \
      '{
        "active": true,
        "session_id": $sid,
        "started_at": $now,
        "last_activity": $now,
        "iteration": 0,
        "error_count": 0,
        "active_task_dir": $dir
      }' > "$STATE_FILE"
  else
    cat > "$STATE_FILE" <<STATEJSON
{
  "active": true,
  "session_id": "$SESSION_ID",
  "started_at": "$NOW_ISO",
  "last_activity": "$NOW_ISO",
  "iteration": 0,
  "error_count": 0,
  "active_task_dir": "$ACTIVE_TASK_DIR"
}
STATEJSON
  fi

  # 활성화 알림
  TASK_INFO=""
  if [ -n "$ACTIVE_TASK_DIR" ]; then
    TASK_INFO="\n연동 작업: ${ACTIVE_TASK_DIR}"
  fi

  if command -v jq &>/dev/null; then
    jq -n --arg info "$TASK_INFO" '{
      "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": ("[Loop 활성화] Persistent Loop이 시작되었습니다. dev/active/의 tasks.md가 모두 완료될 때까지 자동으로 계속합니다.\n종료: \"loop stop\" 입력" + $info)
      }
    }'
  fi
  exit 0
fi

# === 키워드 미감지 → 아무것도 하지 않음 (0T) ===
exit 0
