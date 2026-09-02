#!/bin/bash
# skills/ui-ux-design/scripts/ui-probe.sh — 렌더 증명
#
# 이미 떠 있는 화면을 한 번 열어 **정찰과 증거를 같은 패스에서** 모은다.
# 서버는 띄우지 않는다 — 그것은 내장 /run 이 한다. 이 스크립트는 그 URL 을 받는다.
#
#   ui-probe.sh --url <URL> [옵션]
#
#   --url <URL>         http(s):// 또는 file://  (필수)
#   --ready <selector>  이 요소가 보일 때까지 기다린다 — **가장 신뢰할 수 있는 대기다**
#   --viewport <목록>   기본 mobile,desktop  (mobile 390x844 · tablet 768x1024 · desktop 1440x900)
#   --out <디렉토리>    증거 저장 위치. 기본 .claude/.epcc/ui-probe/ (최근 5회만 보존)
#   --ignore <정규식>   실패 요청·콘솔에서 제외 (favicon.ico 는 기본 제외)
#   --recon             정찰 인벤토리를 종류당 40개까지 낸다 (기본 8개)
#   --timeout <초>      기본 15
#   --quality off       품질 실측(WARN 축)을 끈다
#   --json              서식 없이 JSON 한 덩어리
#   --self-test         픽스처로 자기검증
#   -h, --help
#
# 판정: 콘솔 error · 미포착 예외 · 실패 요청만 결함이다.
#       품질 실측(대비·터치타겟·본문크기·cursor·모션)은 **WARN 이며 종료 코드를 올리지 않는다** —
#       이미지 위 텍스트 같은 오탐이 차단으로 번지면 사용자가 장치를 꺼버린다.
#
# 종료 코드: 0 = 결함 없음 · 1 = 결함 검출 · 2 = 판정 불가(node·playwright·접속 실패)·사용법 오류
set -uo pipefail   # -e 없음: 모든 검사를 끝까지 돌려 전체 보고서를 낸다

FAIL=0; WARN=0; PASS=0
C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_D=$'\033[2m'; C_0=$'\033[0m'
[ -t 1 ] || { C_R=""; C_G=""; C_Y=""; C_D=""; C_0=""; }

# doctor.sh 의 규약을 복사한다 (source 가 아니다 — lib/common.sh 의 set -Eeuo pipefail 과
# ERR trap 은 "모든 검사를 끝까지 돌린다" 정책과 충돌한다). return 0 을 명시한다:
# 원본 bad/warn 은 $2 가 비면 반환값이 1이라 `... && warn ... || ok ...` 가 양쪽 다 실행된다.
ok()   { PASS=$((PASS+1)); printf "  ${C_G}✓${C_0} %s\n" "$1"; return 0; }
# 상세($2)는 여러 줄일 수 있다 — 이어지는 줄도 같이 들여쓴다.
detail() { [ -n "${1:-}" ] || return 0; printf '%s\n' "$1" | sed "s/^/      ${C_D}/;s/\$/${C_0}/"; return 0; }
bad()  { FAIL=$((FAIL+1)); printf "  ${C_R}✗${C_0} %s\n" "$1"; detail "${2:-}"; return 0; }
warn() { WARN=$((WARN+1)); printf "  ${C_Y}!${C_0} %s\n" "$1"; detail "${2:-}"; return 0; }
skip() { printf "  ${C_D}–${C_0} %s\n" "$1"; detail "${2:-}"; return 0; }
sec()  { printf "\n${C_D}── %s ─────────────────────────────${C_0}\n" "$1"; return 0; }
num()  { local v; v=$(printf '%s' "${1:-}" | tr -d '[:space:]'); case "$v" in ''|*[!0-9]*) printf '0';; *) printf '%s' "$v";; esac; }

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUNNER="$HERE/ui-probe.browser.mjs"

URL=""; READY=""; VIEWPORTS="mobile,desktop"; OUT=""; IGNORE=""; RECON=0
TIMEOUT=15; QUALITY=1; JSON_ONLY=0; MODE="run"

while [ $# -gt 0 ]; do
  case "$1" in
    --url)      URL="${2:-}"; shift 2 || exit 2 ;;
    --ready)    READY="${2:-}"; shift 2 || exit 2 ;;
    --viewport) VIEWPORTS="${2:-}"; shift 2 || exit 2 ;;
    --out)      OUT="${2:-}"; shift 2 || exit 2 ;;
    --ignore)   IGNORE="${2:-}"; shift 2 || exit 2 ;;
    --recon)    RECON=1; shift ;;
    --timeout)  TIMEOUT=$(num "${2:-15}"); shift 2 || exit 2 ;;
    --quality)  [ "${2:-}" = "off" ] && QUALITY=0; shift 2 || exit 2 ;;
    --json)     JSON_ONLY=1; shift ;;
    --self-test) MODE="selftest"; shift ;;
    -h|--help)  sed -n '2,25p' "$0" | sed -E 's/^#[[:space:]]?//'; exit 0 ;;
    *) printf "알 수 없는 옵션: %s (--help 참조)\n" "$1" >&2; exit 2 ;;
  esac
