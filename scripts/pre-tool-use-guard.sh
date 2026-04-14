#!/bin/bash
# .claude/hooks/pre-tool-use-guard.sh
# @harness-type: project-specific
# PreToolUse Hook: modification-guardrails 규칙을 동적으로 강제
#
# 기능:
# 1. shared 패키지 무단 수정 차단 + 허용 목록 지원
# 2. 도메인 패턴 확인 가이드 (기존 코드 읽기 유도)
# 보안 검사는 security-check.sh가 전담 (SSOT)
#
# 실행 시점: Claude가 Edit/Write 도구 사용 직전
# 토큰 사용: 0T (패턴 가이드 시 ~50T additionalContext)

set -euo pipefail

# stdin에서 tool use 정보 읽기
INPUT=$(cat /dev/stdin 2>/dev/null)

# 도구 이름과 파일 경로 추출
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

# Edit/Write 도구만 검증
if [[ ! "$TOOL_NAME" =~ ^(Edit|Write)$ ]]; then
  exit 0
fi

# 파일 경로가 없으면 통과
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# ============================================================
# shared 패키지 수정 차단
# ============================================================

if [[ "$FILE_PATH" =~ ^packages/shared/ ]]; then
  # 허용 목록 확인 (상대경로 기반)
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  ALLOWLIST_FILE="${PROJECT_ROOT}/.claude/governance/dynamic-rules/shared-allowlist.json"

  if [ -f "$ALLOWLIST_FILE" ]; then
    ALLOWED=$(jq -r --arg fp "$FILE_PATH" '.allowed_files | index($fp)' "$ALLOWLIST_FILE" 2>/dev/null || echo "null")

    if [ "$ALLOWED" != "null" ]; then
      exit 0
    fi
  fi

  # 차단
  cat >&2 <<EOF
❌ ERROR: packages/shared/ 패키지 수정 차단됨

📋 shared 패키지는 전체 모노레포에 영향을 주므로 신중한 검토가 필요합니다.

💡 수정이 필요한 경우:
  1. 사용자에게 수정 이유 설명
  2. 영향 범위 분석 (어떤 패키지가 이 코드를 사용하는지)
  3. 사용자 승인 획득
  4. .claude/governance/dynamic-rules/shared-allowlist.json에 파일 추가

📖 상세: .claude/rules/modification-guardrails.md 참조
EOF
  exit 1
fi

# ============================================================
# 도메인 패턴 확인 가이드
# 기존 코드를 무시하고 새로 작성하는 "터널 시야" 방지
# ============================================================

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# 도메인 추출 (컨벤션 기반: modification-guardrails.md 참조)
DOMAIN=""
if [[ "$FILE_PATH" =~ src/components/([^/]+)/ ]]; then
  DOMAIN="${BASH_REMATCH[1]}"
elif [[ "$FILE_PATH" =~ src/app/\(main\)/([^/]+)/ ]]; then
  DOMAIN="${BASH_REMATCH[1]}"
elif [[ "$FILE_PATH" =~ src/lib/actions/([a-zA-Z]+) ]]; then
  DOMAIN="${BASH_REMATCH[1]}"
elif [[ "$FILE_PATH" =~ src/app/api/([^/]+)/ ]]; then
  DOMAIN="${BASH_REMATCH[1]}"
fi

# 도메인 없는 파일 (config, shared 등) 또는 .claude/ 내부 파일은 스킵
if [ -z "$DOMAIN" ]; then
  exit 0
fi

# 도메인 내 기존 파일 (최대 5개, 수정 대상 제외, 테스트 제외)
RELATED_FILES=$(find "$PROJECT_ROOT/src" -type f \( -name "*.tsx" -o -name "*.ts" \) \
  -path "*${DOMAIN}*" ! -path "*/__tests__/*" ! -path "*node_modules*" \
  ! -path "$PROJECT_ROOT/$FILE_PATH" ! -name "*.test.*" ! -name "*.spec.*" \
  2>/dev/null | head -5)

# 기존 파일 없으면 (완전히 새 도메인) 스킵
if [ -z "$RELATED_FILES" ]; then
  exit 0
fi

# Read 로그 확인: 이 세션에서 관련 도메인 파일을 읽었는지
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
READ_LOG="/tmp/read-files-${SESSION_ID}.log"
READ_ANY=false

if [ -f "$READ_LOG" ]; then
  while IFS= read -r rf; do
    REL="${rf#$PROJECT_ROOT/}"
    if grep -q "$REL" "$READ_LOG" 2>/dev/null; then
      READ_ANY=true
      break
    fi
  done <<< "$RELATED_FILES"
fi

# 안 읽었으면 additionalContext로 안내 (차단하지 않음)
if [ "$READ_ANY" = false ]; then
  FILE_LIST=$(echo "$RELATED_FILES" | sed "s|$PROJECT_ROOT/||g" | awk '{printf "- %s\\n", $0}')
  jq -n --arg domain "$DOMAIN" --arg files "$FILE_LIST" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": ("⚠️ 도메인 [" + $domain + "] 수정 전 기존 패턴 확인 필요\n\n다음 파일 중 최소 1개를 Read로 먼저 확인하세요:\n" + $files + "\n\n확인 후 동일 패턴(네이밍, import, Props 구조, 에러 핸들링, shadcn/ui 사용 여부)을 따라 구현하세요.")
    }
  }'
fi

# 통과
exit 0
