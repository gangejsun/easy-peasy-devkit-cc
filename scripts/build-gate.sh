#!/bin/bash
# scripts/build-gate.sh — Stop
#
# 소스 코드를 고쳤는데 빌드/테스트를 돌리지 않고 끝내려 하면 막는다.
#
# v2의 stop-guard가 한 번도 차단하지 못한 이유는 두 가지였다:
#   1. {"decision":"block","reason":...} 출력 — Stop 이벤트는 이 필드를 지원하지 않는다.
#      지원 필드는 additionalContext / continue / systemMessage 뿐이다.
#   2. `tail -200 transcript | grep -qE "(build|test)"` — "test"라는 단어가
#      대화 어디에든 있으면 통과했다.
#
# v3는 (1) continue:false + systemMessage로 출력하고
#      (2) transcript JSONL을 파싱해 실제 Bash 도구 호출만 본다.

INPUT=$(cat 2>/dev/null || printf '{}')
# shellcheck source=lib/common.sh
source "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/scripts/lib/common.sh"
epcc_begin "build-gate" "$INPUT"

cd "$EPCC_ROOT" 2>/dev/null || exit 0

# 무한 루프 방지: 이 훅 때문에 이미 계속 중이면 재차 막지 않는다
STOP_ACTIVE=$(epcc_field "$INPUT" '.stop_hook_active')
[ "$STOP_ACTIVE" = "true" ] && exit 0

TRANSCRIPT=$(epcc_field "$INPUT" '.transcript_path')

# ── 1. 이번 세션에 바뀐 소스 파일이 있는가 ───────────────────────────
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

BASELINE="$EPCC_ROOT/.claude/.epcc/session-baseline.txt"
CURRENT=$(git status --porcelain 2>/dev/null | awk '{print $NF}' | sort)

if [ -f "$BASELINE" ]; then
  CHANGED=$(comm -13 "$BASELINE" <(printf '%s\n' "$CURRENT") 2>/dev/null)
else
  CHANGED="$CURRENT"
fi

# 소스 확장자만 (설정·문서·마크다운 제외)
SRC_CHANGED=$(printf '%s\n' "$CHANGED" | grep -E '\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|kt|swift|rb|php|vue|svelte)$' \
  | grep -vE '\.(config|test|spec)\.' | grep -vE '^\s*$' || true)

[ -z "$SRC_CHANGED" ] && exit 0

SRC_COUNT=$(epcc_num "$(printf '%s\n' "$SRC_CHANGED" | grep -c . || printf '0')")
[ "$SRC_COUNT" -eq 0 ] && exit 0

# ── 2. 빌드/테스트가 실제로 실행되었는가 ─────────────────────────────
# transcript JSONL에서 Bash 도구 호출의 command만 추출해서 판정한다.
BUILD_RAN=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && command -v jq >/dev/null 2>&1; then
  if jq -r 'select(.type=="assistant") | .message.content[]?
            | select(.type=="tool_use" and .name=="Bash") | .input.command // empty' \
       "$TRANSCRIPT" 2>/dev/null \
     | grep -qE '(pnpm|npm|npx|yarn|bun|make|cargo|go|uv|poetry|python|pytest|ruff|tsc)([[:space:]]+run)?[[:space:]]+[a-z:]*(build|test|typecheck|check|lint)'; then
    BUILD_RAN=1
  fi
fi

[ "$BUILD_RAN" -eq 1 ] && { epcc_edge "build" "build-gate"; exit 0; }

# ── 3. 차단 ──────────────────────────────────────────────────────────
# config에서 실제 명령을 읽어 구체적으로 안내한다
CFG="${EPCC_CONFIG_PATH:-$EPCC_ROOT/epcc.config.json}"
BUILD_CMD=""; TEST_CMD=""
if [ -f "$CFG" ] && command -v jq >/dev/null 2>&1; then
  BUILD_CMD=$(jq -r '.techStack.commands.build // empty' "$CFG" 2>/dev/null || printf '')
  TEST_CMD=$(jq -r '.techStack.commands.test // empty' "$CFG" 2>/dev/null || printf '')
fi
HINT="빌드 및 테스트"
[ -n "$BUILD_CMD" ] && HINT="$BUILD_CMD"
[ -n "$BUILD_CMD" ] && [ -n "$TEST_CMD" ] && HINT="$BUILD_CMD && $TEST_CMD"

FILES=$(printf '%s\n' "$SRC_CHANGED" | head -5 | sed 's/^/  - /')
MORE=""
[ "$SRC_COUNT" -gt 5 ] && MORE=$(printf '\n  ... 외 %s개' "$((SRC_COUNT-5))")

epcc_edge "build" "build-gate"
epcc_edge "build-gate" "build"
epcc_emit_block "Stop" "$(printf '소스 %s개 파일이 이번 세션에 변경되었으나 빌드/테스트가 실행되지 않았습니다.\n\n%s%s\n\n실행하세요: %s\n\n(작성했다 ≠ 작동한다 — 검증까지가 한 동작입니다)' \
  "$SRC_COUNT" "$FILES" "$MORE" "$HINT")"
exit 0
