#!/bin/bash
# skills/ui-ux-design/scripts/design-sync.sh — 캔버스 ↔ MASTER.md 토큰 대조
#
# 두 문서의 **관할은 겹치지 않는다**: MASTER.md 가 토큰·방향을, 캔버스가 화면별 구성을 갖는다.
# 겹치는 집합은 색·폰트·시그니처 셋뿐이고, 드리프트가 가능한 곳도 정확히 거기뿐이다.
# 이 스크립트는 그중 **기계로 판정 가능한 둘**(색·폰트)만 본다 — 시그니처는 산문이라
# 집합 연산이 불가능하므로 Claude 가 육안 대조한다.
#
#   design-sync.sh [--master <MASTER.md>] [--canvas <캔버스.html>]
#
#   --master <경로>   기본: dev/docs/design/*/MASTER.md 중 첫 번째
#   --canvas <경로>   Save 된 캔버스를 내려받은 로컬 HTML
#   --self-test       픽스처로 자기검증
#   -h, --help
#
# 판정: MASTER.md 의 색·폰트가 캔버스에 **없으면** 결함이다 — 되쓰기가 덜 끝났다는 신호다.
#       반대 방향(캔버스에만 있는 색)은 WARN 이며 종료 코드를 올리지 않는다:
#       캔버스는 파생 음영·경계선·오버레이를 정당하게 갖는다. 그것을 차단으로 접으면
#       오탐이 되고, 오탐은 사용자가 장치를 꺼버리게 만든다.
#
# 종료 코드: 0 = 일치 · 1 = 불일치 · 2 = 판정 불가
#            판정 불가는 두 갈래이며 **서로 뜻이 반대다**:
#              · MASTER.md 에 `## 캔버스` 절이 없다  → 캔버스 미사용 경로(정상)
#              · 절은 있는데 캔버스에 도달 못 한다    → 선언과 실물 불일치(보고 대상)
set -uo pipefail   # -e 없음: 모든 검사를 끝까지 돌려 전체 보고서를 낸다

FAIL=0; WARN=0; PASS=0
C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_D=$'\033[2m'; C_0=$'\033[0m'
[ -t 1 ] || { C_R=""; C_G=""; C_Y=""; C_D=""; C_0=""; }

# doctor.sh 의 규약을 복사한다 (source 가 아니다 — lib/common.sh 의 set -Eeuo pipefail 과
# ERR trap 은 "모든 검사를 끝까지 돌린다" 정책과 충돌한다). return 0 을 명시한다:
# 원본 bad/warn 은 $2 가 비면 반환값이 1이라 `... && warn ... || ok ...` 가 양쪽 다 실행된다.
detail() { [ -n "${1:-}" ] || return 0; printf '%s\n' "$1" | sed "s/^/      ${C_D}/;s/\$/${C_0}/"; return 0; }
ok()   { PASS=$((PASS+1)); printf "  ${C_G}✓${C_0} %s\n" "$1"; detail "${2:-}"; return 0; }
bad()  { FAIL=$((FAIL+1)); printf "  ${C_R}✗${C_0} %s\n" "$1"; detail "${2:-}"; return 0; }
warn() { WARN=$((WARN+1)); printf "  ${C_Y}!${C_0} %s\n" "$1"; detail "${2:-}"; return 0; }
skip() { printf "  ${C_D}–${C_0} %s\n" "$1"; detail "${2:-}"; return 0; }
sec()  { printf "\n${C_D}── %s ─────────────────────────────${C_0}\n" "$1"; return 0; }
num()  { local v; v=$(printf '%s' "${1:-}" | tr -d '[:space:]'); case "$v" in ''|*[!0-9]*) printf '0';; *) printf '%s' "$v";; esac; }

MASTER=""; CANVAS=""; SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --master)   MASTER="${2:-}"; shift 2 ;;
    --canvas)   CANVAS="${2:-}"; shift 2 ;;
    --self-test) SELFTEST=1; shift ;;
    -h|--help)  sed -n '2,27p' "$0" | sed -E 's/^#[[:space:]]?//'; exit 0 ;;
    *) printf "알 수 없는 옵션: %s (--help 참조)\n" "$1" >&2; exit 2 ;;
  esac
done

# ── 추출 ──────────────────────────────────────────────────────────────
# 색은 `### Color Palette`(persist) 또는 `### Colors`(단발 출력) 표에서만 뽑는다.
# 파일 전체를 훑으면 Component Specs 의 예시 CSS 가 팔레트인 척 섞인다.
master_hexes() {   # $1 master
  awk '/^### (Color Palette|Colors)/{on=1; next} on && /^### /{on=0} on' "$1" \
    | grep -oiE '#[0-9a-f]{6}|#[0-9a-f]{3}\b' | norm_hex
}
# 3자리는 6자리로 펴고 대문자로 맞춘다 — #FFF 와 #ffffff 가 다른 색으로 세어지면 안 된다.
norm_hex() {
  tr '[:lower:]' '[:upper:]' \
    | awk '{ h=substr($0,2)
             if (length(h)==3) h=substr(h,1,1) substr(h,1,1) substr(h,2,1) substr(h,2,1) substr(h,3,1) substr(h,3,1)
             print "#" h }' \
    | sort -u
}
canvas_hexes() { grep -oiE '#[0-9a-f]{6}|#[0-9a-f]{3}\b' "$1" | norm_hex; }

