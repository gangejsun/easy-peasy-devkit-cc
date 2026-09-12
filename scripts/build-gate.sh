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

# 스냅샷 줄은 `경로<TAB>mtime<TAB>크기`다 (common.sh · epcc_worktree_snapshot).
# 이름만 비교하면 **세션 시작 시 이미 미커밋이던 소스 파일**이 아무리 바뀌어도
# 차집합에서 빠진다 — 작업을 이어서 하는 가장 흔한 경로에서 게이트가 침묵했다.
BASELINE="$(epcc_state_dir)/session-baseline.txt"
CURRENT=$(epcc_worktree_snapshot)

if [ -f "$BASELINE" ]; then
  # 차집합은 스냅샷 **줄** 단위로 낸 뒤 경로만 꺼낸다: 새로 더러워진 파일과
  # 이미 더러웠으나 이번에 또 바뀐 파일이 함께 남는다.
  CHANGED=$(comm -13 <(sort "$BASELINE") <(printf '%s\n' "$CURRENT" | sort) 2>/dev/null \
            | epcc_snapshot_paths | sort -u)
else
  CHANGED=$(printf '%s\n' "$CURRENT" | epcc_snapshot_paths | sort -u)
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

# 인식은 **세그먼트의 첫 토큰**으로 한다 — security-check의 면제와 같은 규율이다.
# 예전의 한 줄 정규식은 양쪽으로 틀렸다(평가 v9 · E-60): `echo npm run build`·`grep 'pnpm build'`를
# 실행으로 셌고(v2 stop-guard의 실패가 좁아진 채 남아 있었다), 정작 fastapi 프리셋이 처방하는
# `pytest`(맨 명령)와 `python -m pytest`·`tsc --noEmit`·`jest`는 못 알아봐 **자기 처방을 돌린
# 세션을 막았다.** 오탐 차단은 사용자가 훅을 끄게 만들고, 꺼진 훅의 차단력은 0이다.
#
# 세 부류다: ① 검증기 자체가 명령인 경우(pytest·jest·tsc·make …) ② 러너 뒤에 검증 어휘가
# 오는 경우(npm run build · python -m pytest · npx tsc · uv run pytest …) ③ 언어 도구의
# 부명령(cargo test · go vet …). 설치 어휘(install·add)가 있는 세그먼트는 ②에서 뺀다 —
# `python -m pip install pytest`는 검증이 아니다. 알려진 한계: 파일 힙독 **본문**의 한 줄이
# 검증기 이름으로 시작하면 실행으로 센다 — 명령 텍스트만 보는 판정의 원리적 경계다.
_verification_ran() {
  jq -r 'select(.type=="assistant") | .message.content[]?
          | select(.type=="tool_use" and .name=="Bash") | .input.command // empty' \
     "$TRANSCRIPT" 2>/dev/null \
  | awk '
    function head(s) {
      sub(/^[ \t]+/, "", s)
      while (match(s, /^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/)) s = substr(s, RLENGTH + 1)
      while (match(s, /^(time|env|nice|sudo|command)[ \t]+/)) s = substr(s, RLENGTH + 1)
      if (match(s, /^timeout[ \t]+[0-9]+[a-z]?[ \t]+/)) s = substr(s, RLENGTH + 1)
      if (match(s, /^(bash|sh|zsh)[ \t]+-c[ \t]+["\047]?/)) s = substr(s, RLENGTH + 1)
      return s
    }
    { n = split($0, seg, /;|&&|\|\|/)
      for (i = 1; i <= n; i++) {
        s = head(seg[i]); split(s, w, /[ \t]+/); t = w[1]; sub(/.*\//, "", t)
        if (t ~ /^(pytest|jest|vitest|mocha|tsc|vue-tsc|ruff|mypy|pyright|eslint|biome|tox|nox|gradlew|gradle|mvnw|mvn|make)$/) { found = 1; exit }
        if (s ~ /(^|[ \t])(install|add|i)([ \t]|$)/) continue
        if (t ~ /^(pnpm|npm|yarn|bun|npx|bunx|uv|poetry|pipx|python|python3|py|deno)$/ \
            && s ~ /[ \t][a-z:_-]*(build|test|typecheck|check|lint|pytest|unittest|jest|vitest|mocha|tsc|ruff|mypy|clippy)[a-z:_-]*([ \t"\047]|$)/) { found = 1; exit }
        if (t ~ /^(cargo|go|dotnet|swift)$/ && s ~ /^[a-z0-9.\/-]+[ \t]+(build|test|check|clippy|vet)([ \t]|$)/) { found = 1; exit }
      } }
    END { exit found ? 0 : 1 }'
}
BUILD_RAN=0
_verification_ran && BUILD_RAN=1

# ── 2-a. UI 파일은 빌드 통과로 끝나지 않는다 (알림, 차단 아님) ──────
# tsc 는 빈 화면도 콘솔이 터지는 화면도 통과시킨다. 그래서 여기서 **알린다.**
# 차단하지 않는 이유: 헤드리스 브라우저가 없는 환경·서버가 필요 없는 컴포넌트 수정에서
# 오탐이 나고, 오탐이 반복되면 사용자가 훅을 꺼버린다 (security-check.sh의 원칙).
_ui_render_notice() {
  local ui_changed ui_count stamp
  ui_changed=$(printf '%s\n' "$SRC_CHANGED" | grep -E '\.(tsx|jsx|vue|svelte)$' || true)
  [ -z "$ui_changed" ] && return 0
  ui_count=$(epcc_num "$(printf '%s\n' "$ui_changed" | grep -c . || printf '0')")
  [ "$ui_count" -eq 0 ] && return 0

  stamp="$(epcc_state_dir)/ui-notice.stamp"
  [ -f "$stamp" ] && return 0   # 세션당 1회 (session-brief가 매 세션 지운다)

  # 렌더를 확인한 흔적 — 프로브·브라우저 자동화 Bash 호출, 또는 내장 /run 스킬 호출.
  # 문자열 존재가 아니라 **실제 도구 호출**만 본다 (v2 stop-guard의 교훈).
  if jq -r 'select(.type=="assistant") | .message.content[]?
            | select(.type=="tool_use")
            | if .name=="Bash" then (.input.command // empty)
              elif .name=="Skill" then (.input.skill // empty)
              else empty end' "$TRANSCRIPT" 2>/dev/null \
     | grep -qiE '(ui-probe|playwright|puppeteer|chromium|(^|:)run$)'; then
    return 0
  fi

  : > "$stamp" 2>/dev/null || true
  epcc_emit_notice "Stop" "$(printf 'UI 파일 %s개가 이번 세션에 바뀌고 빌드는 통과했으나 **렌더를 확인한 흔적이 없습니다.**\n\n%s\n\n내장 `/run` 으로 띄운 뒤 그 URL에 `ui-ux-design` 스킬의 ui-probe를 거세요.\n타입체크 통과는 화면이 나온다는 증거가 아닙니다 — 차단하지 않으니 필요 없으면 넘어가세요.' \
    "$ui_count" "$(printf '%s\n' "$ui_changed" | head -3 | sed 's/^/  - /')")" 2>/dev/null || true
  return 0
}

if [ "$BUILD_RAN" -eq 1 ]; then
  _ui_render_notice
  exit 0
fi

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
