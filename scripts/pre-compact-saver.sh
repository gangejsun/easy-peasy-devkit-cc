#!/bin/bash
# scripts/pre-compact-saver.sh
# @harness-type: portable
#
# PreCompact Hook: 컨텍스트 컴팩트 전에 진행 중인 작업 상태를 요약하여
# 컴팩트 후에도 작업 연속성을 보장
#
# 작동 원리:
#   1. dev/active/ 디렉토리에서 진행 중인 작업 탐지
#   2. tasks.md에서 미완료/완료 태스크 파싱
#   3. 최근 수정 파일 목록 확인
#   4. 요약을 stdout으로 출력 → 컴팩트 후에도 컨텍스트에 유지
#
# 실행 시점: 컨텍스트 컴팩트 직전
# 토큰 사용: ~100-200T (작업 존재 시) / 0T (작업 없을 시)

set -euo pipefail

# Runtime plugin: PROJECT_ROOT = pwd
PROJECT_ROOT="$(pwd)"
DEV_ACTIVE="$PROJECT_ROOT/dev/active"

# === dev/active 가 없거나 비어있으면 출력 없이 종료 (0T) ===
if [ ! -d "$DEV_ACTIVE" ]; then
  exit 0
fi

TASK_DIRS=$(find "$DEV_ACTIVE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
if [ -z "$TASK_DIRS" ]; then
  exit 0
fi

# === stdin에서 세션 정보 읽기 ===
INPUT=$(cat /dev/stdin 2>/dev/null || echo "{}")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .sessionId // "default"' 2>/dev/null || echo "default")

# === 작업 상태 수집 ===
OUTPUT="## 컴팩트 전 작업 상태 보존\n"
OUTPUT="${OUTPUT}(이 정보는 PreCompact Hook에 의해 자동 생성되었습니다)\n\n"

for TASK_DIR in $TASK_DIRS; do
  TASK_NAME=$(basename "$TASK_DIR")
  OUTPUT="${OUTPUT}### 작업: ${TASK_NAME}\n"

  # --- tasks.md 파싱 ---
  TASKS_FILE=$(find "$TASK_DIR" -name "*tasks*" -type f 2>/dev/null | head -1)
  if [ -n "$TASKS_FILE" ] && [ -f "$TASKS_FILE" ]; then
    TOTAL=$(grep -c '\- \[.\]' "$TASKS_FILE" 2>/dev/null || echo "0")
    COMPLETED=$(grep -c '\- \[x\]' "$TASKS_FILE" 2>/dev/null || echo "0")
    INCOMPLETE=$(grep -c '\- \[ \]' "$TASKS_FILE" 2>/dev/null || echo "0")

    OUTPUT="${OUTPUT}- 진행률: ${COMPLETED}/${TOTAL} 완료\n"

    # 미완료 태스크 목록 (최대 5개)
    if [ "$INCOMPLETE" -gt 0 ]; then
      OUTPUT="${OUTPUT}- 남은 태스크:\n"
      REMAINING=$(grep '\- \[ \]' "$TASKS_FILE" 2>/dev/null | head -5 | sed 's/^/  /g')
      OUTPUT="${OUTPUT}${REMAINING}\n"
    fi

    OUTPUT="${OUTPUT}- tasks 파일: ${TASKS_FILE#$PROJECT_ROOT/}\n"
  fi

  # --- context.md에서 현재 Phase 추론 ---
  CONTEXT_FILE=$(find "$TASK_DIR" -name "*context*" -type f 2>/dev/null | head -1)
  if [ -n "$CONTEXT_FILE" ] && [ -f "$CONTEXT_FILE" ]; then
    # SESSION PROGRESS 섹션에서 마지막 상태 추출
    LAST_PROGRESS=$(grep -E '(P[0-9]|Phase|진행|완료|구현)' "$CONTEXT_FILE" 2>/dev/null | tail -1 || echo "")
    if [ -n "$LAST_PROGRESS" ]; then
      OUTPUT="${OUTPUT}- 최근 진행: ${LAST_PROGRESS}\n"
    fi
    OUTPUT="${OUTPUT}- context 파일: ${CONTEXT_FILE#$PROJECT_ROOT/}\n"
  fi

  # --- plan.md 경로 ---
  PLAN_FILE=$(find "$TASK_DIR" -name "*plan*" -type f 2>/dev/null | head -1)
  if [ -n "$PLAN_FILE" ] && [ -f "$PLAN_FILE" ]; then
    OUTPUT="${OUTPUT}- plan 파일: ${PLAN_FILE#$PROJECT_ROOT/}\n"
  fi

  OUTPUT="${OUTPUT}\n"
done

# --- 최근 수정 파일 (post-tool-use-tracker 로그에서) ---
READ_LOG="/tmp/modified-files-${SESSION_ID}.log"
if [ -f "$READ_LOG" ]; then
  RECENT_FILES=$(tail -5 "$READ_LOG" 2>/dev/null | awk -F' \| ' '{print $2}' | sed "s|$PROJECT_ROOT/||g")
  if [ -n "$RECENT_FILES" ]; then
    OUTPUT="${OUTPUT}### 최근 수정 파일\n"
    while IFS= read -r f; do
      OUTPUT="${OUTPUT}- ${f}\n"
    done <<< "$RECENT_FILES"
    OUTPUT="${OUTPUT}\n"
  fi
fi

# --- Loop 상태 ---
LOOP_STATE="/tmp/epc-loop-${SESSION_ID}.json"
if [ -f "$LOOP_STATE" ]; then
  LOOP_ITER=$(jq -r '.iteration // 0' "$LOOP_STATE" 2>/dev/null || echo "0")
  OUTPUT="${OUTPUT}### Loop 상태\n"
  OUTPUT="${OUTPUT}- Persistent Loop 활성 (반복 ${LOOP_ITER}회)\n"
  OUTPUT="${OUTPUT}- 종료: \"loop stop\" 입력\n\n"
fi

OUTPUT="${OUTPUT}---\n위 파일들을 참조하여 작업을 이어서 진행하세요."

# === stdout으로 출력 (컴팩트 후에도 유지됨) ===
echo -e "$OUTPUT"

exit 0