master_fonts() {   # $1 master — Heading/Body 두 역할만
  grep -oE '^- \*\*(Heading|Body) Font:\*\*.*' "$1" \
    | sed -E 's/^- \*\*(Heading|Body) Font:\*\* *//' \
    | sed -E 's/[[:space:]]+$//' | grep -v '^$' | sort -u
}
# 캔버스의 font-family 선언에 그 이름이 실제로 쓰였는가. 선언 밖의 우연한 문자열
# (본문 카피에 폰트 이름이 등장하는 경우)을 폰트 사용으로 세지 않는다.
canvas_font_decls() { grep -oiE 'font-family[^;}]*' "$1" | tr '[:upper:]' '[:lower:]'; }

# ── 대조 ──────────────────────────────────────────────────────────────
compare() {   # $1 master  $2 canvas
  local m="$1" c="$2" miss_c=0 miss_f=0 extra
  local mh ch
  mh=$(master_hexes "$m"); ch=$(canvas_hexes "$c")

  if [ -z "$mh" ]; then
    warn "MASTER.md 에서 팔레트를 찾지 못했습니다" "\`### Color Palette\` 표가 없습니다 — 색 대조를 건너뜁니다"
  else
    local h
    while IFS= read -r h; do
      [ -z "$h" ] && continue
      printf '%s\n' "$ch" | grep -qxF "$h" || { bad "캔버스에 없는 MASTER 색: $h" "되쓰기가 덜 끝났거나 캔버스가 이 색을 버렸습니다"; miss_c=$((miss_c+1)); }
    done <<< "$mh"
    [ "$miss_c" -eq 0 ] && ok "MASTER 팔레트 $(num "$(printf '%s\n' "$mh" | wc -l)")색 전부 캔버스에 존재"
  fi

  # 반대 방향은 WARN — 파생 음영·경계선을 차단으로 접지 않는다.
  extra=$(printf '%s\n' "$ch" | grep -vxF -f <(printf '%s\n' "$mh") 2>/dev/null | head -8)
  if [ -n "$extra" ] && [ -n "$mh" ]; then
    warn "캔버스에만 있는 색 $(num "$(printf '%s\n' "$ch" | grep -vxcF -f <(printf '%s\n' "$mh") 2>/dev/null)")개" \
         "$(printf '%s' "$extra" | tr '\n' ' ')
파생 음영이면 정상입니다. 새 역할이면 MASTER.md 팔레트에 올리세요"
  fi

  local mf f decls
  mf=$(master_fonts "$m"); decls=$(canvas_font_decls "$c")
  if [ -z "$mf" ]; then
    warn "MASTER.md 에서 폰트 역할을 찾지 못했습니다" "\`- **Heading Font:**\` / \`- **Body Font:**\` 줄이 없습니다"
  else
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      printf '%s' "$decls" | grep -qiF "$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')" \
        || { bad "캔버스 font-family 에 없는 MASTER 폰트: $f" "되쓰기가 덜 끝났거나 캔버스가 다른 폰트를 씁니다"; miss_f=$((miss_f+1)); }
    done <<< "$mf"
    [ "$miss_f" -eq 0 ] && ok "MASTER 폰트 역할 전부 캔버스에 존재"
  fi

  skip "시그니처는 이 스크립트가 판정하지 않습니다" "산문이라 집합 연산이 불가능합니다 — \`## Signature\` 와 캔버스를 Claude 가 육안 대조합니다"
  return 0
}