done

command -v node >/dev/null 2>&1 || {
  printf "판정 불가 — node 를 찾을 수 없습니다. Node.js 18+ 가 필요합니다.\n" >&2; exit 2; }
[ -f "$RUNNER" ] || {
  printf "판정 불가 — 실행부가 없습니다: %s\n" "$RUNNER" >&2; exit 2; }

# ── 한 번의 프로브 ────────────────────────────────────────────────────
# stdout 은 JSON, stderr 는 사람 메시지. 종료 코드 2 = 판정 불가.
probe() {   # $1 url  $2 outdir("" 면 스크린샷 없음)  → RESULT 에 JSON, 반환 0/2
  local url="$1" outdir="$2" cfg
  cfg=$(node -e '
    const [url,ready,vps,out,ignore,recon,timeout,quality] = process.argv.slice(1);
    process.stdout.write(JSON.stringify({
      url, ready: ready || null, viewports: vps.split(",").map(s=>s.trim()).filter(Boolean),
      out: out || null, ignore: ignore || null, recon: recon === "1",
      timeout: Number(timeout), quality: quality === "1",
    }));
  ' "$url" "$READY" "$VIEWPORTS" "$outdir" "$IGNORE" "$RECON" "$TIMEOUT" "$QUALITY")
  RESULT=$(node "$RUNNER" "$cfg" 2>/dev/null)
  return $?
}

# ── 판정 + 서식 ──────────────────────────────────────────────────────
report() {   # $1 JSON
  local j="$1"
  if ! command -v jq >/dev/null 2>&1; then
    printf "판정 불가 — jq 가 없어 서식·판정을 만들 수 없습니다. 원시 결과:\n%s\n" "$j" >&2
    return 2
  fi

  local und; und=$(printf '%s' "$j" | jq -r '.undecidable // empty')
  if [ -n "$und" ]; then
    printf "판정 불가 — %s\n" "$und" >&2
    printf '%s' "$j" | jq -r '.hint // empty' >&2
    return 2
  fi

  local ce pe fr
  ce=$(num "$(printf '%s' "$j" | jq -r '.runtime.consoleErrors | length')")
  pe=$(num "$(printf '%s' "$j" | jq -r '.runtime.pageErrors    | length')")
  fr=$(num "$(printf '%s' "$j" | jq -r '.runtime.failedRequests| length')")

  sec "런타임"
  if [ "$((ce+pe+fr))" -eq 0 ]; then
    ok "콘솔 error 0 · 미포착 예외 0 · 실패 요청 0"
  else
    [ "$ce" -gt 0 ] && bad "콘솔 error ${ce}건" \
      "$(printf '%s' "$j" | jq -r '.runtime.consoleErrors[:3][] | "[\(.viewport)] \(.text)"')"
    [ "$pe" -gt 0 ] && bad "미포착 예외 ${pe}건" \
      "$(printf '%s' "$j" | jq -r '.runtime.pageErrors[:3][] | "[\(.viewport)] \(.text)"')"
    [ "$fr" -gt 0 ] && bad "실패 요청 ${fr}건" \
      "$(printf '%s' "$j" | jq -r '.runtime.failedRequests[:3][] | "\(.status)  \(.url)"')"
  fi
  local wt; wt=$(printf '%s' "$j" | jq -r '.wait.warning // empty')
  [ -n "$wt" ] && skip "대기: $(printf '%s' "$j" | jq -r '.wait.strategy')" "$wt"

  if [ "$QUALITY" -eq 1 ] && [ "$(printf '%s' "$j" | jq -r '.quality // "null"')" != "null" ]; then
    sec "품질 실측 (WARN — 종료 코드를 올리지 않는다)"
    local tt ttv; tt=$(num "$(printf '%s' "$j" | jq -r '.quality.touchTargets.checked // 0')")
    ttv=$(num "$(printf '%s' "$j" | jq -r '.quality.touchTargets.total // 0')")
    if [ "$tt" -gt 0 ]; then
      if [ "$ttv" -eq 0 ]; then ok "터치 타겟 44px — ${tt}개 전부 충족"
      else warn "터치 타겟 44px 미달 ${ttv}/${tt}" \
        "$(printf '%s' "$j" | jq -r '.quality.touchTargets.violations[:3][] | "\(.name)  \(.w)x\(.h)  \(.hint)"')"; fi
    fi
    local bf bok; bf=$(printf '%s' "$j" | jq -r '.quality.bodyFontSize.median // empty')
    bok=$(printf '%s' "$j" | jq -r '.quality.bodyFontSize.ok // empty')
    if [ -n "$bf" ]; then
      if [ "$bok" = "true" ]; then ok "본문 크기 중앙값 ${bf}px"
      else warn "본문 크기 중앙값 ${bf}px — 모바일 권장은 16px 이상"; fi
    fi
    local cu cuv; cu=$(num "$(printf '%s' "$j" | jq -r '.quality.cursor.checked // 0')")
    cuv=$(num "$(printf '%s' "$j" | jq -r '.quality.cursor.total // 0')")
    if [ "$cu" -gt 0 ]; then
      if [ "$cuv" -eq 0 ]; then ok "cursor:pointer — ${cu}개 전부 충족"
      else warn "cursor:pointer 누락 ${cuv}/${cu}" \
        "$(printf '%s' "$j" | jq -r '.quality.cursor.violations[:3][] | "\(.name)  cursor: \(.cursor)  \(.hint)"')"; fi
    fi
    local cc ccv; cc=$(num "$(printf '%s' "$j" | jq -r '.quality.contrast.checked // 0')")
    ccv=$(num "$(printf '%s' "$j" | jq -r '.quality.contrast.total // 0')")
    if [ "$cc" -gt 0 ]; then
      if [ "$ccv" -eq 0 ]; then ok "대비율 — ${cc}개 전부 기준 충족"
      else warn "대비율 미달 ${ccv}/${cc}" \
        "$(printf '%s' "$j" | jq -r '.quality.contrast.violations[:3][] | "\(.name)  \(.ratio):1 (필요 \(.need):1)  \(.hint)"')"; fi
    fi
    local rm; rm=$(num "$(printf '%s' "$j" | jq -r '.reducedMotion // 0')")
    if [ "$rm" -eq 0 ]; then ok "prefers-reduced-motion — 감속 시 실행 중인 애니메이션 없음"
    else warn "prefers-reduced-motion 무시 — 감속 설정에서도 ${rm}개 애니메이션이 돈다"; fi
  fi

  sec "정찰"
  printf "  %s\n" "$(printf '%s' "$j" | jq -r \
    '"버튼 \(.recon.buttons.total) · 링크 \(.recon.links.total) · 입력 \(.recon.inputs.total)"')"
  printf '%s' "$j" | jq -r '
    [(.recon.buttons.items[]|"[button] \(.name)  →  \(.hint)"),
     (.recon.inputs.items[] |"[input]  \(.name)  →  \(.hint)"),
     (.recon.links.items[]  |"[link]   \(.name)  →  \(.hint)")] | .[]' \
    | sed "s/^/      ${C_D}/;s/$/${C_0}/"
  [ "$RECON" -eq 0 ] && printf "      ${C_D}(--recon 으로 종류당 40개까지)${C_0}\n"

  local shots; shots=$(printf '%s' "$j" | jq -r '.screenshots[]?.path')
  if [ -n "$shots" ]; then
    sec "증거"
    printf '%s\n' "$shots" | sed "s/^/  /"
  fi
  return 0
}

# ── --self-test ──────────────────────────────────────────────────────
run_self_test() {
  local fx="$HERE/../assets/probe-fixtures"
  printf "\n${C_D}ui-probe 자기검증${C_0}\n"

  sec "픽스처"
  [ -f "$fx/clean.html" ] && ok "clean.html" || bad "clean.html 없음" "$fx"
  [ -f "$fx/broken.html" ] && ok "broken.html" || bad "broken.html 없음" "$fx"
  [ "$FAIL" -gt 0 ] && return 1

  sec "판정 불가 경로 (의존성 부재 → exit 2)"
  # cwd 를 node_modules 가 없는 빈 디렉토리로 돌려 playwright 해석을 실패시킨다.
  local empty rc; empty=$(mktemp -d)
  rc=0; (cd "$empty" && node "$RUNNER" '{"url":"about:blank","viewports":["desktop"],"timeout":5}' >/dev/null 2>&1) || rc=$?
  rm -rf "$empty"
  if [ "$rc" -eq 2 ]; then ok "playwright 부재 → exit 2 (차단이 아니라 판정 불가)"
  else bad "playwright 부재인데 exit ${rc}" "판정 불가를 결함으로 접으면 오탐이 된다"; fi

  # 여기부터는 playwright 가 실제로 있어야 한다.
  # 판정은 **null 여부**로 한다 — 성공 결과에도 "undecidable":null 키가 늘 있으므로
  # 키 이름만 grep 하면 항상 매치되어 검사가 통째로 건너뛰어진다.
  QUALITY=0; VIEWPORTS="desktop"; RECON=0; TIMEOUT=5
  probe "about:blank" "" || true
  if ! printf '%s' "$RESULT" | grep -q '"undecidable":null'; then
    sec "차단 증명"
    skip "clean/broken 픽스처 미검증 — 이 디렉토리에서 playwright 를 해석할 수 없다" \
      "npm i -D playwright && npx playwright install chromium 후 다시 돌린다. 침묵 통과가 아니라 미검증이다."
    printf "\n────────────────────────────────────────────\n"
    printf "  통과 %s · 경고 %s · 실패 %s\n\n" "$PASS" "$WARN" "$FAIL"
    [ "$FAIL" -gt 0 ] && return 1
    return 0
  fi

  # ① 기준선 오탐 확인이 먼저다 — 깨끗한 픽스처에서 결함이 나오면 안 된다.
  sec "기준선 (오탐 없음)"
  probe "file://$fx/clean.html" ""
  local ce; ce=$(printf '%s' "$RESULT" | jq -r '[.runtime.consoleErrors,.runtime.pageErrors,.runtime.failedRequests]|map(length)|add')
  if [ "$(num "$ce")" -eq 0 ]; then ok "clean.html → 결함 0 (오탐 없음)"
  else bad "clean.html 에서 결함 ${ce}건" "미탐만 막고 오탐을 안 막으면 검사는 곧 무시된다"; fi

  # ② 결함을 심은 픽스처가 **의도한 이유로** 걸리는가.
  sec "차단 증명 (결함 픽스처)"
  probe "file://$fx/broken.html" ""
  local c p f
  c=$(num "$(printf '%s' "$RESULT" | jq -r '.runtime.consoleErrors|length')")
  p=$(num "$(printf '%s' "$RESULT" | jq -r '.runtime.pageErrors|length')")
  f=$(num "$(printf '%s' "$RESULT" | jq -r '.runtime.failedRequests|length')")
  [ "$c" -gt 0 ] && ok "콘솔 error 검출 (${c})" || bad "콘솔 error 미검출"
  [ "$p" -gt 0 ] && ok "미포착 예외 검출 (${p})" || bad "미포착 예외 미검출"
  [ "$f" -gt 0 ] && ok "실패 요청 검출 (${f})" || bad "실패 요청 미검출"
  [ "${EPCC_FX_WHY:-}" = "1" ] && printf '%s' "$RESULT" | jq -r '.runtime | to_entries[] | "      \(.key): \(.value|map(.text // .url)|join(" | "))"'

  printf "\n────────────────────────────────────────────\n"
  printf "  통과 %s · 경고 %s · 실패 %s\n\n" "$PASS" "$WARN" "$FAIL"
  [ "$FAIL" -gt 0 ] && return 1
  return 0
}

# ── 디스패치 ─────────────────────────────────────────────────────────
if [ "$MODE" = "selftest" ]; then
  run_self_test; exit $?
fi

[ -n "$URL" ] || { printf '%s\n' "--url 이 필요합니다 (--help 참조)" >&2; exit 2; }

# 증거 디렉토리 — 최근 5회만 보존한다. append 하는 곳에는 상한을 함께 둔다.
if [ -z "$OUT" ]; then
  BASE="${EPCC_STATE_DIR:-$PWD/.claude/.epcc}/ui-probe"
  OUT="$BASE/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$OUT" 2>/dev/null || OUT=""
  if [ -n "$OUT" ] && [ -d "$BASE" ]; then
    ls -1d "$BASE"/*/ 2>/dev/null | sort -r | tail -n +6 | while IFS= read -r old; do rm -rf "$old"; done
  fi
else
  mkdir -p "$OUT" 2>/dev/null || OUT=""
fi

probe "$URL" "$OUT"
PROBE_RC=$?
if [ "$PROBE_RC" -ne 0 ] && [ -z "$RESULT" ]; then
  printf "판정 불가 — 실행부가 결과를 내지 못했습니다 (node %s)\n" "$(node --version 2>/dev/null)" >&2
  exit 2
fi

if [ "$JSON_ONLY" -eq 1 ]; then
  printf '%s\n' "$RESULT"
  printf '%s' "$RESULT" | grep -q '"undecidable":null' || exit 2
  # 종료 코드는 서식 유무와 무관하게 같아야 한다 — 스크립트가 --json 을 쓰면서
  # 결함을 통과로 받으면 게이트가 아니다.
  command -v jq >/dev/null 2>&1 || exit 0
  DEFECTS=$(num "$(printf '%s' "$RESULT" | jq -r \
    '[.runtime.consoleErrors,.runtime.pageErrors,.runtime.failedRequests]|map(length)|add')")
  [ "$DEFECTS" -gt 0 ] && exit 1
  exit 0
fi

report "$RESULT"; REPORT_RC=$?
[ "$REPORT_RC" -eq 2 ] && exit 2

printf "\n────────────────────────────────────────────\n"
printf "  결함 %s · 경고 %s · 확인 %s\n\n" "$FAIL" "$WARN" "$PASS"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
