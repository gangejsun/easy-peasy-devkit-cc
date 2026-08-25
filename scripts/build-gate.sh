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
epcc_edge "build" "build-gate"   # Stop 시 자동 — 판정 결과와 무관하게 traversal 사실을 기록

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
#
# **판정은 3상태다. "판정 불가"를 "미실행"으로 접으면 안 된다.**
# jq는 macOS 기본 설치에 없다. 접어버리면 빌드를 돌린 세션도 매번 차단되고,
# 그러면 사용자가 훅을 꺼서 차단력이 0이 된다 (security-check.sh가 적어둔 원칙).
# guide-freshness.sh --offline 과 같은 규율: 미판정은 명시 보고하지 단정하지 않는다.
UNDECIDABLE=""
if ! command -v jq >/dev/null 2>&1; then
  UNDECIDABLE="jq 미설치"
elif [ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ]; then
  UNDECIDABLE="transcript를 읽을 수 없음"
fi

if [ -n "$UNDECIDABLE" ]; then
  epcc_emit_notice "Stop" "$(printf '소스 %s개 파일이 변경되었으나 빌드/테스트 실행 여부를 **판정할 수 없습니다** (%s).\n\n차단하지 않습니다 — 직접 확인하세요. jq를 설치하면 이 게이트가 다시 작동합니다.' \
    "$SRC_COUNT" "$UNDECIDABLE")" 2>/dev/null || true
  exit 0
fi

BUILD_RAN=0
if jq -r 'select(.type=="assistant") | .message.content[]?
          | select(.type=="tool_use" and .name=="Bash") | .input.command // empty' \
     "$TRANSCRIPT" 2>/dev/null \
   | grep -qE '(pnpm|npm|npx|yarn|bun|make|cargo|go|uv|poetry|python|pytest|ruff|tsc)([[:space:]]+run)?[[:space:]]+[a-z:]*(build|test|typecheck|check|lint)'; then
  BUILD_RAN=1
fi

[ "$BUILD_RAN" -eq 1 ] && exit 0

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

epcc_edge "build-gate" "build"   # 차단 → build 재진입
epcc_emit_block "Stop" "$(printf '소스 %s개 파일이 이번 세션에 변경되었으나 빌드/테스트가 실행되지 않았습니다.\n\n%s%s\n\n실행하세요: %s\n\n(작성했다 ≠ 작동한다 — 검증까지가 한 동작입니다)' \
  "$SRC_COUNT" "$FILES" "$MORE" "$HINT")"
exit 0
