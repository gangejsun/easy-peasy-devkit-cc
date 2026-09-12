#!/bin/bash
# skills/health-check/scripts/build-parser.sh
# 빌드/린트/타입체크/테스트 출력을 JSON으로 구조화한다.
# 원시 로그(수백 줄)를 그대로 컨텍스트에 넣는 대신 구조화 요약만 소비해 토큰을 아낀다.
#
# 사용: build-parser.sh <build|lint|typecheck|test|sonar> [명령...]
#   명령 미지정 시 ./epcc.config.json 의 techStack.commands.<mode> 를 읽는다.
#   그것도 없으면 package.json scripts 에서 동명 스크립트를 찾는다.
#
# 출력(JSON): { mode, command, success, exit_code, error_count, warning_count,
#               errors: [최대 40줄 구조화], tail: [실패 시 마지막 15줄] }
#
# sonar 모드는 SonarQube 서버가 필요하다 (SONAR_HOST_URL · SONAR_TOKEN 환경변수).
#   토큰은 환경변수로만 받는다 — config 에 적으면 security-check 훅이 쓰기를 차단한다.
#   서버·토큰·스캐너가 없거나 분석이 끝나지 않으면 **실패가 아니라 판정 불가(exit 2)** 로 낸다:
#   { undecidable: true, reason: "..." }. 도구 부재를 결함 부재로 접지 않기 위해서다.
#   추가 필드: severity_counts{blocker,critical,major,minor,info} · total(서버가 센 전체 이슈 수)
set -u

MODE="${1:-build}"; shift 2>/dev/null || true
CMD="${*:-}"

command -v jq >/dev/null 2>&1 || { printf '{"success":false,"error":"jq 필요"}\n'; exit 2; }

# ── 판정 불가 — 검사하지 못했다는 뜻이지 통과가 아니다 ──
undecidable() {
  jq -n --arg r "$1" --arg cmd "${CMD:-}" \
    '{mode:"sonar", command:$cmd, success:false, exit_code:2, undecidable:true,
      reason:$r, error_count:0, warning_count:0, errors:[], tail:[]}'
  exit 2
}

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
[ "$MODE" = "sonar" ] && [ -z "$CMD" ] && CMD="sonar-scanner"

if [ -z "$CMD" ]; then
  jq -n --arg m "$MODE" '{mode:$m, success:false, error:"명령 미지정 — epcc.config.json techStack.commands 또는 인자로 제공"}'
  exit 2
fi

# ── sonar 모드 — 스캐너 실행 → CE task 대기 → Web API 로 이슈 조회 ──
# 다른 모드의 경로는 여기를 지나가지 않는다.
if [ "$MODE" = "sonar" ]; then
  command -v curl >/dev/null 2>&1 || undecidable "curl 미설치 — SonarQube Web API 조회 불가"
  command -v "${CMD%% *}" >/dev/null 2>&1 || undecidable "${CMD%% *} 미설치 — 정적 분석을 수행하지 못함"
  [ -n "${SONAR_HOST_URL:-}" ] || undecidable "SONAR_HOST_URL 미설정 — 분석 서버를 알 수 없음"
  [ -n "${SONAR_TOKEN:-}" ]    || undecidable "SONAR_TOKEN 미설정 — Web API 인증 불가 (토큰은 환경변수로만 받는다)"

  HOST="${SONAR_HOST_URL%/}"
  curl -sf -m 10 -u "$SONAR_TOKEN:" "$HOST/api/system/status" >/dev/null 2>&1 \
    || undecidable "SonarQube 서버 응답 없음 ($HOST) — 미기동이거나 토큰이 유효하지 않음"

  SOUT=$(eval "$CMD" 2>&1); SCODE=$?
  if [ "$SCODE" -ne 0 ]; then
    undecidable "sonar-scanner 실패(exit $SCODE) — $(printf '%s\n' "$SOUT" | tail -3 | tr '\n' ' ')"
  fi

  TASKFILE=".scannerwork/report-task.txt"
  [ -f "$TASKFILE" ] || undecidable "$TASKFILE 없음 — 스캐너가 분석을 업로드하지 않았음"
  CE_ID=$(grep -E '^ceTaskId=' "$TASKFILE" | cut -d= -f2-)
  PKEY=$(grep -E '^projectKey=' "$TASKFILE" | cut -d= -f2-)
  [ -n "$CE_ID" ] && [ -n "$PKEY" ] || undecidable "report-task.txt 에서 ceTaskId·projectKey 를 읽지 못함"

  # CE task 폴링 — 상한 60초. 술어도 카운터도 없는 대기는 만들지 않는다.
  STATUS=""; ELAPSED=0
  while [ "$ELAPSED" -lt 60 ]; do
    STATUS=$(curl -sf -m 10 -u "$SONAR_TOKEN:" "$HOST/api/ce/task?id=$CE_ID" 2>/dev/null \
             | jq -r '.task.status // empty')
    case "$STATUS" in
      SUCCESS) break;;
      FAILED|CANCELED) undecidable "서버측 분석 $STATUS — 결과 없음";;
    esac
    sleep 5; ELAPSED=$((ELAPSED + 5))
  done
  [ "$STATUS" = "SUCCESS" ] || undecidable "서버측 분석 60초 내 미완료 (마지막 상태: ${STATUS:-무응답})"

  ISSUES=$(curl -sf -m 30 -u "$SONAR_TOKEN:" \
    "$HOST/api/issues/search?componentKeys=$PKEY&resolved=false&ps=100" 2>/dev/null) \
    || undecidable "이슈 조회 실패 — $HOST/api/issues/search"

  # SonarQube 10+ 는 severity 대신 impacts[].severity(HIGH/MEDIUM/LOW)만 줄 수 있다 — 정규화한다.
  printf '%s' "$ISSUES" | jq \
    --arg cmd "$CMD" \
    'def sev: (.severity // (.impacts // [] | .[0].severity // "MAJOR"))
              | if . == "HIGH" then "CRITICAL" elif . == "MEDIUM" then "MAJOR"
                elif . == "LOW" then "MINOR" else . end;
     (.issues // []) as $all
     | ($all | map(sev)) as $sevs
     | {mode:"sonar", command:$cmd,
        exit_code:0,
        error_count:   ($sevs | map(select(. == "BLOCKER" or . == "CRITICAL")) | length),
        warning_count: ($sevs | map(select(. == "MAJOR")) | length),
        severity_counts: {
          blocker:  ($sevs | map(select(. == "BLOCKER"))  | length),
          critical: ($sevs | map(select(. == "CRITICAL")) | length),
          major:    ($sevs | map(select(. == "MAJOR"))    | length),
          minor:    ($sevs | map(select(. == "MINOR"))    | length),
          info:     ($sevs | map(select(. == "INFO"))     | length)
        },
        total: (.paging.total // ($all | length)),
        errors: ($all | map("\(sev) \(.component // "?"):\(.line // 0) — \(.message // "") [\(.rule // "?")]")
                      | .[0:40]),
        tail: []}
     | .success = (.error_count == 0)'
  exit 0
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
