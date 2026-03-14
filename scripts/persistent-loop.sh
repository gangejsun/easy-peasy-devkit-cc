#!/bin/bash
# scripts/persistent-loop.sh
# @harness-type: portable
#
# Stop Hook: Large 작업 시 Claude가 중간에 멈추지 않고 완주하도록 루프 유지
#
# 작동 원리:
#   1. UserPromptSubmit Hook(loop-keyword-detector.sh)이 상태 파일 생성
#   2. Claude가 작업 후 멈추려 할 때 이 Hook이 실행
#   3. dev/active/*/tasks.md에서 미완료 태스크 확인
#   4. 미완료 존재 시 { "continue": false } 반환 → Claude가 계속 작업
#   5. 모두 완료 시 상태 파일 삭제 → 루프 종료
#
# 안전 장치:
#   - 사용자 중단 (Ctrl+C) → 무조건 허용
#   - 2시간 비활성 → 부활 상태 판정, 차단 안 함
#   - 동일 에러 5회+ → 대안 접근 방식 제안
#   - 최대 반복 50회 → 경고 후 사용자 확인 유도
#
# 실행 시점: Stop Hook (command 타입, prompt Hook보다 먼저 실행)
# 토큰 사용: 0T (루프 미활성 시) / ~100T (continue 메시지)

set -euo pipefail

# === 상수 ===
STALENESS_THRESHOLD=7200  # 2시간 (초)
MAX_ITERATIONS=50
ERROR_RETRY_LIMIT=5

# === stdin에서 세션 정보 읽기 ===
INPUT=$(cat /dev/stdin 2>/dev/null || echo "{}")

# jq가 없으면 node 사용
if command -v jq &>/dev/null; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .sessionId // "default"' 2>/dev/null || echo "default")
  STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // .stopReason // ""' 2>/dev/null || echo "")
  USER_REQUESTED=$(echo "$INPUT" | jq -r '.user_requested // .userRequested // false' 2>/dev/null || echo "false")
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .transcriptPath // ""' 2>/dev/null || echo "")
else
  SESSION_ID=$(echo "$INPUT" | node -e "
    const c=[]; process.stdin.on('data',d=>c.push(d));
    process.stdin.on('end',()=>{try{const d=JSON.parse(Buffer.concat(c).toString());
    process.stdout.write(d.session_id||d.sessionId||'default')}catch{process.stdout.write('default')}})
  " 2>/dev/null || echo "default")
  STOP_REASON="unknown"
  USER_REQUESTED="false"
  TRANSCRIPT_PATH=""
fi

# === 상태 파일 경로 ===
STATE_FILE="/tmp/epc-loop-${SESSION_ID}.json"

# === 루프 미활성 시 즉시 종료 ===
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# === 안전 장치 1: 사용자 중단 → 무조건 허용 ===
if [ "$USER_REQUESTED" = "true" ]; then
  # 사용자가 명시적으로 중단 → 루프 상태 파일 삭제하고 허용
  rm -f "$STATE_FILE"
  exit 0
fi

# === 상태 파일 읽기 ===
if command -v jq &>/dev/null; then
  STARTED_AT=$(jq -r '.started_at // ""' "$STATE_FILE" 2>/dev/null || echo "")
  LAST_ACTIVITY=$(jq -r '.last_activity // ""' "$STATE_FILE" 2>/dev/null || echo "")
  ITERATION=$(jq -r '.iteration // 0' "$STATE_FILE" 2>/dev/null || echo "0")
  ERROR_COUNT=$(jq -r '.error_count // 0' "$STATE_FILE" 2>/dev/null || echo "0")
  ACTIVE_TASK_DIR=$(jq -r '.active_task_dir // ""' "$STATE_FILE" 2>/dev/null || echo "")
else
  ITERATION=0
  ERROR_COUNT=0
  STARTED_AT=""
  LAST_ACTIVITY=""
  ACTIVE_TASK_DIR=""
fi

# === 안전 장치 2: 비활성 감지 (2시간) ===
if [ -n "$LAST_ACTIVITY" ]; then
  LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST_ACTIVITY%%.*}" "+%s" 2>/dev/null || echo "0")
  NOW_EPOCH=$(date "+%s")
  ELAPSED=$((NOW_EPOCH - LAST_EPOCH))

  if [ "$ELAPSED" -gt "$STALENESS_THRESHOLD" ]; then
    # 2시간 이상 비활성 → 이전 세션의 잔여 상태로 판정, 차단 안 함
    rm -f "$STATE_FILE"
    exit 0
  fi
fi

# === 안전 장치 3: 컨텍스트 한계 감지 ===
if [ "$STOP_REASON" = "context_limit" ] || [ "$STOP_REASON" = "max_tokens" ]; then
  # 컨텍스트 한계 도달 → 컴팩트 데드락 방지를 위해 무조건 허용
  # (단, 상태 파일은 유지 → 컴팩트 후 루프 재개)
  exit 0
fi

# === dev/active 에서 미완료 태스크 확인 ===
# Runtime plugin: PROJECT_ROOT = pwd (사용자 프로젝트)
PROJECT_ROOT="$(pwd)"
INCOMPLETE_TASKS=0
INCOMPLETE_LIST=""
TASKS_FILE=""

# 특정 태스크 디렉토리가 지정된 경우
if [ -n "$ACTIVE_TASK_DIR" ] && [ -d "$PROJECT_ROOT/$ACTIVE_TASK_DIR" ]; then
  TASKS_FILE=$(find "$PROJECT_ROOT/$ACTIVE_TASK_DIR" -name "*tasks*" -type f 2>/dev/null | head -1)
