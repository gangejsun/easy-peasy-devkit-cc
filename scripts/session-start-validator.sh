#!/bin/bash
# .claude/hooks/session-start-validator.sh
# @harness-type: portable
# SessionStart Hook: agent-governance 규칙을 조건부로 출력
#
# 기능:
# - Large 작업 시에만 Agent 거버넌스 규칙 출력
# - Small 작업은 출력 없음 (0T 절약)
# - Self-Improvement: 교훈 승격 후보 감지
# - Self-Evolution: 외부 변화 점검 알림
#
# 실행 시점: 세션 시작, clear, compact 시
# 토큰 사용: 조건부 (~50T 또는 0T)

set -euo pipefail

# stdin에서 세션 정보 읽기
INPUT=$(cat /dev/stdin 2>/dev/null || echo "{}")

# 작업 유형 추론 (환경 변수 또는 휴리스틱)
TASK_TYPE="${CLAUDE_TASK_TYPE:-unknown}"

# Large 작업 판단 (task-workflow.md 기준: 3+파일 또는 50줄+)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHANGED_FILES=$(git -C "$PROJECT_ROOT" status --short 2>/dev/null | wc -l || echo "0")
LINES_CHANGED=$(git -C "$PROJECT_ROOT" diff --stat HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")

# ── 규모 판정 ──
if [ "$CHANGED_FILES" -ge 3 ] || [ "$LINES_CHANGED" -ge 50 ] || [ "$TASK_TYPE" = "large" ]; then
  TASK_SIZE="Large"
elif [ "$CHANGED_FILES" -ge 2 ] || [ "$LINES_CHANGED" -ge 11 ] || [ "$TASK_TYPE" = "medium" ]; then
  TASK_SIZE="Medium"
else
  TASK_SIZE="Small"
fi

# Large: Agent Governance 출력 (~50T)
if [ "$TASK_SIZE" = "Large" ]; then
  cat <<'EOF'
## Agent Governance (조건부 로드)

Large 작업이 감지되었습니다. Agent 협업 규칙:

**Available Agents**:
- `planning-agent`: PRD 검색/생성, 개발 문서 작성
- `review-agent`: 완료 검증, 코드 리뷰 오케스트레이션

**핵심 규칙**:
- Agent 간 handoff 시 검증 필수
- 최대 3회 재시도 상한
- Phase 라우팅 준수 (CLAUDE.md 참조)

📖 상세: .claude/rules/agent-governance.md
EOF
elif [ "$TASK_SIZE" = "Medium" ]; then
  echo "작업 규모 힌트: Medium (${CHANGED_FILES}파일, ${LINES_CHANGED}줄 변경)"
fi

# ── Act→Plan 폐루프: 최근 승격 규칙 요약 출력 ──
SELF_IMPROVEMENT="$PROJECT_ROOT/.claude/rules/self-improvement.md"
if [ -f "$SELF_IMPROVEMENT" ]; then
  PROMOTED=$(sed -n '/^## 승격된 규칙/,/^## [^#]/p' "$SELF_IMPROVEMENT" \
    | grep '^### ' | sed 's/^### [0-9]*\. *//' 2>/dev/null)

  if [ -n "$PROMOTED" ]; then
    echo ""
    echo "## Act→Plan: 승격된 규칙 리마인더"
    echo ""
    echo "이전 세션에서 승격된 규칙입니다. 이번 작업의 Plan/Do 시 참고하세요:"
    echo "$PROMOTED" | while read -r rule; do
      echo "- $rule"
    done
    echo ""
    echo "📖 상세: .claude/rules/self-improvement.md '승격된 규칙' 섹션"
  fi
fi

# ── Self-Improvement: 교훈 승격 후보 감지 ──
LESSONS_FILE="$PROJECT_ROOT/docs/lessons.md"
if [ -f "$LESSONS_FILE" ]; then
  PROMOTABLE=$(grep -oE '\[category: [^]]+\]' "$LESSONS_FILE" 2>/dev/null \
    | sed 's/\[category: //;s/\]//' \
    | sort | uniq -c | sort -rn \
    | awk '$1 >= 3 {print $2}' || true)

  if [ -n "$PROMOTABLE" ]; then
    echo ""
    echo "## Self-Improvement: 규칙 승격 후보"
    echo ""
    echo "다음 카테고리에서 교훈이 3회 이상 반복되었습니다:"
    echo "$PROMOTABLE" | while read -r cat; do
      COUNT=$(grep -c "\[category: $cat\]" "$LESSONS_FILE" 2>/dev/null || echo "0")
      echo "- **$cat** ($COUNT건)"
    done
    echo ""
    echo "ACTION REQUIRED: 아래 승격 후보는 이전 세션에서 미처리되었습니다. 사용자에게 승격 진행 여부를 질문하세요. 각 후보별로 승격 형태(규칙/스킬/기타)를 제안하고 승인을 요청하세요."
  fi

  # ── Self-Improvement: 반복 요청 패턴 감지 ──
  PROMOTABLE_REQ=$(grep -oE '\[request: [^]]+\]' "$LESSONS_FILE" 2>/dev/null \
    | sed 's/\[request: //;s/\]//' \
    | sort | uniq -c | sort -rn \
    | awk '$1 >= 3 {print $2}' || true)

  if [ -n "$PROMOTABLE_REQ" ]; then
    echo ""
    echo "## Self-Improvement: 반복 요청 자동화 후보"
    echo ""
    echo "다음 유형의 요청이 3회 이상 반복되었습니다:"
    echo "$PROMOTABLE_REQ" | while read -r req; do
      COUNT=$(grep -c "\[request: $req\]" "$LESSONS_FILE" 2>/dev/null || echo "0")
      echo "- **$req** ($COUNT건)"
    done
    echo ""
    echo "ACTION REQUIRED: 아래 자동화 후보는 이전 세션에서 미처리되었습니다. 사용자에게 자동화 승인 여부를 질문하세요. 각 후보별로 자동화 형태(스킬/규칙/커맨드 별칭)를 제안하고 승인을 요청하세요. Harness Change Protocol(modification-guardrails.md §6) 준수."
  fi
fi

# ── 외부 변화 점검 알림 (자가-진화 루프 1단계) ──
LAST_SCAN_FILE="$PROJECT_ROOT/dev/docs/harness-evolution/last-scan.txt"
SCAN_INTERVAL_DAYS=30

if [ -f "$LAST_SCAN_FILE" ]; then
  LAST_SCAN_DATE=$(cat "$LAST_SCAN_FILE" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$LAST_SCAN_DATE" ]; then
    LAST_TS=$(date -j -f "%Y-%m-%d" "$LAST_SCAN_DATE" +%s 2>/dev/null || echo 0)
    if [ "$LAST_TS" -gt 0 ]; then
      DAYS_SINCE=$(( ( $(date +%s) - LAST_TS ) / 86400 ))
    else
      DAYS_SINCE=999
    fi
  else
    DAYS_SINCE=999
  fi
else
  DAYS_SINCE=999
fi

if [ "$DAYS_SINCE" -ge "$SCAN_INTERVAL_DAYS" ]; then
  echo ""
  echo "## Self-Evolution: 외부 변화 점검 알림"
  echo ""
  if [ "$DAYS_SINCE" -ge 999 ]; then
    echo "아직 외부 변화 점검이 수행되지 않았습니다."
  else
    echo "마지막 외부 변화 점검 후 ${DAYS_SINCE}일 경과 (임계: ${SCAN_INTERVAL_DAYS}일)."
  fi
  echo "  → /harness-evaluation (8번 + 10번 축) 호출 후 자가-진화 루프 진입을 권장합니다."
fi

# ── Shadow 만료 알림 (자가-진화 루프 8단계) ──
SHADOW_DIR="$PROJECT_ROOT/.claude/deprecated"
if [ -d "$SHADOW_DIR" ]; then
  TODAY=$(date +%Y-%m-%d)
  EXPIRED_LIST=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    EXPIRE_DATE=$(echo "$f" | sed -n 's/.*shadow-expires-\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\).*/\1/p')
    if [ -n "$EXPIRE_DATE" ] && [[ "$EXPIRE_DATE" < "$TODAY" || "$EXPIRE_DATE" == "$TODAY" ]]; then
      REL=$(echo "$f" | sed "s|^$PROJECT_ROOT/||")
      EXPIRED_LIST="${EXPIRED_LIST}  - ${REL}\n"
    fi
  done < <(find "$SHADOW_DIR" -name "*.shadow-expires-*" -type f 2>/dev/null)

  if [ -n "$EXPIRED_LIST" ]; then
    echo ""
    echo "## Self-Evolution: Shadow 기간 만료 자산"
    echo ""
    echo "다음 자산의 Shadow 기간이 만료되었습니다:"
    echo -e "$EXPIRED_LIST"
    echo "ACTION SUGGESTED: 사용자에게 최종 삭제 또는 롤백 결정을 요청하세요."
  fi
fi

exit 0
