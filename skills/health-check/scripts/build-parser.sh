#!/bin/bash
# skills/health-check/scripts/build-parser.sh
# 빌드/린트/타입체크/테스트 출력을 JSON으로 구조화한다.
# 원시 로그(수백 줄)를 그대로 컨텍스트에 넣는 대신 구조화 요약만 소비해 토큰을 아낀다.
#
# 사용: build-parser.sh <build|lint|typecheck|test> [명령...]
#   명령 미지정 시 ./epcc.config.json 의 techStack.commands.<mode> 를 읽는다.
#   그것도 없으면 package.json scripts 에서 동명 스크립트를 찾는다.
#
# 출력(JSON): { mode, command, success, exit_code, error_count, warning_count,
#               errors: [최대 40줄 구조화], tail: [실패 시 마지막 15줄] }
set -u

MODE="${1:-build}"; shift 2>/dev/null || true
CMD="${*:-}"

command -v jq >/dev/null 2>&1 || { printf '{"success":false,"error":"jq 필요"}\n'; exit 2; }

# 명령 해석: 인자 > epcc.config.json > package.json scripts
if [ -z "$CMD" ] && [ -f epcc.config.json ]; then
  CMD=$(jq -r ".techStack.commands.${MODE} // empty" epcc.config.json 2>/dev/null)
fi
if [ -z "$CMD" ] && [ -f package.json ]; then
  if jq -e ".scripts.\"${MODE}\"" package.json >/dev/null 2>&1; then
    PM="npm"
    [ -f pnpm-lock.yaml ] && PM="pnpm"
    [ -f yarn.lock ] && PM="yarn"
    [ -f bun.lockb ] && PM="bun"
    CMD="$PM run $MODE"
  fi
fi
if [ -z "$CMD" ]; then
  jq -n --arg m "$MODE" '{mode:$m, success:false, error:"명령 미지정 — epcc.config.json techStack.commands 또는 인자로 제공"}'
  exit 2
fi

OUT=$(eval "$CMD" 2>&1); CODE=$?

# 에러/경고 라인 추출 — TS(file(l,c): error TSxxxx), ESLint(error/warning),
# Python(File "...", Error:), Rust(error[Exxx]), 일반(error 포함 라인)
ERR_LINES=$(printf '%s\n' "$OUT" | grep -nE \
  '(: error TS[0-9]+|: warning|[[:space:]]error[[:space:]]|^Error|error\[|ERROR|FAILED|✕|✗|Traceback|File "|SyntaxError|TypeError|AssertionError)' \
  | head -40)
# grep -c 는 0건이어도 "0"을 출력한다 (exit 1일 뿐). '|| echo 0' 폴백은
# 0을 두 번 찍어 JSON을 깨뜨린다 — v2 침묵 실패의 §1.1 관용구. 공백 제거만 한다.
ERR_COUNT=$(printf '%s\n' "$OUT" | grep -cE '(: error TS[0-9]+|[[:space:]]error[[:space:]]|^Error|error\[|ERROR|FAILED)' | tr -d '[:space:]')
WARN_COUNT=$(printf '%s\n' "$OUT" | grep -cE '(: warning|[[:space:]]warning[[:space:]]|WARN)' | tr -d '[:space:]')
case "$ERR_COUNT" in ''|*[!0-9]*) ERR_COUNT=0;; esac
case "$WARN_COUNT" in ''|*[!0-9]*) WARN_COUNT=0;; esac

SUCCESS=false; [ "$CODE" -eq 0 ] && SUCCESS=true

TAIL_JSON="[]"
if [ "$CODE" -ne 0 ]; then
  TAIL_JSON=$(printf '%s\n' "$OUT" | tail -15 | jq -R . | jq -s .)
fi

printf '%s\n' "$ERR_LINES" | jq -R . | jq -s \
  --arg mode "$MODE" --arg cmd "$CMD" \
  --argjson success "$SUCCESS" --argjson code "$CODE" \
  --argjson ec "$ERR_COUNT" --argjson wc "$WARN_COUNT" \
  --argjson tail "$TAIL_JSON" \
  '{mode:$mode, command:$cmd, success:$success, exit_code:$code,
    error_count:$ec, warning_count:$wc,
    errors:(map(select(length>0))), tail:$tail}'
exit 0