fi

# 지정 안 된 경우 dev/active 전체 검색
if [ -z "$TASKS_FILE" ]; then
  TASKS_FILE=$(find "$PROJECT_ROOT/dev/active" -name "*tasks*" -type f 2>/dev/null | head -1)
fi

if [ -n "$TASKS_FILE" ] && [ -f "$TASKS_FILE" ]; then
  # 체크박스 미완료 [ ] 카운트 (- [ ] 형식)
  INCOMPLETE_TASKS=$(grep -c '\- \[ \]' "$TASKS_FILE" 2>/dev/null || echo "0")
  # 미완료 태스크 목록 (최대 5개)
  INCOMPLETE_LIST=$(grep '\- \[ \]' "$TASKS_FILE" 2>/dev/null | head -5 | sed 's/- \[ \] /  - /g' || echo "")
fi

# === 모든 태스크 완료 → 루프 종료 ===
if [ "$INCOMPLETE_TASKS" -eq 0 ]; then
  rm -f "$STATE_FILE"

  # dev/active/ 디렉토리 존재 여부로 P5 안내 결정
  ACTIVE_DIR_EXISTS="false"
  if [ -d "$PROJECT_ROOT/dev/active" ] && [ "$(ls -A "$PROJECT_ROOT/dev/active" 2>/dev/null)" ]; then
    ACTIVE_DIR_EXISTS="true"
  fi

  if [ "$ACTIVE_DIR_EXISTS" = "true" ]; then
    COMPLETION_MSG="[Loop 완료] 모든 태스크가 완료되었습니다. 루프를 종료합니다.\n\n[P5 검증 안내] dev/active/ 에 작업 문서가 있습니다. review-agent를 호출하여 코드 리뷰 및 문서 최신화(P5)를 진행하세요."
  else
    COMPLETION_MSG="[Loop 완료] 모든 태스크가 완료되었습니다. 루프를 종료합니다."
  fi

  # 완료 메시지를 additionalContext로 전달
  if command -v jq &>/dev/null; then
    jq -n --arg msg "$COMPLETION_MSG" '{
      "continue": true,
      "hookSpecificOutput": {
        "hookEventName": "Stop",
        "additionalContext": $msg
      }
    }'
  fi
  exit 0
fi

# === 반복 횟수 증가 ===
ITERATION=$((ITERATION + 1))
NOW_ISO=$(date -u "+%Y-%m-%dT%H:%M:%S.000Z")

# === 안전 장치 4: 최대 반복 경고 ===
WARNING=""
if [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
  WARNING="\n\n[경고] ${MAX_ITERATIONS}회 반복 도달. 진행 상황을 점검하세요. 중단하려면 'loop stop'을 입력하세요."
fi

# === 안전 장치 5: 에러 반복 감지 ===
ERROR_GUIDANCE=""
if [ "$ERROR_COUNT" -ge "$ERROR_RETRY_LIMIT" ]; then
  ERROR_GUIDANCE="\n\n[에러 반복 ${ERROR_COUNT}회] 동일한 접근 방식이 반복 실패하고 있습니다.\n다음을 시도하세요:\n1. 완전히 다른 접근 방식 시도\n2. 환경/의존성 상태 확인\n3. 현재 태스크를 건너뛰고 다음 태스크 진행"
fi

# === 상태 파일 갱신 ===
if command -v jq &>/dev/null; then
  jq --arg now "$NOW_ISO" --argjson iter "$ITERATION" \
    '.last_activity = $now | .iteration = $iter' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
else
  # jq 없이 간단 갱신 (node 사용)
  node -e "
    const fs=require('fs');
    const s=JSON.parse(fs.readFileSync('$STATE_FILE','utf8'));
    s.last_activity='$NOW_ISO'; s.iteration=$ITERATION;
    fs.writeFileSync('$STATE_FILE',JSON.stringify(s,null,2));
  " 2>/dev/null
fi

# === 계속 진행 지시 출력 ===
# Large 작업 판단: 미완료 태스크 3개 이상이면 서브에이전트 권장
SUBAGENT_GUIDANCE=""
if [ "$INCOMPLETE_TASKS" -ge 3 ]; then
  SUBAGENT_GUIDANCE="\n\n[서브에이전트 권장] 미완료 태스크가 3개 이상입니다. 각 태스크를 Task tool(general-purpose)로 개별 디스패치하세요.\n- 태스크 텍스트를 인라인으로 전달 (파일 경로가 아닌 완전한 텍스트)\n- 서브에이전트 완료 후 상태 코드(DONE/DONE_WITH_CONCERNS/NEEDS_CONTEXT/BLOCKED) 확인\n- 상세 규칙: task-workflow.md 'P4 구현 세부 규칙' 참조"
fi

REASON="[Loop ${ITERATION}/${MAX_ITERATIONS}] 미완료 태스크 ${INCOMPLETE_TASKS}개 남음. 계속 진행하세요.\n\n남은 태스크:\n${INCOMPLETE_LIST}${SUBAGENT_GUIDANCE}${WARNING}${ERROR_GUIDANCE}\n\ntasks.md 참조: ${TASKS_FILE#$PROJECT_ROOT/}"

if command -v jq &>/dev/null; then
  jq -n --arg reason "$REASON" '{
    "continue": false,
    "decision": "block",
    "reason": $reason
  }'
else
  echo "{\"continue\":false,\"decision\":\"block\",\"reason\":\"미완료 태스크 ${INCOMPLETE_TASKS}개. 계속 진행하세요.\"}"
fi

exit 0