# ── 자기검증 ──────────────────────────────────────────────────────────
# 결함을 심은 픽스처가 **의도한 이유로** 판정을 받는지까지 확인한다. 살아있음 ≠ 작동함.
self_test() {
  sec "design-sync 자기검증"
  local T; T=$(mktemp -d); trap 'rm -rf "$T"' RETURN
  local sfail=0

  cat > "$T/MASTER.md" <<'MD'
# Design System: Fixture

## Signature
큰 시각 앵커 하나.

## 방향 심사
기본값 군집을 벗어나기 위해 악센트를 바꿨다.

## 캔버스
- URL: https://example.invalid/artifact/fixture
- 확정: 2026-09-10

## Global Rules

### Color Palette

| Role | Hex | CSS Variable |
|------|-----|--------------|
| Primary | `#2563EB` | `--color-primary` |
| CTA/Accent | `#F97316` | `--color-cta` |

### Typography

- **Heading Font:** Playfair Display
- **Body Font:** Inter
MD

  # 일치 픽스처 — 파생 음영(#1E40AF)을 일부러 넣는다: WARN 이지 결함이 아니다.
  cat > "$T/match.html" <<'HT'
<style>
  :root { --p: #2563eb; --c: #F97316; --shade: #1E40AF; }
  h1 { font-family: "Playfair Display", serif; }
  body { font-family: 'Inter', sans-serif; }
</style>
HT
  sed 's/#2563eb/#7C3AED/' "$T/match.html" > "$T/hex-drift.html"
  sed "s/'Inter'/'Roboto'/" "$T/match.html" > "$T/font-drift.html"
  grep -v '^## 캔버스$' "$T/MASTER.md" | grep -v 'example.invalid' | grep -v '^- 확정' > "$T/MASTER-nocanvas.md"

  _case() {   # $1 라벨  $2 기대코드  $3 기대문구  $4.. 인자
    local label="$1" want="$2" needle="$3"; shift 3
    local out rc
    out=$(bash "$0" "$@" 2>&1); rc=$?
    if [ "$rc" -ne "$want" ]; then
      bad "$label — exit $rc (기대 $want)" "$(printf '%s' "$out" | head -4)"; sfail=$((sfail+1)); return 0
    fi
    if ! printf '%s' "$out" | grep -qF "$needle"; then
      bad "$label — exit 는 맞지만 사유가 다르다" "기대 문구: $needle"; sfail=$((sfail+1)); return 0
    fi
    ok "$label — exit $rc · 사유 대조 통과"
    return 0
  }

  _case "일치하는 캔버스"        0 "전부 캔버스에 존재"  --master "$T/MASTER.md" --canvas "$T/match.html"
  _case "hex 하나를 바꾼 캔버스" 1 "#2563EB"            --master "$T/MASTER.md" --canvas "$T/hex-drift.html"
  _case "본문 폰트를 바꾼 캔버스" 1 "Inter"              --master "$T/MASTER.md" --canvas "$T/font-drift.html"
  _case "캔버스 미사용 MASTER"   2 "캔버스 미사용"      --master "$T/MASTER-nocanvas.md"
  _case "선언은 있고 실물 없음"  2 "도달하지 못했습니다" --master "$T/MASTER.md"

  printf "\n"
  if [ "$sfail" -gt 0 ]; then
    printf "${C_R}자기검증 실패 %d건${C_0}\n" "$sfail"; return 1
  fi
  printf "${C_G}자기검증 통과 — 픽스처 5종${C_0}\n"; return 0
}

if [ "$SELFTEST" -eq 1 ]; then
  self_test; exit $?
fi

# ── 실행 ──────────────────────────────────────────────────────────────
if [ -z "$MASTER" ]; then
  MASTER=$(ls -1 dev/docs/design/*/MASTER.md 2>/dev/null | head -1)
fi
[ -n "$MASTER" ] && [ -f "$MASTER" ] || {
  printf "판정 불가 — MASTER.md 를 찾지 못했습니다%s\n" "${MASTER:+: $MASTER}" >&2
  printf "  dev/docs/design/<project>/MASTER.md 를 --master 로 지정하세요\n" >&2
  exit 2; }

sec "디자인 토큰 대조"
printf "  ${C_D}MASTER: %s${C_0}\n" "$MASTER"

CANVAS_DECLARED=0
grep -qE '^## 캔버스' "$MASTER" && CANVAS_DECLARED=1

if [ -z "$CANVAS" ]; then
  if [ "$CANVAS_DECLARED" -eq 0 ]; then
    ok "캔버스 미사용 — MASTER.md 가 구성까지 정본입니다" \
       "\`## 캔버스\` 절이 없습니다. 레이아웃은 방향 심사 1패스 항목이 담습니다 (rules/ui-design.md §3)"
    exit 2
  fi
  warn "캔버스가 선언됐으나 도달하지 못했습니다" \
       "$(grep -A3 -E '^## 캔버스' "$MASTER" | grep -oE 'https?://[^ )]+' | head -1)
발행본을 내려받아 --canvas 로 넘기세요"
  exit 2
fi

[ -f "$CANVAS" ] || {
  warn "캔버스 파일에 도달하지 못했습니다" "$CANVAS"; exit 2; }

printf "  ${C_D}캔버스: %s${C_0}\n" "$CANVAS"
compare "$MASTER" "$CANVAS"

printf "\n"
if [ "$FAIL" -gt 0 ]; then
  printf "${C_R}불일치 %d건${C_0} · 경고 %d건 — 되쓰기가 덜 끝났습니다 (Step 2.7)\n" "$FAIL" "$WARN"
  exit 1
fi
printf "${C_G}토큰 일치${C_0} · 경고 %d건 — 시그니처 육안 대조만 남았습니다\n" "$WARN"
exit 0
